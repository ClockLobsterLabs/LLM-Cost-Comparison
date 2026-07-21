"""Smoke test that the package is importable."""

import llm_cost_comparison


def test_version() -> None:
    """The package exposes a version string."""
    assert llm_cost_comparison.__version__ == "2.0.0"
