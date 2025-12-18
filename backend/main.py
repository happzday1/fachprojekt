import logging
import time
import os
import hashlib
import asyncio
from typing import Optional, List, Dict
from contextlib import asynccontextmanager
from datetime import datetime, timedelta
import threading

from fastapi import FastAPI, HTTPException, UploadFile, File, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from sse_starlette.sse import EventSourceResponse

# Scrapers & Tools
from boss_scraper import BossScraper
from moodle_scraper import MoodleScraper
from lsf_scraper import LsfScraper
from backend_config import MODEL_NAME, SYSTEM_INSTRUCTION
from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from webdriver_manager.chrome import ChromeDriverManager
from cachetools import TTLCache

# Modern Google GenAI SDK
from google import genai
from google.genai import types
from google.genai import errors as genai_errors

# Workspace API router
from workspace_api import router as workspace_router

# Load env vars
from dotenv import load_dotenv
load_dotenv()

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration moved to backend_config.py

# ============================================
# MEMORY & CACHING
# ============================================

class ConversationMemory:
    """In-memory conversation storage with 24-hour TTL per user."""
    
    def __init__(self, ttl_hours: int = 24):
        self._store: Dict[str, Dict] = {}  # user_id -> {messages: [], last_access: datetime}
        self._lock = threading.Lock()
        self._ttl = timedelta(hours=ttl_hours)
    
    def _cleanup_expired(self):
        now = datetime.now()
        expired = [uid for uid, data in self._store.items() 
                   if now - data['last_access'] > self._ttl]
        for uid in expired:
            del self._store[uid]
    
    def add_message(self, user_id: str, role: str, content: str):
        with self._lock:
            self._cleanup_expired()
            if user_id not in self._store:
                self._store[user_id] = {'messages': [], 'last_access': datetime.now()}
            
            self._store[user_id]['messages'].append({
                'role': role,
                'content': content,
                'timestamp': datetime.now().isoformat()
            })
            self._store[user_id]['last_access'] = datetime.now()
            
            # Keep only last 20 messages
            if len(self._store[user_id]['messages']) > 20:
                self._store[user_id]['messages'] = self._store[user_id]['messages'][-20:]
    
    def get_history(self, user_id: str) -> List[Dict]:
        with self._lock:
            self._cleanup_expired()
            if user_id in self._store:
                self._store[user_id]['last_access'] = datetime.now()
                return self._store[user_id]['messages'].copy()
            return []

conversation_memory = ConversationMemory(ttl_hours=24)

# User Data Caching
USER_CACHE_TTL = 86400  # 24 hours
user_login_cache = TTLCache(maxsize=500, ttl=USER_CACHE_TTL)
user_grades_cache = TTLCache(maxsize=500, ttl=USER_CACHE_TTL)
from webdriver_utils import get_cached_driver_path, DEBUG_DIR

def get_cache_key(username: str) -> str:
    return hashlib.sha256(username.encode()).hexdigest()[:16]

def invalidate_user_cache(username: str):
    key = get_cache_key(username)
    if key in user_login_cache: del user_login_cache[key]
    if key in user_grades_cache: del user_grades_cache[key]
    logger.info(f"Cache invalidated for: {username}")

# ============================================
# LIFESPAN & APP SETUP
# ============================================

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Initialize Gemini Client
    api_key = os.getenv("GEMINI_API_KEY")
    if api_key:
        try:
            client = genai.Client(api_key=api_key)
            app.state.genai_client = client
            logger.info(f"✅ Gemini client initialized for model: {MODEL_NAME}")
        except Exception as e:
            logger.error(f"Failed to initialize Gemini client: {e}")
            app.state.genai_client = None
    else:
        logger.warning("GEMINI_API_KEY not set. Chat features will fail.")
        app.state.genai_client = None
        
    yield
    logger.info("Shutting down...")

app = FastAPI(title="Ayla Backend", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origin_regex="https?://.*",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include Workspace Router
app.include_router(workspace_router)

# ============================================
# MODELS
# ============================================

class Credentials(BaseModel):
    username: str
    password: str
    totp_secret: Optional[str] = None
    force_refresh: bool = False

class ChatRequest(BaseModel):
    prompt: str = Field(..., min_length=1)
    user_id: Optional[str] = None
    student_context: Optional[dict] = None
    max_tokens: Optional[int] = 4096

# ============================================
# DEPENDENCIES
# ============================================

def get_client(app_instance: FastAPI = Depends(lambda: app)) -> genai.Client:
    if not hasattr(app_instance.state, "genai_client") or not app_instance.state.genai_client:
        raise HTTPException(status_code=503, detail="Gemini client not initialized")
    return app_instance.state.genai_client

# ============================================
# GENERAL CHAT ENDPOINTS (Merged from gemini_api.py)
# ============================================

@app.post("/chat")
async def chat_with_memory(
    request: ChatRequest,
    client: genai.Client = Depends(get_client)
):
    """
    General Ayla Chat endpoint (Floating Widget).
    Includes memory and student context.
    """
    try:
        user_id = request.user_id or "anonymous"
        messages = []
        
        # 1. Add context
        if request.student_context:
            ctx = request.student_context
            if ctx.get('name') or ctx.get('gpa'):
                messages.append(f"""
[STUDENT DATA]
- Name: {ctx.get('name', 'Student')}
- GPA: {ctx.get('gpa', 'N/A')}
- ECTS: {ctx.get('ects', 'N/A')}
- Degree: {ctx.get('degree', 'Informatik')}
""")
        
        # 2. Add History
        history = conversation_memory.get_history(user_id)
        for msg in history[-10:]:
            role = "User" if msg['role'] == 'user' else "Ayla"
            messages.append(f"{role}: {msg['content']}")
        
        # 3. Add Current Message
        messages.append(f"User: {request.prompt}")
        full_prompt = "\n\n".join(messages)
        
        logger.info(f"Chat request from {user_id}")
        
        # Generate
        response = await client.aio.models.generate_content(
            model=MODEL_NAME,
            contents=full_prompt,
            config=types.GenerateContentConfig(
                system_instruction=SYSTEM_INSTRUCTION,
                max_output_tokens=request.max_tokens,
                temperature=0.7,
            )
        )
        
        answer = response.text
        
        # Save to memory
        conversation_memory.add_message(user_id, "user", request.prompt)
        conversation_memory.add_message(user_id, "assistant", answer)
        
        return {
            "result": answer,
            "model": MODEL_NAME,
            "user_id": user_id,
            "history_count": len(history) + 2
        }
        
    except Exception as e:
        logger.error(f"Chat error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# ============================================
# LOGIN / SCRAPER ENDPOINTS
# ============================================

@app.post("/login")
async def login(creds: Credentials):
    logger.info(f"Login request for {creds.username}")
    
    if creds.force_refresh:
        invalidate_user_cache(creds.username)
    
    key = get_cache_key(creds.username)
    if key in user_login_cache:
        return user_login_cache[key]
    
    # Combined Logic: Single browser session for verification and scraping
    moodle_deadlines = []
    current_classes = []
    try:
        logger.info("Verifying credentials and fetching initial data...")
        
        # 1. Fetch Deadlines (Moodle)
        moodle_scraper = MoodleScraper(creds.username, creds.password)
        m_result = moodle_scraper.get_deadlines(close_driver=True)
        
        if m_result.get("success"):
            moodle_deadlines = m_result.get("deadlines", [])
        else:
            error_status = m_result.get("error", "error")
            if "Authentication failed" in error_status or "Login failed" in error_status:
                 return {"success": False, "error": "invalid_credentials"}
            logger.warning(f"Moodle fetch failed but continuing: {error_status}")

        # 2. Fetch Current Classes (LSF)
        # Note: We create a new scraper for LSF to ensure clean navigation, 
        # though ideally we could reuse the driver if needed for extreme speed.
        lsf_scraper = LsfScraper(creds.username, creds.password, creds.totp_secret)
        l_result = lsf_scraper.get_current_classes()
        if l_result.get("success"):
            current_classes = l_result.get("current_classes", [])
            logger.info(f"Fetched {len(current_classes)} current classes from LSF.")
            
    except Exception as e:
        logger.error(f"Login/Fetch error: {e}")
        return {"success": False, "error": "error"}
    
    response = {
        "success": True, 
        "data": {
            "profile_name": "Student (Verified)",
            "ects_data": {
                "total_ects": 0,
                "courses_count": 0, 
                "degree_program": "Verified User"
            },
            "moodle_deadlines": moodle_deadlines,
            "exam_requirements": [],
            "current_classes": current_classes,
            "detailed_grades": []
        }
    }
    user_login_cache[key] = response
    return response

@app.post("/fetch-grades")
async def fetch_grades(creds: Credentials):
    logger.info(f"fetch-grades request for {creds.username}")
    
    key = get_cache_key(creds.username)
    if not creds.force_refresh and key in user_grades_cache:
        return user_grades_cache[key]
        
    scraper = BossScraper(creds.username, creds.password, creds.totp_secret)
    data = scraper.get_data()
    
    if "error" in data:
        return {"success": False, "error": data["error"]}
        
    # Build detailed grades from scraper data
    exams = data.get("exams", [])
    detailed_grades = []
    
    # Collect numeric grades for calculating average and best
    numeric_grades = []
    
    for exam in exams:
        grade_val = exam.get("grade")
        credits_val = exam.get("credits", 0)
        status_val = exam.get("status", "").lower()
        
        # Determine if exam is passed:
        # - Grade between 1.0 and 4.0 (German grading: 1.0-4.0 is passing)
        # - Status contains 'bestanden' or 'BE' (passed in German)
        is_passed = False
        if grade_val is not None and isinstance(grade_val, (int, float)):
            is_passed = 1.0 <= grade_val <= 4.0
        elif "bestanden" in status_val or status_val == "be":
            is_passed = True
        
        detailed_grades.append({
            "id": exam.get("id", ""),
            "title": exam.get("title", "Unknown"),
            "grade": grade_val,
            "credits": credits_val,
            "semester": exam.get("semester", ""),
            "status": exam.get("status", ""),
            "passed": is_passed,
        })
        
        # Collect valid numeric grades (excluding null/None and 0)
        if grade_val is not None and isinstance(grade_val, (int, float)) and grade_val > 0:
            numeric_grades.append(float(grade_val))
    
    # Calculate average and best grade
    average_grade = None
    best_grade = None
    
    if numeric_grades:
        average_grade = round(sum(numeric_grades) / len(numeric_grades), 2)
        best_grade = min(numeric_grades)  # In German grading, lower is better (1.0 is best)
        logger.info(f"Calculated grades - Average: {average_grade}, Best: {best_grade} from {len(numeric_grades)} grades")
    
    # Get summary data
    summary = data.get("summary", {})
    official_gpa = summary.get("current_gpa", 0.0)

    # Use official GPA if available and valid (>0), otherwise fall back to manual calculation
    final_average_grade = official_gpa if (official_gpa and official_gpa > 0) else average_grade
    
    # Use official_gpa as default if manual calculation is missing completely
    if not final_average_grade:
        final_average_grade = official_gpa

    logger.info(f"Final Grade Logic: Official={official_gpa}, Calculated={average_grade} -> Selected={final_average_grade}")
    
    response = {
        "success": True,
        "data": {
            "profile_name": data.get("identity", {}).get("degree_subject", "Student"),
            "ects_data": {
                "total_ects": summary.get("total_credits", 0),
                "courses_count": len(exams),
                "degree_program": data.get("identity", {}).get("degree_subject", "Unknown"),
                "gpa": summary.get("current_gpa", 0),
                "average_grade": final_average_grade,
                "best_grade": best_grade,
            },
            "detailed_grades": detailed_grades,
            "exam_requirements": [
                {
                    "category": "All Exams",
                    "exams": [
                        {
                            "name": g["title"],
                            "ects": g["credits"],
                            "type": "compulsory", # Default
                            "required": True,
                            "passed": g["passed"]
                        } for g in detailed_grades
                    ]
                }
            ],
            "moodle_deadlines": [],  # Moodle deadlines are merged in login endpoint
            "current_classes": []    # LSF classes are merged in login endpoint
        }
    }
    user_grades_cache[key] = response
    return response

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
