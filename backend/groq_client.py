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

def generate_chat_response(message: str, recent_memories: list) -> str:
    """
    Generiert eine Chat-Antwort basierend auf den Erinnerungen der Oma.
    Die KI antwortet nicht als Oma selbst, sondern beschreibt, wie Oma wahrscheinlich antworten würde.
    """
    try:
        # Erstelle Kontext aus den letzten Erinnerungen
        memories_context = ""
        if recent_memories:
            memories_context = "Here are Grandma's recent memories:\n"
            for memory in recent_memories:
                title = memory.get('title', 'Untitled')
                content = memory.get('content', '')
                date = memory.get('date', '')
                memories_context += f"- {title}: {content}\n"
        
        # Prompt für Chat-Antwort
        prompt = f"""You are an AI assistant helping family members understand their elderly relative's perspective based on her memories. 

{memories_context}

The family member asked: "{message}"

Based on Grandma's memories and experiences, describe how she would likely respond to this question. Do NOT write as if you are Grandma herself. Instead, describe her perspective and likely response in third person, explaining what she would probably say or think based on her memories and experiences.

Keep the response conversational, warm, and helpful. Focus on insights from her memories that would inform her response. If the question is about something not covered in her memories, explain that based on her general experiences and personality that can be inferred from her memories.

Response (2-3 sentences, conversational tone):"""

        # Groq API-Aufruf
        response = client.chat.completions.create(
            model="llama-3.1-8b-instant",
            messages=[
                {"role": "system", "content": "You are a helpful AI assistant that helps family members understand their elderly relative's perspective based on her memories."},
                {"role": "user", "content": prompt}
            ],
            max_tokens=200,
            temperature=0.7,
        )
        
        if response.choices and len(response.choices) > 0:
            ai_response = response.choices[0].message.content.strip()
            print(f"Groq Chat-Antwort generiert: {ai_response[:100]}...")
            return ai_response
        else:
            print("Groq Chat-Antwort fehlgeschlagen - keine Antwort erhalten")
            return "Based on Grandma's memories, she would likely appreciate your question, but I'm having trouble accessing her specific thoughts right now. Please try asking about something related to her recent experiences."
            
    except Exception as e:
        print(f"Fehler bei Groq Chat-Antwort: {e}")
        return "I'm having trouble accessing Grandma's memories right now. Please try again later or ask about something specific from her recent experiences."
