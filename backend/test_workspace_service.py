import pytest
import asyncio
from unittest.mock import MagicMock, AsyncMock, patch
from datetime import datetime, timedelta, timezone
from workspace_service import WorkspaceService

# Mock data
WORKSPACE_ID = "ws-123"
USER_ID = "user-456"
VALID_CACHE_NAME = "cached-content/12345"
EXPIRED_TIME = (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat()
FUTURE_TIME = (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat()

@pytest.fixture
def mock_supabase():
    with patch("workspace_service.create_client") as mock:
        client = MagicMock()
        mock.return_value = client
        
        # Create separate mocks for different tables
        caches_table = MagicMock()
        files_table = MagicMock()
        
        def table_side_effect(name):
            if name == "gemini_caches":
                return caches_table
            elif name == "workspace_files":
                return files_table
            return MagicMock()

        client.table.side_effect = table_side_effect
        yield client, caches_table, files_table

@pytest.fixture
def mock_gemini():
    with patch("workspace_service.genai.Client") as mock:
        client = MagicMock()
        # Setup async mocks
        client.aio = MagicMock()
        client.aio.caches = AsyncMock()
        client.aio.files = AsyncMock()
        mock.return_value = client
        yield client

@pytest.fixture
def service(mock_supabase, mock_gemini):
    client, _, _ = mock_supabase
    with patch.dict("os.environ", {"SUPABASE_URL": "http://test", "SUPABASE_SERVICE_KEY": "test", "GEMINI_API_KEY": "test"}):
        return WorkspaceService()

@pytest.mark.asyncio
async def test_get_active_context_cache_hit(service, mock_supabase):
    client, caches_table, files_table = mock_supabase
    
    # Setup Supabase mock to return valid cache
    caches_table.select.return_value.eq.return_value.execute.return_value.data = [{
        "resource_name": VALID_CACHE_NAME,
        "expires_at": FUTURE_TIME
    }]

    result = await service.get_active_context(WORKSPACE_ID, USER_ID)

    assert result == VALID_CACHE_NAME
    # Verify we didn't query files
    files_table.select.assert_not_called()

@pytest.mark.asyncio
async def test_get_active_context_cache_miss_create_new(service, mock_supabase, mock_gemini):
    client, caches_table, files_table = mock_supabase
    
    # 1. Cache miss (return empty)
    caches_table.select.return_value.eq.return_value.execute.return_value.data = []

    # 2. Return files
    files_table.select.return_value.eq.return_value.execute.return_value.data = [
        {"id": "file-1", "storage_path": "path/to/doc.pdf", "gemini_uri": "uri-1", "file_name": "doc.pdf"},
        {"id": "file-2", "storage_path": "path/to/img.png", "gemini_uri": None, "file_name": "img.png"} 
    ]
    
    # 3. Mock Upload for file-2
    mock_gemini.aio.files.upload.return_value.uri = "uri-2"
    
    # 4. Mock Cache Creation
    mock_cache = MagicMock()
    mock_cache.name = "new-cache-123"
    mock_cache.expire_time = FUTURE_TIME
    mock_gemini.aio.caches.create.return_value = mock_cache

    # Mock DB update for files
    files_table.update.return_value.eq.return_value.execute.return_value.data = []
    
    # Mock DB upsert for cache
    caches_table.upsert.return_value.execute.return_value.data = []
    
    # Mock storage download
    client.storage.from_.return_value.download.return_value = b"fake-content"

    # Execute
    result = await service.get_active_context(WORKSPACE_ID, USER_ID)

    assert result == "new-cache-123"
    
    # Verification
    # Check upload called for file-2
    assert mock_gemini.aio.files.upload.call_count == 1
    
    # Check cache created
    mock_gemini.aio.caches.create.assert_called_once()
    
    # Check DB updated for file-2 URI
    files_table.update.assert_called()
    
    # Check DB upsert for cache
    caches_table.upsert.assert_called()

    
