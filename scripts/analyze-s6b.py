import csv
from collections import defaultdict

s6b=list(csv.DictReader(open('data/output-experiment/session6b-expansion-raw.csv')))
s6=list(csv.DictReader(open('data/output-experiment/session6-output-verbosity.csv')))

# Honest per-task baseline from S6 uncompressed output
task_base=defaultdict(list)
for r in s6:
    if r.get('status') in ('success','') and r.get('output_tokens'):
        task_base[r['task_id']].append(float(r['output_tokens']))
task_base={t:sum(v)/len(v) for t,v in task_base.items()}

succ=[r for r in s6b if r['status']=='success']
print('=== HONEST compression ratios (CR = 1 - method_task_avg / S6_task_baseline) ===')
print()
method_cr={}
for m in ['smc','json-envelope','diff-only','verb-noun','word-deletion']:
    crs=[]
    for t in task_base:
        grp=[float(r['output_tokens']) for r in succ if r['method']==m and r['task_id']==t]
        if grp:
            crs.append(1 - (sum(grp)/len(grp))/task_base[t])
    avg_cr=sum(crs)/len(crs)
    method_cr[m]=avg_cr
    allt=[float(r['output_tokens']) for r in succ if r['method']==m]
    allw=[float(r['output_words']) for r in succ if r['method']==m and r['output_words']]
    cost=sum(float(r['cost']) for r in succ if r['method']==m and r.get('cost') not in ('','None',None))
    print(f'  {m:14s} CR={avg_cr:+.2f} | avg_tok={sum(allt)/len(allt):6.1f} | avg_words={sum(allw)/len(allw):5.1f} | cost=${cost:.4f}')

print()
print('RANKING by compression (higher CR = more compression):')
for m,cr in sorted(method_cr.items(), key=lambda x:-x[1]):
    print(f'  {m:14s} CR={cr:+.2f}')
print()
overall=sum(task_base.values())/len(task_base)
spend=sum(float(r['cost']) for r in succ if r.get('cost') not in ('','None',None))
print(f'Uncompressed baseline (S6 per-task avg): {overall:.0f} tokens')
print(f'S6b corrected spend: ${spend:.2f}')
print(f'S6b calls: {len(succ)} | models: {len(set(r["model_name"] for r in succ))} | tasks: {len(set(r["task_id"] for r in succ))}')
print()
# Per-task breakdown for diff-only (the winner) to show it's real
print('Per-task CR for diff-only (winner) vs baseline:')
for t in sorted(task_base):
    grp=[float(r['output_tokens']) for r in succ if r['method']=='diff-only' and r['task_id']==t]
    if grp:
        mt=sum(grp)/len(grp)
        print(f'  {t:18s} method={mt:6.1f} base={task_base[t]:6.1f} CR={1-mt/task_base[t]:+.2f}')
