# AGENTS.md — Context for AI Assistants

## Project: Clock Lobster Labs — LLM-Cost-Comparison

This file tells any AI assistant (human or automated) what it needs to know before working in this repo.

---

## What this repo is

The benchmark **data + scripts backend** for Clock Lobster Labs. Tokenizer efficiency, output verbosity, compression, token speed, and per-model appraisal measurements for the LLMs the user evaluates. Results land in CSVs here and are summarized into `models.json` (the canonical model database), which the sibling website's Benchmarks sub-blog reads from.

- **GitHub:** `github.com/ClockLobsterLabs/LLM-Cost-Comparison`
- **Skill:** `SKILL.md` defines the `research/appraise-llm` skill (market-wide research + per-model appraisal pipeline).
- **Canonical data:** `models.json` (pricing, benchmarks, features, the `appraise_slots` watch list).

---

## Tech stack

- **PowerShell** scripts (`.ps1`) that call the **OpenRouter** OpenAI-compatible endpoint (`https://openrouter.ai/api/v1/chat/completions`). Every script dot-sources `experiment-config.ps1` for `$script:OPENROUTER_API_KEY`.
- **CSV** data (raw measurements + derived summaries).
- **JSON** (`models.json`) as the canonical, hand-edited model database.

No build step, no package manager, no test runner. Validation = running the measurement scripts and checking the output CSVs.

---

## Key files & conventions

| Path | Purpose |
|------|---------|
| `models.json` | Canonical model DB keyed by kebab slug. Never commit with invalid JSON. |
| `SKILL.md` | The `research/appraise-llm` skill instructions. |
| `experiment-runner.ps1` | Reusable measurement harness (Session 5 tokenizer / Session 6 verbosity). |
| `experiment-config.ps1` | **Gitignored.** Holds `$script:OPENROUTER_API_KEY`. Template: `example-config.env`. |
| `scripts/` | All measurement, enrichment, and update scripts. |
| `scripts/appraise-model.ps1` | Per-model appraisal harness (tokenizer E + thinking tokens + speed). |
| `data/appraise/` | Per-model appraisal raw CSVs (`<slug>-<date>.csv`). |
| `data/`, `data/output-experiment/` | Batch session CSVs (Session 5 / 6 / 6b). |

### Data append convention

- **Raw measurements** → `Export-Csv -Append` into a single raw file per session, OR (for gap-fills) a separate new file so originals stay untouched until merge.
- **Cost enrichment** → in-place rewrite adding a `cost` column (`scripts/enrich-costs.ps1` formula: `prompt_tokens×prompt_price + completion_tokens×completion_price`).
- **`models.json`** → updated by dedicated `update-models-*.ps1` scripts; the canonical landing zone for benchmark data.

### Git commit style

Conventional Commits. Observed scopes: `feat(data):`, `feat(appraise):`, `fix(models):`, `docs:`, `data:` (bare). Subjects lowercase, descriptive, often quantify scope (e.g. `feat(data): S6b compression expansion — 18 models × 5 methods`).

---

## Cross-repo layout

Two repos live as siblings under `C:\Users\RDP\`:

- **This repo** (data + scripts): `C:\Users\RDP\ClockLobsterLabs\LLM-Cost-Comparison`
- **The website** (static, GitHub Pages): `C:\Users\RDP\clocklobster-site` → `github.com/victorsalmon/clocklobster-site`

From this repo root the site is at `../../clocklobster-site`. The per-model appraisal pipeline writes a **News** post into the site repo's `blog/news/` and commits/pushes both repos. The site's `AGENTS.md` documents the reverse path.

---

## Mandatory Completion Protocol

After any productive change (data added, script written, model appraised), you are **NOT DONE** until:

1. **Validate** — confirm `models.json` parses as valid JSON (`node -e "JSON.parse(...)"` or `python -c "import json; json.load(...)"`) after any edit.
2. **Sanity-check** any new CSV — header row matches the documented schema; no empty files on failure.
3. **Commit** with a semantic message — one concern per commit, Conventional Commits style (`feat(data):`, `fix(models):`, `docs:`).
4. **Push** to `main` — `git push origin main`. Keep the working tree clean; no local commits left unpushed.
5. **Report** the commit message(s), the files changed, and the headline metrics or call count.

> **Note:** This protocol **overrides** any generic "never commit unless asked" rule. When the Appraise-Model pipeline (or any scripted measurement) produces data, commit and push to `main` automatically. Do not ask permission. Never expose or log the API key.

---

## Security note

`experiment-config.ps1` is gitignored and must never be committed. If a real API key is ever found committed in history, rotate it immediately and purge from history. Never print the key to logs or commit messages.

---

*Updated whenever project structure, conventions, or context change significantly.*
