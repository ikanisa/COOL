import hashlib,json,pathlib,re,subprocess,os,sys
from datetime import datetime,timezone
root=pathlib.Path(__file__).resolve().parents[2];stage=pathlib.Path(__file__).resolve().parent;out=stage/'canonical-attempt1';out.mkdir(exist_ok=False)
ruby=pathlib.Path('/usr/bin/ruby');docker=pathlib.Path('/Volumes/PRO-G40/Applications/Docker.app/Contents/Resources/bin/docker');paths={ruby,docker,pathlib.Path(__file__).resolve()}
tests=['collect_inactive_restore_overlay_test.rb','collect_inactive_restore_caller_test.rb','collect_recovery_source_test.rb','production_archive_restore_test.rb','collect_encrypted_database_backup_test.rb']
pending=[root/'scripts/tests'/n for n in tests];seen=set()
while pending:
 p=pending.pop().resolve()
 if p in seen:continue
 seen.add(p)
 for rel in re.findall(r'^\s*require_relative\s+[\'\"]([^\'\"]+)[\'\"]',p.read_text(),re.M):
  t=(p.parent/rel).with_suffix('.rb');assert t.is_file(),str(t);pending.append(t)
paths|=seen|{root/'scripts/sql/collect_recovery_source_catalog.sql',root/'scripts/sql/collect_inactive_restore_overlay.sql',root/'scripts/sql/collect_receipt_worker_inventory.sql'}
paths|=set((root/'supabase/migrations').glob('*.sql'));paths={p for p in paths if p.is_file()}
h=lambda p:hashlib.file_digest(p.open('rb'),'sha256').hexdigest();before={str(p):h(p)for p in sorted(paths)};(out/'inputs.json').write_text(json.dumps(before,indent=2)+'\n');(out/'executed-runner.py').write_bytes(pathlib.Path(__file__).read_bytes())
commands=[('unit-'+str(i),[str(ruby),str(root/'scripts/tests'/n)])for i,n in enumerate(tests)]
commands += [('syntax-'+str(i),[str(ruby),'-c',str(p)])for i,p in enumerate(sorted(seen))]
result={'status':'failed','scope':'Seven canonical restore changes and exact affected backup/parser callers. Synthetic contract/caller adapters and pure functions; no encrypted archive/Vault/hosted/real restore claim. SQL78 private proof remains separate.','commands':[]}
try:
 for name,argv in commands:
  c=subprocess.run(argv,cwd=root,capture_output=True,timeout=60,env={**os.environ,'PATH':'/usr/bin:/bin:'+str(docker.parent)})
  (out/(name+'.stdout')).write_bytes(c.stdout);(out/(name+'.stderr')).write_bytes(c.stderr)
  summary=re.findall(r'(\d+) runs, (\d+) assertions, (\d+) failures, (\d+) errors, (\d+) skips',c.stdout.decode());result['commands'].append({'name':name,'argv':argv,'exit_code':c.returncode,'summary':summary,'stdout_sha256':hashlib.sha256(c.stdout).hexdigest(),'stderr_sha256':hashlib.sha256(c.stderr).hexdigest()});assert c.returncode==0,name
 drift=[p for p,s in before.items()if h(pathlib.Path(p))!=s];assert not drift,drift
 result.update(status='passed',captured_inputs=len(before),input_drift=drift,unit_cases=sum(int(c['summary'][0][0])for c in result['commands']if c['summary']),unit_assertions=sum(int(c['summary'][0][1])for c in result['commands']if c['summary']),syntax_checks=len(seen))
finally:(out/'result.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items()if k!='commands'}))
