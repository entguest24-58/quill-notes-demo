"""Personal notes: each user sees and changes only their own."""
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field

from app.db import connect
from app.security import current_user

router = APIRouter(prefix="/notes", tags=["notes"])


class NoteIn(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    body: str = Field(default="", max_length=10_000)
    pinned: bool = False


class NotePatch(BaseModel):
    title: Optional[str] = Field(default=None, min_length=1, max_length=200)
    body: Optional[str] = Field(default=None, max_length=10_000)
    pinned: Optional[bool] = None


def _out(row) -> dict:
    return {"id": row["id"], "title": row["title"], "body": row["body"], "pinned": bool(row["pinned"]),
            "created_at": row["created_at"], "updated_at": row["updated_at"]}


def _own_note(conn, note_id: int, user_id: int):
    row = conn.execute("SELECT * FROM notes WHERE id = ?", (note_id,)).fetchone()
    if row is None or row["owner_id"] != user_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Note not found")
    return row


@router.get("")
def list_notes(q: Optional[str] = Query(default=None, max_length=100), pinned: Optional[bool] = None,
               user: dict = Depends(current_user)) -> list:
    sql = "SELECT * FROM notes WHERE owner_id = ?"
    args: list = [user["id"]]
    if pinned is not None:
        sql += " AND pinned = ?"
        args.append(1 if pinned else 0)
    if q:
        sql += " AND title LIKE ?"
        args.append(f"%{q}%")
    sql += " ORDER BY pinned DESC, created_at DESC, id DESC"
    with connect() as conn:
        return [_out(r) for r in conn.execute(sql, args).fetchall()]


@router.post("", status_code=status.HTTP_201_CREATED)
def create_note(body: NoteIn, user: dict = Depends(current_user)) -> dict:
    with connect() as conn:
        cur = conn.execute(
            "INSERT INTO notes (owner_id, title, body, pinned) VALUES (?, ?, ?, ?)",
            (user["id"], body.title.strip(), body.body, int(body.pinned)),
        )
        row = conn.execute("SELECT * FROM notes WHERE id = ?", (cur.lastrowid,)).fetchone()
    return _out(row)


@router.get("/{note_id}")
def get_note(note_id: int, user: dict = Depends(current_user)) -> dict:
    with connect() as conn:
        return _out(_own_note(conn, note_id, user["id"]))


@router.patch("/{note_id}")
def update_note(note_id: int, body: NotePatch, user: dict = Depends(current_user)) -> dict:
    changes = body.model_dump(exclude_none=True)
    if not changes:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Nothing to update")
    with connect() as conn:
        _own_note(conn, note_id, user["id"])
        if "pinned" in changes:
            changes["pinned"] = int(changes["pinned"])
        sets = ", ".join(f"{k} = ?" for k in changes)
        conn.execute(f"UPDATE notes SET {sets}, updated_at = datetime('now') WHERE id = ?", [*changes.values(), note_id])
        return _out(conn.execute("SELECT * FROM notes WHERE id = ?", (note_id,)).fetchone())


@router.delete("/{note_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_note(note_id: int, user: dict = Depends(current_user)) -> None:
    with connect() as conn:
        _own_note(conn, note_id, user["id"])
        conn.execute("DELETE FROM notes WHERE id = ?", (note_id,))
