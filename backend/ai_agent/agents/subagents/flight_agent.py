from __future__ import annotations
import re

from ai_agent.agents.llm_factory import get_chat_llm, build_prompt_with_history, get_language_instruction
from ai_agent.agents.response_utils import finalize_ai_response
from ai_agent.agents.validation_agent import normalize_for_matching
from ai_agent.tools.web_search import WebSearchResponse, search_web


def strip_prefix(text: str) -> str:
    text = text.strip()
    text = re.sub(r'\((?:Raspuns|ex|raspunde)[^)]*\)\s*', '', text, flags=re.IGNORECASE)
    text = re.sub(r'^Raspuns:\s*', '', text, flags=re.IGNORECASE)
    # Remove robotic openers
    bad_openers = [
        r'^[Îî]ți spun că\s*,?\s*',
        r'^[Îî]ți pot spune că\s*,?\s*',
        r'^Trebuie să ții cont că\s*,?\s*',
        r'^[Cc]a asistent(ul)? (virtual )?de călătorii,?\s*',
        r'^[Dd]esigur[,!]?\s*',
        r'^[Ss]igur[,!]?\s*',
        r'^Bineînțeles[,!]?\s*',
        r'^[Cc]u plăcere[,!]?\s*',
        r'^[Ff]oarte bine[,!]?\s*',
    ]
    for pattern in bad_openers:
        text = re.sub(pattern, '', text, flags=re.IGNORECASE)
    return text.strip()

FLIGHT_SYSTEM_PROMPT = """Esti Voya, un asistent prietenos de calatorie.

TON SI STIL:
- Vorbeste natural, ca un prieten care se pricepe la zboruri, nu ca un robot.
- Adreseaza-te direct utilizatorului ("Poti zbura...", "Recomand...", "Cel mai bun moment...").
- NU incepe niciodata cu: "Iti spun ca", "Iti pot spune ca", "Ca asistent", "Desigur", "Sigur", "Bineinteles".
- NU vorbi niciodata la persoana I despre tine (NU: "Vreau sa zbor", "Prefer", "Imi place").
- Raspunde SCURT si la obiect, in maximum 4 propozitii scurte.
- Daca raspunsul nu incape, omite detalii; nu lasa fraze neterminate.
- Daca primesti context web actualizat, foloseste-l prioritar si nu inventa informatii care nu apar in surse.
- Pentru preturi, statusuri, orare sau disponibilitati, spune clar ca trebuie confirmate pe site-ul companiei/agregatorului.
- Daca era nevoie de web dar nu exista context web live, spune pe scurt ca raspunzi din cunostinte generale neverificate live.
- La final pune o singura intrebare scurta, naturala, pentru a afla mai multe.
- {language_instruction}
"""

FLIGHT_WEB_SEARCH_KEYWORDS = [
    "acum", "azi", "astazi", "astăzi", "curent", "curenta", "curentă", "actual",
    "actuale", "momentan", "recent", "recente", "ultim", "ultima", "ultimele",
    "latest", "today", "now", "current", "recent",
    "zboruri", "flight", "flights", "bilet", "bilete", "ticket", "tickets",
    "pret", "preț", "preturi", "prețuri", "price", "prices", "fare", "fares",
    "ruta", "rute", "route", "routes", "direct", "directe", "escala", "escală",
    "layover", "stopover", "orar", "program", "schedule", "timetable",
    "status", "intarziere", "întârziere", "delay", "delayed", "anulat",
    "anulare", "cancelled", "canceled", "greva", "grevă", "strike",
    "aeroport", "airport", "terminal", "bagaj", "bagaje", "baggage", "luggage",
    "check-in", "checkin", "boarding", "airline", "companie aeriana",
]


class FlightAgent:
    """Sub-agent specializat pe informatii despre zboruri."""

    name = "flight_agent"
    description = "Expert in zboruri, rute aeriene, companii aeriene si tips pentru bilete."

    def __init__(self, llm=None):
        self.llm = llm
        self.last_sources: list[dict] = []
        self.last_web_search: dict | None = None

    def run(self, formatted_prompt_dict: dict) -> str:
        if self.llm is None:
            self.llm = get_chat_llm()
        history = formatted_prompt_dict.get("conversation_history", [])
        web_response = self.maybe_search_web(formatted_prompt_dict)
        system_prompt = FLIGHT_SYSTEM_PROMPT.format(
            language_instruction=get_language_instruction(formatted_prompt_dict.get("language")),
        )
        prompt = build_prompt_with_history(
            system_prompt,
            self.build_context_message(formatted_prompt_dict, web_response=web_response),
            history,
        )
        result = self.llm.invoke(prompt)
        raw = result.content if hasattr(result, "content") else result
        return finalize_ai_response(strip_prefix(raw))

    def build_context_message(self, data: dict, web_response: WebSearchResponse | None = None) -> str:
        parts = [f"Intrebarea utilizatorului: {data.get('original_query', '')}"]

        if data.get("origin"):
            parts.append(f"Origine: {data['origin']}")
        if data.get("destinations"):
            parts.append(f"Destinatii: {', '.join(data['destinations'])}")
        if data.get("travel_dates"):
            parts.append(f"Date calatorie: {data['travel_dates']}")
        if data.get("travelers_count"):
            parts.append(f"Numar calatori: {data['travelers_count']}")
        if data.get("budget"):
            parts.append(f"Buget: {data['budget']}")
        if data.get("extra_context"):
            parts.append(f"Context suplimentar: {data['extra_context']}")
        if web_response:
            parts.append(self.format_web_context(web_response))

        return "\n".join(parts)

    def maybe_search_web(self, data: dict) -> WebSearchResponse | None:
        self.last_sources = []
        self.last_web_search = None

        query = build_flight_web_query(data)
        if not needs_flight_web_search(query):
            return None

        web_response = search_web(query, max_results=4)
        self.last_web_search = {
            "provider": web_response.provider,
            "query": web_response.query,
            "used": web_response.has_results,
            "error": web_response.error,
        }
        self.last_sources = web_response.source_dicts()
        return web_response

    def format_web_context(self, web_response: WebSearchResponse) -> str:
        if not web_response.has_results:
            reason = web_response.error or "no_results"
            return (
                "Context web live pentru zboruri: indisponibil "
                f"({reason}). Raspunde din cunostinte generale, mentioneaza ca nu ai putut verifica live "
                "si nu inventa preturi, statusuri sau disponibilitati exacte."
            )

        lines = ["Context web actualizat pentru zboruri (Tavily):"]
        if web_response.answer:
            lines.append(f"Sinteza Tavily: {web_response.answer}")

        for index, result in enumerate(web_response.results, start=1):
            lines.append(f"{index}. {result.title}")
            lines.append(f"URL: {result.url}")
            if result.published_date:
                lines.append(f"Data publicare/actualizare: {result.published_date}")
            if result.content:
                lines.append(f"Rezumat: {result.content}")

        return "\n".join(lines)


def build_flight_web_query(data: dict) -> str:
    parts = [
        data.get("original_query") or "",
        data.get("origin") or "",
        ", ".join(data.get("destinations") or []),
        data.get("travel_dates") or "",
        data.get("extra_context") or "",
    ]
    return " ".join(part for part in parts if part).strip()


def needs_flight_web_search(query: str) -> bool:
    lower = normalize_for_matching(query)
    if not lower:
        return False
    if re.search(r"\b20[2-9]\d\b", lower):
        return True
    return any(normalize_for_matching(keyword) in lower for keyword in FLIGHT_WEB_SEARCH_KEYWORDS)
