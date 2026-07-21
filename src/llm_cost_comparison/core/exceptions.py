"""Domain exceptions for the LLM Cost Comparison pipeline."""


class LLMCCError(Exception):
    """Base exception for the package."""


class ConfigurationError(LLMCCError):
    """Raised when configuration is missing or invalid."""


class CatalogError(LLMCCError):
    """Raised when a catalog file or lookup fails."""


class APIError(LLMCCError):
    """Raised when an external API call fails."""


class ModelNotFoundError(APIError):
    """Raised when the requested model is not available on the provider."""


class RateLimitError(APIError):
    """Raised when a provider rate limit is hit."""


class TimeoutError(APIError):
    """Raised when an API call times out."""


class ValidationError(LLMCCError):
    """Raised when data fails a validation check."""
