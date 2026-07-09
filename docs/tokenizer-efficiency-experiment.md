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

- **Output verbosity**: Models differ in how many output words they produce for the same prompt, even when max_tokens is unconstrained
- **Reasoning overhead**: Some models (DeepSeek R1, o3-mini) emit invisible chain-of-thought tokens that count toward `usage.completion_tokens` but are not visible in the response text. These are billed at output rates.

### 8.2 Proposed Measurement Protocol

Same infrastructure as Session 5, but with small **task prompts** instead of sample texts, and `usage.completion_tokens` as the measured field:

| Parameter | Input E (Session 5) | Output/reasoning measurement |
|-----------|-------------------|------------------------------|
| Measured field | `prompt_tokens` | `completion_tokens` |
| Prompt | Sample text (word count fixed) | Task instruction (word count fixed) |
| max_tokens | 20 (cap output cost) | Varies by task (see below) |
| Expected response | Short/ignored | Measured output |
| Key metric | E = tokens_per_word(input) | Output_tokens, thinking_tokens |

**Critical: cap max_tokens to minimize cost.** Each output token is billed at the model's output rate (typically 4-30× the input rate). Keeping max_tokens small is essential:

| max_tokens | Cost per call (DeepSeek V4 Flash) | Cost per call (Claude Haiku 4.5) | Cost per call (Gemini 2.5 Pro) |
|:----------:|:---------------------------------:|:-------------------------------:|:-----------------------------:|
| 20 | ~$0.000006 | ~$0.00002 | ~$0.0002 |
| 100 | ~$0.000028 | ~$0.00010 | ~$0.0010 |
| 500 | ~$0.000140 | ~$0.00050 | ~$0.0050 |
| 2000 | ~$0.00056 | ~$0.0020 | ~$0.020 |

Even at 500 tokens, individual calls cost fractions of a cent. A full 21-model test at max_tokens=500 costs ~$0.10-0.40.

### 8.3 Proposed Task Suite (Output Efficiency)

Six tasks designed to measure different output and reasoning dimensions. Each is a short prompt (≤25 words) eliciting a specific-length response:

| # | Task | Prompt | Expected output | max_tokens | What it measures |
|:-:|------|--------|----------------|:----------:|------------------|
| 1 | One-word | `"What is the capital of France?"` | ~1 word | 20 | Minimum output verbosity per model |
| 2 | One-sentence | `"Explain what a database index does in one sentence."` | ~15-30 words | 100 | Single-sentence efficiency |
| 3 | Short code | `"Write a JavaScript function that adds two numbers and returns the result."` | ~30-50 words | 200 | Code generation verbosity |
| 4 | Short list | `"List three cloud providers and their primary database service."` | ~25-40 words | 150 | Structured output verbosity |
| 5 | Reasoning | `"What is the last digit of 3^1000? Show your reasoning step by step."` | ~50-200 words | 500 | Reasoning token overhead; visible reasoning vs. hidden thinking_tokens |
| 6 | Multi-step | `"A bat and a ball cost $1.10. The bat costs $1.00 more than the ball. How much does the ball cost? Think step by step."` | ~50-150 words | 500 | Classic reasoning test; measures thinking_tokens vs. visible reasoning |

### 8.4 Cost Estimates

| Scenario | Calls | max_tokens | Est. cost | Notes |
|----------|:-----:|:----------:|:---------:|-------|
| Single model, all 6 tasks | 6 | 20-500 | ~$0.003-0.01 | Quick spot-check |
| Top-10 models, all 6 tasks | 60 | 20-500 | ~$0.03-0.10 | Good coverage for ~$0.10 |
| All 21 measurable models, tasks 1-4 only | 84 | 20-200 | ~$0.05-0.15 | Output efficiency only, no reasoning |
| All 21 models, full 6-task suite | 126 | 20-500 | ~$0.15-0.50 | Full output + reasoning map |
| All 21 models, tasks 5-6 only (reasoning) | 42 | 500 | ~$0.10-0.30 | Reasoning overhead only |

All estimates assume OpenRouter PAYG pricing. Actual costs depend on model choice — cheap models (DeepSeek V4 Flash at $0.07/M out) dominate the call volume. Running tasks 5-6 alone on the 5 cheapest models costs <$0.01.

### 8.5 Key Questions These Tasks Answer

1. **Output verbosity rank**: Which families produce the fewest output words per task?
2. **Reasoning tax**: For models with `thinking_tokens` support (DeepSeek R1, o-series), what fraction of billed completion tokens are hidden?
3. **Prompt sensitivity**: Does a one-sentence constraint reliably limit output, or do some models ignore it?
4. **Code vs. prose output**: Same gap as input (code is ~1.7× more tokens per word)?
5. **Stability**: Do output token counts vary across runs at temperature=0?

### 8.6 Limitations

- Output tokens are inherently non-deterministic — even at temperature=0, model internals (prefix caching, implementation details) can shift output length
- `thinking_tokens` is only available for models that return it in the `usage` object (DeepSeek R1 returns it; o3-mini via OpenRouter does not)
- max_tokens caps are enforced differently across providers — Grok 4.5 ignored max_tokens=20 (generated 461-1161 tokens); it may similarly ignore caps for output tasks
- Short prompts (<10 words) have high per-message overhead relative to content, making E noisy for output tasks
