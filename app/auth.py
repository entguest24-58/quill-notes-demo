"""Sign-up and sign-in."""
import sqlite3

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, Field

from app.db import connect
from app.security import hash_password, issue_token, verify_password

router = APIRouter(prefix="/auth", tags=["auth"])


class Credentials(BaseModel):
    email: str = Field(min_length=3, max_length=254, pattern=r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
    password: str = Field(min_length=8, max_length=128)


@router.post("/register", status_code=status.HTTP_201_CREATED)
def register(body: Credentials) -> dict:
    email = body.email.strip().lower()
    try:
        with connect() as conn:
            cur = conn.execute(
                "INSERT INTO users (email, password_hash) VALUES (?, ?)", (email, hash_password(body.password))
            )
            user_id = cur.lastrowid
    except sqlite3.IntegrityError:
        raise HTTPException(status.HTTP_409_CONFLICT, "Email already registered")
    return {"id": user_id, "email": email}


@router.post("/login")
def login(body: Credentials) -> dict:
    email = body.email.strip().lower()
    with connect() as conn:
        row = conn.execute("SELECT id, password_hash FROM users WHERE email = ?", (email,)).fetchone()
    if row is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "No account with that email")
    if not verify_password(body.password, row["password_hash"]):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Wrong password")
    return {"access_token": issue_token(row["id"]), "token_type": "bearer"}
