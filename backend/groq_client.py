from groq import Groq
from typing import Optional
import os
from dotenv import load_dotenv

# .env Datei laden
load_dotenv()

# Groq API Key aus Umgebungsvariable laden
GROQ_API_KEY = os.getenv("GROQ_API_KEY")
if not GROQ_API_KEY:
    print("WARNUNG: GROQ_API_KEY nicht gefunden - Titel-Generierung deaktiviert")
    client = None
else:
    # Groq Client initialisieren
    client = Groq(api_key=GROQ_API_KEY)

def generate_text(
    prompt: str,
    model: str = "llama-3.1-8b-instant",
    max_tokens: int = 20,
    temperature: float = 0.3,
) -> Optional[str]:
    """
    Sendet eine Anfrage an die Groq API und gibt den generierten Text zurück.
    Extrem schnell - meist unter 1 Sekunde.
    """
    if not client:
        print("Groq Client nicht verfügbar - API Key fehlt")
        return None
        
    try:
        response = client.chat.completions.create(
            model=model,
            messages=[{"role": "user", "content": prompt}],
            max_tokens=max_tokens,
            temperature=temperature,
        )
        return response.choices[0].message.content.strip()
    except Exception as e:
        print(f"Fehler bei der Groq-Anfrage: {e}")
        return None

def generate_smart_title(content: str) -> str:
    """
    Generiert einen intelligenten Titel mit Groq.
    Extrem schnell - meist unter 1 Sekunde.
    """
    print(f"Generiere Titel mit Groq für: '{content[:50]}...'")
    
    if not client:
        print("Groq nicht verfügbar - Titel bleibt leer")
        return ""
    
    try:
        # Optimized prompt for Groq - only neutral summaries in English
        prompt = f"""Create a short, neutral title (maximum 4 words) for the following text.

IMPORTANT RULES:
- The title should ONLY be a factual summary of the content
- NO reactions, comments, or evaluations
- NO emotional expressions like "great", "nice", "wonderful"
- NO personal opinions or interpretations
- Use simple, clear language
- Focus on the main activity or main topic
- RESPOND IN ENGLISH ONLY

Text: {content}

Title:"""
        
        ai_title = generate_text(prompt, max_tokens=15, temperature=0.3)
        
        if ai_title and len(ai_title.strip()) > 0:
            # Bereinige den Titel
            clean_title = ai_title.strip().strip('"').strip("'")
            print(f"Groq Titel generiert: '{clean_title}'")
            return clean_title
        else:
            print("Groq Titel-Generierung fehlgeschlagen - bleibt leer")
            return ""
            
    except Exception as e:
        print(f"Fehler bei Groq Titel-Generierung: {e}")
        return ""
