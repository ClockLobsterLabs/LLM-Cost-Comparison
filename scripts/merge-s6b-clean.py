#!/usr/bin/env python3
"""Merge all clean S6b compression data into the canonical raw file.

Sources (all must share the S6b schema):
  1. session6b-expansion-raw.csv  -> keep only the 10 clean model-configs' good rows
  2. session6b-gapfill-raw.csv    -> GLM 5.2 (3 methods), Phi-4, Nemotron (210 rows)
  3. session6b-rerun-cheap.csv    -> Llama 3.3, MiMo, Codestral, Perplexity Sonar,
                                     GPT-5.4 Nano (400 rows)

Dropped (corrupted originals, not re-run per user decision - cost ceiling too high):
  - Grok Build 0.1 ($0.66 ceiling), Kimi K2.6 ($1.12), Qwen3.7 Plus ($0.42)

After merging, regenerates:
  - session6b-expansion-summary.csv  (by method, with costs)
  - session6b-compression-costs.csv  (by method, total/avg cost)
Also enriches any rows missing a 'cost' value from the OpenRouter pricing API.
"""
import csv, json, os, shutil, urllib.request

OUTDIR = 'data/output-experiment'
RAW = f'{OUTDIR}/session6b-expansion-raw.csv'
GAP = f'{OUTDIR}/session6b-gapfill-raw.csv'
RERUN = f'{OUTDIR}/session6b-rerun-cheap.csv'
COLS = ['model_id','model_name','method','method_desc','task_id','category',
        'prompt_tokens','output_tokens','output_words','is_maxed','max_tokens',
        'reasoning','status','error','cost']

REAL_TASKS = {'one-word','one-sentence','short-code','short-list','reasoning','multi-step',
              'haiku','describe-sunset','grumpy-sysadmin','pirate-speak','socratic',
              'repeat-exact','json-format','phishing-refusal','french-translate','extract-emails'}

# Model-configs whose ORIGINAL rows are clean and kept as-is.
KEEP_ORIGINAL = {'Claude Haiku 4.5','DS V4 Flash','DS V4 Flash Max','DS V4 Pro',
                 'DS V4 Pro Max','Gemini 3 Flash','Jamba Large 1.7','North Mini Code Free',
                 'Nova Pro'}
# GLM 5.2 original has 2 clean methods (smc, json-envelope); gap-fill supplies the other 3.
GLM_KEEP_METHODS = {'smc','json-envelope'}

def load(path):
    if not os.path.exists(path): return []
    with open(path) as f:
        return list(csv.DictReader(f))

# Fetch live pricing for cost enrichment
def get_prices():
    try:
        d = json.loads(urllib.request.urlopen(
            urllib.request.Request('https://openrouter.ai/api/v1/models'), timeout=20).read())
        return {m['id']: {'in': float(m['pricing']['prompt']),
                          'out': float(m['pricing']['completion'])} for m in d['data']}
    except Exception as e:
        print(f'  WARN: could not fetch prices ({e}); skipping enrichment')
        return {}

prices = get_prices()

# 1. From original: keep clean rows of KEEP_ORIGINAL + GLM 5.2's 2 good methods
orig = load(RAW)
kept_orig = []
for r in orig:
    if r['model_name'] in KEEP_ORIGINAL and r['task_id'] in REAL_TASKS:
        kept_orig.append(r)
    elif r['model_name'] == 'GLM 5.2' and r['method'] in GLM_KEEP_METHODS and r['task_id'] in REAL_TASKS:
        kept_orig.append(r)
print(f'From original: kept {len(kept_orig)} clean rows (of {len(orig)} total)')

# 2. Gap-fill rows (GLM new methods + Phi-4 + Nemotron)
gap = load(GAP)
print(f'From gap-fill: {len(gap)} rows')

# 3. Re-run rows (5 cheap models)
rerun = load(RERUN)
print(f'From re-run:   {len(rerun)} rows')

# Combine
all_rows = kept_orig + gap + rerun

# Enrich cost for any row missing it (recompute from live prices + token counts)
enriched = 0
for r in all_rows:
    if not r.get('cost') or r['cost'] in ('', 'N/A', 'None'):
        p = prices.get(r['model_id'])
        if p and r.get('output_tokens') and r.get('prompt_tokens'):
            c = float(r['prompt_tokens'])*p['in'] + float(r['output_tokens'])*p['out']
            r['cost'] = round(c, 8)
            enriched += 1
print(f'Enriched {enriched} rows with computed costs')

# Normalize: ensure every row has all COLS (re-run added 'cost'; originals may lack it)
for r in all_rows:
    for c in COLS:
        r.setdefault(c, '')
    # keep only COLS in consistent order

# Dedupe by (model_name, method, task_id) - later source wins (rerun > gap > orig)
seen = {}
for r in all_rows:
    seen[(r['model_name'], r['method'], r['task_id'])] = r
merged = list(seen.values())

# Sort
method_order = ['smc','json-envelope','diff-only','verb-noun','word-deletion']
task_order = ['one-word','one-sentence','short-code','short-list','reasoning','multi-step',
              'haiku','describe-sunset','grumpy-sysadmin','pirate-speak','socratic',
              'repeat-exact','json-format','phishing-refusal','french-translate','extract-emails']
# build model order from a sensible canonical list
model_order_src = ['Jamba Large 1.7','North Mini Code Free','Nova Pro','Claude Haiku 4.5',
                   'DS V4 Flash','DS V4 Flash Max','DS V4 Pro','DS V4 Pro Max','Gemini 3 Flash',
                   'GLM 5.2','Phi-4','Nemotron 3 Ultra Free','Llama 3.3 70B','MiMo-V2.5',
                   'Codestral','Perplexity Sonar','GPT-5.4 Nano']
model_order = sorted(set(r['model_name'] for r in merged),
                     key=lambda m: model_order_src.index(m) if m in model_order_src else 999)
def sortkey(r):
    return (model_order.index(r['model_name']),
            method_order.index(r['method']),
            task_order.index(r['task_id']))
merged.sort(key=sortkey)

# Backup original raw file
if os.path.exists(RAW):
    shutil.copy(RAW, RAW + '.premerge-bak')

# Write merged raw
with open(RAW, 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=COLS)
    w.writeheader()
    for r in merged:
        w.writerow({c: r.get(c, '') for c in COLS})

# Report
from collections import Counter
print(f'\nMerged raw: {len(merged)} rows -> {RAW}')
print('models:', len(set(r['model_name'] for r in merged)))
print('status:', dict(Counter(r['status'] for r in merged)))
print('errors:', [(r['model_name'],r['method'],r['task_id']) for r in merged if r['status']!='success'])

# ---- Regenerate summary by method ----
succ = [r for r in merged if r['status']=='success' and r['output_tokens']]
summary = []
for meth in method_order:
    grp = [r for r in succ if r['method']==meth]
    if not grp: continue
    toks = [float(r['output_tokens']) for r in grp]
    words = [float(r['output_words']) for r in grp if r['output_words']]
    costs = [float(r['cost']) for r in grp if r.get('cost') not in ('','N/A',None)]
    summary.append({
        'method': meth, 'desc': grp[0]['method_desc'], 'count': len(grp),
        'avg_tokens': round(sum(toks)/len(toks),1),
        'max_tokens': int(max(toks)), 'min_tokens': int(min(toks)),
        'avg_words': round(sum(words)/len(words),1) if words else '',
        'total_cost': round(sum(costs),5) if costs else '',
        'avg_cost': round(sum(costs)/len(costs),7) if costs else '',
    })
with open(f'{OUTDIR}/session6b-expansion-summary.csv','w',newline='') as f:
    w=csv.DictWriter(f, fieldnames=['method','desc','count','avg_tokens','max_tokens','min_tokens','avg_words','total_cost','avg_cost'])
    w.writeheader(); [w.writerow(s) for s in summary]
print('\n=== Summary by method ===')
for s in summary:
    print(f"  {s['method']:14s} avg_tok={s['avg_tokens']:7.1f} avg_words={s['avg_words']:6.1f} n={s['count']:3d} total=${s['total_cost']}")

# ---- Per-model coverage check ----
print('\n=== Per-model coverage (method count / 5 expected) ===')
for m in model_order:
    mr=[r for r in succ if r['model_name']==m]
    mcount=len(set(r['method'] for r in mr))
    print(f"  {m:24s} {mcount}/5 methods | {len(mr):3d} rows")
