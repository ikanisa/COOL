from pathlib import Path
import datetime, hashlib, json, os, shutil, subprocess, sys

E=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/collect-post-acceptance-review-20261001-current1')
P=Path(__file__).resolve().parent
OUT=E/'docs/release/post-delta-ordinary187'
SQL_RECEIPT=P.parent/'sql-current/result.json'
DOCKER=Path('/Volumes/PRO-G40/Applications/Docker.app/Contents/Resources/bin/docker')
EXPECTED={
 'supabase/migrations/20261001190000_exception_followup_v2.sql':'18994064a277e26c4dec5cd9713829195d52dad58b4d8deb4127710ddb4999d7',
 'supabase/migrations/20261001200000_exception_inbox_audit_v2.sql':'a83543aa0266eb40ba5abd4c94c26b0db6d3fc8e238929bc2794154a7fa773f9',
}
HELPERS=[
 'scripts/tests/current_ordinary_installer_rehearsal.py',
 'scripts/tests/collect_current_release_upgrade_uat.py',
 'scripts/sql/receipt_transport_platform_prerequisites.sql',
 '.cache/receipt-foundation-attempt8/schema-only.sql',
 'docs/release/collect-codex-goal-2026-09-30/hosted-readback/metadata.json',
]
def stamp(): return datetime.datetime.now(datetime.timezone.utc).isoformat()
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def write(name, value):
 tmp=P/(name+'.tmp')
 tmp.write_text(json.dumps(value,indent=2,sort_keys=True)+'\n')
 tmp.replace(P/name)
def input_map():
 paths=sorted((E/'supabase/migrations').glob('*.sql'))
 return {str(p.relative_to(E)):sha(p) for p in paths}

assert not OUT.exists(), 'installer output must be fresh'
before=input_map()
assert len(before)==187, f'expected 187 migration files, got {len(before)}'
sql=json.loads(SQL_RECEIPT.read_text())
assert sql['status']=='pass' and sql['sources_unchanged'] is True
for path, expected in EXPECTED.items():
 assert before[path]==expected, f'new migration differs from SQL100 acceptance: {path}'
 assert sql['source_sha256'][path]==expected, f'SQL100 binding mismatch: {path}'
helper_before={path:sha(E/path) for path in HELPERS}
command=['/usr/bin/python3',str(E/HELPERS[0]),'--output',str(OUT)]
allowed={'HOME','USER','LOGNAME','TMPDIR','PATH','LANG','LC_ALL','LC_CTYPE','SHELL'}
env={k:v for k,v in os.environ.items() if k in allowed}
env.update(PYTHONDONTWRITEBYTECODE='1',PYTHONUTF8='1')
binding={
 'kind':'ordinary187_frozen_input_binding','started_at':stamp(),
 'composite':str(E),'migration_count':len(before),'source_sha256':before,
 'helper_and_platform_sha256':helper_before,
 'sql100_receipt':{'path':str(SQL_RECEIPT),'sha256':sha(SQL_RECEIPT),'status':sql['status']},
 'tools':{'python':{'path':'/usr/bin/python3','version':subprocess.check_output(['/usr/bin/python3','--version'],text=True).strip(),'sha256':sha('/usr/bin/python3')},'docker':{'path':str(DOCKER),'sha256':sha(DOCKER)}},
 'command':command,'cwd':str(E),
 'networkless_target':True,'shared_database_written':False,'hosted_called':False,'provider_called':False,
}
write('source-binding.json',binding)
with (P/'command.stdout').open('w') as stdout, (P/'command.stderr').open('w') as stderr:
 child=subprocess.Popen(command,cwd=E,env=env,stdout=stdout,stderr=stderr)
 write('execution.json',{'status':'running','pid':child.pid,'wrapper_pid':os.getpid(),'command':command,'started_at':binding['started_at'],'generated_output':str(OUT)})
 print(json.dumps({'status':'running','pid':child.pid,'wrapper_pid':os.getpid(),'generated_output':str(OUT)}),flush=True)
 code=child.wait()
after=input_map()
helper_after={path:sha(E/path) for path in HELPERS}
write('source-readback.json',{'migration_count':len(after),'source_sha256':after,'helper_and_platform_sha256':helper_after,'sources_unchanged':before==after and helper_before==helper_after,'checked_at':stamp()})
if OUT.exists(): shutil.copytree(OUT,P/'evidence')
result_path=OUT/'result.json'
result=json.loads(result_path.read_text()) if result_path.is_file() else {}
source_parity=before==after and helper_before==helper_after
checks={
 'command_exit_zero':code==0,
 'installer_status_pass':result.get('status')=='pass',
 'all_task_containers_removed':result.get('all_task_containers_removed') is True,
 'exact187_source_and_helpers_unchanged':source_parity,
 'external_calls_excluded':result.get('shared_database_written') is False and result.get('hosted_called') is False and result.get('provider_called') is False,
}
accepted=all(checks.values())
receipt={
 'kind':'ordinary187_clean_and_populated_installer_acceptance',
 'status':'pass' if accepted else 'failed','exit_code':code,'checks':checks,
 'migration_count':len(before),'case_count':len(result.get('cases',[])),
 'phases':result.get('phases',{}),'source_binding_sha256':sha(P/'source-binding.json'),
 'source_readback_sha256':sha(P/'source-readback.json'),
 'installer_result':{'path':str(result_path),'sha256':sha(result_path) if result_path.is_file() else None},
 'copied_evidence':str(P/'evidence'),'finished_at':stamp(),
 'shared_database_written':False,'source_rows_copied':False,'hosted_called':False,'provider_called':False,
 'signed_jwt_tested':False,'managed_hosted_owner_parity':False,
 'scope':'Frozen187-migration candidate; clean ordinary-owner install and124-version populated predecessor upgrade. No mutable shared-checkout acceptance claim.',
}
write('validation.json',receipt)
write('execution.json',{'status':receipt['status'],'pid':child.pid,'wrapper_pid':os.getpid(),'command':command,'started_at':binding['started_at'],'finished_at':receipt['finished_at'],'exit_code':code,'validation':str(P/'validation.json')})
print(json.dumps({'status':receipt['status'],'exit_code':code,'checks':checks,'case_count':receipt['case_count'],'validation':str(P/'validation.json')}),flush=True)
sys.exit(0 if accepted else 1)
