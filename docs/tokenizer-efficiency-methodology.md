# Tokenizer Efficiency — Measurement Methodology

## Purpose

Tokenizer efficiency (E) measures how many tokens a model family generates per word of text. It is the bridge between per-token pricing and per-task costing: a model with E=1.65 costs 65% more per word than naive per-token comparisons suggest, while a model with E=2.46 costs 146% more.

Each model family has its own tokenizer (BPE, DSL, o200k, SentencePiece, etc.), producing different token densities for the same text.

## Measurement Protocol

### Sample Texts

Two sample texts are used:

- **Code sample** (~306 words): A realistic multi-function TypeScript file with imports, type definitions, async error handling, generic constraints, and array methods. Capture the verbosity of real coding (braces, dots, parentheses, operators, whitespace).
- **Prose sample** (~235 words): A technical architecture discussion with paragraphs, bullet points, dashes, and colons. Reflects documentation and planning text.

### API Call Pattern

For each model family:

1. POST to `https://openrouter.ai/api/v1/chat/completions` with `max_tokens=20` and `temperature=0`
2. Submit each sample as a single user message
3. Read `usage.prompt_tokens` from response
4. Compute `E = prompt_tokens / word_count(sample)`

Two calls per family (one code, one prose). `max_tokens=20` minimizes output cost — only the input tokenization matters for E.

### Blend Formula

The single `tokenizer_efficiency` value stored in `models.json` is a 60:40 weighted average of code and prose E, reflecting a typical coding workload:

```
E_blend = 0.60 × E_code + 0.40 × E_prose
```

For task-specific estimates, substitute the raw code or prose value from the family table in SKILL.md.

## Measurement Campaign History

### Session 1 (2026-07-08, earlier) — 8 original families + diagnostics

| Model | Code E | Prose E | Blend | Status |
|-------|:-----:|:------:|:-----:|--------|
| DeepSeek V4 Flash | 1.98 | 1.16 | 1.65 | Measured |
| Claude Haiku 4.5 | 2.25 | 1.25 | 1.85 | Measured |
| GPT-5.4 Nano | — | — | 1.72 | Failed — no `usage` field |
| GPT-5.4 Mini | — | — | 1.72 | Failed — no `usage` field |
| GPT-5.4 Nano (re-test) | 2.07 | 1.19 | 1.72 | Measured (max_tokens >= 16) |
| GLM 5.2 | 1.87 | 1.18 | 1.59 | Measured |
| Kimi K2.7 Code | 1.90 | 1.16 | 1.60 | Measured |
| Grok 4.5 (short sample) | 3.82 | 2.71 | — | Overestimated (short-sample artifact) |
| MiniMax M3 (short sample) | 3.30 | 2.49 | — | Overestimated (short-sample artifact) |
| Qwen3.7 Plus | — | — | 1.60 | Blocked — guardrail |
| Qwen3.7 Max | — | — | 1.60 | Blocked — guardrail |

**Short-sample artifact**: Initial ~77-word tests gave inflated E values for Grok and MiniMax because the ~20-token message-formatting overhead disproportionately affected short samples. Long-sample re-tests corrected this.

### Session 2 (2026-07-08, later) — Long-sample re-tests + 13 new models

| Model | Code E | Prose E | Blend | Status |
|-------|:-----:|:------:|:-----:|--------|
| Grok 4.5 (long) | 2.89 | 1.81 | 2.46 | Measured (confirmed genuinely high) |
| MiniMax M3 (long) | 2.67 | 1.72 | 2.29 | Measured (confirmed genuinely high) |
| DeepSeek R1 | — | — | 1.80 | Measured (long sample) |
| DeepSeek V3.2 | — | — | 1.84 | Measured |
| DeepSeek Chat V3 | — | — | 1.78 | Measured |
| Gemini 2.5 Pro | — | — | 1.83 | Measured |
| Llama 3.3 70B | — | — | 1.72 | Measured |
| Llama 4 Maverick | — | — | 1.75 | Measured |
| Phi-4 | — | — | 1.69 | Measured |
| Amazon Nova Pro | — | — | 1.87 | Measured |
| o4-mini | — | — | 1.72 | Blocked — privacy guardrail |
| o3-mini | — | — | 1.72 | Blocked — privacy guardrail |
| Mistral Large 3 | — | — | 1.74 | Blocked — privacy guardrail |
| Codestral | — | — | 1.74 | Blocked — privacy guardrail |
| Cohere Command A | — | — | 1.74 | Blocked — privacy guardrail |

### Session 3 (2026-07-08, later) — Expensive models (> $6/M out)

| Model | Code E | Prose E | Blend | Status |
|-------|:-----:|:------:|:-----:|--------|
| Perplexity Sonar Pro Search | 2.22 | 1.15 | 1.79 | Measured (long sample) |
| Perplexity Sonar Pro | 2.22 | 1.15 | 1.79 | Measured (long sample, same tokenizer) |
| Amazon Nova Premier | 2.88 | 1.29 | 2.24 | Measured (long sample) |
| Sakana Fugu Ultra | — | — | — | Blocked — privacy guardrail |
| Inflection-3 Pi | — | — | — | Blocked — privacy guardrail |
| Inflection-3 Productivity | — | — | — | Blocked — privacy guardrail |
| AI21 Jamba Large 1.7 | — | — | — | Blocked — privacy guardrail |
| Perplexity Sonar Reasoning Pro | — | — | — | Timed out (search model) |
| Perplexity Sonar Deep Research | — | — | — | Timed out (search model) |

### Session 4 (2026-07-08) — Guardrail-unblocked models

After relaxing OpenRouter workspace guardrails (Model Access filtering), 5 previously blocked models became measurable:

| Model | Code E | Prose E | Blend | Status |
|-------|:-----:|:------:|:-----:|--------|
| o3-mini | 1.97 | 1.15 | 1.64 | Measured (max_tokens≥16) |
| Mistral Large 3 | 2.04 | 1.15 | 1.68 | Measured |
| Codestral | 2.04 | 1.15 | 1.68 | Measured (same tokenizer as Large 3) |
| Command A | 2.13 | 1.10 | 1.72 | Measured |
| Jamba Large 1.7 | 2.48 | 1.21 | 1.97 | Measured |
| o4-mini | — | — | 1.72 | Cannot measure — encrypted reasoning responses, no `usage.prompt_tokens` field |
| Sakana Fugu Ultra | — | — | — | Non-standard token counting (~95 tok/word), $0.39/test, not comparable |
| Inflection 3 Pi / Productivity | — | — | — | Provider returns empty responses (502) |

Session 4 used shorter sample texts (152-word code, 125-word prose) than Sessions 1-3 (306-word code, 235-word prose). Values are consistent within the session but may have slightly different absolute values due to per-message overhead being amortized over fewer words.

**Guardrail root cause**: The 11 blocked models were filtered by workspace-level guardrails (Model Access section), not account-level privacy settings. Relaxing the guardrail allowlist or policy restored access to all models that have working inference endpoints on OpenRouter.

### Families with Estimated Values (unmeasurable via OpenRouter)

| Family | Est. Blend | Reason |
|--------|:---------:|--------|
| Gemini (3.x) | 1.65 | OpenRouter doesn't report `usage` for Gemini 3.x models |
| Qwen | 1.60 | OpenRouter guardrail blocks API access |

Gemini 2.5 Pro does report usage — the limitation is specific to Gemini 3.x on OpenRouter.

## Cost Breakdown

All API calls used `max_tokens=20` with minimal output text, making input tokens the dominant cost. Total expenditure across both sessions:

| Component | Calls | Est. Cost |
|-----------|:-----:|:---------:|
| Session 1 — 8 families (short sample) | 18 | ~$0.002 |
| Session 1 — diagnostics & re-tests | 4 | ~$0.001 |
| Session 2 — long-sample re-tests | 4 | ~$0.003 |
| Session 2 — 8 newly measured models | 16 | ~$0.005 |
| Session 2 — 5 guardrail-blocked models | 10 | $0 (not billed) |
| Session 3 — 9 expensive models (> $6/M out) | 18 | ~$0.06 |
| **Total** | **70** | **~$0.07** |

The entire measurement campaign cost approximately **1 cent (USD)** on OpenRouter. This is why the methodology is sustainable: measuring a new model costs about $0.0003–0.002 per family.

### Cost Per Model (detailed)

Most expensive calls:
- Perplexity Sonar Pro: ~$0.015 (2 calls) — $3.00/M input + $15/M output, verbose code (2.22)
- Amazon Nova Premier: ~$0.008 (2 calls) — $2.50/M input + $12.50/M output, very verbose (2.88 code)
- Gemini 2.5 Pro: ~$0.002 (2 calls) — $1.25/M input + $10/M output

Cheapest calls:
- Phi-4: ~$0.00009 (2 calls) — $0.07/M input
- DeepSeek V4 Flash: ~$0.00003 (2 calls) — $0.07/M input
- Llama 3.3 70B: ~$0.00013 (2 calls) — $0.10/M input

## How E Values Are Used

1. **Blended pricing formula** in SKILL.md normalizes per-token price to per-task cost using E:
   ```
   C_total = (W_in × E × Pin/1e6) + ((W_out × E + T_think) × Pout/1e6)
   ```
2. **7:2:1 blend** comparisons use E for per-task cost parity (though E cancels out in same-family comparisons, it matters across families)
3. **Cost-per-work-unit** examples in `work-unit-examples.md` use E to compute real USD cost per coding/planning/review task
4. **Strategy assessments** factor E into "is this model actually cheaper?" — a model with lower per-token price but higher E may cost more per task

## How to Measure a New Model

1. Prepare code sample (300+ words) and prose sample (200+ words)
2. Count words precisely
3. POST to OpenRouter (or direct API) with `max_tokens=20`, `temperature=0`
4. Read `usage.prompt_tokens`
5. Compute `E_code = tokens_code / words_code`, `E_prose = tokens_prose / words_prose`
6. Compute `E_blend = 0.60 × E_code + 0.40 × E_prose`
7. Store in `models.json` under the model key

If the API doesn't return `usage`, the model cannot be measured via that provider. Try a different provider (some models report usage on direct API but not via OpenRouter routing).
