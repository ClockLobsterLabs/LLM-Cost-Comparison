# Architecture

This document describes the modular Python redesign of the LLM Cost Comparison pipeline.

## Design goals

- **Reproducible**: every experiment is declared in YAML catalog files.
- **Testable**: all network and storage boundaries are abstracted and unit-tested.
- **Composable**: experiments, clients, storage, validation, and export are independent packages.
- **Site-ready**: measurements can be aggregated into a `benchmarks.json` v2 artifact.

## Package layout

```
src/llm_cost_comparison/
├── cli/           # Typer CLI (run, appraise, validate, export, migrate-legacy)
├── clients/       # LLMClient base, OpenRouterClient with retries, PricingService
├── core/          # Pydantic domain models, YAML catalog loader, Settings, exceptions
├── experiments/   # Experiment base/Runner and concrete experiment types
├── calculations/  # Cost, efficiency, compression ratio math
├── storage/       # SQLModel tables, session, and MeasurementRepository
├── validation/    # Measurement validators and legacy CSV corruption checks
└── exporters/     # CSV and JSON (benchmarks.json) exporters
```

## Catalog-driven experiments

All experiments are configured in `catalogs/experiments.yaml` and resolved through `Catalog`:

- `tokenizer_efficiency` measures tokens per word for code/prose/blended samples.
- `output_verbosity` measures token usage per task.
- `compression` compares a baseline prompt to system-prompt compression methods.
- `speed` measures tokens per second for a fixed generation prompt.
- `appraisal` runs tokenizer + speed + reasoning checks for a single model.

The `ExperimentRunner` creates an `ExperimentRun`, calls `Experiment.run`, persists `Measurement` rows, and marks the run complete or failed.

## Storage model

Three SQLModel tables:

- `ExperimentRun` - a single execution of an experiment configuration.
- `Measurement` - one raw or derived measurement row (tokens, words, elapsed time, cost).
- `PricingSnapshot` - cached live-pricing observation from OpenRouter.

## CLI commands

- `llmcc run <experiment-id>` - run a configured experiment.
- `llmcc appraise <model-slug>` - run the appraisal pipeline for one model.
- `llmcc validate <csv>` - detect Session 6b corruption signatures.
- `llmcc export <path> --run-id/--experiment-id [--format csv|json]` - export measurements.
- `llmcc migrate-legacy <csv> <experiment-id>` - import legacy Session 5/6 CSV rows.

## Legacy scripts

The `scripts/` directory still contains the original PowerShell measurement and enrichment scripts. They are preserved while the new Python CLI is validated against them, and will be removed once all workflows are fully migrated.
