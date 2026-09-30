#!/usr/bin/env python3
"""Source-bound local144 Admin checks. SQL receipts are root-written files only."""
from pathlib import Path
import datetime,hashlib,json,os,subprocess
ROOT=Path(__file__).resolve().parents[3]
FLUTTER='/Volumes/PRO-G40/Development/Flutter/flutter/bin/flutter'
OUT=Path(os.environ.get('COLLECT_ROSTER_RELOAD_PACKET',str(Path(__file__).resolve().parent/'attempt1')))
OUT.mkdir(parents=True,exist_ok=False)
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
inputs=[p for p in (ROOT/'lib').rglob('*.dart')]+[ROOT/p for p in [
 'test/admin_roster_reload_test.dart','test/admin_roster_bookmark_browser_test.dart','test/admin_roster_import_test.dart',
 'test/admin_roster_dialog_test.dart','test/admin_roster_sql_receipts_test.dart','test/support/admin_roster_fixture.dart',
 'test/admin_roster_file_parser_test.dart','test/admin_roster_xlsx_preflight_test.dart','pubspec.yaml','pubspec.lock',
 'assets/typefaces/Inter-Variable.ttf','assets/typefaces/AeonikPro-Regular.ttf',
 'supabase/migrations/20260930100000_roster_import_provenance.sql',
 'supabase/migrations/20260930120000_roster_import_reload_recovery.sql',
 'scripts/tests/roster_import_reload_receipts_uat.sql','scripts/tests/roster_import_reload_adversarial_uat.sql',
 'scripts/tests/roster_import_reload_concurrency_uat.rb',
 'docs/release/roster-import-provenance-2026-09-30/receipts142.stdout']]
receipt=os.environ.get('ROSTER_RELOAD_SQL_RECEIPTS','')
if receipt:inputs.append(Path(receipt))
def snapshot():return {str(p.relative_to(ROOT)) if p.is_relative_to(ROOT) else str(p):digest(p) for p in sorted(inputs)}
now=lambda:datetime.datetime.now(datetime.timezone.utc).isoformat()
result={'started_at':now(),'source_hashes_before':snapshot(),'commands':[],
 'database_calls':False,'provider_calls':False,'hosted_calls':False,
 'actual144_sql_decoder_executed':bool(receipt),'sql144_input':receipt or None}
commands=[('runtime',[FLUTTER,'--version','--machine']),
 ('roster-tests',[FLUTTER,'test','--no-pub','--reporter','expanded',
 '--dart-define=ROSTER_SQL_RECEIPTS='+str(ROOT/'docs/release/roster-import-provenance-2026-09-30/receipts142.stdout'),
 '--dart-define=ROSTER_RELOAD_SQL_RECEIPTS='+receipt,
 'test/admin_roster_reload_test.dart','test/admin_roster_import_test.dart','test/admin_roster_dialog_test.dart','test/admin_roster_sql_receipts_test.dart']),
 ('xlsx-regression',[FLUTTER,'test','--no-pub','--reporter','expanded','test/admin_roster_file_parser_test.dart','test/admin_roster_xlsx_preflight_test.dart']),
 ('browser-bookmark',[FLUTTER,'test','--no-pub','--platform','chrome','--reporter','expanded','test/admin_roster_bookmark_browser_test.dart']),
 ('analyze',[FLUTTER,'analyze','--no-pub','lib/admin/core/admin_roster_import.dart','lib/admin/core/admin_roster_models.dart',
 'lib/admin/core/admin_roster_dialog.dart','lib/admin/core/admin_roster_checkpoint.dart','lib/admin/core/admin_roster_checkpoint_stub.dart',
 'lib/admin/core/admin_roster_checkpoint_web.dart','test/admin_roster_reload_test.dart','test/admin_roster_bookmark_browser_test.dart']),
 ('concurrency-source-syntax',['ruby','-c','scripts/tests/roster_import_reload_concurrency_uat.rb'])]
for name,argv in commands:
 with (OUT/(name+'.stdout')).open('w') as out,(OUT/(name+'.stderr')).open('w') as err:
  c=subprocess.run(argv,cwd=ROOT,stdout=out,stderr=err)
 result['commands'].append({'name':name,'argv':argv,'exit_code':c.returncode,
 'stdout_sha256':digest(OUT/(name+'.stdout')),'stderr_sha256':digest(OUT/(name+'.stderr'))})
 print(name,c.returncode,flush=True)
 if c.returncode:break
result['source_hashes_after']=snapshot()
result['source_unchanged']=result['source_hashes_before']==result['source_hashes_after']
result['completed_at']=now()
result['passed']=len(result['commands'])==len(commands) and all(c['exit_code']==0 for c in result['commands']) and result['source_unchanged']
(OUT/'validation.json').write_text(json.dumps(result,indent=2)+'\n')
raise SystemExit(0 if result['passed'] else 1)
