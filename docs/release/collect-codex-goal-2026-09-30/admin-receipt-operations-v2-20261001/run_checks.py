#!/usr/bin/env python3
"""Bounded credential-free Admin v2 policy UI verification; no hosted calls."""
from pathlib import Path
import datetime, hashlib, json, subprocess, sys
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
PACKET=ROOT/'docs/release/collect-codex-goal-2026-09-30/admin-receipt-operations-v2-20261001'
DART=Path('/Volumes/PRO-G40/Development/Flutter/flutter/bin/cache/dart-sdk/bin/dart')
FLUTTER=Path('/Volumes/PRO-G40/Development/Flutter/flutter/bin/flutter')
CHROME='/Volumes/PRO-G40/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
now=lambda:datetime.datetime.now(datetime.timezone.utc).isoformat()
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
owned=list(ROOT.glob('lib/admin/core/admin_receipt_operations*.dart'))+list(ROOT.glob('test/admin_receipt_operations*_test.dart'))+[ROOT/'test/support/admin_receipt_operations_fixture.dart']
def sources():
 files=list((ROOT/'lib/admin').rglob('*.dart'))+list((ROOT/'lib/app/theme').rglob('*.dart'))
 files+=list((ROOT/'lib/core/supabase').rglob('*.dart'))+[ROOT/'lib/core/data/exact_json_values.dart']+owned+list((ROOT/'test/fixtures/admin_receipt_operations_v2').glob('*.json'))
 files+=[ROOT/'pubspec.yaml',ROOT/'pubspec.lock',ROOT/'test/admin_action_session_test.dart',ROOT/'supabase/migrations/20261001110000_receipt_operational_authority.sql']
 return {str(f.relative_to(ROOT)):sha(f)for f in sorted(set(files))if f.is_file()}
if len(sys.argv)!=2 or sys.argv[1]not in ['attempt1','attempt2','attempt3','attempt4','attempt5','capture1','capture2','capture3','capture4','browser1','analysis-final']:raise SystemExit('Explicit check stage required')
stage=sys.argv[1];dest=PACKET/stage;dest.mkdir(exist_ok=False)
baseenv={'PATH':'/usr/bin:/bin','HOME':'/Users/jeanbosco','LANG':'en_US.UTF-8','PUB_CACHE':'/Volumes/PRO-G40/Development/PubCache','PYTHONDONTWRITEBYTECODE':'1'}
vm=['test/admin_receipt_operations_models_test.dart','test/admin_receipt_operations_checkpoint_test.dart','test/admin_receipt_operations_runtime_test.dart','test/admin_receipt_operations_card_test.dart']
commands=[('analysis',[str(DART),'analyze',*[str(f.relative_to(ROOT))for f in owned]],60),('vm',[str(FLUTTER),'test','--no-pub','--reporter','expanded',*vm],180)]
if stage in ['capture1','capture2','capture3','capture4']:
 capture=dest/'captures';capture.mkdir();baseenv['COLLECT_RECEIPT_OPERATIONS_CAPTURE_DIRECTORY']=str(capture)
 commands=[('captures',[str(FLUTTER),'test','--no-pub','--reporter','expanded','test/admin_receipt_operations_card_test.dart','--plain-name','optional source-bound light/dark captures render through actual shared theme'],90)]
if stage=='browser1':
 baseenv['CHROME_EXECUTABLE']=CHROME
 commands=[('browser',[str(FLUTTER),'test','--no-pub','--platform','chrome','--reporter','expanded','test/admin_receipt_operations_checkpoint_browser_test.dart'],90)]
if stage=='analysis-final':commands=commands[:1]+[('hygiene',['/usr/bin/make','revolut-design-authority'],90)]
before=sources();(dest/'sources-before.json').write_text(json.dumps(before,indent=2)+'\n');receipts=[]
for name,cmd,timeout in commands:
 start=now()
 with(dest/f'{name}.stdout.log').open('xb')as out,(dest/f'{name}.stderr.log').open('xb')as err:
  try:r=subprocess.run(cmd,cwd=ROOT,env=baseenv,stdout=out,stderr=err,timeout=timeout);code=r.returncode
  except subprocess.TimeoutExpired:code='deadline'
 receipts.append({'name':name,'command':cmd,'started_at':start,'finished_at':now(),'exit_code':code,'timeout_seconds':timeout})
 (dest/'commands.json').write_text(json.dumps(receipts,indent=2)+'\n')
 if code!=0:break
after=sources();(dest/'sources-after.json').write_text(json.dumps(after,indent=2)+'\n')
delta=[{'path':p,'before':before.get(p),'after':after.get(p)}for p in sorted(set(before)|set(after))if before.get(p)!=after.get(p)]
receipt={'captured_at':now(),'stage':stage,'commands':receipts,'source_inputs':len(before),'source_unchanged':not delta,'source_delta':delta,'dart_sha256':sha(DART),'flutter_launcher_sha256':sha(FLUTTER),'environment_keys':sorted(baseenv),'hosted_calls':0,'live_otp_requests':0,'live_sender_calls':0,'production_accepted':False,'source_freeze':False}
(dest/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps({'stage':stage,'commands':[{'name':c['name'],'exit_code':c['exit_code']}for c in receipts],'source_inputs':len(before),'source_delta':[d['path']for d in delta]}))
