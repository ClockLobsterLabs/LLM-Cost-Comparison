"""Tests for validators and legacy CSV corruption checks."""


from llm_cost_comparison.storage.models import Measurement
from llm_cost_comparison.validation.legacy import (
    find_constant_prompt_tokens,
    find_empty_required_values,
    find_task_id_leaking_method_names,
    validate_csv_signature,
)
from llm_cost_comparison.validation.validators import MeasurementValidator


def test_valid_measurement() -> None:
    """A success measurement with valid token counts passes."""
    measurement = Measurement(
        run_id=1,
        experiment_id="tokenizer-efficiency",
        model_slug="deepseek-v4-flash",
        prompt_tokens=100,
        completion_tokens=50,
        elapsed_ms=1200,
        status="success",
    )
    assert MeasurementValidator.validate(measurement) == []


def test_missing_model_slug() -> None:
    """Missing model_slug is rejected."""
    measurement = Measurement(
        run_id=1,
        experiment_id="output-verbosity",
        model_slug="",
        prompt_tokens=10,
        completion_tokens=5,
        status="success",
    )
    errors = MeasurementValidator.validate(measurement)
    assert any("model_slug" in e for e in errors)


def test_negative_tokens() -> None:
    """Negative token counts on success rows are rejected."""
    measurement = Measurement(
        run_id=1,
        experiment_id="output-verbosity",
        model_slug="x",
        prompt_tokens=-1,
        completion_tokens=5,
        status="success",
    )
    errors = MeasurementValidator.validate(measurement)
    assert any("prompt_tokens" in e for e in errors)


def test_constant_prompt_tokens_signature() -> None:
    """Constant prompt_tokens within a variance group is flagged as corruption."""
    rows = [
        {"model_id": "a", "task_id": "t1", "method_id": "smc", "prompt_tokens": 100},
        {"model_id": "a", "task_id": "t1", "method_id": "smc", "prompt_tokens": 100},
        {"model_id": "a", "task_id": "t1", "method_id": "smc", "prompt_tokens": 100},
    ]
    result = find_constant_prompt_tokens(rows, ["model_id", "task_id", "method_id"])
    assert len(result) == 1
    assert result[0][1] == 1


def test_task_id_leaking_method_names() -> None:
    """task_id values matching method names are flagged."""
    rows = [
        {"task_id": "smc"},
        {"task_id": "short-code"},
    ]
    leaked = find_task_id_leaking_method_names(
        rows, "task_id", {"smc", "diff-only"}, {"short-code", "one-word"}
    )
    assert leaked == ["smc"]


def test_empty_required_values() -> None:
    """Empty required columns on success rows are counted."""
    rows = [
        {"status": "success", "category": "coding"},
        {"status": "success", "category": ""},
        {"status": "error", "category": ""},
    ]
    assert find_empty_required_values(rows, "category") == 1


def test_validate_csv_signature_integration() -> None:
    """validate_csv_signature returns errors and warnings together."""
    rows = [
        {"task_id": "smc", "prompt_tokens": 100, "category": "x", "status": "success"},
        {"task_id": "smc", "prompt_tokens": 100, "category": "", "status": "success"},
        {"task_id": "smc", "prompt_tokens": 100, "category": "x", "status": "success"},
    ]
    errors, warnings = validate_csv_signature(
        rows,
        variance_groups=["task_id"],
        task_col="task_id",
        method_names={"smc"},
        known_tasks={"one-word"},
        required_cols=["category"],
    )
    assert any("CORRUPTION" in e for e in errors)
    assert any("task_id contains method" in e for e in errors)
    assert any("empty 'category'" in w for w in warnings)
