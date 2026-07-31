
import os
from unittest.mock import Mock, patch

from django.test import Client, TestCase
from django.contrib.auth import get_user_model
from django.urls import reverse
from rest_framework.test import APIClient
from rest_framework import status

from .models import ConversationLog
from .agents.validation_agent import ValidationAgent, ValidationResult
from .agents.supervisor_agent import supervisor_routing_node
from .agents.subagents.flight_agent import FlightAgent
from .agents.subagents.general_travel_agent import GeneralTravelAgent
from .agents.response_utils import finalize_ai_response
from .tools.web_search import (
    WebSearchResponse,
    WebSearchResult,
    clear_web_search_cache,
    search_web,
)


User = get_user_model()


class CapturingLlm:
    def __init__(self, content="Raspuns generat complet."):
        self.content = content
        self.prompt = None

    def invoke(self, prompt):
        self.prompt = prompt
        return type("LlmResult", (), {"content": self.content})()


class ResponseFinalizationTests(TestCase):
    def test_trims_long_response_only_after_complete_sentence(self):
        response = finalize_ai_response(
            "Prima propozitie e completa. A doua propozitie continua cu multe detalii",
            max_chars=55,
        )

        self.assertEqual(response, "Prima propozitie e completa.")

    def test_removes_incomplete_trailing_sentence(self):
        response = finalize_ai_response(
            "Poti vizita Colosseumul. Apoi poti merge la",
        )

        self.assertEqual(response, "Poti vizita Colosseumul.")

    def test_uses_fallback_when_no_complete_sentence_exists(self):
        response = finalize_ai_response(
            "Poti merge la",
            fallback="Raspuns incomplet.",
        )

        self.assertEqual(response, "Raspuns incomplet.")


class ValidationAgentTests(TestCase):
    """Teste pentru ValidationAgent."""

    def test_valid_travel_prompt(self):
        """Prompt valid despre calatorii trebuie acceptat."""
        agent = ValidationAgent()
        result = agent.run("Vreau sa merg la Roma in iulie")

        self.assertTrue(result.is_valid)
        self.assertIsNotNone(result.formatted_prompt)
        self.assertEqual(result.formatted_prompt.intent, "destination_info")
        self.assertIn("Roma", result.formatted_prompt.destinations)

    def test_invalid_non_travel_prompt(self):
        """Prompt care nu e despre calatorii trebuie respins (keyword fallback)."""
        agent = ValidationAgent()
        result = agent.run("Cum fac o pizza napoletana?")

        self.assertFalse(result.is_valid)
        self.assertIsNotNone(result.rejection_reason)

    def test_short_follow_up_uses_conversation_context(self):
        """Un raspuns scurt precum 'small' trebuie acceptat daca istoricul e despre travel."""
        agent = ValidationAgent()
        result = agent.run(
            "small",
            conversation_history=[
                {"role": "assistant", "content": "What group size are you planning for your Barcelona trip?"},
                {"role": "user", "content": "I want to travel to Barcelona with friends."},
            ],
        )

        self.assertTrue(result.is_valid)
        self.assertEqual(result.formatted_prompt.language, "en")
        self.assertIn("Follow-up answer", result.formatted_prompt.extra_context)

    def test_english_invalid_prompt_returns_english_rejection(self):
        agent = ValidationAgent()
        result = agent.run("small")

        self.assertFalse(result.is_valid)
        self.assertEqual(result.language, "en")
        self.assertIn("does not seem related to travel", result.rejection_reason)

    def test_accepts_diacritic_popular_destinations_query(self):
        agent = ValidationAgent()
        result = agent.run("Ce destinații sunt populare acum în 2026?")

        self.assertTrue(result.is_valid)
        self.assertEqual(result.formatted_prompt.intent, "general_travel")

    def test_flight_prompt_infers_flight_intent(self):
        agent = ValidationAgent()
        result = agent.run("Cauta zboruri catre Paris")

        self.assertTrue(result.is_valid)
        self.assertEqual(result.formatted_prompt.intent, "flight_search")

    def test_hotel_prompt_infers_hotel_intent(self):
        agent = ValidationAgent()
        result = agent.run("Vreau cazare la Roma")

        self.assertTrue(result.is_valid)
        self.assertEqual(result.formatted_prompt.intent, "hotel_search")

    def test_budget_prompt_infers_budget_intent_and_amount(self):
        agent = ValidationAgent()
        result = agent.run("Am buget 500 EUR pentru Barcelona")

        self.assertTrue(result.is_valid)
        self.assertEqual(result.formatted_prompt.intent, "budget_planning")
        self.assertEqual(result.formatted_prompt.budget, "500 EUR")


class SupervisorRoutingTests(TestCase):
    def build_state(self, query, intent="general_travel", budget=None):
        return {
            "user_prompt": query,
            "conversation_history": [],
            "validation_result": {
                "is_valid": True,
                "original_query": query,
                "intent": intent,
                "destinations": [],
                "origin": None,
                "travel_dates": None,
                "travelers_count": None,
                "budget": budget,
                "extra_context": None,
                "language": "ro",
            },
            "assigned_agents": [],
            "agent_responses": {},
            "final_response": None,
            "error": None,
        }

    def test_routes_flight_intent_to_flight_agent(self):
        state = self.build_state("Cauta zboruri catre Paris", "flight_search")

        routed = supervisor_routing_node(state)

        self.assertEqual(routed["assigned_agents"], ["flight_agent"])

    def test_routes_hotel_intent_to_hotel_agent(self):
        state = self.build_state("Vreau hotel in Roma", "hotel_search")

        routed = supervisor_routing_node(state)

        self.assertEqual(routed["assigned_agents"], ["hotel_agent"])

    def test_routes_mixed_request_to_multiple_specialized_agents(self):
        state = self.build_state(
            "Vreau zbor, hotel si buget de 500 EUR pentru Roma",
            "flight_search",
            budget="500 EUR",
        )

        routed = supervisor_routing_node(state)

        self.assertEqual(
            routed["assigned_agents"],
            ["flight_agent", "hotel_agent", "budget_planning_agent"],
        )

    def test_routes_itinerary_request_to_general_agent(self):
        state = self.build_state("Fa-mi un itinerar de weekend la Paris", "itinerary")

        routed = supervisor_routing_node(state)

        self.assertEqual(routed["assigned_agents"], ["general_travel_agent"])

    def test_routes_diacritic_destination_query_to_general_agent(self):
        state = self.build_state("Ce destinații sunt populare acum în 2026?", "general_travel")

        routed = supervisor_routing_node(state)

        self.assertEqual(routed["assigned_agents"], ["general_travel_agent"])


class WebSearchToolTests(TestCase):
    def setUp(self):
        clear_web_search_cache()

    @patch.dict(os.environ, {"TAVILY_API_KEY": "test-key"})
    @patch("ai_agent.tools.web_search.requests.post")
    def test_search_web_returns_normalized_tavily_results(self, mock_post):
        mock_response = Mock(status_code=200)
        mock_response.raise_for_status.return_value = None
        mock_response.json.return_value = {
            "query": "visa rules japan 2026",
            "answer": "Travelers should check current entry requirements.",
            "results": [
                {
                    "title": "Japan entry requirements",
                    "url": "https://example.com/japan-entry",
                    "content": "Current visa and entry information.",
                    "score": 0.92,
                }
            ],
        }
        mock_post.return_value = mock_response

        response = search_web("visa rules japan 2026", max_results=3, cache_ttl_seconds=0)

        self.assertTrue(response.has_results)
        self.assertEqual(response.provider, "tavily")
        self.assertEqual(response.results[0].title, "Japan entry requirements")
        self.assertEqual(response.source_dicts()[0]["url"], "https://example.com/japan-entry")
        self.assertEqual(
            mock_post.call_args.kwargs["headers"]["Authorization"],
            "Bearer test-key",
        )

    @patch.dict(os.environ, {}, clear=True)
    @patch("ai_agent.tools.web_search.requests.post")
    def test_search_web_returns_fallback_error_without_api_key(self, mock_post):
        response = search_web("visa rules japan 2026", cache_ttl_seconds=0)

        self.assertFalse(response.has_results)
        self.assertEqual(response.error, "missing_api_key")
        mock_post.assert_not_called()


class GeneralTravelAgentWebTests(TestCase):
    @patch("ai_agent.agents.subagents.general_travel_agent.search_web")
    def test_general_agent_adds_web_context_and_sources_for_current_queries(self, mock_search):
        mock_search.return_value = WebSearchResponse(
            query="Care sunt regulile de viza pentru Japonia acum?",
            answer="Entry rules should be checked before travel.",
            results=[
                WebSearchResult(
                    title="Japan travel advice",
                    url="https://example.com/japan-travel-advice",
                    content="Recent entry guidance for travelers.",
                )
            ],
        )
        llm = CapturingLlm("Poti verifica regulile recente inainte de plecare.")
        agent = GeneralTravelAgent(llm=llm)

        response = agent.run(
            {
                "original_query": "Care sunt regulile de viza pentru Japonia acum?",
                "destinations": ["Japonia"],
                "language": "ro",
            }
        )

        latest_user_message = llm.prompt[-1]["content"]
        self.assertIn("Context web actualizat", latest_user_message)
        self.assertIn("Japan travel advice", latest_user_message)
        self.assertEqual(agent.last_sources[0]["url"], "https://example.com/japan-travel-advice")
        self.assertIn("regulile recente", response)

    @patch("ai_agent.agents.subagents.general_travel_agent.search_web")
    def test_general_agent_adds_memory_fallback_when_web_is_unavailable(self, mock_search):
        mock_search.return_value = WebSearchResponse(
            query="Care sunt regulile de viza pentru Japonia acum?",
            results=[],
            error="timeout",
        )
        llm = CapturingLlm("Nu am putut verifica live, dar din cunostinte generale poti verifica viza.")
        agent = GeneralTravelAgent(llm=llm)

        response = agent.run(
            {
                "original_query": "Care sunt regulile de viza pentru Japonia acum?",
                "destinations": ["Japonia"],
                "language": "ro",
            }
        )

        latest_user_message = llm.prompt[-1]["content"]
        self.assertIn("Context web live: indisponibil (timeout)", latest_user_message)
        self.assertEqual(agent.last_sources, [])
        self.assertIn("cunostinte generale", response)


class FlightAgentWebTests(TestCase):
    @patch("ai_agent.agents.subagents.flight_agent.search_web")
    def test_flight_agent_adds_web_context_and_sources_for_current_queries(self, mock_search):
        mock_search.return_value = WebSearchResponse(
            query="zboruri directe Bucuresti Paris azi",
            answer="Direct flights may be available on several carriers.",
            results=[
                WebSearchResult(
                    title="Bucharest to Paris flights",
                    url="https://example.com/bucharest-paris-flights",
                    content="Current flight route information.",
                )
            ],
        )
        llm = CapturingLlm("Poti cauta zboruri directe, dar confirma orarul inainte de rezervare.")
        agent = FlightAgent(llm=llm)

        response = agent.run(
            {
                "original_query": "Ce zboruri directe sunt Bucuresti Paris azi?",
                "origin": "Bucuresti",
                "destinations": ["Paris"],
                "language": "ro",
            }
        )

        latest_user_message = llm.prompt[-1]["content"]
        self.assertIn("Context web actualizat pentru zboruri", latest_user_message)
        self.assertIn("Bucharest to Paris flights", latest_user_message)
        self.assertEqual(agent.last_sources[0]["url"], "https://example.com/bucharest-paris-flights")
        self.assertTrue(agent.last_web_search["used"])
        self.assertIn("zboruri directe", response)

    @patch("ai_agent.agents.subagents.flight_agent.search_web")
    def test_flight_agent_adds_memory_fallback_when_web_is_unavailable(self, mock_search):
        mock_search.return_value = WebSearchResponse(
            query="status zbor azi",
            results=[],
            error="timeout",
        )
        llm = CapturingLlm("Nu am putut verifica live, dar din cunostinte generale verifica statusul la companie.")
        agent = FlightAgent(llm=llm)

        response = agent.run(
            {
                "original_query": "Care e statusul zborului azi?",
                "language": "ro",
            }
        )

        latest_user_message = llm.prompt[-1]["content"]
        self.assertIn("Context web live pentru zboruri: indisponibil (timeout)", latest_user_message)
        self.assertEqual(agent.last_sources, [])
        self.assertFalse(agent.last_web_search["used"])
        self.assertIn("cunostinte generale", response)


class ConversationLogModelTests(TestCase):

    def test_create_log(self):
        log = ConversationLog.objects.create(
            user_prompt="Test prompt",
            status="success",
            response="Test response",
            assigned_agent="general_travel_agent",
        )
        self.assertIsNotNone(log.id)
        self.assertEqual(log.status, "success")

    def test_str_representation(self):
        log = ConversationLog.objects.create(
            user_prompt="Vreau sa calatoresc la Paris",
            status="success",
        )
        self.assertIn("success", str(log))


class ConversationHistoryPrivacyTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(
            username="alice",
            email="alice@example.com",
            password="testpass123",
        )
        self.other_user = User.objects.create_user(
            username="bob",
            email="bob@example.com",
            password="testpass123",
        )
        self.own_log = ConversationLog.objects.create(
            user=self.user,
            user_prompt="Planifica-mi o excursie la Roma",
            response="Poti vizita Colosseumul.",
            status="success",
        )
        self.other_log = ConversationLog.objects.create(
            user=self.other_user,
            user_prompt="Vreau hotel in Paris",
            response="Iti recomand zona Marais.",
            status="success",
        )
        self.client.force_authenticate(user=self.user)

    def test_history_lists_only_authenticated_user_logs(self):
        response = self.client.get(reverse("ai-history"))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(response.data[0]["id"], self.own_log.id)

    def test_history_detail_cannot_access_other_users_log(self):
        response = self.client.get(reverse("ai-history-detail", args=[self.other_log.id]))

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)


class ChatViewErrorHandlingTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(
            username="charlie",
            email="charlie@example.com",
            password="testpass123",
        )
        self.client.force_authenticate(user=self.user)

    @patch("ai_agent.views.SupervisorAgent.run")
    def test_chat_does_not_leak_internal_exception_details(self, mock_run):
        mock_run.side_effect = RuntimeError("groq timeout secret-debug-detail")

        response = self.client.post(
            reverse("ai-chat"),
            {"prompt": "Vreau sa merg la Barcelona"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_500_INTERNAL_SERVER_ERROR)
        self.assertEqual(
            response.data["error"],
            "A aparut o eroare interna la procesarea cererii.",
        )
        self.assertNotIn("secret-debug-detail", response.data["error"])


class ChatViewValidationLocalizationTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(
            username="diana",
            email="diana@example.com",
            password="testpass123",
        )
        self.client.force_authenticate(user=self.user)

    @patch("ai_agent.agents.supervisor_agent.ValidationAgent.run")
    def test_invalid_english_request_returns_english_message(self, mock_run):
        mock_run.return_value = ValidationResult(
            is_valid=False,
            rejection_reason="Your message does not seem related to travel.",
            language="en",
        )

        response = self.client.post(
            reverse("ai-chat"),
            {"prompt": "small"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_422_UNPROCESSABLE_ENTITY)
        self.assertIn("I can't help with this request", response.data["final_response"])


class ChatViewSourcesTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(
            username="elena",
            email="elena@example.com",
            password="testpass123",
        )
        self.client.force_authenticate(user=self.user)

    @patch("ai_agent.views.SupervisorAgent.run")
    def test_chat_returns_tool_sources(self, mock_run):
        mock_run.return_value = {
            "validation_result": {
                "is_valid": True,
                "intent": "destination_info",
                "destinations": ["Japonia"],
                "origin": None,
                "travel_dates": None,
                "travelers_count": None,
                "budget": None,
            },
            "final_response": "Poti verifica regulile recente inainte de plecare.",
            "assigned_agents": ["general_travel_agent"],
            "agent_responses": {
                "general_travel_agent": "Poti verifica regulile recente inainte de plecare.",
            },
            "sources": [
                {
                    "title": "Japan travel advice",
                    "url": "https://example.com/japan-travel-advice",
                    "provider": "tavily",
                }
            ],
            "tool_metadata": {
                "general_travel_agent": {
                    "web_search": {
                        "provider": "tavily",
                        "query": "Japonia viza",
                        "used": True,
                        "error": None,
                    }
                }
            },
            "error": None,
        }

        response = self.client.post(
            reverse("ai-chat"),
            {"prompt": "Care sunt regulile de viza pentru Japonia acum?"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["sources"][0]["provider"], "tavily")
        self.assertTrue(response.data["tool_metadata"]["general_travel_agent"]["web_search"]["used"])


class ConversationLogAdminTests(TestCase):
    def setUp(self):
        self.client = Client()
        self.admin_user = User.objects.create_superuser(
            username="admin",
            email="admin@example.com",
            password="adminpass123",
        )
        ConversationLog.objects.create(
            user_prompt="Need a city break in Rome",
            response="Try Trastevere for food and walks.",
            status="success",
        )
        self.client.force_login(self.admin_user)

    def test_admin_changelist_renders(self):
        response = self.client.get(reverse("admin:ai_agent_conversationlog_changelist"))

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "Conversation Logs")
