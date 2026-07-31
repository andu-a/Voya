from __future__ import annotations

import logging
import os
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import requests
from dotenv import load_dotenv


logger = logging.getLogger(__name__)

ENV_PATH = Path(__file__).resolve().parent.parent.parent / ".env"
load_dotenv(ENV_PATH, override=False)

TAVILY_SEARCH_URL = "https://api.tavily.com/search"
DEFAULT_MAX_RESULTS = 4
DEFAULT_TIMEOUT_SECONDS = 8
DEFAULT_CACHE_TTL_SECONDS = 60 * 60 * 6

CACHE: dict[tuple[str, int, str, str | None], tuple[float, "WebSearchResponse"]] = {}


@dataclass(frozen=True)
class WebSearchResult:
    title: str
    url: str
    content: str
    score: float | None = None
    published_date: str | None = None

    def as_dict(self) -> dict[str, Any]:
        return {
            "title": self.title,
            "url": self.url,
            "content": self.content,
            "score": self.score,
            "published_date": self.published_date,
        }


@dataclass(frozen=True)
class WebSearchResponse:
    query: str
    results: list[WebSearchResult]
    answer: str | None = None
    error: str | None = None
    provider: str = "tavily"

    @property
    def has_results(self) -> bool:
        return bool(self.results)

    def source_dicts(self) -> list[dict[str, Any]]:
        return [
            {
                "title": result.title,
                "url": result.url,
                "provider": self.provider,
            }
            for result in self.results
            if result.title and result.url
        ]


def search_web(
    query: str,
    *,
    max_results: int = DEFAULT_MAX_RESULTS,
    topic: str = "general",
    time_range: str | None = None,
    timeout: int = DEFAULT_TIMEOUT_SECONDS,
    cache_ttl_seconds: int = DEFAULT_CACHE_TTL_SECONDS,
) -> WebSearchResponse:
    cleaned_query = " ".join(str(query or "").split())
    if not cleaned_query:
        return WebSearchResponse(query="", results=[], error="empty_query")

    api_key = os.environ.get("TAVILY_API_KEY", "").strip()
    if not api_key:
        return WebSearchResponse(query=cleaned_query, results=[], error="missing_api_key")

    max_results = max(1, min(int(max_results), 8))
    cache_key = (cleaned_query.lower(), max_results, topic, time_range)
    cached = get_cached(cache_key)
    if cached:
        return cached

    payload: dict[str, Any] = {
        "query": cleaned_query,
        "search_depth": "basic",
        "topic": topic,
        "max_results": max_results,
        "include_answer": "basic",
        "include_raw_content": False,
        "include_images": False,
    }
    if time_range:
        payload["time_range"] = time_range

    try:
        response = requests.post(
            TAVILY_SEARCH_URL,
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            json=payload,
            timeout=timeout,
        )
        if response.status_code in {401, 403}:
            return WebSearchResponse(query=cleaned_query, results=[], error="auth_failed")
        if response.status_code == 429:
            return WebSearchResponse(query=cleaned_query, results=[], error="rate_limited")
        response.raise_for_status()
        data = response.json()
    except requests.Timeout:
        logger.warning("Tavily search timed out for query: %s", cleaned_query)
        return WebSearchResponse(query=cleaned_query, results=[], error="timeout")
    except requests.RequestException:
        logger.exception("Tavily search request failed")
        return WebSearchResponse(query=cleaned_query, results=[], error="request_failed")
    except ValueError:
        logger.exception("Tavily search returned invalid JSON")
        return WebSearchResponse(query=cleaned_query, results=[], error="invalid_json")

    search_response = WebSearchResponse(
        query=str(data.get("query") or cleaned_query),
        answer=clean_text(data.get("answer"), max_length=900),
        results=normalize_results(data.get("results")),
    )
    set_cached(cache_key, search_response, cache_ttl_seconds)
    return search_response


def clear_web_search_cache() -> None:
    CACHE.clear()


def get_cached(cache_key: tuple[str, int, str, str | None]) -> WebSearchResponse | None:
    cached = CACHE.get(cache_key)
    if not cached:
        return None

    expires_at, response = cached
    if expires_at < time.time():
        CACHE.pop(cache_key, None)
        return None
    return response


def set_cached(
    cache_key: tuple[str, int, str, str | None],
    response: WebSearchResponse,
    ttl_seconds: int,
) -> None:
    if ttl_seconds <= 0:
        return
    CACHE[cache_key] = (time.time() + ttl_seconds, response)


def normalize_results(raw_results: Any) -> list[WebSearchResult]:
    if not isinstance(raw_results, list):
        return []

    results: list[WebSearchResult] = []
    for raw_result in raw_results:
        if not isinstance(raw_result, dict):
            continue

        title = clean_text(raw_result.get("title"), max_length=180)
        url = str(raw_result.get("url") or "").strip()
        content = clean_text(raw_result.get("content"), max_length=900)
        if not title or not url:
            continue

        results.append(
            WebSearchResult(
                title=title,
                url=url,
                content=content,
                score=to_float(raw_result.get("score")),
                published_date=clean_text(
                    raw_result.get("published_date") or raw_result.get("publishedDate"),
                    max_length=40,
                ),
            )
        )

    return results


def clean_text(value: Any, *, max_length: int) -> str:
    text = " ".join(str(value or "").split())
    if len(text) <= max_length:
        return text
    return text[:max_length].rsplit(" ", 1)[0].strip()


def to_float(value: Any) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None
