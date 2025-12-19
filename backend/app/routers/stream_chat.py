import logging
import json
import asyncio
from datetime import datetime
from typing import AsyncGenerator, Optional

from fastapi import APIRouter, Depends, HTTPException, Body
from sse_starlette.sse import EventSourceResponse
from pydantic import BaseModel

from google import genai
from google.genai import types

from app.auth.supabase_auth import get_current_user_id
from app.services.gemini_engine import GeminiEngine
from backend_config import MODEL_NAME

# Setup Router
router = APIRouter(prefix="/chat", tags=["Chat"])
logger = logging.getLogger(__name__)

# Request Model
class ChatMessage(BaseModel):
    message: str
    workspace_id: Optional[str] = None
    stream: bool = True

# Dependency to get Gemini Client from App State (Assuming main.py setup)
# We need to import the dependency logic or duplicate it.
# Since app.state is attached to the app instance, we can import `get_client` from main if possible,
# or redefine it. to avoid circular imports, it's better to implement a clean dependency here
# or pass the client via request.app.state.

async def get_gemini_client():
    from main import app # Late import to avoid circular dependency
    if not app.state.genai_client:
        raise HTTPException(status_code=503, detail="AI Service Unavailable")
    return app.state.genai_client

@router.post("/stream")
async def stream_chat(
    request: ChatMessage,
    user_id: str = Depends(get_current_user_id),
    client: genai.Client = Depends(get_gemini_client)
):
    """
    SSE Endpoint for Chat.
    Supports "Workspace Mode" via Gemini Context Caching.
    """
    logger.info(f"Chat request from {user_id}. Workspace: {request.workspace_id}")

    async def event_generator() -> AsyncGenerator[str, None]:
        try:
            cached_content_name = None
            
            # 1. Resolve Workspace Context
            if request.workspace_id:
                engine = GeminiEngine(client)
                cached_content_name = await engine.get_or_create_cache(request.workspace_id)
                if cached_content_name:
                    logger.info(f"Using Cache: {cached_content_name}")
            
            # 2. Config
            config = types.GenerateContentConfig(
                temperature=0.7,
                cached_content=cached_content_name # Pass null/None if no cache
            )
            
            # 3. Stream from Gemini
            # In google-genai V1, use generate_content_stream for aio
            
            async for chunk in client.aio.models.generate_content_stream(
                model=MODEL_NAME, 
                contents=request.message,
                config=config,
            ):
                if chunk.text:
                    # SSE format: data: <json>\n\n
                    payload = json.dumps({"text": chunk.text})
                    yield f"data: {payload}\n\n"
            
            # End of stream
            yield "data: {\"done\": true}\n\n"

        except Exception as e:
            logger.error(f"Stream error: {e}")
            yield json.dumps({"error": str(e)})

    return EventSourceResponse(event_generator())
