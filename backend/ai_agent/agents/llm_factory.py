from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from functools import lru_cache

import requests
from dotenv import load_dotenv


ENV_PATH = Path(__file__).resolve().parent.parent.parent / ".env"
load_dotenv(ENV_PATH, override=True)


@dataclass
class LlmResponse:
    content: str
    finish_reason: str | None = None


class GroqChatLlm:
    def __init__(self, api_key: str, temperature: float = 0.3, max_tokens: int = 320):
        self.api_key = api_key
        self.temperature = temperature
        self.max_tokens = max_tokens

    def invoke(self, prompt: str | list[dict]) -> LlmResponse:
        response = requests.post(
            "https://api.groq.com/openai/v1/chat/completions",
            headers={
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json",
            },
            json={
                "model": "llama-3.3-70b-versatile",
                "messages": normalize_messages(prompt),
                "temperature": self.temperature,
                "max_tokens": self.max_tokens,
            },
            timeout=60,
        )
        response.raise_for_status()
        payload = response.json()
        choice = payload["choices"][0]
        content = choice["message"]["content"]
        return LlmResponse(
            content=str(content).strip(),
            finish_reason=choice.get("finish_reason"),
        )


def normalize_messages(prompt: str | list[dict]) -> list[dict[str, str]]:
    if isinstance(prompt, str):
        return [{"role": "user", "content": prompt}]

    messages: list[dict[str, str]] = []
    for message in prompt:
        role = str(message.get("role") or "user").strip().lower()
        if role not in {"system", "user", "assistant"}:
            role = "user"
        content = str(message.get("content") or "").strip()
        if not content:
            continue
        messages.append({"role": role, "content": content})
    return messages


@lru_cache(maxsize=8)
def getGroqLlm(temperature: float = 0.3, max_tokens: int = 320):
    api_key = os.environ.get("GROQ_API_KEY", "")
    if not api_key:
        raise EnvironmentError(
            "GROQ_API_KEY nu este setat"
        )
    return GroqChatLlm(
        api_key=api_key,
        temperature=temperature,
        max_tokens=max_tokens,
    )


def get_chat_llm(temperature: float = 0.3, max_tokens: int = 320):
    
    groq_api_key = os.environ.get("GROQ_API_KEY", "")
    if groq_api_key:
        return getGroqLlm(temperature=temperature, max_tokens=max_tokens)

    raise EnvironmentError(
        "GROQ_API_KEY nu este configurat. Configureaza cheia Groq pentru AI agent."
    )



def get_language_instruction(language: str | None) -> str:
    lang = (language or "ro").strip().lower()
    language_map = {
        "ro": "Romanian",
        "en": "English",
        "es": "Spanish",
        "it": "Italian",
        "fr": "French",
        "de": "German",
        "pt": "Portuguese",
    }
    language_name = language_map.get(lang, "the same language as the latest user message")

    if lang in language_map:
        return (
            f"Respond STRICTLY in {language_name} ({lang}). "
            f"If the conversation history contains other languages, ignore them and answer only in {language_name}."
        )

    return "Respond STRICTLY in the same language as the latest user message, not the history."

def build_prompt(system: str, user: str) -> list:
    return [
        {"role": "system", "content": system},
        {"role": "user", "content": user},
    ]


def build_prompt_with_history(system: str, user: str, history: list[dict]) -> list:
    messages = [{"role": "system", "content": system}]
    for turn in history:
        role = turn.get("role", "")
        content = turn.get("content", "")
        if role == "user":
            messages.append({"role": "user", "content": content})
        elif role == "assistant":
            messages.append({"role": "assistant", "content": content})
    messages.append({"role": "user", "content": user})
    return messages
