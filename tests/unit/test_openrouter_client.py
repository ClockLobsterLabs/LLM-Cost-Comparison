"""Tests for the OpenRouter client."""

import httpx
import pytest
import respx

from llm_cost_comparison.clients.openrouter import OpenRouterClient
from llm_cost_comparison.core.config import Settings
from llm_cost_comparison.core.exceptions import ModelNotFoundError, TimeoutError
from llm_cost_comparison.core.models import ChatRequest, Message


def _success_payload(prompt_tokens: int = 10, completion_tokens: int = 5) -> dict:
    return {
        "model": "deepseek/deepseek-v4-flash",
        "choices": [{"message": {"role": "assistant", "content": "hello"}}],
        "usage": {
            "prompt_tokens": prompt_tokens,
            "completion_tokens": completion_tokens,
            "total_tokens": prompt_tokens + completion_tokens,
        },
    }


def test_chat_success(settings: Settings) -> None:
    """A successful chat completion is parsed into a ChatResponse."""
    with respx.mock:
        route = respx.post("https://openrouter.ai/api/v1/chat/completions").respond(
            200, json=_success_payload()
        )

        client = OpenRouterClient(settings)
        request = ChatRequest(
            model_id="deepseek/deepseek-v4-flash",
            messages=[Message(role="user", content="hi")],
            max_tokens=20,
        )
        response = client.chat(request)

        assert response.model_id == "deepseek/deepseek-v4-flash"
        assert response.content == "hello"
        assert response.prompt_tokens == 10
        assert response.completion_tokens == 5
        assert response.total_tokens == 15
        assert response.elapsed_ms >= 0
        assert route.call_count == 1


def test_chat_404_is_not_retried(settings: Settings) -> None:
    """A 404 is translated to ModelNotFoundError and not retried."""
    with respx.mock:
        route = respx.post("https://openrouter.ai/api/v1/chat/completions").respond(
            404, text="Model not found"
        )

        client = OpenRouterClient(settings)
        request = ChatRequest(
            model_id="missing/model",
            messages=[Message(role="user", content="hi")],
            max_tokens=20,
        )
        with pytest.raises(ModelNotFoundError):
            client.chat(request)

        assert route.call_count == 1


def test_chat_500_is_retried(settings: Settings, monkeypatch: pytest.MonkeyPatch) -> None:
    """A 5xx triggers the configured number of retries."""
    monkeypatch.setenv("LLMCC_DEFAULT_RETRIES", "3")
    settings = Settings()
    with respx.mock:
        route = respx.post("https://openrouter.ai/api/v1/chat/completions").mock(
            side_effect=[
                httpx.Response(500, text="boom"),
                httpx.Response(500, text="boom"),
                httpx.Response(200, json=_success_payload()),
            ]
        )

        client = OpenRouterClient(settings)
        request = ChatRequest(
            model_id="deepseek/deepseek-v4-flash",
            messages=[Message(role="user", content="hi")],
            max_tokens=20,
        )
        response = client.chat(request)

        assert response.content == "hello"
        assert route.call_count == 3


def test_chat_timeout_is_raised(settings: Settings) -> None:
    """An actual timeout is converted to TimeoutError."""
    with respx.mock:
        route = respx.post("https://openrouter.ai/api/v1/chat/completions").mock(
            side_effect=httpx.TimeoutException("too slow")
        )

        client = OpenRouterClient(settings)
        request = ChatRequest(
            model_id="deepseek/deepseek-v4-flash",
            messages=[Message(role="user", content="hi")],
            max_tokens=20,
        )
        with pytest.raises(TimeoutError):
            client.chat(request)

        assert route.call_count == settings.default_retries
