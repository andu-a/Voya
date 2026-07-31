from __future__ import annotations

import re


DEFAULT_RESPONSE_MAX_CHARS = 900

SENTENCE_BOUNDARY_RE = re.compile(r'[.!?][)"\']*(?=\s|$)')
TRAILING_INCOMPLETE_RE = re.compile(
    r'([,:;]|\b(si|și|sau|dar|iar|cu|la|in|în|pentru|de|din|spre|pe|and|or|but|with|to|for|of|from|on|at)\b)$',
    flags=re.IGNORECASE,
)


def normalize_response_text(text: str) -> str:
    lines = [line.strip() for line in str(text or "").strip().splitlines()]
    cleaned: list[str] = []

    for line in lines:
        if not line:
            if cleaned and cleaned[-1]:
                cleaned.append("")
            continue
        cleaned.append(re.sub(r"\s+", " ", line))

    return "\n".join(cleaned).strip()


def trim_to_complete_sentence(text: str, max_chars: int = DEFAULT_RESPONSE_MAX_CHARS) -> str:
    text = normalize_response_text(text)
    if not text:
        return ""

    candidate = text
    if len(candidate) > max_chars:
        candidate = candidate[:max_chars].rsplit(" ", 1)[0].strip()

    if looks_complete(candidate):
        return candidate

    last_boundary_end = None
    for match in SENTENCE_BOUNDARY_RE.finditer(candidate):
        last_boundary_end = match.end()

    if last_boundary_end:
        return candidate[:last_boundary_end].strip()

    return ""


def finalize_ai_response(
    text: str,
    *,
    max_chars: int = DEFAULT_RESPONSE_MAX_CHARS,
    fallback: str = "Nu am putut genera un raspuns complet. Incearca sa reformulezi cererea.",
) -> str:
    response = trim_to_complete_sentence(text, max_chars=max_chars)
    return response or fallback


def looks_complete(text: str) -> bool:
    stripped = text.rstrip()
    if not stripped:
        return False
    if TRAILING_INCOMPLETE_RE.search(stripped):
        return False
    return bool(SENTENCE_BOUNDARY_RE.search(stripped[-8:]))
