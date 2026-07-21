"""Tests for the Typer CLI."""


import pytest
from typer.testing import CliRunner

from llm_cost_comparison.cli.main import app
from llm_cost_comparison.storage.models import Measurement
from llm_cost_comparison.storage.repository import MeasurementRepository
from llm_cost_comparison.storage.session import get_engine, init_db

runner = CliRunner()


def test_run_dry_run() -> None:
    """The run command with --dry-run exits without calling APIs."""
    result = runner.invoke(
        app,
        ["run", "tokenizer-efficiency", "--dry-run"],
    )
    assert result.exit_code == 0
    assert "Dry run" in result.stdout


def test_validate_detects_corruption(tmp_path: pytest.TempPathFactory) -> None:
    """validate flags the constant prompt_tokens corruption signature."""
    csv = tmp_path / "corrupt.csv"
    csv.write_text(
        "model_id,sample_type,method_id,prompt_tokens,output_tokens,status\n"
        "x,t1,m,100,5,success\n"
        "x,t1,m,100,5,success\n"
        "x,t1,m,100,5,success\n"
    )
    result = runner.invoke(app, ["validate", str(csv)])
    assert result.exit_code == 1
    assert "CORRUPTION" in result.stdout


def test_export_measurements(
    tmp_path: pytest.TempPathFactory,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """export writes measurements for a given run to CSV."""
    monkeypatch.setenv("OPENROUTER_API_KEY", "sk-test-key")
    db = tmp_path / "db.sqlite"
    engine = get_engine(f"sqlite:///{db}")
    init_db(engine)
    repo = MeasurementRepository(engine)
    run = repo.create_run("output-verbosity")
    repo.add_measurement(
        Measurement(
            run_id=run.id,
            experiment_id="output-verbosity",
            model_slug="deepseek-v4-flash",
            prompt_tokens=10,
            completion_tokens=5,
        )
    )

    output = tmp_path / "out.csv"
    result = runner.invoke(
        app,
        ["export", str(output), f"--db=sqlite:///{db}", f"--run-id={run.id}"],
    )
    assert result.exit_code == 0
    assert "Exported 1" in result.stdout
    assert output.exists()


def test_migrate_legacy(tmp_path: pytest.TempPathFactory, monkeypatch: pytest.MonkeyPatch) -> None:
    """migrate-legacy imports Session 5 style rows into the database."""
    monkeypatch.setenv("OPENROUTER_API_KEY", "sk-test-key")
    db = tmp_path / "db.sqlite"
    csv = tmp_path / "legacy.csv"
    csv.write_text(
        "model_id,model_name,family,sample_type,word_count,prompt_tokens,output_tokens,tokens_per_word,status\n"
        "ai21/jamba-large-1.7,Jamba Large,ai21,prose,235,287,20,1.22,success\n"
    )

    result = runner.invoke(
        app,
        ["migrate-legacy", str(csv), "session-5", f"--db=sqlite:///{db}"],
    )
    assert result.exit_code == 0
    assert "Migrated 1" in result.stdout

    engine = get_engine(f"sqlite:///{db}")
    repo = MeasurementRepository(engine)
    rows = repo.get_measurements(experiment_id="session-5")
    assert len(rows) == 1
    assert rows[0].model_slug == "ai21/jamba-large-1.7"
    assert rows[0].prompt_tokens == 287
