"""Quill Notes API."""
from fastapi import FastAPI

from app import auth, notes, sharing
from app.db import init_db

app = FastAPI(title="Quill Notes API")
app.include_router(auth.router)
app.include_router(notes.router)
app.include_router(sharing.router)


@app.on_event("startup")
def _startup() -> None:
    init_db()


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "service": "quill-notes"}
