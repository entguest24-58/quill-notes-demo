"""Sharing a note with another person (read-only) and taking the share back."""
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from app.db import connect
from app.notes import _out, _own_note
from app.security import current_user

router = APIRouter(tags=["sharing"])


class ShareIn(BaseModel):
    email: str = Field(min_length=3, max_length=254)


@router.post("/notes/{note_id}/shares", status_code=status.HTTP_201_CREATED)
def share_note(note_id: int, body: ShareIn, user: dict = Depends(current_user)) -> dict:
    with connect() as conn:
        _own_note(conn, note_id, user["id"])
        target = conn.execute("SELECT id FROM users WHERE email = ?", (body.email.strip().lower(),)).fetchone()
        if target is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "No account with that email")
        if target["id"] == user["id"]:
            raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "You cannot share a note with yourself")
        conn.execute("INSERT OR IGNORE INTO note_shares (note_id, user_id) VALUES (?, ?)", (note_id, target["id"]))
    return {"note_id": note_id, "shared_with": body.email.strip().lower()}


@router.get("/shared")
def shared_with_me(user: dict = Depends(current_user)) -> list:
    with connect() as conn:
        rows = conn.execute(
            "SELECT n.* FROM notes n JOIN note_shares s ON s.note_id = n.id WHERE s.user_id = ? ORDER BY n.updated_at DESC",
            (user["id"],),
        ).fetchall()
    return [_out(r) for r in rows]


@router.delete("/notes/{note_id}/shares", status_code=status.HTTP_204_NO_CONTENT)
def unshare_note(note_id: int, body: ShareIn, user: dict = Depends(current_user)) -> None:
    with connect() as conn:
        _own_note(conn, note_id, user["id"])
        conn.execute(
            "DELETE FROM note_shares WHERE note_id = ? AND user_id = (SELECT id FROM users WHERE email = ?)",
            (note_id, body.email.strip().lower()),
        )
