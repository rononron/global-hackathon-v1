# Memory Keeper Backend

## Setup

1. **Virtuelle Umgebung erstellen:**
   ```bash
   python3 -m venv venv
   source venv/bin/activate  # Auf Windows: venv\Scripts\activate
   ```

2. **Dependencies installieren:**
   ```bash
   pip install -r requirements.txt
   ```

3. **Umgebungsvariablen konfigurieren:**
   - Kopiere `.env.example` zu `.env`
   - Setze deinen OpenAI API Key in der `.env` Datei:
     ```
     OPENAI_API_KEY=dein_openai_api_key_hier
     ```

4. **Server starten:**
   ```bash
   python main.py
   ```

## API Endpoints

- `GET /memories` - Alle Memories abrufen
- `POST /memories` - Neues Memory erstellen
- `POST /upload-media` - Media-Datei hochladen
- `GET /media/{filename}` - Media-Datei abrufen

## Sicherheit

⚠️ **Wichtig:** Die `.env` Datei enthält sensible Daten und ist bereits in `.gitignore` ausgeschlossen. Teile diese Datei niemals öffentlich!
