"""Abstract base class for LLM API clients."""

from abc import ABC, abstractmethod

from llm_cost_comparison.core.models import ChatRequest, ChatResponse


class LLMClient(ABC):
    """Abstract client for sending chat completion requests."""

    @abstractmethod
    def chat(self, request: ChatRequest) -> ChatResponse:
        """Send a chat request and return a typed response."""

    @abstractmethod
    def close(self) -> None:
        """Close any underlying HTTP resources."""
