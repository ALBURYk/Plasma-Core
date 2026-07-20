# Deployment notes

## Backend verification

The FastAPI backend was verified locally with:

```powershell
python -m uvicorn backend.app.main:app --host 127.0.0.1 --port 8001
curl http://127.0.0.1:8001/health
```

Expected response:

```json
{"status":"ok"}
```

## Vercel-ready build

The repository includes:

- `vercel.json` for static web output and Python API routing
- `scripts/vercel_build.sh` for Flutter web release build
- `api/index.py` as the Python function entrypoint
