# Quill Notes API

A small notes service with sharing: people sign up, sign in and keep personal notes.

    pip install -r requirements.txt
    JWT_SECRET=dev-secret uvicorn app.main:app --reload

`JWT_SECRET` is required. `DATABASE_PATH` (default `quill.db`) is the SQLite file. `GET /health` answers when the service is up.
