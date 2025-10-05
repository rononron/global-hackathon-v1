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
from groq_client import generate_smart_title

# --- Konfiguration ---
DB_PATH = "memory_keeper.db"
QUESTIONS_DB_PATH = "questions.db"
DAILY_SUMMARIES_DB_PATH = "daily_summaries.db"
LIKES_DB_PATH = "likes.db"
UPLOAD_DIR = "uploads"

# Upload-Verzeichnis erstellen
os.makedirs(UPLOAD_DIR, exist_ok=True)

# --- SQLite Verbindung ---
def get_db_connection():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def get_questions_db_connection():
    conn = sqlite3.connect(QUESTIONS_DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def get_daily_summaries_db_connection():
    conn = sqlite3.connect(DAILY_SUMMARIES_DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def get_likes_db_connection():
    conn = sqlite3.connect(LIKES_DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

# --- Likes Datenbank initialisieren ---
def init_likes_db():
    conn = get_likes_db_connection()
    cursor = conn.cursor()
    
    # Tabelle für Likes erstellen
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS likes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            memory_id INTEGER NOT NULL,
            user_type TEXT NOT NULL, -- 'family_member' oder 'input_giver'
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(memory_id, user_type)
        )
    ''')
    
    conn.commit()
    conn.close()

# --- Fragenvorschläge Datenbank initialisieren ---
def init_questions_db():
    conn = get_questions_db_connection()
    cursor = conn.cursor()
    
    # Tabelle für Fragenvorschläge erstellen
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS questions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            question_text TEXT NOT NULL,
            category TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            is_active BOOLEAN DEFAULT 1
        )
    ''')
    
    # Prüfen ob bereits Daten vorhanden sind
    cursor.execute("SELECT COUNT(*) FROM questions")
    count = cursor.fetchone()[0]
    
    if count == 0:
        # 10 Testfragen einfügen
        test_questions = [
            "Wie war dein Tag heute – ruhig, stressig oder besonders ereignisreich?",
            "Worüber möchtest du heute erzählen: Arbeit, Familie, Freizeit oder etwas ganz anderes?",
            "Was hat dich heute glücklich gemacht oder dir ein Lächeln geschenkt?",
            "Gab es heute etwas, das dich überrascht oder zum Nachdenken gebracht hat?",
            "Mit wem hast du heute Zeit verbracht, und was habt ihr gemeinsam erlebt?",
            "Hattest du heute einen Moment, in dem du besonders stolz auf dich warst?",
            "Wie hast du dich heute körperlich und seelisch gefühlt?",
            "Gibt es etwas, worauf du dich morgen besonders freust?",
            "Möchtest du heute lieber in Erinnerungen schwelgen oder von neuen Plänen erzählen?",
            "Wenn du den Tag in einem Wort zusammenfassen müsstest – welches wäre das und warum?"
        ]
        
        for question in test_questions:
            cursor.execute(
                "INSERT INTO questions (question_text, category) VALUES (?, ?)",
                (question, "allgemein")
            )
        
        print(f"✅ {len(test_questions)} Testfragen in die Datenbank eingefügt")
    
    conn.commit()
    conn.close()

# Datenbank beim Start initialisieren
init_questions_db()
init_likes_db()

# --- Tageszusammenfassungen Datenbank initialisieren ---
def init_daily_summaries_db():
    conn = get_daily_summaries_db_connection()
    cursor = conn.cursor()
    
    # Tabelle für Tageszusammenfassungen erstellen
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS daily_summaries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date DATE NOT NULL UNIQUE,
            summary TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    
    conn.commit()
    conn.close()

init_daily_summaries_db()

def generate_ai_title(content: str) -> str:
    """
    Generiert einen kurzen, beschreibenden Titel für den gegebenen Inhalt mit Hugging Face.
    Kostenfrei und lokal ausführbar.
    """
    print(f"Generiere Titel mit Hugging Face für: '{content[:50]}...'")
    return generate_smart_title(content)

def generate_title_on_demand(content: str) -> str:
    """
    Generiert einen Titel nur auf explizite Anfrage (z.B. über API-Endpoint).
    Wird nicht automatisch bei der Erstellung aufgerufen.
    """
    print(f"Generiere Titel auf Anfrage für: '{content[:50]}...'")
    return generate_smart_title(content)


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
            life_chapter TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    
    # Füge life_chapter Spalte hinzu, falls sie nicht existiert (für bestehende Datenbanken)
    try:
        cursor.execute("ALTER TABLE memories ADD COLUMN life_chapter TEXT")
        conn.commit()
    except sqlite3.OperationalError:
        # Spalte existiert bereits
        pass
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
    file_size: Optional[int] = None  # Für Demo optional
    duration: Optional[int] = None  # Für Audio/Video in Sekunden

class Memory(BaseModel):
    id: Optional[int] = None
    title: str
    content: str
    media_files: Optional[List[MediaFile]] = []
    life_chapter: Optional[str] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

class DailySummary(BaseModel):
    id: Optional[int] = None
    date: str  # Format: YYYY-MM-DD
    summary: str
    created_at: Optional[datetime] = None

class LikeRequest(BaseModel):
    memory_id: int
    user_type: str  # 'family_member' oder 'input_giver'

class LikeResponse(BaseModel):
    memory_id: int
    is_liked: bool
    like_count: int
    updated_at: Optional[datetime] = None

# --- Endpoints ---
@app.get("/")
def root():
    return {"message": "Memory Keeper API läuft!"}

# Wake-up endpoint for demo purposes
@app.get("/wake-up")
def wake_up():
    """Wake-up endpoint to keep the backend server warm for demo purposes"""
    return {"message": "Backend is awake and ready!", "timestamp": datetime.now().isoformat()}

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
            "title": row["title"] or "",  # Leerer String statt None
            "content": row["content"],
            "life_chapter": row["life_chapter"],
            "created_at": row["created_at"],
            "updated_at": None  # updated_at existiert nicht in der DB
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
    
    # Titel wird NICHT automatisch generiert - bleibt leer oder verwendet den übergebenen Titel
    final_title = memory.title if memory.title else ""
    print(f"Speichere Memory ohne automatische Titel-Generierung: '{final_title}'")
    
    # Media Files zu JSON konvertieren
    media_files_json = json.dumps([media.dict() for media in memory.media_files]) if memory.media_files else "[]"
    
    cursor.execute(
        "INSERT INTO memories (title, content, media_files, life_chapter) VALUES (?, ?, ?, ?)", 
        (final_title, memory.content, media_files_json, memory.life_chapter)
    )
    conn.commit()
    memory.id = cursor.lastrowid
    memory.title = final_title
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

# Endpoint für KI-Titel-Generierung auf Anfrage
@app.post("/generate-title")
def generate_title(request: dict):
    """Generiert einen Titel für den gegebenen Inhalt"""
    content = request.get("content", "")
    if not content:
        return {"error": "Kein Inhalt bereitgestellt"}
    
    print(f"Generiere Titel auf Anfrage für: '{content}'")
    ai_title = generate_title_on_demand(content)
    print(f"KI-Titel generiert: '{ai_title}'")
    
    return {
        "original_content": content,
        "generated_title": ai_title,
        "success": True
    }

# Endpoint um Titel für bestehende Memory zu aktualisieren
@app.put("/memories/{memory_id}/title")
def update_memory_title(memory_id: int, request: dict):
    """Aktualisiert den Titel einer bestehenden Memory"""
    content = request.get("content", "")
    if not content:
        return {"error": "Kein Inhalt bereitgestellt"}
    
    # Generiere neuen Titel
    new_title = generate_title_on_demand(content)
    
    # Aktualisiere in der Datenbank
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute(
        "UPDATE memories SET title = ? WHERE id = ?", 
        (new_title, memory_id)
    )
    conn.commit()
    conn.close()
    
    return {
        "memory_id": memory_id,
        "new_title": new_title,
        "success": True
    }

# --- Fragenvorschläge API Endpoints ---

@app.get("/questions")
def get_questions():
    """Holt alle aktiven Fragenvorschläge"""
    conn = get_questions_db_connection()
    questions = conn.execute(
        "SELECT * FROM questions WHERE is_active = 1 ORDER BY RANDOM()"
    ).fetchall()
    conn.close()
    
    result = []
    for row in questions:
        result.append({
            "id": row["id"],
            "question_text": row["question_text"],
            "category": row["category"],
            "created_at": row["created_at"],
            "updated_at": row["updated_at"]
        })
    
    return result

@app.get("/questions/random")
def get_random_question():
    """Holt eine zufällige Frage"""
    conn = get_questions_db_connection()
    question = conn.execute(
        "SELECT * FROM questions WHERE is_active = 1 ORDER BY RANDOM() LIMIT 1"
    ).fetchone()
    conn.close()
    
    if question:
        return {
            "id": question["id"],
            "question_text": question["question_text"],
            "category": question["category"],
            "created_at": question["created_at"],
            "updated_at": question["updated_at"]
        }
    else:
        return {"error": "Keine Fragen gefunden"}

@app.post("/questions")
def add_question(question_data: dict):
    """Fügt eine neue Frage hinzu"""
    question_text = question_data.get("question_text", "")
    category = question_data.get("category", "allgemein")
    
    if not question_text:
        return {"error": "Fragentext ist erforderlich"}
    
    conn = get_questions_db_connection()
    cursor = conn.cursor()
    cursor.execute(
        "INSERT INTO questions (question_text, category) VALUES (?, ?)",
        (question_text, category)
    )
    conn.commit()
    question_id = cursor.lastrowid
    conn.close()
    
    return {
        "id": question_id,
        "question_text": question_text,
        "category": category,
        "success": True
    }

@app.put("/questions/{question_id}")
def update_question(question_id: int, question_data: dict):
    """Aktualisiert eine bestehende Frage"""
    question_text = question_data.get("question_text", "")
    category = question_data.get("category", "")
    
    conn = get_questions_db_connection()
    cursor = conn.cursor()
    
    if question_text:
        cursor.execute(
            "UPDATE questions SET question_text = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
            (question_text, question_id)
        )
    
    if category:
        cursor.execute(
            "UPDATE questions SET category = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
            (category, question_id)
        )
    
    conn.commit()
    conn.close()
    
    return {"success": True, "question_id": question_id}

@app.delete("/questions/{question_id}")
def delete_question(question_id: int):
    """Löscht eine Frage (setzt is_active auf 0)"""
    conn = get_questions_db_connection()
    cursor = conn.cursor()
    cursor.execute(
        "UPDATE questions SET is_active = 0, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
        (question_id,)
    )
    conn.commit()
    conn.close()
    
    return {"success": True, "question_id": question_id}

@app.delete("/memories/{memory_id}")
def delete_memory(memory_id: int):
    """Löscht eine Memory komplett aus der Datenbank"""
    conn = get_db_connection()
    cursor = conn.cursor()
    
    # Prüfe ob Memory existiert
    cursor.execute("SELECT id FROM memories WHERE id = ?", (memory_id,))
    if not cursor.fetchone():
        conn.close()
        return {"error": "Memory nicht gefunden"}
    
    # Lösche Memory
    cursor.execute("DELETE FROM memories WHERE id = ?", (memory_id,))
    conn.commit()
    conn.close()
    
    return {"success": True, "memory_id": memory_id}

# --- Tageszusammenfassungen Endpoints ---
@app.get("/daily-summaries", response_model=List[DailySummary])
def get_daily_summaries():
    """Alle Tageszusammenfassungen abrufen"""
    conn = get_daily_summaries_db_connection()
    summaries = conn.execute("SELECT * FROM daily_summaries ORDER BY date DESC").fetchall()
    conn.close()
    
    result = []
    for row in summaries:
        summary_data = {
            "id": row["id"],
            "date": row["date"],
            "summary": row["summary"],
            "created_at": row["created_at"],
            "updated_at": row["updated_at"]
        }
        result.append(summary_data)
    
    return result

@app.get("/daily-summaries/{date}", response_model=DailySummary)
def get_daily_summary(date: str):
    """Tageszusammenfassung für ein bestimmtes Datum abrufen"""
    conn = get_daily_summaries_db_connection()
    summary = conn.execute("SELECT * FROM daily_summaries WHERE date = ?", (date,)).fetchone()
    conn.close()
    
    if not summary:
        return {"error": "Keine Zusammenfassung für dieses Datum gefunden"}
    
    return {
        "id": summary["id"],
        "date": summary["date"],
        "summary": summary["summary"],
        "created_at": summary["created_at"],
        "updated_at": summary["updated_at"]
    }

@app.post("/daily-summaries", response_model=DailySummary)
def create_daily_summary(summary: DailySummary):
    """Neue Tageszusammenfassung erstellen oder aktualisieren"""
    conn = get_daily_summaries_db_connection()
    cursor = conn.cursor()
    
    # Prüfe ob bereits eine Zusammenfassung für dieses Datum existiert
    existing = cursor.execute("SELECT id FROM daily_summaries WHERE date = ?", (summary.date,)).fetchone()
    
    if existing:
        # Aktualisiere bestehende Zusammenfassung
        cursor.execute(
            "UPDATE daily_summaries SET summary = ?, updated_at = CURRENT_TIMESTAMP WHERE date = ?",
            (summary.summary, summary.date)
        )
        summary.id = existing["id"]
    else:
        # Erstelle neue Zusammenfassung
        cursor.execute(
            "INSERT INTO daily_summaries (date, summary) VALUES (?, ?)",
            (summary.date, summary.summary)
        )
        summary.id = cursor.lastrowid
    
    conn.commit()
    conn.close()
    
    return summary

@app.delete("/daily-summaries/{date}")
def delete_daily_summary(date: str):
    """Tageszusammenfassung für ein bestimmtes Datum löschen"""
    conn = get_daily_summaries_db_connection()
    cursor = conn.cursor()
    
    # Prüfe ob Zusammenfassung existiert
    cursor.execute("SELECT id FROM daily_summaries WHERE date = ?", (date,))
    if not cursor.fetchone():
        conn.close()
        return {"error": "Keine Zusammenfassung für dieses Datum gefunden"}
    
    cursor.execute("DELETE FROM daily_summaries WHERE date = ?", (date,))
    conn.commit()
    conn.close()
    
    return {"success": True, "date": date}

# Test-Endpoint für KI-Titel-Generierung
@app.post("/test-ai-title")
def test_ai_title(request: dict):
    """Test-Endpoint um KI-Titel-Generierung zu testen"""
    content = request.get("content", "")
    if not content:
        return {"error": "Kein Inhalt bereitgestellt"}
    
    print(f"Teste KI-Titel-Generierung für: '{content}'")
    ai_title = generate_ai_title(content)
    print(f"KI-Titel generiert: '{ai_title}'")
    
    return {
        "original_content": content,
        "ai_title": ai_title,
        "success": True
    }

# --- Like Endpoints ---
@app.post("/likes", response_model=LikeResponse)
def toggle_like(like_request: LikeRequest):
    """Toggle like for a memory"""
    try:
        conn = get_likes_db_connection()
        cursor = conn.cursor()
        
        # Prüfe ob Like bereits existiert
        cursor.execute(
            "SELECT id FROM likes WHERE memory_id = ? AND user_type = ?",
            (like_request.memory_id, like_request.user_type)
        )
        existing_like = cursor.fetchone()
        
        if existing_like:
            # Like entfernen
            cursor.execute(
                "DELETE FROM likes WHERE memory_id = ? AND user_type = ?",
                (like_request.memory_id, like_request.user_type)
            )
            is_liked = False
        else:
            # Like hinzufügen
            cursor.execute(
                "INSERT INTO likes (memory_id, user_type) VALUES (?, ?)",
                (like_request.memory_id, like_request.user_type)
            )
            is_liked = True
        
        # Like-Count für diese Memory berechnen
        cursor.execute(
            "SELECT COUNT(*) as count FROM likes WHERE memory_id = ?",
            (like_request.memory_id,)
        )
        like_count = cursor.fetchone()['count']
        
        conn.commit()
        conn.close()
        
        return LikeResponse(
            memory_id=like_request.memory_id,
            is_liked=is_liked,
            like_count=like_count
        )
        
    except Exception as e:
        return {"error": str(e)}

@app.get("/likes/{memory_id}")
def get_likes_for_memory(memory_id: int):
    """Get all likes for a specific memory"""
    try:
        conn = get_likes_db_connection()
        cursor = conn.cursor()
        
        cursor.execute(
            "SELECT user_type, created_at FROM likes WHERE memory_id = ? ORDER BY created_at DESC",
            (memory_id,)
        )
        likes = cursor.fetchall()
        
        conn.close()
        
        return {
            "memory_id": memory_id,
            "likes": [{"user_type": like['user_type'], "created_at": like['created_at']} for like in likes],
            "like_count": len(likes)
        }
        
    except Exception as e:
        return {"error": str(e)}

@app.get("/likes/user/{user_type}")
def get_likes_by_user_type(user_type: str):
    """Get all liked memory IDs for a specific user type"""
    try:
        conn = get_likes_db_connection()
        cursor = conn.cursor()
        
        cursor.execute(
            "SELECT memory_id FROM likes WHERE user_type = ?",
            (user_type,)
        )
        likes = cursor.fetchall()
        
        conn.close()
        
        return {
            "user_type": user_type,
            "liked_memory_ids": [like['memory_id'] for like in likes]
        }
        
    except Exception as e:
        return {"error": str(e)}

# --- Chat Endpoint ---
@app.post("/chat")
def chat_with_ai(request: dict):
    """Chat with AI based on Grandma's memories"""
    try:
        from groq_client import generate_chat_response
        
        message = request.get('message', '')
        recent_memories = request.get('recent_memories', [])
        
        if not message:
            return {"error": "No message provided"}
        
        # Generiere KI-Antwort basierend auf den Erinnerungen
        response = generate_chat_response(message, recent_memories)
        
        return {
            "response": response,
            "timestamp": datetime.now().isoformat()
        }
        
    except Exception as e:
        return {"error": str(e)}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
