"""Tests for the JSON benchmark exporter."""

import json
from pathlib import Path
from typing import Any

import pytest

from llm_cost_comparison.exporters.json import BenchmarkExporter
from llm_cost_comparison.storage.models import Measurement


def test_benchmark_exporter_aggregates_tokenizer_and_speed(tmp_path: object) -> None:
    """The JSON exporter produces a model-keyed artifact with tokenizer and speed stats."""
    measurements = [
        Measurement(
            run_id=1,
            experiment_id="tokenizer-efficiency",
            model_slug="deepseek-v4-flash",
            sample_id="code",
            prompt_tokens=600,
            completion_tokens=1,
            elapsed_ms=1000,
            meta={"sample_word_count": 300, "tokens_per_word": "2.0"},
        ),
        Measurement(
            run_id=1,
            experiment_id="speed",
            model_slug="deepseek-v4-flash",
            prompt_tokens=10,
            completion_tokens=100,
            elapsed_ms=1000,
        ),
    ]

    output = tmp_path / "benchmarks.json"
    BenchmarkExporter(measurements).to_path(output)

    data = json.loads(output.read_text(encoding="utf-8"))
    assert "last_updated" in data
    assert "models" in data
    model = data["models"]["deepseek-v4-flash"]
    assert model["tokenizer_efficiency"] == 2.0
    assert model["speed_tok_per_s"] == 100.0


def test_export_failure_leaves_destination_unchanged(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A failing export keeps the previous file and leaves no temp artifact."""
    output = tmp_path / "benchmarks.json"
    output.write_text('{"previous": true}', encoding="utf-8")

    def _boom(_self: BenchmarkExporter) -> dict[str, Any]:
        raise RuntimeError("injected failure")

    monkeypatch.setattr(BenchmarkExporter, "_aggregate", _boom)

    with pytest.raises(RuntimeError):
        BenchmarkExporter([]).to_path(output)

    assert output.read_text(encoding="utf-8") == '{"previous": true}'
    assert not (tmp_path / "benchmarks.json.tmp").exists()


def test_export_success_atomically_replaces_destination(tmp_path: Path) -> None:
    """A successful export replaces the previous file and leaves no temp artifact."""
    output = tmp_path / "benchmarks.json"
    output.write_text("stale", encoding="utf-8")

    BenchmarkExporter([]).to_path(output)

    data = json.loads(output.read_text(encoding="utf-8"))
    assert "models" in data
    assert not (tmp_path / "benchmarks.json.tmp").exists()
