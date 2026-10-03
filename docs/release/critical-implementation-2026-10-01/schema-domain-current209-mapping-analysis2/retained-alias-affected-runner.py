"""Private bounded consumer receipts; never runs SQL or writes maintained source."""
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = next(p for p in HERE.parents if (p/'supabase/migrations').is_dir())
PYTHON = '/Volumes/PRO-G40/Development/Python/codex-agents-venv/bin/python3'
CATALOG = ROOT/'docs/release/critical-implementation-2026-10-01/ordinary-schema-catalog209-execution1/observed-output'
OUTPUT = HERE/'generated-current209-successor3'
GENERATOR = HERE/'scripts/audits/collect_schema_domain_map.py'
FILES = ['scripts/audits/collect_schema_domain_map.py', 'scripts/audits/collect_schema_function_lineage.py',
         'scripts/tests/collect_schema_function_lineage_test.py', 'scripts/tests/collect_schema_function_lineage_cases.json']

def hashes():
    return {p:hashlib.sha256((HERE/p).read_bytes()).hexdigest() for p in FILES}

operation, receipt = sys.argv[1:]
if (HERE/(receipt+'.json')).exists():
    raise SystemExit('receipt exists; preservation requires a new name')
if operation == 'focused':
    argv = [PYTHON,'-I','-B',str(HERE/'scripts/tests/collect_schema_function_lineage_test.py')]
elif operation == 'alias-affected':
    argv = [PYTHON,'-I','-B',str(HERE/'scripts/tests/collect_schema_function_lineage_test.py'),
            'test_alias_normalization_refuses_qualified_quoted_and_custom_types_first',
            'test_self_contained34_case_hashes_and_controlled_lineage',
            'test_current209_retains_only_uninterrupted_fixture_case']
elif operation == 'generate':
    if OUTPUT.exists():
        raise SystemExit('output exists; preservation requires a new name')
    argv = [PYTHON,'-I','-B',str(GENERATOR),'--root',str(ROOT),
            '--catalog',str(CATALOG/'ordinary_clean/final-effective-catalog.json'),
            '--catalog',str(CATALOG/'ordinary_populated/final-effective-catalog.json'),
            '--replay-migrations',str(CATALOG/'captured-migrations'),'--output',str(OUTPUT),'--require-current']
elif operation == 'verify':
    argv = [PYTHON,'-I','-B',str(GENERATOR),'--root',str(ROOT),'--output',str(OUTPUT),'--verify','--require-current']
else:
    raise SystemExit('unknown private operation')
environment = {'PATH':'/usr/bin:/bin:/usr/sbin:/sbin'}
before = hashes(); start = time.monotonic(); timed_out = False
process = subprocess.Popen(argv,cwd=ROOT,env=environment,start_new_session=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
try:
    stdout,stderr = process.communicate(timeout=30)
except subprocess.TimeoutExpired:
    timed_out = True; os.killpg(process.pid,signal.SIGKILL); stdout,stderr = process.communicate(timeout=5)
elapsed = time.monotonic()-start
try:
    os.killpg(process.pid,0); group_absent = False
except ProcessLookupError:
    group_absent = True
after = hashes()
(HERE/(receipt+'.stdout')).write_bytes(stdout); (HERE/(receipt+'.stderr')).write_bytes(stderr)
result = dict(argv=argv,environment=environment,actual_seconds=round(elapsed,3),deadline_seconds=30,
              exit_code=process.returncode,timed_out=timed_out,group_absent=group_absent,
              code_before=before,code_after=after,code_unchanged=before==after,SQL_executed=False,maintained_changes=False)
(HERE/(receipt+'.json')).write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
print(json.dumps(result,sort_keys=True))
raise SystemExit(0 if process.returncode==0 and not timed_out and group_absent and before==after else 1)
