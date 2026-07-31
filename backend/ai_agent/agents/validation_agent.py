
from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass, field
from typing import Optional

@dataclass
class ValidationResult:
    is_valid: bool
    rejection_reason: Optional[str] = None
    formatted_prompt: Optional["FormattedTravelPrompt"] = None
    language: str = "ro"


@dataclass
class FormattedTravelPrompt:
    original_query: str
    intent: str
    destinations: list[str] = field(default_factory=list)
    origin: Optional[str] = None
    travel_dates: Optional[str] = None
    travelers_count: Optional[int] = None
    budget: Optional[str] = None
    extra_context: Optional[str] = None
    language: str = "ro"


TRAVEL_KEYWORDS = [
    "zbor", "zboruri", "hotel", "hoteluri", "cazare", "calatorie", "calatorii",
    "destinatie", "destinatii", "bilet", "bilete", "avion", "aeroport",
    "vacanta", "vacante", "turist", "turism", "itinerar", "viza", "vize",
    "transport", "tren", "autocar", "croaziera", "sejur", "rezervare",
    "flight", "travel", "trip", "hotel", "destination", "airport", "visa",
    "booking", "holiday", "vacation", "tour", "ticket",
    "vizita", "vizitez", "vizitat", "planifica", "planific", "zile", "zilele",
    "ce pot vizita", "ce fac", "oras", "oraș", "city break", "weekend",
    "buget", "cost", "costuri", "cheap", "visit", "itinerary", "days",
]

FLIGHT_INTENT_KEYWORDS = [
    "zbor", "zboruri", "flight", "flights", "avion", "aeroport", "airport",
    "bilet", "bilete", "ticket", "tickets", "airline", "companie aeriana",
]

HOTEL_INTENT_KEYWORDS = [
    "hotel", "hoteluri", "cazare", "accommodation", "hostel", "hosteluri",
    "resort", "camera", "camere", "stay", "stau", "cazez",
]

BUDGET_INTENT_KEYWORDS = [
    "buget", "budget", "cost", "costuri", "pret", "preț", "preturi",
    "prețuri", "ieftin", "cheap", "cat costa", "cât costă", "econom",
]

ITINERARY_INTENT_KEYWORDS = [
    "itinerar", "itinerary", "program", "planifica", "planifică", "planific",
    "ce pot vizita", "ce vizitez", "ce fac", "obiective", "zile", "days",
    "weekend", "city break",
]


def detectLanguage(text: str) -> str:
    lower = normalize_for_matching(text)
    english_markers = [
        "hello", "hi", "hey", "who are you", "what are you", "help", "small",
        "medium", "large", "yes", "no", "tomorrow", "today", "adults", "people",
    ]
    if any(marker in lower for marker in english_markers):
        return "en"
    return "ro"


def buildRejectionMessage(language: str, contextual: bool = False) -> str:
    if language == "en":
        if contextual:
            return "Your message does not seem related to travel in the current conversation context."
        return "Your message does not seem related to travel."
    if contextual:
        return "Mesajul nu pare să fie legat de călătorii în contextul conversației curente."
    return "Mesajul nu pare să fie legat de călătorii."


def normalize_for_matching(text: str) -> str:
    normalized = unicodedata.normalize("NFKD", str(text or ""))
    without_marks = "".join(char for char in normalized if not unicodedata.combining(char))
    return without_marks.lower().strip()


def keywordCheck(text: str) -> bool:
    normalized_text = normalize_for_matching(text)
    return any(normalize_for_matching(keyword) in normalized_text for keyword in TRAVEL_KEYWORDS)


def hasKeyword(text: str, keywords: list[str]) -> bool:
    normalized_text = normalize_for_matching(text)
    return any(normalize_for_matching(keyword) in normalized_text for keyword in keywords)


def historyIndicatesTravel(conversation_history: list[dict]) -> bool:
    history_text = " ".join(turn.get("content", "") for turn in conversation_history)
    return keywordCheck(history_text)


def extract_destinations_from_history(conversation_history: list[dict]) -> list[str]:
    found: list[str] = []
    for turn in conversation_history:
        for destination in extract_destinations(turn.get("content", "")):
            if destination not in found:
                found.append(destination)
    return found


def is_short_follow_up(text: str) -> bool:
    lower = normalize_for_matching(text)
    if len(lower.split()) <= 6:
        return True
    short_markers = [
        "si", "și", "ok", "bine", "da", "nu", "perfect", "super",
        "mai multe", "detalii", "cat costa", "cât costă", "ce altceva",
        "unde", "cand", "când", "cum ajung", "ce fac", "inca", "încă",
    ]
    return any(marker in lower for marker in short_markers)


def extract_destinations(text: str) -> list[str]:
    matches = re.findall(r'\b(?:la|in|în|spre|to)\s+([A-ZĂÂÎȘȚ][\wĂÂÎȘȚăâîșț-]*(?:\s+[A-ZĂÂÎȘȚ][\wĂÂÎȘȚăâîșț-]*)*)', text)
    cleaned: list[str] = []
    for match in matches:
        value = match.strip(" ,.!?:;")
        if value and value not in cleaned:
            cleaned.append(value)
    return cleaned


def extract_budget(text: str) -> Optional[str]:
    match = re.search(
        r'\b\d+(?:[.,]\d+)?\s*(?:€|eur|euro|usd|dolari|ron|lei)\b',
        text,
        flags=re.IGNORECASE,
    )
    return match.group(0) if match else None


def inferIntentFromPrompt(user_prompt: str, destinations: list[str]) -> str:
    if hasKeyword(user_prompt, FLIGHT_INTENT_KEYWORDS):
        return "flight_search"
    if hasKeyword(user_prompt, HOTEL_INTENT_KEYWORDS):
        return "hotel_search"
    if hasKeyword(user_prompt, BUDGET_INTENT_KEYWORDS):
        return "budget_planning"
    if hasKeyword(user_prompt, ITINERARY_INTENT_KEYWORDS):
        return "itinerary"
    if destinations:
        return "destination_info"
    return "general_travel"


def inferIntentFromHistory(conversation_history: list[dict]) -> str:
    history_text = " ".join(turn.get("content", "") for turn in conversation_history)
    destinations = extract_destinations(history_text)
    return inferIntentFromPrompt(history_text, destinations)


class ValidationAgent:
    def run(self, user_prompt: str, conversation_history: list[dict] | None = None) -> ValidationResult:
        conversation_history = conversation_history or []
        request_language = detectLanguage(user_prompt)

        destinations = extract_destinations(user_prompt)
        is_travel = keywordCheck(user_prompt) or bool(destinations)
        extra_context = None
        budget = extract_budget(user_prompt)

        if not is_travel and conversation_history and is_short_follow_up(user_prompt) and historyIndicatesTravel(conversation_history):
            is_travel = True
            extra_context = f"Follow-up answer in current conversation: {user_prompt}"
            if not destinations:
                destinations = extract_destinations_from_history(conversation_history)

        if not is_travel:
            return ValidationResult(
                is_valid=False,
                rejection_reason=buildRejectionMessage(request_language, contextual=bool(conversation_history)),
                language=request_language,
            )

        if not destinations and conversation_history and historyIndicatesTravel(conversation_history):
            destinations = extract_destinations_from_history(conversation_history)

        data = {
            "is_travel_related": True,
            "intent": inferIntentFromHistory(conversation_history)
            if extra_context
            else inferIntentFromPrompt(user_prompt, destinations),
            "destinations": destinations,
            "origin": None,
            "travel_dates": None,
            "travelers_count": None,
            "budget": budget,
            "extra_context": extra_context,
            "language": request_language,
        }

        if not data.get("is_travel_related", False):
            language = data.get("language") or request_language
            return ValidationResult(
                is_valid=False,
                rejection_reason=buildRejectionMessage(language, contextual=bool(conversation_history)),
                language=language,
            )

        formatted = FormattedTravelPrompt(
            original_query=user_prompt,
            intent=data.get("intent") or "general_travel",
            destinations=data.get("destinations") or [],
            origin=data.get("origin"),
            travel_dates=data.get("travel_dates"),
            travelers_count=data.get("travelers_count"),
            budget=data.get("budget"),
            extra_context=data.get("extra_context"),
            language=data.get("language") or request_language,
        )

        return ValidationResult(is_valid=True, formatted_prompt=formatted, language=formatted.language)
