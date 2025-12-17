import os
import pytest
from unittest.mock import MagicMock, AsyncMock, patch
from fastapi.testclient import TestClient

# Set ENV vars before importing modules that use them
os.environ["SUPABASE_URL"] = "https://example.supabase.co"
os.environ["SUPABASE_SERVICE_KEY"] = "mock-key"
os.environ["GEMINI_API_KEY"] = "mock-gemini-key"

# We must mock 'supabase.create_client' so that when workspace_api imports it, it gets a mock
# AND we must mock 'google.genai.Client'
with patch("supabase.create_client") as mock_create_client, \
     patch("google.genai.Client") as mock_gemini_cls:
    
    # Configure Mocks
    mock_supabase_instance = MagicMock()
    mock_create_client.return_value = mock_supabase_instance
    
    mock_gemini_instance = MagicMock()
    mock_gemini_cls.return_value = mock_gemini_instance
    mock_gemini_aio = AsyncMock()
    mock_gemini_instance.aio = mock_gemini_aio

    # Now import the module under test
    # We also need to mock WorkspaceService inside it, but it's imported from a file.
    # We can patch 'workspace_api.WorkspaceService' ONLY AFTER importing 'workspace_api' 
    # OR we patch 'workspace_service.WorkspaceService' before importing 'workspace_api'.
    
    # Let's patch the class in the service module to be safe
    with patch("workspace_service.WorkspaceService") as mock_service_cls:
        mock_service_instance = AsyncMock()
        mock_service_cls.return_value = mock_service_instance
        
        # Import
        from workspace_api import router
        from fastapi import FastAPI
        
        app = FastAPI()
        app.include_router(router)
        client = TestClient(app)

# Test Cases
def test_get_workspaces():
    # Mock DB response
    mock_supabase_instance.table.return_value.select.return_value.eq.return_value.order.return_value.execute.return_value.data = [
        {"id": "ws-1", "name": "Math 101", "created_at": "2023-01-01", "user_id": "u-1"}
    ]
    
    response = client.get("/workspaces/u-1")
    assert response.status_code == 200
    assert response.json()["success"] is True
    assert len(response.json()["workspaces"]) == 1
    assert response.json()["workspaces"][0]["name"] == "Math 101"

def test_create_workspace():
    # Mock Insert response
    mock_supabase_instance.table.return_value.insert.return_value.execute.return_value.data = [
        {"id": "ws-new", "name": "History Will Be Made", "user_id": "u-1"}
    ]
    
    response = client.post("/workspaces", json={"student_id": "u-1", "name": "History Will Be Made"})
    assert response.status_code == 200
    assert response.json()["success"] is True
    assert response.json()["workspace"]["id"] == "ws-new"

@pytest.mark.asyncio
async def test_send_chat_with_cache():
    # Setup fresh mocks for the async test to ensure isolation if needed
    # But we are using the global mock instances defined above which persist across the file scope in this simplified script.
    # Ideally we should re-import or use fixtures, but for this regression check it's okay.
    
    # Mock Service to return a cache name
    mock_service_instance.get_active_context.return_value = "cache/123"
    
    # Mock Chat Session Check (existing chat)
    chats_table = MagicMock()
    chats_table.select.return_value.eq.return_value.execute.return_value.data = [{"id": "chat-1"}]
    
    # Mock Msg Insert
    msgs_table = MagicMock()
    msgs_table.insert.return_value.execute.return_value = None
    
    # Distribute table mocks
    def table_side_effect(name):
        if name == "chats": return chats_table
        if name == "messages": return msgs_table
        return MagicMock()
    mock_supabase_instance.table.side_effect = table_side_effect
    
    # Mock Gemini Generation
    mock_response = MagicMock()
    mock_response.text = "Hello with Context!"
    
    # We need to mock the aio.models.generate_content call
    mock_gemini_aio.models.generate_content.return_value = mock_response

    # Call Endpoint
    response = client.post("/workspaces/ws-1/chat", json={
        "user_id": "u-1",
        "message": "Hello",
        "notes_context": "Some notes"
    })
    
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert data["answer"] == "Hello with Context!"
    
    # Verify Service Call
    mock_service_instance.get_active_context.assert_called_with("ws-1", "u-1")
    
    # Verify Gemini Call
    mock_gemini_aio.models.generate_content.assert_called_once()
    # Check config arg
    call_args = mock_gemini_aio.models.generate_content.call_args
    assert call_args is not None
    # We expect config to have cached_content="cache/123"
    _, kwargs = call_args
    assert kwargs["config"].cached_content == "cache/123"
