# Plasma Core Backend

FastAPI prototype for the `/api/v1/optimize` pipeline.

## Run

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

## API

`POST /api/v1/optimize`

Multipart form fields:

- `file`: `.pdb` protein structure.
- `temperature`: target temperature from 20 to 60.
- `ph`: target pH from 0 to 14.

Example:

```powershell
curl.exe -X POST http://127.0.0.1:8000/api/v1/optimize `
  -F "file=@5xjh.pdb" `
  -F "temperature=45" `
  -F "ph=7.2"
```

The response contains optimized PDB text, FASTA DNA text, the amino acid sequence,
and mutation positions for the 3D viewer.
