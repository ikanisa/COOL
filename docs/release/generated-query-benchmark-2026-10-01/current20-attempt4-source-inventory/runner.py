#!/usr/bin/env python3
"""Outer inventory recorder for the current immutable benchmark, no SQL of its own."""
import datetime,hashlib,json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[4]
OUT=Path(__file__).resolve().parent
INNER=ROOT/'docs/release/generated-query-benchmark-2026-10-01/current20-attempt4-1000-10000'
REVIEW=ROOT/'docs/release/local-database-runtime-2026-09-30/staged-bundle154-attempt18-current20-policy-audit-actor/result.json'
sys.path.insert(0,str(ROOT/'scripts/tests'))
import staged_bundle_upgrade_uat as B

def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def snapshot():return {p.name:digest(p) for p in sorted((ROOT/'supabase/migrations').glob('*.sql'))}
def save(n,v):(OUT/n).write_text(json.dumps(v,indent=2)+'\n')
before=snapshot();proof=json.loads(REVIEW.read_text());stages={n:before.get(n) for n in B.STAGES}
assert len(before)==154+len(B.STAGES) and proof['source_migration_sha256']==stages and proof['status']=='pass'
save('migration-inputs-before.json',before)
source=OUT/'migration-sources';source.mkdir()
for name,sha in before.items():
 data=(ROOT/'supabase/migrations'/name).read_bytes();assert hashlib.sha256(data).hexdigest()==sha;(source/name).write_bytes(data)
argv=[sys.executable,str(ROOT/'scripts/tests/current_generated_query_benchmark_uat.py'),'--output',str(INNER),'--reviewed-stages',str(REVIEW),'--volumes','1000,10000']
save('outer-inputs.json',{'runner_sha256':digest(Path(__file__)),'reviewed_proof_sha256':digest(REVIEW),'source_count':len(before),'stage_count':len(B.STAGES),'argv':argv,'started_at':datetime.datetime.now(datetime.timezone.utc).isoformat()})
with (OUT/'benchmark.stdout').open('w') as stdout,(OUT/'benchmark.stderr').open('w') as stderr:
 run=subprocess.Popen(argv,cwd=ROOT,stdout=stdout,stderr=stderr)
 save('live-process.json',{'owned_benchmark_pid':run.pid,'parent_pid':__import__('os').getpid(),'status':'running'})
 code=run.wait()
after=snapshot();save('migration-inputs-after.json',after)
drift=[n for n in sorted(set(before)|set(after)) if before.get(n)!=after.get(n)]
inner=json.loads((INNER/'result.json').read_text()) if (INNER/'result.json').is_file() else None
result={'status':'pass_scoped' if code==0 and inner and inner['status']=='pass_scoped' and not drift else 'failed','exit_code':code,'inner_packet':str(INNER.relative_to(ROOT)),'inner_result_sha256':digest(INNER/'result.json') if inner else None,'migration_input_count':len(before),'stage_count':len(B.STAGES),'migration_source_drift':drift,'all_migration_files_exact_before_after':not drift,'inner_acceptance':inner['status'] if inner else 'missing','database_calls_here':0,'sql_executed_only_by_owned_inner':True,'provider_truth':False,'completed_at':datetime.datetime.now(datetime.timezone.utc).isoformat()}
save('validation.json',result);save('live-process.json',{'owned_benchmark_pid':run.pid,'status':'terminal','exit_code':code});print(json.dumps(result),flush=True);sys.exit(int(result['status']!='pass_scoped'))
