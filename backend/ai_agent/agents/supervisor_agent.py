from __future__ import annotations

import logging
from typing import TypedDict, Literal

from ai_agent.agents.llm_factory import get_chat_llm, build_prompt, get_language_instruction
from ai_agent.agents.response_utils import finalize_ai_response
from ai_agent.agents.validation_agent import ValidationAgent, ValidationResult, normalize_for_matching
from ai_agent.agents.subagents.flight_agent import FlightAgent
from ai_agent.agents.subagents.hotel_agent import HotelAgent
from ai_agent.agents.subagents.general_travel_agent import GeneralTravelAgent
from ai_agent.agents.subagents.budget_agent import BudgetPlanningAgent


logger = logging.getLogger(__name__)

GREETING_INTRO_RO = (
    "Salut! Sunt Voya, asistentul tău inteligent de călătorii. 🌍✈️\n\n"
    "Te pot ajuta cu:\n"
    "• ✈️ Informații despre zboruri și rute aeriene\n"
    "• 🏨 Recomandări de hoteluri și cazare\n"
    "• 🗺️ Planificarea itinerarelor și destinații\n"
    "• 💰 Estimări de buget pentru călătorii\n\n"
    "Spune-mi unde vrei să mergi și te ajut să planifici totul!"
)

GREETING_INTRO_EN = (
    "Hi! I'm Voya, your intelligent travel assistant. 🌍✈️\n\n"
    "I can help you with:\n"
    "• ✈️ Flight information and routes\n"
    "• 🏨 Hotel and accommodation recommendations\n"
    "• 🗺️ Itinerary planning and destination ideas\n"
    "• 💰 Travel budget estimates\n\n"
    "Tell me where you want to go and I'll help you plan it!"
)

GREETING_PATTERNS = [
    "salut", "buna", "bună", "buna ziua", "bună ziua", "hello", "hi ", "hey",
    "cine esti", "cine ești", "ce esti", "ce ești", "prezinta", "prezintă",
    "ajutor", "help", "ce poti", "ce poți", "ce faci", "cum te cheama",
    "cum te cheamă", "what are you", "who are you",
]

def is_greeting(text: str) -> bool:
    lower = text.lower().strip()
    return any(p in lower for p in GREETING_PATTERNS)


def detect_message_language(text: str) -> str:
    lower = normalize_for_matching(text)
    english_markers = ["hello", "hi", "hey", "who are you", "what are you", "help"]
    if any(marker in lower for marker in english_markers):
        return "en"
    return "ro"


def get_greeting_intro(language: str) -> str:
    return GREETING_INTRO_EN if language == "en" else GREETING_INTRO_RO

class AgentState(TypedDict):
    user_prompt: str
    conversation_history: list[dict]   # [{"role": "user"|"assistant", "content": str}]
    validation_result: dict | None
    assigned_agents: list[str]
    agent_responses: dict[str, str]
    sources: list[dict]
    tool_metadata: dict[str, dict]
    final_response: str | None
    error: str | None


GENERIC_SUBAGENT_FAILURE_MESSAGE = (
    "Momentan nu am putut genera un raspuns complet. Incearca sa reformulezi cererea."
)

GENERIC_SUBAGENT_FAILURE_MESSAGE_EN = (
    "I couldn't generate a complete answer right now. Please try rephrasing your request."
)


def validate_node(state: AgentState) -> AgentState:

    if is_greeting(state["user_prompt"]):
        language = detect_message_language(state["user_prompt"])
        return {
            **state,
            "validation_result": {"is_valid": True, "intent": "greeting", "language": language},
            "assigned_agents": [],
            "agent_responses": {},
            "sources": [],
            "tool_metadata": {},
            "final_response": get_greeting_intro(language),
            "error": None,
        }

    agent = ValidationAgent()
    result: ValidationResult = agent.run(
        state["user_prompt"],
        conversation_history=state.get("conversation_history", []),
    )

    if not result.is_valid:
        language = result.language or detect_message_language(state["user_prompt"])
        final_response = (
            f"❌ I can't help with this request: {result.rejection_reason}"
            if language == "en"
            else f"❌ Nu pot ajuta cu aceasta cerere: {result.rejection_reason}"
        )
        return {
            **state,
            "validation_result": {
                "is_valid": False,
                "rejection_reason": result.rejection_reason,
                "language": language,
            },
            "sources": [],
            "tool_metadata": {},
            "error": result.rejection_reason,
            "final_response": final_response,
        }

    fp = result.formatted_prompt
    return {
        **state,
        "validation_result": {
            "is_valid": True,
            "original_query": fp.original_query,
            "intent": fp.intent,
            "destinations": fp.destinations,
            "origin": fp.origin,
            "travel_dates": fp.travel_dates,
            "travelers_count": fp.travelers_count,
            "budget": fp.budget,
            "extra_context": fp.extra_context,
            "language": fp.language,
        },
        "error": None,
    }


INTENT_TO_AGENTS: dict[str, list[str]] = {
    "flight_search":    ["flight_agent"],
    "hotel_search":     ["hotel_agent"],
    "itinerary":        ["general_travel_agent"],
    "destination_info": ["general_travel_agent"],
    "budget_planning":  ["budget_planning_agent"],
    "general_travel":   ["general_travel_agent"],
}

FLIGHT_ROUTING_KEYWORDS = [
    "zbor", "zboruri", "flight", "flights", "avion", "aeroport", "airport",
    "bilet", "bilete", "ticket", "tickets", "airline", "companie aeriana",
]

HOTEL_ROUTING_KEYWORDS = [
    "hotel", "hoteluri", "cazare", "accommodation", "hostel", "hosteluri",
    "resort", "camera", "camere", "stay", "stau", "cazez",
]

BUDGET_ROUTING_KEYWORDS = [
    "buget", "budget", "cost", "costuri", "pret", "preț", "preturi",
    "prețuri", "ieftin", "cheap", "cat costa", "cât costă", "econom",
]

GENERAL_ROUTING_KEYWORDS = [
    "itinerar", "itinerary", "program", "planifica", "planifică", "planific",
    "ce pot vizita", "ce vizitez", "ce fac", "obiective", "zile", "days",
    "weekend", "city break", "destinatie", "destinație", "destination",
    "viza", "visa", "vacanta", "vacanță", "travel", "trip",
]


def text_has_any(text: str, keywords: list[str]) -> bool:
    normalized_text = normalize_for_matching(text)
    return any(normalize_for_matching(keyword) in normalized_text for keyword in keywords)


def append_agent(agents: list[str], agent_name: str) -> None:
    if agent_name not in agents:
        agents.append(agent_name)


def infer_agents_from_validation(validation_result: dict) -> list[str]:
    intent = validation_result.get("intent", "general_travel")
    query_parts = [
        validation_result.get("original_query") or "",
        validation_result.get("extra_context") or "",
    ]
    query_text = " ".join(query_parts)

    agents: list[str] = []
    if text_has_any(query_text, FLIGHT_ROUTING_KEYWORDS):
        append_agent(agents, "flight_agent")
    if text_has_any(query_text, HOTEL_ROUTING_KEYWORDS):
        append_agent(agents, "hotel_agent")
    if validation_result.get("budget") or text_has_any(query_text, BUDGET_ROUTING_KEYWORDS):
        append_agent(agents, "budget_planning_agent")
    if text_has_any(query_text, GENERAL_ROUTING_KEYWORDS):
        append_agent(agents, "general_travel_agent")

    if not agents:
        for agent_name in INTENT_TO_AGENTS.get(intent, ["general_travel_agent"]):
            append_agent(agents, agent_name)

    return agents


def supervisor_routing_node(state: AgentState) -> AgentState:
    if state.get("error"):
        return state

    assigned = infer_agents_from_validation(state["validation_result"])
    return {**state, "assigned_agents": assigned}


def run_subagents_node(state: AgentState) -> AgentState:
    if state.get("error"):
        return state

    agents_map = {
        "flight_agent": FlightAgent(),
        "hotel_agent": HotelAgent(),
        "general_travel_agent": GeneralTravelAgent(),
        "budget_planning_agent": BudgetPlanningAgent(),
    }

    vr = state["validation_result"]
    # Injectam istoricul conversatiei in contextul trimis catre subagenti
    vr_with_history = {**vr, "conversation_history": state.get("conversation_history", [])}
    responses: dict[str, str] = {}
    sources: list[dict] = []
    tool_metadata: dict[str, dict] = {}

    for agent_name in state.get("assigned_agents", []):
        agent = agents_map.get(agent_name)
        if agent:
            try:
                response = agent.run(vr_with_history)
                if response:
                    responses[agent_name] = response
                agent_sources = getattr(agent, "last_sources", [])
                if agent_sources:
                    sources.extend(agent_sources)
                agent_web_search = getattr(agent, "last_web_search", None)
                if agent_web_search:
                    tool_metadata[agent_name] = {"web_search": agent_web_search}
            except Exception as exc:
                logger.exception("Subagent failed: %s", agent_name)

    if not responses:
        language = (state.get("validation_result") or {}).get("language", "ro")
        failure_message = (
            GENERIC_SUBAGENT_FAILURE_MESSAGE_EN
            if language == "en"
            else GENERIC_SUBAGENT_FAILURE_MESSAGE
        )
        return {
            **state,
            "agent_responses": {},
            "sources": sources,
            "tool_metadata": tool_metadata,
            "final_response": failure_message,
            "error": failure_message,
        }

    return {**state, "agent_responses": responses, "sources": sources, "tool_metadata": tool_metadata}


def combine_responses_node(state: AgentState) -> AgentState:
    
    if state.get("error"):
        return state

    responses = state.get("agent_responses", {})

    if not responses:
        return {**state, "final_response": "Nu am putut genera un raspuns."}

    if len(responses) == 1:
        # Un singur agent -> returnam direct raspunsul lui
        final = finalize_ai_response(list(responses.values())[0])
    else:
        # Mai multi agenti -> combinam cu sectiuni clare
        combine_llm = get_chat_llm(temperature=0.3)
        language = state["validation_result"].get("language", "ro")
        agent_labels = {
            "flight_agent": "✈️ Informatii Zboruri",
            "hotel_agent": "🏨 Informatii Cazare",
            "general_travel_agent": "🗺️ Informatii Destinatie",
            "budget_planning_agent": "💰 Planificare Buget",
        }

        parts = []
        for agent_name, response in responses.items():
            label = agent_labels.get(agent_name, agent_name)
            parts.append(f"=== {label} ===\n{response}")

        combined_raw = "\n\n".join(parts)

        system_msg = """Esti Voya, asistent virtual de calatorii.
Combina raspunsurile de mai jos intr-un raspuns unitar, coerent si scurt (maxim 6 randuri).
REGULI STRICTE:
- Adreseaza-te INTOTDEAUNA la persoana a II-a (ex: "Poti zbura...", "Iti recomand...", "Vei gasi...").
- NU vorbi la persoana I (NU spune "Vreau", "Prefer", "Imi place").
- Elimina redundantele.
- Raspunde in maximum 5 propozitii scurte si termina fiecare propozitie.
- Daca raspunsul nu incape, omite detalii; nu lasa fraze neterminate.
- La sfarsit pune o singura intrebare scurta.
- {language_instruction}""".format(
        language_instruction=get_language_instruction(language),
    )
        user_msg = f"Intrebarea originala: {state['validation_result'].get('original_query', '')}\n\nRaspunsurile agentilor:\n{combined_raw}"
        synthesis_response = combine_llm.invoke(build_prompt(system_msg, user_msg))
        final = synthesis_response.content if hasattr(synthesis_response, "content") else synthesis_response
        final = finalize_ai_response(final)

    return {**state, "final_response": final}
def should_continue(state: AgentState) -> Literal["supervisor", "end"]:
    if state.get("error"):
        return "end"
    if state.get("final_response"):  # greeting sau eroare cu raspuns direct
        return "end"
    return "supervisor"


class SupervisorPipeline:
    def invoke(self, initial_state: AgentState) -> AgentState:
        state = validate_node(initial_state)
        if should_continue(state) == "end":
            return state

        state = supervisor_routing_node(state)
        state = run_subagents_node(state)
        state = combine_responses_node(state)
        return state


def build_agent_pipeline() -> SupervisorPipeline:
    return SupervisorPipeline()


class SupervisorAgent:
    """
    Punctul de intrare principal in sistemul multi-agent.

    Utilizare:
        supervisor = SupervisorAgent()
        result = supervisor.run("Vreau sa calatoresc la Roma in iulie, ce imi recomanzi?")
        print(result['final_response'])
    """

    def __init__(self):
        self.pipeline = build_agent_pipeline()

    def run(self, user_prompt: str, conversation_history: list[dict] | None = None) -> dict:
        """
        Ruleaza pipeline-ul complet: validare -> routing -> sub-agenti -> sinteza.

        Returns:
            dict cu cheile:
              - final_response: str  (raspunsul final)
              - assigned_agents: list[str]
              - validation_result: dict
              - agent_responses: dict
              - error: str | None
        """
        initial_state: AgentState = {
            "user_prompt": user_prompt,
            "conversation_history": conversation_history or [],
            "validation_result": None,
            "assigned_agents": [],
            "agent_responses": {},
            "sources": [],
            "tool_metadata": {},
            "final_response": None,
            "error": None,
        }

        final_state = self.pipeline.invoke(initial_state)
        return final_state
