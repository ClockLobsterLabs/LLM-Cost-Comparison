"""Tests for SQLModel storage and repository."""

from llm_cost_comparison.storage.models import Measurement, PricingSnapshot
from llm_cost_comparison.storage.repository import MeasurementRepository
from llm_cost_comparison.storage.session import get_engine, init_db


def test_create_and_query_measurements() -> None:
    """Measurements can be persisted and retrieved by experiment and model."""
    engine = get_engine("sqlite://")
    init_db(engine)
    repo = MeasurementRepository(engine)

    run = repo.create_run("tokenizer-efficiency", {"max_tokens": 20})
    measurement = Measurement(
        run_id=run.id,
        experiment_id="tokenizer-efficiency",
        model_slug="deepseek-v4-flash",
        model_id="deepseek/deepseek-v4-flash",
        sample_id="code",
        prompt_tokens=612,
        completion_tokens=1,
        elapsed_ms=1200,
    )
    saved = repo.add_measurement(measurement)

    assert saved.id is not None
    assert saved.run_id == run.id

    rows = repo.get_measurements(experiment_id="tokenizer-efficiency")
    assert len(rows) == 1
    assert rows[0].model_slug == "deepseek-v4-flash"


def test_run_lifecycle() -> None:
    """Runs are created in 'running' status and can be completed."""
    engine = get_engine("sqlite://")
    init_db(engine)
    repo = MeasurementRepository(engine)

    run = repo.create_run("output-verbosity")
    assert run.status == "running"

    finished = repo.finish_run(run.id, "completed", "all good")
    assert finished.status == "completed"
    assert finished.finished_at is not None


def test_pricing_snapshot() -> None:
    """Pricing snapshots are stored and fetched by recency."""
    engine = get_engine("sqlite://")
    init_db(engine)
    repo = MeasurementRepository(engine)

    snapshot = PricingSnapshot(
        model_id="deepseek/deepseek-v4-flash",
        input="0.0938",
        output="0.1876",
        cached_read="0.01876",
        source="openrouter",
    )
    saved = repo.save_pricing_snapshot(snapshot)

    assert saved.id is not None
    latest = repo.get_latest_pricing("deepseek/deepseek-v4-flash")
    assert latest is not None
    assert latest.model_id == snapshot.model_id
