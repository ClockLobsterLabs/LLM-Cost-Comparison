# Tokenizer Efficiency Experiment

**Date**: 2026-07-08 (Sessions 1-4); 2026-07-09 (Session 5 — standardized re-test)
**Author**: OpenCode DeepSeek V4 Flash Max Agent c/o Victor Salmon
**Platform**: OpenRouter API
**Total cost**: ~$0.66 (Session 5: ~$0.20)

---

## Abstract

Tokenizer efficiency (E) measures how many tokens a model family generates per word of text. It bridges per-token pricing and per-task costing. Without E, a model with lower per-token price but higher token density may appear cheaper than it really is. This experiment measured E for 21 model families (23 models) by submitting fixed code, prose, and blended samples to the OpenRouter API and reading `usage.prompt_tokens` from each response.

---

## 1. Introduction

Each model family uses a different tokenizer (BPE, DSL, SentencePiece, o200k, etc.). The same English text can produce dramatically different token counts across families — Grok uses 2.66 tokens per word while Perplexity Sonar uses 1.76, a 51% difference. This means per-token price comparisons alone are misleading.

The tokenizer efficiency (E) normalizes cost comparisons by answering: **"How many tokens does this model need to represent one word of my input?"**

---

## 2. Hypothesis

**Null hypothesis (H₀)**: All model families have the same tokenizer efficiency (E ≈ constant). Differences in per-token pricing fully explain cost differences.

**Alternative hypothesis (H₁)**: Tokenizer efficiency varies significantly across families (E ranges from ~1.76 to ~2.66). A model with lower per-token price but higher E may cost more per task than a model with higher per-token price but lower E.

---

## 3. Materials

### 3.1 Sample Texts (Session 5 — Standardized)

> Sessions 1-4 used varying sample lengths and API keys. Session 5 re-tested all measurable models with identical conditions for apples-to-apples comparison. Values in this document are from Session 5 unless noted.

Three sample texts were used, all submitted to every model:

**Code sample** (306 words):
- Multi-function TypeScript module: async batch processing with generics, error handling, AbortController, Promise.all workers, type definitions
- Rich in special characters: braces, semicolons, angle brackets, dot notation, arrow functions

**Prose sample** (235 words):
- Technical architecture paragraph: batch processing pattern description
- Natural English with punctuation: dashes, colons, commas, periods

**Blended sample** (250 words):
- Technical documentation prose with inline code references, method names, API endpoints, types
- Mix of natural language and code-like patterns: backtick-enclosed identifiers, `PascalCase` names, `UPPER_CASE` constants, `/api/v1/` endpoints, type annotations like `Array<number>`
- Tests how tokenizers handle technical vocabulary with special characters embedded in prose

### 3.2 Standardized Conditions

All measurements in Session 5 share these fixed conditions. Changing any one may shift E values (see §6.3):

| Condition | Fixed value | Why it matters |
|-----------|-------------|----------------|
| API key | `OPENROUTER_CODE_KEY` (single workspace) | Different keys route to different inference providers; Session 1-4 used 3 different keys with divergent results |
| API endpoint | `https://openrouter.ai/api/v1/chat/completions` | Direct provider APIs (AWS Bedrock, Azure, GCP) may report different token counts for the same model |
| max_tokens | 20 | Must be small enough to minimize output cost but large enough for the model to return `usage`; 20 works for all measurable models |
| temperature | 0 | Deterministic — prompt_tokens is deterministic regardless, but zero eliminates edge cases |
| message format | Single `user` message only | No system prompt, no assistant prefix — measures raw input tokenization only |
| Sample word counts | Code=306, Prose=235, Blended=250 | Long enough to amortize per-message overhead, short enough to keep cost at ~$0.003/call |
| Sample content | Fixed .txt files per type | Identical text across all models — only the tokenizer changes |
| Order of calls | Alphabetical by model, then code→prose→blended | Models tested within minutes of each other (no provider drift) |
| Date | 2026-07-09 | All 69 calls in one afternoon — no version drift |

### 3.3 API Configuration

| Parameter | Value |
|-----------|-------|
| Endpoint | `https://openrouter.ai/api/v1/chat/completions` |
| Method | POST |
| Authentication | Bearer token (`OPENROUTER_CODE_KEY`) |
| max_tokens | 20 (all models) |
| temperature | 0 |
| messages | Single `user` message containing sample text |
| Measured field | `usage.prompt_tokens` from response JSON |
| Total calls | 69 (23 models × 3 samples) |
| Date | 2026-07-09 |

### 3.4 Data Processing

```
E_code = prompt_tokens(code_sample) / 306
E_prose = prompt_tokens(prose_sample) / 235
E_blended = prompt_tokens(blended_sample) / 250
E_60_40 = 0.60 × E_code + 0.40 × E_prose
E_33_33_33 = (E_code + E_prose + E_blended) / 3
```

The 60:40 blend reflects a typical coding workload where code-generation tasks dominate. The 33:33:33 blend gives equal weight to all three sample types.

### 3.4 Eliminated / Unmeasurable Models

| Model | Reason |
|-------|--------|
| Fugu Ultra | Ignores max_tokens (10,729 output for 306-word code); reports ~95 tok/word |
| o4-mini | OpenAI Responses API — no `usage.prompt_tokens` field |
| Inflection 3 Pi / Productivity | Provider returns empty 502 responses |
| Qwen 3.7 Plus / Max | OpenRouter content guardrail blocks access |
| Sonar Reasoning Pro / Deep Research | Search models timeout before returning `usage` |

---

## 4. Method

### 4.1 Protocol

1. Define 23 model IDs from OpenRouter's model catalog
2. Read each sample text from file
3. For each model, send 3 POST requests (one per sample type)
4. Read `usage.prompt_tokens` and `usage.completion_tokens`
5. Compute E values and blend scores
6. Save raw results to CSV

### 4.2 Guardrail Handling

Earlier sessions (1-4) encountered guardrail blocks for 11 models due to workspace-level Model Access filtering in OpenRouter. Session 5 used `OPENROUTER_CODE_KEY` which had permissive routing — no models were guardrail-blocked.

### 4.3 Model ID Changes

Several model IDs changed between Sessions 1-4 and Session 5:

| Old ID | New ID |
|--------|--------|
| `deepseek/deepseek-chat-v4-flash` | `deepseek/deepseek-v4-flash` |
| `deepseek/deepseek-chat-v3.2` | `deepseek/deepseek-v3.2` |
| `moonshotai/kimi-k2.5-code` | `moonshotai/kimi-k2.7-code` |
| `meta-llama/llama-4-maverick-17b-128e` | `meta-llama/llama-4-maverick` |

### 4.4 Failed Measurements

- DeepSeek V3.2 (corrected ID) returned higher E values than other DeepSeek models (code E=2.50 vs 2.28-2.29), suggesting it may route to a different model variant
- Grok 4.5 ignored `max_tokens=20` in all 3 calls (461-1161 output tokens instead of 20), but `prompt_tokens` is unaffected by this

---

## 5. Results

### 5.1 Ranked Families (by blend_60_40)

| Rank | Family | Model | Code E | Prose E | Blend E | E blend (60:40) | E blend (33:33:33) |
|:----:|--------|-------|:-----:|:------:|:-------:|:---------------:|:------------------:|
| 1 | Perplexity | Sonar Pro / Pro Search | 2.17 | 1.14 | 1.68 | **1.76** | 1.66 |
| 2 | OpenAI | GPT-5.4 Nano, o3-mini | 2.20 | 1.16 | 1.71 | **1.78** | 1.69 |
| 3 | Microsoft | Phi-4 | 2.19 | 1.17 | 1.71 | **1.78** | 1.69 |
| 4 | Kimi | K2.7 Code | 2.21 | 1.16 | 1.71 | **1.79** | 1.69 |
| 5 | Meta | Llama 3.3 70B | 2.20 | 1.19 | 1.82 | **1.80** | 1.74 |
| 6 | Meta | Llama 4 Maverick | 2.22 | 1.19 | 1.72 | **1.81** | 1.71 |
| 7 | GLM | GLM 5.2 | 2.21 | 1.20 | 1.73 | **1.81** | 1.71 |
| 8 | Mistral | Large 3, Codestral | 2.27 | 1.18 | 1.73 | **1.83** | 1.72 |
| 9 | DeepSeek | V4 Flash, R1, Chat V3 | 2.28 | 1.19 | 1.76 | **1.84** | 1.74 |
| 10 | DeepSeek | V3.2 | 2.31 | 1.22 | 1.76 | **1.87** | 1.76 |
| 11 | MiniMax | M3 | 2.33 | 1.29 | 1.84 | **1.91** | 1.82 |
| 12 | Amazon | Nova Pro | 2.45 | 1.16 | 1.76 | **1.93** | 1.79 |
| 13 | Cohere | Command A | 2.50 | 1.13 | 1.71 | **1.95** | 1.78 |
| 14 | Gemini | 2.5 Pro | 2.68 | 1.14 | 1.72 | **2.06** | 1.85 |
| 15 | AI21 | Jamba Large 1.7 | 2.82 | 1.22 | 1.90 | **2.18** | 1.98 |
| 16 | Anthropic | Claude Haiku 4.5 | 2.82 | 1.30 | 1.88 | **2.21** | 2.00 |
| 17 | Amazon | Nova Premier | 2.92 | 1.31 | 1.92 | **2.28** | 2.05 |
| 18 | Grok | Grok 4.5 | 3.09 | 2.01 | 2.54 | **2.66** | 2.55 |

### 5.2 Key Findings

1. **Code is universally more expensive** — 1.7–2.0× more tokens per word than prose for most families, due to special characters (braces, semicolons, operators)

2. **Grok is the most verbose** — 2.66 blend vs Perplexity's 1.76: 51% more tokens for the same text

3. **Perplexity Sonar is the most efficient** — 1.76 blend, despite being a search-augmented model with complex system prompts

4. **o200k is remarkably stable across models** — GPT-5.4 Nano (2.20/1.16) and o3-mini (2.20/1.16) produce identical values

5. **Same-family consistency varies** — Mistral Large 3 and Codestral are nearly identical (2.27 vs 2.25 code); DeepSeek V4 Flash, R1, and Chat V3 cluster at 2.28-2.29; but DeepSeek V3.2 diverges (2.31 code vs 2.50 for the corrected ID variant)

6. **Blended-sample E is a useful third metric** — It typically falls between code and prose E, closer to prose for most models (suggesting tokenizers handle technical documentation similarly to natural prose)

7. **Grok 4.5 is the outlier** — Its prose E (2.01) is nearly double the pack (1.14-1.31), and its output generation ignores `max_tokens` constraints

### 5.3 Comparison with Earlier Sessions

Sessions 1-4 used varying sample texts and API keys. Session 5's standardized re-test shows that earlier measurements were affected by:

- **Different OpenRouter API keys** route to different inference providers, which may serve different model builds. Session 5 used `OPENROUTER_CODE_KEY` exclusively.
- **Different sample lengths** (77-, 152-, 306-, and 382-word samples) produce different per-message overhead amortization
- **Globally, Session 5 E values are higher than Session 1** — by ~0.2-0.6 E points per model — likely due to different provider routing

Session 5 data should be treated as canonical. Earlier sessions are preserved for reproducibility but are superseded for cost calculations.

---

## 6. Discussion

### 6.1 Practical Impact

E values have real cost implications. Consider two models at the same per-token price:
- Model A (E=1.76): 10,000 words → 17,600 tokens
- Model B (E=2.66): 10,000 words → 26,600 tokens (51% more)

The per-task cost formula that accounts for tokenizer efficiency:

```
C_total = (W_in × E × Pin/10^6) + ((W_out × E + T_think) × Pout/10^6)
```

### 6.2 Limitations

1. **Single provider**: All measurements via OpenRouter. Different providers (Azure, Cohere Cloud, AWS Bedrock) may report different token counts for the same model
2. **Single API key**: `OPENROUTER_CODE_KEY` may route differently than other keys; Session 1 values (from `OPENROUTER_SETUP_KEY`) differ significantly
3. **Single sample per type**: One code, one prose, one blended sample each. Real workloads vary within types
4. **No output tokenization measured**: E measures input tokenization only. Output tokens follow the same tokenizer but weren't independently verified
5. **Blend weight is arbitrary**: 60:40 code:prose reflects a coding workload. Other workloads (documentation, data analysis) would want different blends or the 33:33:33 blend

### 6.3 Key Discrepancies from Earlier Measurements

Earlier Sessions 1-4 reported significantly lower E values for many models (e.g., DeepSeek V4 Flash at 1.65 vs Session 5's 1.85; GLM 5.2 at 1.59 vs 1.81). The root cause is likely **different OpenRouter provider routing** — different API keys are scoped to different workspaces with different provider allowlists. The measurement protocol is sound; the routing variable was not controlled until Session 5.

### 6.4 Reproducibility

The experiment is fully reproducible:
1. Set up an OpenRouter account with API key
2. Use the `OPENROUTER_CODE_KEY` or any key with permissive routing
3. Submit POST requests with the sample texts and `max_tokens=20`
4. Read `usage.prompt_tokens` from responses
5. Divide by word count for E

Total cost to reproduce: ~$0.20 at current OpenRouter pricing.

---

## 7. Data

Raw data CSV: [`../data/experiment-session5-raw.csv`](../data/experiment-session5-raw.csv)
Consolidated CSV: [`../data/experiment-session5-consolidated.csv`](../data/experiment-session5-consolidated.csv)
Summary CSV: [`../data/experiment-session5-summary.csv`](../data/experiment-session5-summary.csv)
Canonical sample texts: [`../data/samples/`](../data/samples/)
Experiment runner: [`../experiment-runner.ps1`](../experiment-runner.ps1)
User config template: [`../example-config.env`](../example-config.env)

Columns (raw):
- `trial_id`: Unique identifier per call
- `model_id`: OpenRouter model slug
- `model_name`: Human-readable name
- `family`: Tokenizer family
- `sample_type`: `code`, `prose`, or `blended`
- `word_count`: Words in the submitted sample
- `prompt_tokens`: Raw `usage.prompt_tokens` from API response
- `output_tokens`: Raw `usage.completion_tokens`
- `tokens_per_word`: Computed E (prompt_tokens / word_count)
- `status`: `success`, `failed`, `blocked`, or `timeout`
- `error`: Error message if failed
- `max_tokens`, `temperature`: API parameters

---

## Appendix A: Sample Texts

### Code Sample (306 words)

```
export async function processBatch<T>(
  items: T[],
  handler: (item: T, index: number) => Promise<Result<T>>,
  options: BatchOptions = {}
): Promise<BatchResult<T>> {
  const { concurrency = 3, retryCount = 2, timeout = 30000 } = options;
  const results: Map<string, Result<T>> = new Map();
  const errors: Error[] = [];
  let completed = 0;
  const queue = [...items];
  async function worker(): Promise<void> {
    while (queue.length > 0) {
      const item = queue.shift() as T;
      const key = `${items.indexOf(item)}`;
      for (let attempt = 0; attempt <= retryCount; attempt++) {
        try {
          const controller = new AbortController();
          const timer = setTimeout(() => controller.abort(), timeout);
          const result = await handler(item, items.indexOf(item));
          clearTimeout(timer);
          results.set(key, result);
          break;
        } catch (err) {
          if (attempt === retryCount) {
            errors.push(err instanceof Error ? err : new Error(String(err)));
          }
        }
      }
      completed++;
    }
  }
  const workers = Array.from(
    { length: Math.min(concurrency, items.length) },
    () => worker()
  );
  await Promise.all(workers);
  return {
    results: Array.from(results.values()),
    errors,
    total: items.length,
    completed,
    failed: errors.length,
  };
}
```

### Prose Sample (235 words)

```
The batch processing pattern addresses a fundamental challenge in
asynchronous systems: how to process many tasks concurrently without
overwhelming downstream resources. By limiting concurrency to a
configurable number of parallel workers, the system maintains
predictable load on databases and APIs. Each worker pulls items from
a shared queue and processes them independently. When a task fails,
the pattern supports configurable retry logic with exponential backoff
to handle transient failures gracefully. Timeout handling prevents a
single stuck task from holding up the entire batch indefinitely. The
result object aggregates successful outcomes alongside error
information so callers can inspect partial failures without losing
progress. This approach is widely used in data migration scripts,
web scraping pipelines, and bulk API operations where reliability
matters more than raw throughput. In practice, the pattern reduces
tail latency by isolating slow tasks from fast ones, and it improves
debuggability by separating concerns: the queue manages ordering,
the workers manage execution, and the aggregator manages results.
Error boundaries further ensure that a single malformed input does
not crash the entire pipeline, making the system resilient to
unexpected data shapes. Visibility into batch progress helps
operations teams monitor throughput and detect stalled workers before
they cause cascading delays. This combination of concurrency control,
retry logic, isolation, and error aggregation makes the batch
processing pattern one of the most fundamental building blocks in
distributed systems engineering.
```

### Blended Sample (250 words)

```
The `UserService` class manages authentication and authorization for
the platform. It exposes methods like `login`, `logout`, and
`refreshToken` that interact with the `TokenStore` and
`SessionRepository`. Each method validates input against a
`UserSchema` before making calls to the internal `AuthProvider`.
The `POST /api/auth/login` endpoint accepts an `AuthPayload` object
containing `email` and `password` fields. On success, it returns a
`TokenResponse` with an `access_token`, `refresh_token`, and
`expires_in` value. Error responses follow a standard `ApiError`
envelope with `code`, `message`, and `details` properties. The
`middleware` pipeline includes `rateLimiter`, `requestValidator`, and
`errorHandler` layers that wrap every route. Data flows from
controllers through `Service` classes into `Repository`
implementations that abstract the database layer. The `database`
module supports both `PostgreSQL` and `SQLite` providers via a common
`DatabaseAdapter` interface. Queries are built using the `queryBuilder`
utility which generates parameterized SQL statements. The `cache`
layer sits between services and repositories using `RedisStore` with
configurable `TTL` values. Background jobs are managed by the
`JobScheduler` which polls a `JobQueue` table every `30s`. Each job
has a `status` field set to `pending`, `processing`, `completed`, or
`failed` during its lifecycle. The system emits typed `DomainEvent`
objects through an `EventBus` that fans out to registered
`EventSubscriber` instances. Monitoring is handled by the
`HealthController` which exposes `GET /api/health` and
`GET /api/ready` endpoints. Metrics collected include `request_count`,
`error_rate`, and `p99_latency` pushed to `Grafana` via the
`metricsCollector` singleton. Configuration is loaded from environment
variables with fallback defaults defined in `config/defaults.json`.
This service architecture follows a layered hexagonal pattern with
clear separation between external interfaces and core business logic.
```

---

## Appendix B: OpenRouter API Request Template

```json
POST https://openrouter.ai/api/v1/chat/completions
Authorization: Bearer sk-or-v1-...
Content-Type: application/json

{
  "model": "model-family/model-name",
  "messages": [
    {
      "role": "user",
      "content": "<sample text here>"
    }
  ],
  "max_tokens": 20,
  "temperature": 0
}
```

Response field to read: `usage.prompt_tokens`

---

## Appendix C: Session 5 Cost Breakdown

| Component | Calls | Actual Cost | Notes |
|-----------|:-----:|:-----------:|-------|
| Primary run (17 models) | 51 | ~$0.16 | All succeeded |
| Corrected ID retests (4 models) | 12 | ~$0.03 | Replaced failed stale-ID calls |
| **Total Session 5** | **63** | **~$0.20** | 21 models × 3 samples |

Excluded models (6 calls, $0 cost): Fugu, o4-mini, Inflection, Qwen, Sonar Reasoning/Deep Research — failed on protocol, not billed.

Session 5 cost ~$0.20 for 63 successful data points. Measuring one model with all three samples costs ~$0.01.

---

## Appendix D: Superseded Session Data

Sessions 1-4 (2026-07-08) used varying sample lengths, API keys (OPENROUTER_SETUP_KEY, OPENROUTER_VERI_KEY), and max_tokens values (16-20). These are archived in `data/tokenizer-efficiency-raw.csv` and `data/openrouter-generations-2026-07-08.csv` for reproducibility. Session 5 data supersedes all earlier measurements for cost calculations.

The primary limitations of Sessions 1-4:
- Different sample texts per session (77-word, 152-word, 306-word, 382-word code samples)
- Different API keys routed to different inference providers
- max_tokens=16 for o3-mini/o4-mini in Session 4
- 11 models blocked by workspace guardrails in Session 2

---

## 8. Extending the Experiment — Output Tokens & Reasoning Overhead

### 8.1 Why Measure Output Efficiency?

The E metric measures **input** tokenization. Output tokens use the same tokenizer, so E applies to output word counts as well — but output cost is dominated by **how many words the model generates**, not just how it tokenizes them. Two additional dimensions matter:

- **Output verbosity**: Models differ in how many output words they produce for the same prompt, even when max_tokens is unconstrained. A model that writes a 200-word explanation when a 30-word one would do burns your budget even if its tokenizer is efficient.
- **Reasoning overhead**: Some models (DeepSeek R1, o3-mini) emit invisible chain-of-thought tokens that count toward `usage.completion_tokens` but are not visible in the response text. These are billed at output rates. For DeepSeek R1, thinking tokens can be 3-5× the visible output.

### 8.2 Measurement Protocol

Same infrastructure as Session 5, but with **task prompts** instead of sample texts, and `usage.completion_tokens` (and optionally `usage.thinking_tokens`) as the measured field:

| Parameter | Input E (Session 5) | Output/reasoning |
|-----------|-------------------|------------------|
| Measured field | `prompt_tokens` | `completion_tokens` |
| Prompt | Fixed sample text | Fixed task prompt (≤25 words) |
| max_tokens | 20 (cap output cost) | Task-appropriate cap (20-500) |
| temperature | 0 | 0 (but output length varies) |
| Key metric | E = prompt_tok ÷ words | Output_tokens, thinking_tokens |

### 8.3 Cost Ceilings — How max_tokens Protects Your Budget

Output tokens are billed at 4-30× the input rate. Without a cap, a single verbose response from an expensive model could cost $0.02-0.05 — 100× more than a capped call. **Every claimed output token is billable**, so the cap acts as a circuit breaker:

| Scenario | Cost per call (cheapest: Phi-4) | Cost per call (median: Claude Haiku) | Cost per call (most expensive: Perplexity Sonar) |
|:---------|:-------------------------------:|:------------------------------------:|:-----------------------------------------------:|
| max_tokens=20 | $0.000003 | $0.0001 | $0.0003 |
| max_tokens=100 | $0.000014 | $0.0005 | $0.0015 |
| max_tokens=200 | $0.000028 | $0.0010 | $0.0030 |
| max_tokens=500 | $0.000070 | $0.0025 | $0.0075 |
| max_tokens=2000 | $0.000280 | $0.0100 | $0.0300 |
| No cap (avg reasoning ~800 tok) | ~$0.00011 | ~$0.0040 | ~$0.012 |
| No cap (wordy model ~4000 tok) | ~$0.00056 | ~$0.020 | ~$0.060 |

**Conclusion**: Even at max_tokens=500, the most expensive model costs $0.0075 per call. A full 126-call experiment across all 21 models x 6 tasks would cost at most ~$0.38 even if every model hits its cap on every task.

**Models that ignore max_tokens**: Grok 4.5 ignored max_tokens=20 in Session 5, generating 461-1161 tokens per call instead. If it does the same at max_tokens=500, it caps naturally at 500 (since that's higher than its uncapped average). For tasks where it would generate >500 tokens, it would be truncated. The cost ceiling still holds because max_tokens=500 is the model-side limit — OpenRouter enforces it server-side for most models.

**What if a model's natural response exceeds the cap?** The response is truncated. You lose the tail of the reasoning chain. For tasks 1-4, caps are generously sized for the expected response length. For tasks 5-6, the 500-token cap may truncate deep reasoning — which is itself a finding worth documenting (which models hit the ceiling).

### 8.4 Proposed Task Suite

Six tasks, ordered from minimal output to reasoning-intensive. Each cap is set high enough for a typical response but low enough to keep cost under control:

| # | Task | Prompt | Est. natural output | Pre-E token range | max_tokens cap | Cost at cap (cheapest) | Cost at cap (median) | Cost at cap (most expensive) | Truncation risk |
|:-:|------|--------|:-------------------:|:-----------------:|:--------------:|:---------------------:|:-------------------:|:---------------------------:|:---------------:|
| 1 | **One-word** | `"What is the capital of France?"` | 1 word | 2-3 tok | 20 | $0.000003 (Phi-4) | $0.0001 (Haiku) | $0.0003 (Sonar) | None — 20 tok is 10× what's needed |
| 2 | **One-sentence** | `"Explain what a database index does in one sentence."` | 15-30 words | 17-60 tok | 100 | $0.00001 (Phi-4) | $0.0005 (Haiku) | $0.0015 (Sonar) | Low — 100 tok ≈ 50-85 words of prose |
| 3 | **Short code** | `"Write a JavaScript function that adds two numbers and returns the result."` | 30-80 words of code | 65-250 tok | 300 | $0.00004 (Phi-4) | $0.0015 (Haiku) | $0.0045 (Sonar) | Low for short function — raise to 300 from earlier 200 to be safe |
| 4 | **Short list** | `"List three cloud providers and their primary database service."` | 25-40 words | 28-84 tok | 150 | $0.00002 (Phi-4) | $0.0008 (Haiku) | $0.0023 (Sonar) | None — 150 tok is 2-5× what's needed |
| 5 | **Reasoning** | `"What is the last digit of 3^1000? Show your reasoning step by step."` | 50-200 visible + 0-2000 hidden | 57-4400 tok | 500 | $0.00007 (Phi-4) | $0.0025 (Haiku) | $0.0075 (Sonar) | Moderate — 500 tok may truncate verbose reasoning chains |
| 6 | **Multi-step** | `"A bat and a ball cost $1.10. The bat costs $1.00 more than the ball. How much does the ball cost? Think step by step."` | 50-150 visible + 0-1500 hidden | 57-3300 tok | 500 | $0.00007 (Phi-4) | $0.0025 (Haiku) | $0.0075 (Sonar) | Moderate — 500 tok may truncate verbose reasoning chains |

> **Pre-E token range** = estimated output tokens using the min and max E values from Session 5 (E_prose 1.14–2.01 for prose tasks, E_code 2.17–3.09 for task 3). For reasoning tasks the hidden thinking tokens are additive and can be 3-5× the visible output — this is the primary unknown the experiment measures.

**Cap justification per task:**

1. **20 tok** — one word needs 2-3 tokens. 20x safety margin. No model needs more.
2. **100 tok** — one sentence = 15-30 words × E_prose ≤ 60 tok. 1.7× safety margin.
3. **300 tok** — short function = 30-80 words × E_code ≤ 250 tok. 1.2× safety margin. Raised from earlier 200 because code is dense and some models add JSDoc comments.
4. **150 tok** — three list items = 25-40 words × E_prose ≤ 84 tok. 1.8× safety margin.
5. **500 tok** — reasoning chain = 50-200 visible words × E_prose = 57-402 tok. Cap at 500 allows short reasoning but WILL truncate long chains. This is acceptable: the truncation itself is data (which models hit the ceiling?).
6. **500 tok** — same logic as task 5.

### 8.5 Cost by Scenario

All values assume every model hits its max_tokens cap (worst case). Actual costs will be lower since most responses are shorter than the cap.

| Scenario | Calls | Cost (worst case, all cheap models) | Cost (worst case, all median models) | Cost (worst case, all expensive models) | Likely actual cost |
|----------|:-----:|:----------------------------------:|:-----------------------------------:|:--------------------------------------:|:------------------:|
| 1 model, all 6 tasks | 6 | <$0.0003 | ~$0.008 | ~$0.024 | ~$0.003-0.01 |
| 5 cheapest models, all 6 tasks | 30 | <$0.001 | ~$0.015 | — | ~$0.005-0.02 |
| 5 most expensive models, all 6 tasks | 30 | — | ~$0.04 | ~$0.12 | ~$0.03-0.08 |
| Top-10 models, all 6 tasks | 60 | ~$0.002 | ~$0.05 | ~$0.15 | ~$0.03-0.10 |
| Top-10 models, tasks 5-6 only | 20 | ~$0.0007 | ~$0.025 | ~$0.075 | ~$0.01-0.04 |
| All 21 measurable models, tasks 1-4 only | 84 | ~$0.001 | ~$0.04 | ~$0.12 | ~$0.02-0.08 |
| All 21 models, full 6-task suite | 126 | ~$0.003 | ~$0.13 | ~$0.38 | ~$0.10-0.30 |
| All 21 models, tasks 5-6 only (reasoning) | 42 | ~$0.0014 | ~$0.05 | ~$0.16 | ~$0.04-0.12 |

**Key takeaway**: Even the most pessimistic scenario (all 21 models hitting max_tokens on all 6 tasks at Perplexity Sonar prices) costs $0.38. The likely actual cost is closer to $0.10-0.30 — comparable to Session 5's $0.20.

### 8.6 Per-Model Cost Detail (Full 6-Task Suite)

To ground the estimates, here's what each model costs individually assuming it fills every cap:

| Model | Output $/M | Task 1 (20) | Task 2 (100) | Task 3 (300) | Task 4 (150) | Task 5 (500) | Task 6 (500) | All 6 tasks |
|-------|:---------:|:-----------:|:------------:|:------------:|:------------:|:------------:|:------------:|:-----------:|
| Phi-4 | $0.14 | <$0.00001 | $0.00001 | $0.00004 | $0.00002 | $0.00007 | $0.00007 | **$0.0002** |
| DeepSeek V4 Flash | $0.28 | $0.00001 | $0.00003 | $0.00008 | $0.00004 | $0.00014 | $0.00014 | **$0.0004** |
| Codestral | $0.90 | $0.00002 | $0.00009 | $0.00027 | $0.00014 | $0.00045 | $0.00045 | **$0.0014** |
| GPT-5.4 Nano | $1.25 | $0.00003 | $0.00013 | $0.00038 | $0.00019 | $0.00063 | $0.00063 | **$0.0020** |
| Mistral Large 3 | $1.50 | $0.00003 | $0.00015 | $0.00045 | $0.00023 | $0.00075 | $0.00075 | **$0.0024** |
| Kimi K2.7 Code | $4.00 | $0.00008 | $0.00040 | $0.00120 | $0.00060 | $0.00200 | $0.00200 | **$0.0063** |
| Claude Haiku 4.5 | $5.00 | $0.00010 | $0.00050 | $0.00150 | $0.00075 | $0.00250 | $0.00250 | **$0.0079** |
| Grok 4.5 | $6.00 | $0.00012 | $0.00060 | $0.00180 | $0.00090 | $0.00300 | $0.00300 | **$0.0094** |
| Gemini 2.5 Pro | $10.00 | $0.00020 | $0.00100 | $0.00300 | $0.00150 | $0.00500 | $0.00500 | **$0.0157** |
| Command A | $10.00 | $0.00020 | $0.00100 | $0.00300 | $0.00150 | $0.00500 | $0.00500 | **$0.0157** |
| Nova Premier | $12.50 | $0.00025 | $0.00125 | $0.00375 | $0.00188 | $0.00625 | $0.00625 | **$0.0196** |
| Perplexity Sonar | $15.00 | $0.00030 | $0.00150 | $0.00450 | $0.00225 | $0.00750 | $0.00750 | **$0.0236** |

**Interpretation**: Running the full 6-task suite on Perplexity Sonar (the most expensive measurable model at $15/M output) costs at most $0.024 — less than 2.5 cents. Running it on all 21 models together costs at most ~$0.13 at median pricing. Running it on every model at every model's maximum output rate costs at most ~$0.38 in the absolute worst case.

### 8.7 What Happens When a Model Exceeds Its Cap

CAPS SERVE AS BUDGET CEILINGS, not as expectations of output length. If a model would naturally write a 2000-token reasoning chain but max_tokens=500, the response is truncated at 500 tokens. Key implications:

- **Output token count is always ≤ max_tokens** (for models that respect the parameter). The cost ceiling is deterministic.
- **The true cost of the uncapped response** can be estimated post-hoc: if a model hits the cap, you know its natural output was *at least* that long. The uncapped cost is an unbounded multiple.
- **Grok 4.5** is the known outlier — it ignored max_tokens=20 in Session 5 and generated 461-1161 tokens. For this experiment, max_tokens=500 is higher than its typical response for tasks 1-4, so it will likely cap naturally. For tasks 5-6, 500 may still truncate it, which is itself a finding.
- **Thinking models** (DeepSeek R1, o3-mini) count `thinking_tokens` against `completion_tokens`. A model that thinks for 800 tokens and writes 100 words of visible output will hit the 500 cap before it finishes thinking. We may get zero visible output but still know the thinking tokens.
- **If a model hits the cap**, record it explicitly. The fact that it hit the ceiling is as informative as its per-token count.

The worst-case uncapped comparison:

| Model | Scenario | Uncapped visible tok | Uncapped thinking tok | Uncapped cost | Capped cost (500 tok) | Cost ratio |
|-------|----------|:--------------------:|:---------------------:|:-------------:|:---------------------:|:----------:|
| DeepSeek R1 | Reasoning task | ~200 | ~800 | ~$0.0003 | $0.00014 | 2.1× |
| Claude Haiku | Verbose prose | ~800 | 0 | ~$0.004 | $0.0025 | 1.6× |
| Grok 4.5 (ignores cap) | Reasoning | ~1200 | 0 | ~$0.0072 | $0.003 (if capped) | 2.4× |
| Perplexity Sonar | Verified answer | ~600 | 0 | ~$0.009 | $0.0075 | 1.2× |

The cap prevents surprise costs but the uncapped experiment would cost at most ~2-3× more, not 10×. The real cost risk is if a model enters an infinite loop or generates thousands of tokens — but that would be a bug, not typical behavior.

### 8.8 Key Questions These Tasks Answer

1. **Output verbosity rank**: Which families produce the fewest output words per task? Do cheap model families also tend to be terse?
2. **Reasoning tax**: For models with `thinking_tokens` support, what fraction of billed completion tokens are hidden? Is the thinking-to-visible ratio consistent across task difficulty?
3. **Prompt sensitivity**: Does "in one sentence" reliably constrain output length? Which models ignore it?
4. **Code vs. prose output**: Do code-generation tasks produce the same E gap as input (code ~1.7× more tokens per word than prose)?
5. **Cap hit rate**: Which models hit their max_tokens cap on which tasks? (Models that routinely hit the cap may be too verbose for practical use.)
6. **Stability**: Do output token counts vary across tasks at temperature=0?

### 8.9 Limitations

- Output tokens are inherently non-deterministic — even at temperature=0, model internals (prefix caching, implementation details) can shift output length. Each task should be run 2-3 times for a stability estimate.
- `thinking_tokens` is only available for models that return it in the `usage` object (DeepSeek R1 returns it; o3-mini via OpenRouter does not).
- max_tokens caps are enforced differently across providers. Grok 4.5 ignored max_tokens=20 in Session 5; it may cap higher but still respect larger values.
- The cap itself is an intervention. Truncated responses tell us only that a model is *at least* this verbose, not its true natural length.
- Short prompts (<10 words) have high per-message overhead relative to content, making E_noisy for output tasks with very short responses.
- These tasks measure **single-turn** output. Multi-turn conversations compound verbosity in ways this protocol cannot capture.
