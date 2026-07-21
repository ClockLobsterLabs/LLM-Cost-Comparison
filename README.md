# LLM Cost Comparison

A reproducible, testable benchmark pipeline for measuring LLM tokenizer efficiency, output verbosity, compression, speed, and cost.

## Quick start

```bash
# Install dependencies and create the virtual environment
uv sync --all-extras

# Copy the example environment file and add your OpenRouter key
cp .env.example .env
# edit .env

# See available commands
uv run llmcc --help

# Validate existing data
uv run llmcc validate

# Run an experiment
uv run llmcc run tokenizer-efficiency --dry-run

# Export the site-facing benchmark artifact
uv run llmcc export
```

## Development

```bash
# Run the test suite
uv run pytest

# Lint and typecheck
uv run ruff check .
uv run mypy src
```

## Project layout

- `catalogs/` — YAML source of truth for models, tasks, samples, compression methods, and experiments.
- `src/llm_cost_comparison/` — Python package: CLI, experiments, storage, validation.
- `tests/` — pytest suite with mocked API clients.
- `data/raw/` — generated SQLite database and raw exports (gitignored).
- `data/processed/` — generated CSV/Parquet summaries.
- `data/site/` — generated `benchmarks.json` consumed by the website.

See `ARCHITECTURE.md` (after Phase 7) for the full design.
