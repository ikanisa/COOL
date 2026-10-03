"""Private bounded proof collector; no SQL or maintained writes."""
import hashlib,json,os,signal,subprocess,sys,time
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=next(p for p in HERE.parents if (p/'supabase/migrations').is_dir())
PYTHON='/Volumes/PRO-G40/Development/Python/codex-agents-venv/bin/python3'
CATALOG=ROOT/'docs/release/critical-implementation-2026-10-01/ordinary-schema-catalog209-execution1/observed-output'
OUTPUT=HERE/'generated-current209-invalidation1'
SCRIPT=HERE/'scripts/audits/collect_schema_domain_map.py'
FILES=['scripts/audits/collect_schema_domain_map.py','scripts/tests/collect_schema_lineage_invalidation_test.py']
hashes=lambda:{p:hashlib.sha256((HERE/p).read_bytes()).hexdigest() for p in FILES}
operation,receipt=sys.argv[1:]
assert not (HERE/(receipt+'.json')).exists()
if operation=='focused':
 argv=[PYTHON,'-I','-B',str(HERE/FILES[1])]
elif operation=='generate':
 assert not OUTPUT.exists()
 argv=[PYTHON,'-I','-B',str(SCRIPT),'--root',str(ROOT),'--catalog',str(CATALOG/'ordinary_clean/final-effective-catalog.json'),
 '--catalog',str(CATALOG/'ordinary_populated/final-effective-catalog.json'),'--replay-migrations',str(CATALOG/'captured-migrations'),'--output',str(OUTPUT),'--require-current']
elif operation=='verify':
 argv=[PYTHON,'-I','-B',str(SCRIPT),'--root',str(ROOT),'--output',str(OUTPUT),'--verify','--require-current']
else:raise SystemExit('unknown private operation')
env={'PATH':'/usr/bin:/bin:/usr/sbin:/sbin'};before=hashes();start=time.monotonic();timed_out=False
p=subprocess.Popen(argv,cwd=ROOT,env=env,start_new_session=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
try:out,err=p.communicate(timeout=30)
except subprocess.TimeoutExpired:
 timed_out=True;os.killpg(p.pid,signal.SIGKILL);out,err=p.communicate(timeout=5)
elapsed=time.monotonic()-start
try:os.killpg(p.pid,0);absent=False
except ProcessLookupError:absent=True
after=hashes()
(HERE/(receipt+'.stdout')).write_bytes(out);(HERE/(receipt+'.stderr')).write_bytes(err)
r=dict(argv=argv,environment=env,actual_seconds=round(elapsed,3),deadline_seconds=30,exit_code=p.returncode,
 timed_out=timed_out,group_absent=absent,code_before=before,code_after=after,code_unchanged=before==after,SQL_executed=False,maintained_changes=False)
(HERE/(receipt+'.json')).write_text(json.dumps(r,indent=2,sort_keys=True)+'\n')
print(json.dumps(r,sort_keys=True))
raise SystemExit(0 if p.returncode==0 and not timed_out and absent and before==after else 1)
