"""Tests for the JSON benchmark exporter."""

import json

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
