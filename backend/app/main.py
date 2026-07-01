from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from .pipeline import optimize_pdb

app = FastAPI(
    title="Plasma Core AI Protein Optimizer",
    version="0.1.0",
    description="FastAPI backend for demo protein mutation and FASTA generation.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


class Mutation(BaseModel):
    position: int
    original: str
    replacement: str
    reason: str


class OptimizeResponse(BaseModel):
    optimized_pdb: str = Field(description="PDB text for the 3D viewer.")
    fasta: str = Field(description="DNA FASTA text for synthesis order.")
    amino_acid_sequence: str
    mutations: list[Mutation]


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/api/v1/optimize", response_model=OptimizeResponse)
async def optimize(
    file: UploadFile = File(..., description="Input protein structure in .pdb format."),
    temperature: float = Form(..., ge=20, le=60),
    ph: float = Form(..., ge=0, le=14),
) -> OptimizeResponse:
    if not file.filename.lower().endswith(".pdb"):
        raise HTTPException(status_code=400, detail="Only .pdb files are supported.")

    raw = await file.read()
    try:
        pdb_text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise HTTPException(status_code=400, detail="PDB file must be UTF-8 text.") from exc

    try:
        result = optimize_pdb(pdb_text=pdb_text, temperature=temperature, ph=ph)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return OptimizeResponse(**result)
