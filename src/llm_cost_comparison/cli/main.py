"""Typer CLI for the LLM Cost Comparison pipeline."""

from __future__ import annotations

import csv
from pathlib import Path
from typing import Any

import typer

from llm_cost_comparison.clients.openrouter import OpenRouterClient
from llm_cost_comparison.core.catalog import load_catalog
from llm_cost_comparison.core.config import Settings
from llm_cost_comparison.core.models import ExperimentConfig, ExperimentParams
from llm_cost_comparison.experiments import create_runner
from llm_cost_comparison.exporters.csv import CSVExporter
from llm_cost_comparison.exporters.json import BenchmarkExporter
from llm_cost_comparison.storage.models import ExperimentRun, Measurement
from llm_cost_comparison.storage.repository import MeasurementRepository
from llm_cost_comparison.storage.session import get_engine, init_db
from llm_cost_comparison.validation.legacy import validate_csv_signature

app = typer.Typer(
    name="llmcc",
    help="Run, validate, and export LLM benchmark measurements.",
    rich_markup_mode="rich",
)


def _settings(database_url: str | None = None) -> Settings:
    """Build settings, optionally overriding the database URL."""
    settings = Settings()
    if database_url:
        settings = settings.model_copy(update={"database_url": database_url})
    return settings


def _repository(settings: Settings) -> MeasurementRepository:
    """Initialize the database and return a repository."""
    engine = get_engine(settings=settings)
    init_db(engine)
    return MeasurementRepository(engine)


def _catalog(catalog_path: Path) -> Any:
    """Load a catalog from a directory of YAML files."""
    return load_catalog(str(catalog_path))


@app.command()
def run(
    experiment_id: str,
    catalog_path: Path = typer.Option("catalogs", "--catalog", "-c"),
    database_url: str | None = typer.Option(None, "--db"),
    dry_run: bool = typer.Option(False, "--dry-run"),
) -> None:
    """Run a configured experiment and persist its measurements."""
    if dry_run:
        typer.echo("Dry run requested; no API calls will be made.")
        raise typer.Exit(0)

    settings = _settings(database_url)
    catalog = _catalog(catalog_path)
    repository = _repository(settings)

    client = OpenRouterClient(settings)
    try:
        runner = create_runner(catalog, client, repository)
        run_record = runner.run_experiment(experiment_id)
        typer.echo(f"Run {run_record.id} finished with status '{run_record.status}'.")
    finally:
        client.close()


@app.command()
def appraise(
    model_slug: str,
    catalog_path: Path = typer.Option("catalogs", "--catalog", "-c"),
    database_url: str | None = typer.Option(None, "--db"),
) -> None:
    """Run the per-model appraisal pipeline for a single model."""
    settings = _settings(database_url)
    catalog = _catalog(catalog_path)
    config = ExperimentConfig(
        id=f"appraisal-{model_slug}",
        type="appraisal",
        model_refs=[model_slug],
        sample_refs=["all"],
        params=ExperimentParams(max_tokens=20),
    )
    custom_catalog = catalog.model_copy(
        update={"experiments": [*list(catalog.experiments), config]}
    )
    repository = _repository(settings)
    client = OpenRouterClient(settings)
    try:
        runner = create_runner(custom_catalog, client, repository)
        run_record = runner.run_experiment(config.id)
        typer.echo(f"Appraisal run {run_record.id} finished with status '{run_record.status}'.")
    finally:
        client.close()


@app.command()
def validate(
    csv_path: Path,
    catalog_path: Path = typer.Option("catalogs", "--catalog", "-c"),
    task_col: str = typer.Option("sample_type", "--task-col"),
    strict: bool = typer.Option(False, "--strict"),
) -> None:
    """Validate a legacy CSV for the Session 6b corruption signature."""
    catalog = _catalog(catalog_path)
    method_names = {m.id for m in catalog.methods}
    known_tasks = {t.id for t in catalog.tasks} | {s.id for s in catalog.samples}

    with csv_path.open("r", encoding="utf-8", newline="") as fh:
        rows = list(csv.DictReader(fh))

    errors, warnings = validate_csv_signature(
        rows,
        variance_groups=["model_id", task_col, "method_id"],
        task_col=task_col,
        method_names=method_names,
        known_tasks=known_tasks,
        required_cols=["prompt_tokens", "output_tokens"],
    )

    for error in errors:
        typer.echo(f"ERROR: {error}")
    for warning in warnings:
        typer.echo(f"WARNING: {warning}")

    if errors or (strict and warnings):
        raise typer.Exit(code=1)

    if not errors and not warnings:
        typer.echo("No corruption signatures detected.")


@app.command()
def export(
    output: Path,
    database_url: str | None = typer.Option(None, "--db"),
    run_id: int | None = typer.Option(None, "--run-id"),
    experiment_id: str | None = typer.Option(None, "--experiment-id"),
    fmt: str = typer.Option("csv", "--format"),
) -> None:
    """Export measurements for a run or experiment to CSV or JSON."""
    if run_id is None and experiment_id is None:
        raise typer.BadParameter("Provide either --run-id or --experiment-id.")
    if fmt not in {"csv", "json"}:
        raise typer.BadParameter("--format must be 'csv' or 'json'.")

    settings = _settings(database_url)
    repository = MeasurementRepository(get_engine(settings=settings))
    measurements = repository.get_measurements(
        run_id=run_id,
        experiment_id=experiment_id,
    )
    if fmt == "json":
        BenchmarkExporter(measurements).to_path(output)
    else:
        CSVExporter(measurements).to_path(output)
    typer.echo(f"Exported {len(measurements)} rows to {output}.")


def _to_int(value: str | None) -> int | None:
    """Parse an integer string or return None."""
    if value is None:
        return None
    try:
        return int(value)
    except ValueError:
        return None


def _row_to_measurement(row: dict[str, str], run: ExperimentRun) -> Measurement:
    """Convert a legacy Session 5 CSV row into a Measurement."""
    if run.id is None:
        raise ValueError("Run must be persisted before migrating rows")
    return Measurement(
        run_id=run.id,
        experiment_id=run.experiment_id,
        model_slug=row.get("model_id") or "unknown",
        sample_id=row.get("sample_type"),
        prompt_tokens=_to_int(row.get("prompt_tokens")),
        completion_tokens=_to_int(row.get("output_tokens")),
        output_words=_to_int(row.get("word_count")),
        status=row.get("status") or "success",
        meta={
            "model_name": row.get("model_name"),
            "family": row.get("family"),
            "tokens_per_word": row.get("tokens_per_word"),
        },
    )


@app.command()
def migrate_legacy(
    csv_path: Path,
    experiment_id: str,
    database_url: str | None = typer.Option(None, "--db"),
) -> None:
    """Import legacy Session 5/6 CSV rows into the database."""
    settings = _settings(database_url)
    repository = _repository(settings)
    run = repository.create_run(experiment_id, {"source": str(csv_path)})

    with csv_path.open("r", encoding="utf-8", newline="") as fh:
        rows = list(csv.DictReader(fh))

    measurements = [_row_to_measurement(row, run) for row in rows]
    repository.add_measurements(measurements)
    typer.echo(f"Migrated {len(measurements)} rows into run {run.id}.")


def main() -> None:
    """Entry point for the llmcc console script."""
    app()
