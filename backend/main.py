# backend/main.py
from fastapi import FastAPI, File, UploadFile, Form
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional
import sqlite3
import os
import json
import uuid
from datetime import datetime

# --- Konfiguration ---
DB_PATH = "memory_keeper.db"
UPLOAD_DIR = "uploads"

# Upload-Verzeichnis erstellen
os.makedirs(UPLOAD_DIR, exist_ok=True)

# --- SQLite Verbindung ---
def get_db_connection():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def init_database():
    """Tabelle anlegen, falls sie noch nicht existiert"""
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS memories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            media_files TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    conn.commit()
    conn.close()

# Tabelle direkt beim Start erstellen
init_database()

# --- FastAPI App ---
app = FastAPI(title="Memory Keeper API")

# CORS für Flutter Web
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Für Demo, später evtl. einschränken
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- Datenmodelle ---
class MediaFile(BaseModel):
    filename: str
    file_type: str  # 'photo', 'video', 'audio'
    file_size: int
    duration: Optional[int] = None  # Für Audio/Video in Sekunden

class Memory(BaseModel):
    id: Optional[int] = None
    title: str
    content: str
    media_files: Optional[List[MediaFile]] = []
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

# --- Endpoints ---
@app.get("/")
def root():
    return {"message": "Memory Keeper API läuft!"}

# Alle Memories abrufen
@app.get("/memories", response_model=List[Memory])
def get_memories():
    conn = get_db_connection()
    memories = conn.execute("SELECT * FROM memories ORDER BY created_at DESC").fetchall()
    conn.close()
    
    result = []
    for row in memories:
        memory_data = {
            "id": row["id"],
            "title": row["title"],
            "content": row["content"],
            "created_at": row["created_at"],
            "updated_at": row["updated_at"]
        }
        
        # Media Files parsen
        if row["media_files"]:
            try:
                media_files_data = json.loads(row["media_files"])
                memory_data["media_files"] = [MediaFile(**media) for media in media_files_data]
            except:
                memory_data["media_files"] = []
        else:
            memory_data["media_files"] = []
            
        result.append(memory_data)
    
    return result

# Neue Memory hinzufügen
@app.post("/memories", response_model=Memory)
def add_memory(memory: Memory):
    conn = get_db_connection()
    cursor = conn.cursor()
    
    # Media Files zu JSON konvertieren
    media_files_json = json.dumps([media.dict() for media in memory.media_files]) if memory.media_files else "[]"
    
    cursor.execute(
        "INSERT INTO memories (title, content, media_files) VALUES (?, ?, ?)", 
        (memory.title, memory.content, media_files_json)
    )
    conn.commit()
    memory.id = cursor.lastrowid
    conn.close()
    return memory

# Media-Datei hochladen
@app.post("/upload-media")
async def upload_media(
    file: UploadFile = File(...),
    file_type: str = Form(...),  # 'photo', 'video', 'audio'
    duration: Optional[int] = Form(None)
):
    # Dateiname generieren
    file_extension = file.filename.split('.')[-1] if '.' in file.filename else 'bin'
    unique_filename = f"{uuid.uuid4()}.{file_extension}"
    file_path = os.path.join(UPLOAD_DIR, unique_filename)
    
    # Datei speichern
    with open(file_path, "wb") as buffer:
        content = await file.read()
        buffer.write(content)
    
    # MediaFile-Objekt erstellen
    media_file = MediaFile(
        filename=unique_filename,
        file_type=file_type,
        file_size=len(content),
        duration=duration
    )
    
    return media_file

# Media-Datei abrufen
@app.get("/media/{filename}")
async def get_media(filename: str):
    file_path = os.path.join(UPLOAD_DIR, filename)
    if os.path.exists(file_path):
        from fastapi.responses import FileResponse
        return FileResponse(file_path)
    else:
        return {"error": "Datei nicht gefunden"}
