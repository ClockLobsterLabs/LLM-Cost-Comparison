---
name: research/appraise-llm
description: Appraise new and existing LLMs — research benchmarks, pricing, features, and produce comparison tables. Use when asked to appraise, evaluate, compare, review, or audit LLMs.
type: skill
container: opencode
---

# Appraise LLM — Skill

## Purpose

Research and evaluate LLMs against the user's real-world usage strategy. Output a structured comparison table showing benchmarks, pricing, new features, and specialty for each model. Answer one question: "Is this model worth my attention given my current setup?"

## User's Strategy (Baseline)

| Layer | Model | Source | Use case |
|-------|-------|--------|----------|
| Daily driver | DeepSeek V4 Flash | OpenCode Zen ($0.28/M out) | General coding, daily agent work |
| Max variant | DeepSeek V4 Flash Max | OpenRouter (~$0.28/M out) | When Flash's Max config is needed |
| Complex planning | GLM 5.2 | OpenCode Zen ($4.40/M out) | Audits, architecture, planning from scratch |
| Subscription | OpenCode Zen | $20 PAYG top-up, auto-reload at $5 | Primary API gateway |
| Secondary | OpenRouter | PAYG + 5.5% fee | Max variants and models not on Zen |

Goal: **minimize cost, maximize effective capability.** New models are evaluated against this stack.

## Price Tiers (by Output $/M tokens)

All pricing sourced from [OpenCode Zen](https://opencode.ai/zen) (primary) and [OpenRouter](https://openrouter.ai) (secondary for Max variants).

| Tier | Output $/M | Role | Current top pick |
|------|-----------|------|-----------------|
| **Complex** | $18+ | Hardest problems — architecture, audits, planning from scratch | Claude Fable 5 |
| **Daily** | $8 – $17.99 | Strong daily driver — general coding, reasoning | Claude Sonnet 5 |
| **Taskrunner** | $2 – $7.99 | Fast routine tasks — implementation, refactoring, reviews | GLM 5.2 |
| **Budget Taskrunner** | $0.01 – $1.99 | High-volume, cost-sensitive work | DeepSeek V4 Flash |
| **Free** | $0 | No-cost experimentation (data may train models) | DeepSeek V4 Flash Free |

Repeat every appraisal: check for new models in each tier. Every tier gets at least one entry.

## Required Model Slots

Every appraisal report must include:

1. **Latest GLM** — currently GLM 5.2. Check for GLM 5.3+
2. **Latest DeepSeek Flash** — currently DeepSeek V4 Flash. Check for V5+
3. **Top 3 in each tier** — by AA Intelligence Index, then by output price (cheaper = better tiebreak)
4. **New arrivals** — any model released since the last appraisal that doesn't fit existing slots

## Appraisal Table Template — Primary View

**Primary benchmarks** (always shown): SWE-bench Pro, Terminal-Bench 2.1 — these are the most relevant for agentic coding workflows. SWE-bench Verified shown when available.

Show top 3 per tier by default. When asked "show all models" or "full breakdown", show every model in the database.

| Model | Tier | SWE-bench Pro | Terminal-Bench 2.1 | SWE-bench Verified | Input $/M | Output $/M | AAII | New Features | Specialty | Beats your stack? |
|-------|:---:|:-----------:|:---------------:|:----------------:|:--------:|:--------:|:---:|-------------|-----------|:---------------:|
|       |      |             |                  |                  |          |          |      |             |           |                  |

- **SWE-bench Pro**: Primary coding benchmark. Scores: [swebench.com](https://swebench.com). N/A if untested.
- **Terminal-Bench 2.1**: Primary agentic benchmark. Scores: [tbench.ai](https://tbench.ai). N/A if untested.
- **SWE-bench Verified**: Human-validated subset. Typically 5-15 pts higher than Pro.
- **Beats your stack?**: "Yes" / "Maybe" / "No" based on whether this model outperforms the equivalent-tier pick in your current strategy at similar or lower cost.

### Additional Benchmark Views

Ask for specific views: "show me OSWorld scores", "compare GPQA Diamond", "show HLE", "full benchmark breakdown", etc.

## Full Benchmark Schema

All benchmarks stored in `models.json` per model. A dash `-` means no score available.

| Field | Benchmark | Category | What it measures | Best score in DB |
|-------|-----------|----------|-----------------|:----------------:|
| `swe_bench_pro` | SWE-bench Pro | Coding | Harder GitHub issue resolution | Claude Fable 5: 80.3% |
| `swe_bench_verified` | SWE-bench Verified | Coding | Human-validated GitHub issue resolution | Claude Fable 5: 95.0% |
| `terminal_bench_2_1` | Terminal-Bench 2.1 | Agentic | Terminal-based SE, sysadmin, ML, security tasks | Claude Fable 5: 88.0% |
| `os_world_verified` | OSWorld-Verified | RPA / Vision | Operating real computer environments via screenshots | GPT-5.5: 78.7% |
| `browse_comp` | BrowseComp | Web Search | Persistent web search for hard-to-find info | GPT-5.5 Pro: 90.1% |
| `gpqa_diamond` | GPQA Diamond | Research | Graduate-level science reasoning | Gemini 3.1 Pro: 98.0% (ARC-1) |
| `hle_no_tools` | HLE (no tools) | Research | Humanity's Last Exam without tool use | Claude Opus 4.7: 46.9% |
| `hle_with_tools` | HLE (with tools) | Research | Humanity's Last Exam with browsing/code tools | GPT-5.4 Pro: 58.7% |
| `arc_agi_1` | ARC-AGI-1 Verified | Reasoning | Abstract visual reasoning puzzles (easy) | Gemini 3.1 Pro: 98.0% |
| `arc_agi_2` | ARC-AGI-2 Verified | Reasoning | Abstract visual reasoning puzzles (hard) | GPT-5.5: 85.0% |
| `tau2_bench_telecom` | Tau²-Bench Telecom | Tool Use | Complex customer-service tool workflows | GPT-5.5: 98.0% |
| `mcp_atlas` | MCP Atlas | Tool Use | Multi-MCP-server tool orchestration (Scale AI) | Claude Opus 4.7: 79.1% |
| `toolathlon` | Toolathlon | Tool Use | Real-world API tool calling across multi-step tasks | GPT-5.5: 55.6% |
| `frontier_math_t1_3` | FrontierMath T1-3 | Math | Competition-level math (easier tiers) | GPT-5.5 Pro: 52.4% |
| `frontier_math_t4` | FrontierMath T4 | Math | Frontier math (hardest tier) | GPT-5.5 Pro: 39.6% |
| `aa_intelligence_index` | AA Intelligence Index | Composite | Weighted avg of 10 evals by Artificial Analysis | Claude Fable 5: 56 |

### Use-Case-to-Benchmark Mapping

| If you are building... | You should look at... | What it proves |
|------------------------|----------------------|----------------|
| Autonomous RPA / Web Scrapers | WebArena, OSWorld | Can the model navigate visual interfaces and multi-step UI flows? |
| Deep Research / Strategy Agents | HLE, GPQA Diamond | Can the model reason at a postgraduate level without hallucinating? |
| Algorithmic Generators | LiveCodeBench | Can the model solve novel logic problems it has never seen before? |
| Complex Tool Orchestrators | Tau²-Bench, GAIA | Does the model crash when an API returns an unexpected error? |

## Research Protocol

When asked to appraise:

1. **Load models.json** for baseline data
2. **Fetch live Zen models** — check `GET https://opencode.ai/zen/v1/models` for new models, price changes, deprecations
3. **Check OpenRouter** for new Max variants or models not on Zen
4. **Cross-reference benchmarks** — visit swebench.com, tbench.ai, artificialanalysis.ai for updated scores
5. **Compare vs models.json** — flag:
   - New models not in the database
   - Price changes (up or down)
   - Deprecated/sunset models
   - Unexpectedly strong benchmark results
6. **Classify into tiers** by output $/M token
7. **Produce the table** — top 3 per tier by default (or all if asked)
8. **Strategy assessment** — for each tier, say whether any model beats the user's current pick
9. **Update models.json** with verified findings

## Data Files

| File | Purpose |
|------|---------|
| `Skills/Research/Appraise-LLM/models.json` | Canonical model database with pricing, benchmarks, features |
| `Skills/Research/Appraise-LLM/SKILL.md` | This file — skill instructions |

## Provider Notes

- **OpenCode Zen**: PAYG via $20 top-up. Zero markup — prices = provider cost + processing fee. Auto-reload at $5 balance. Free models available (usage data may train models).
- **OpenRouter**: PAYG with 5.5% platform fee. Used for Max variants (DeepSeek V4 Flash Max, V4 Pro Max) and any model not on Zen.
- **Direct API**: Fallback only. Noted explicitly in the database.
