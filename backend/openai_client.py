import os
import openai
from typing import Optional
from dotenv import load_dotenv

# .env Datei laden
load_dotenv()

# API-Key aus Umgebungsvariable laden
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
if not OPENAI_API_KEY:
    raise ValueError("Bitte setze die Umgebungsvariable OPENAI_API_KEY!")

openai.api_key = OPENAI_API_KEY

def generate_text(
    prompt: str,
    model: str = "gpt-3.5-turbo",
    max_tokens: int = 150,
    temperature: float = 0.7,
) -> Optional[str]:
    """
    Sendet eine Anfrage an die OpenAI GPT-API und gibt den generierten Text zurück.
    Kontingent-sicher: Bei Überschreitung oder Fehler wird None zurückgegeben.
    """
    try:
        response = openai.ChatCompletion.create(
            model=model,
            messages=[{"role": "user", "content": prompt}],
            max_tokens=max_tokens,
            temperature=temperature,
        )
        return response.choices[0].message.content.strip()
    except openai.error.RateLimitError:
        print("OpenAI-Kontingent erschöpft oder Rate Limit erreicht.")
        return None
    except Exception as e:
        print(f"Fehler bei der OpenAI-Anfrage: {e}")
        return None
