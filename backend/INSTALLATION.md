# Installation Instructions for Enhanced Features

## Step 1: Install Playwright

Since the system uses an externally-managed Python environment, install Playwright in your project:

```bash
cd /home/bilel0-0/uniapp/backend

# If using a virtual environment (recommended)
python3 -m venv venv
source venv/bin/activate
pip install playwright

# Install Chromium browser for Playwright
playwright install chromium
```

If you don't want to use a virtual environment, you can use `--break-system-packages` (not recommended):
```bash
python3 -m pip install playwright --break-system-packages
playwright install chromium
```

## Step 2: Restart Backend Server

After installation, restart your FastAPI server:

```bash
# If using a service
sudo systemctl restart ayla-backend

# Or manually
pkill -f "uvicorn main:app"
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

## Step 3: Test Enhanced Features

Test the new capabilities:

1. **Chain-of-Thought Reasoning**: Ask a complex question like "What's the best strategy to prepare for my upcoming exams?"
   - The AI should now show its thinking process

2. **Smart Context**: Ask specific questions and check logs - you'll see only relevant context being sent

3. **JavaScript Web Scraping**: Ask about a modern website with dynamic content
   - Example: "What are the latest AI news from TechCrunch?"
   - The AI will automatically use Playwright if installed, fall back to requests if not

## Verification

Check logs for these indicators:
- `📊 Including grades context` - Smart summarization working
- `🧠 REASONING PROTOCOL` in AI responses - Chain-of-thought active
- `🌐 Advanced Web Reader` - Playwright being used
- `⚠️ Playwright not available, using simple reader` - Fallback working

## Dependencies Added

The following was added to `requirements.txt`:
- `playwright` - For JavaScript-aware web scraping

Total additional size: ~200MB (Chromium browser)
