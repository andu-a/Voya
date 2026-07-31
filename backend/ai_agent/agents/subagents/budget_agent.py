from __future__ import annotations
import re

from ai_agent.agents.llm_factory import get_chat_llm, build_prompt_with_history, get_language_instruction
from ai_agent.agents.response_utils import finalize_ai_response


def strip_prefix(text: str) -> str:
    """Sterge prefixele echo si fragmentele de prompt repetate."""
    text = text.strip()
    text = re.sub(r'\((?:Raspuns|ex|raspunde)[^)]*\)\s*', '', text, flags=re.IGNORECASE)
    text = re.sub(r'^Raspuns:\s*', '', text, flags=re.IGNORECASE)
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

BUDGET_SYSTEM_PROMPT = """Esti Voya, un asistent prietenos de calatorie.

TON SI STIL:
- Vorbeste natural, ca un prieten care se pricepe la planificarea bugetului de calatorie, nu ca un robot.
- Adreseaza-te direct utilizatorului ("Poti aloca...", "Recomand...", "Cel mai bun raport calitate-pret...").
- NU incepe niciodata cu: "Iti spun ca", "Iti pot spune ca", "Ca asistent", "Desigur", "Sigur", "Bineinteles".
- NU vorbi niciodata la persoana I despre tine (NU: "Vreau sa calatoresc", "Am un buget", "Prefer").
- Raspunde SCURT si la obiect, in maximum 4 propozitii scurte.
- Daca raspunsul nu incape, omite detalii; nu lasa fraze neterminate.
- La final pune o singura intrebare scurta, naturala, pentru a afla mai multe.
- {language_instruction}
"""



class BudgetPlanningAgent:
    """Sub-agent specializat pe planificarea bugetului pentru calatorii."""

    name = "budget_planning_agent"
    description = "Expert in costuri de calatorie, planificare buget si tips pentru economii."

    def __init__(self, llm=None):
        self.llm = llm

    def run(self, formatted_prompt_dict: dict) -> str:
        if self.llm is None:
            self.llm = get_chat_llm()
        history = formatted_prompt_dict.get("conversation_history", [])
        system_prompt = BUDGET_SYSTEM_PROMPT.format(
            language_instruction=get_language_instruction(formatted_prompt_dict.get("language")),
        )
        prompt = build_prompt_with_history(system_prompt, self.build_context_message(formatted_prompt_dict), history)
        result = self.llm.invoke(prompt)
        raw = result.content if hasattr(result, "content") else result
        return finalize_ai_response(strip_prefix(raw))

    def build_context_message(self, data: dict) -> str:
        parts = [f"Intrebarea utilizatorului: {data.get('original_query', '')}"]

        if data.get("destinations"):
            parts.append(f"Destinatii: {', '.join(data['destinations'])}")
        if data.get("origin"):
            parts.append(f"Tara de origine: {data['origin']}")
        if data.get("travel_dates"):
            parts.append(f"Perioada: {data['travel_dates']}")
        if data.get("travelers_count"):
            parts.append(f"Numar calatori: {data['travelers_count']}")
        if data.get("budget"):
            parts.append(f"Buget disponibil: {data['budget']}")
        if data.get("extra_context"):
            parts.append(f"Context suplimentar: {data['extra_context']}")

        return "\n".join(parts)
