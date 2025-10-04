# backend/main.py
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List
import sqlite3
import os

app = FastAPI(title="Memory Keeper API")

# CORS für Flutter Web
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Für Demo, später evtl. einschränken
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# SQLite DB Verbindung
DB_PATH = "memory_keeper.db"

def get_db_connection():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

# Datenmodell
class Memory(BaseModel):
    id: int = None
    content: str

# Root-Route
@app.get("/")
def root():
    return {"message": "Memory Keeper API läuft!"}

# Alle Memories abrufen
@app.get("/memories", response_model=List[Memory])
def get_memories():
    conn = get_db_connection()
    memories = conn.execute("SELECT * FROM memories").fetchall()
    conn.close()
    return [{"id": row["id"], "content": row["content"]} for row in memories]

# Neue Memory hinzufügen
@app.post("/memories", response_model=Memory)
def add_memory(memory: Memory):
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("INSERT INTO memories (content) VALUES (?)", (memory.content,))
    conn.commit()
    memory.id = cursor.lastrowid
    conn.close()
    return memory
