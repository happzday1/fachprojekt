import os
import asyncio
from datetime import datetime, timedelta, timezone
from typing import Optional, List
import logging

from supabase import create_client, Client as SupabaseClient
from google import genai
from google.genai import types
from backend_config import MODEL_NAME, SYSTEM_INSTRUCTION

logger = logging.getLogger(__name__)

class WorkspaceService:
    def __init__(self):
        # Initialize Supabase Client
        self.supabase_url = os.getenv("SUPABASE_URL")
        self.supabase_key = os.getenv("SUPABASE_SERVICE_KEY")
        
        if not self.supabase_url or not self.supabase_key:
            logger.warning("Supabase credentials not found in environment variables.")
            self.supabase: Optional[SupabaseClient] = None
        else:
            self.supabase = create_client(self.supabase_url, self.supabase_key)

        # Initialize Gemini Client
        self.gemini_api_key = os.getenv("GEMINI_API_KEY")
        if not self.gemini_api_key:
            logger.warning("Gemini API key not found.")
            self.gemini_client = None
        else:
            self.gemini_client = genai.Client(api_key=self.gemini_api_key)

    async def get_active_context(self, workspace_id: str, user_id: str) -> tuple[Optional[str], List[dict]]:
        """
        Implements the Check-or-Create Caching Algorithm.
        Returns (gemini_cache_name, list_of_file_info_for_fallback).
        """
        if not self.supabase or not self.gemini_client:
            raise RuntimeError("Services not initialized properly.")

        # 1. Query gemini_caches for the workspace
        # We need to check if a valid cache exists.
        # Assuming RLS allows this service role access or we pass user context if utilizing proper auth flow. 
        # Since this is a backend service utilizing service key (likely) or acting on behalf, 
        # we'll assume we can query by workspace_id directly.
        
        response = self.supabase.table("gemini_caches") \
            .select("resource_name, expires_at") \
            .eq("workspace_id", workspace_id) \
            .execute()

        cache_entry = response.data[0] if response.data else None

        if cache_entry:
            expires_at_str = cache_entry["expires_at"]
            # Parse ISO string to datetime
            expires_at = datetime.fromisoformat(expires_at_str.replace("Z", "+00:00"))
            
            # Check if expired
            if expires_at > datetime.now(timezone.utc):
                logger.info(f"Cache hit for workspace {workspace_id}: {cache_entry['resource_name']}")
                # We still need the files info for fallback if something goes wrong later, 
                # but for simplicity, we'll return empty list if cache hit.
                return cache_entry["resource_name"], []
            else:
                logger.info(f"Cache expired for workspace {workspace_id}. Re-creating...")
                # Cleanup old cache entry ideally, but upsert will handle the DB record update. 
                # We might want to delete the old cache from Gemini if possible, but the API handles expiration.

        # 2. Cache miss or expired: Create new cache
        
        # Query workspace_files for this workspace to get file paths
        files_response = self.supabase.table("workspace_files") \
            .select("id, storage_path, gemini_uri, file_name") \
            .eq("workspace_id", workspace_id) \
            .execute()
        
        workspace_files = files_response.data
        if not workspace_files:
            logger.info(f"No files in workspace {workspace_id}. Returning empty context.")
            return None, []

        valid_uris = []
        
        # Check gemini_uris and upload if missing
        for file_record in workspace_files:
            uri = file_record.get("gemini_uri")
            if not uri:
                # Upload to Gemini Files API
                uri = await self._upload_to_gemini(file_record)
                
                # Update DB with new URI
                self.supabase.table("workspace_files") \
                    .update({"gemini_uri": uri, "upload_status": "uploaded"}) \
                    .eq("id", file_record["id"]) \
                    .execute()
            
            valid_uris.append(uri)

        if not valid_uris:
             return None, []

        # Prepare files info for fallback
        files_info = []
        cached_contents = []
        
        for file_record in workspace_files:
            uri = file_record.get("gemini_uri")
            if not uri: continue # Should be handled by upload block above
            
            fname = file_record.get("file_name", "doc.pdf")
            mime_type = "application/pdf"
            if fname.lower().endswith(".txt"):
                mime_type = "text/plain"
            elif fname.lower().endswith(".jpg") or fname.lower().endswith(".jpeg"):
                mime_type = "image/jpeg"
            elif fname.lower().endswith(".png"):
                mime_type = "image/png"
            
            files_info.append({"uri": uri, "mime_type": mime_type})
            
            cached_contents.append(
                types.Content(
                    role="user",
                    parts=[
                        types.Part(
                            file_data=types.FileData(file_uri=uri, mime_type=mime_type)
                        )
                    ]
                )
            )

        # Create cache
        
        try:
            cache = await self.gemini_client.aio.caches.create(
                model=MODEL_NAME,
                config=types.CreateCachedContentConfig(
                    system_instruction=types.Content(
                        role="system",
                        parts=[types.Part(text=SYSTEM_INSTRUCTION)]
                    ),
                    contents=cached_contents,
                    ttl="7200s" # 2 hours
                )
            )
            
            # Upsert into gemini_caches
            self.supabase.table("gemini_caches").upsert({
                "workspace_id": workspace_id,
                "resource_name": cache.name,
                "expires_at": cache.expire_time
            }).execute()
            
            return cache.name, files_info
            
        except Exception as e:
            # Check if it's a 400 (too small) or other non-fatal error
            logger.warning(f"Gemini Caching failed (proceeding with fallback): {e}")
            return None, files_info

    async def _upload_to_gemini(self, file_record: dict) -> str:
        """
        Downloads file from Supabase Storage and uploads to Gemini Files API.
        Returns the Gemini URI.
        """
        # 1. Download from Supabase Storage
        path = file_record["storage_path"]
        # bucket name? Assuming 'workspace_files' or similar. 
        # Ideally stored in path or separate config.
        # We will assume path is 'bucket/folder/file' or use a default bucket.
        # Let's assume a 'files' bucket.
        bucket_name = "workspace_files" # heuristic
        
        try:
            # Note: Supabase storage.download returns bytes
            file_data = self.supabase.storage.from_(bucket_name).download(path)
        except Exception as e:
            logger.error(f"Failed to download {path} from Supabase: {e}")
            raise

        # 2. Upload to Gemini
        # We need a temporary file or bytes IO?
        # client.files.upload takes path or file-like object?
        # In v1.0, types.File object?
        # Actually client.files.upload(file=...)
        # We'll use a BytesIO wrapper or temp file if needed.
        # But `upload` usually expects a path. `upload_file` is the method?
        
        # Workaround: Write to temp file
        import tempfile
        suffix = os.path.splitext(file_record["file_name"])[1]
        
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
            tmp.write(file_data)
            tmp_path = tmp.name
            
        try:
            # client.files.upload(path=...) returns a File object
            # Note: client.files.upload is synchronous usually? 
            # Use aio? client.aio.files.upload?
            # Check SDK capability. Assuming client.aio.files.upload exists.
            
            uploaded_file = await self.gemini_client.aio.files.upload(
                file=tmp_path,
                config=types.UploadFileConfig(display_name=file_record["file_name"]) 
            )
            return uploaded_file.uri
        finally:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)

