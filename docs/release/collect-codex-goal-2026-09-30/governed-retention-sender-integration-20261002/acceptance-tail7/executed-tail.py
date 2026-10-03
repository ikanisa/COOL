import hashlib,json,pathlib,subprocess,sys,os
from datetime import datetime,timezone
root=pathlib.Path(__file__).resolve().parents[2]; stage=pathlib.Path(__file__).resolve().parent;out=stage/'acceptance-tail7';out.mkdir(exist_ok=False)
sha=lambda p:hashlib.file_digest(p.open('rb'),'sha256').hexdigest()
old=json.loads((stage/'attempt6/inputs.json').read_text());changes={str(root/'scripts/qa/revolut_design_authority.py'),str(root/'test/admin_sender_retention_view_test.dart')};bad=[p for p,s in old.items() if p not in changes and sha(pathlib.Path(p))!=s];assert not bad,bad
paths=set(old)|{str(root/'scripts/tests/revolut_design_authority_test.py'),str(root/'docs/release/revolut-design/authority.json'),str(root/'AGENTS.md'),str(pathlib.Path(sys.executable).resolve()),str(pathlib.Path(__file__).resolve())}
refs=json.loads((root/'.cache/collect-governed-sender-retention-20261002/proof/accepted-retention-controls-current2/REFERENCES.json').read_text())
paths|={p for p in refs if p.endswith('MaterialIcons-Regular.otf')}
links={}
for p in (root/'.cache/collect-callback-deadlines-20261002/implementation/validation-app/test/fixtures').glob('successor*.json'):
 if p.is_symlink():links[str(p)]=os.readlink(p);paths.add(str(p.resolve()))
assert len(links)==7
before={p:sha(pathlib.Path(p)) for p in sorted(paths)};(out/'inputs.json').write_text(json.dumps(before,indent=2)+'\n');(out/'links.json').write_text(json.dumps(links,indent=2)+'\n')
(out/'executed-tail.py').write_bytes(pathlib.Path(__file__).read_bytes())
result={'status':'failed','scope':'Reuse exact current product71-case VM and clean18-file analysis from attempt6; actual six-case capture-fixture tail, authority regressions and full sole-authority check. No fresh whole-candidate aggregate.','preceding_result':str(stage/'attempt6/result.json'),'retained_inputs':len(old)-len(changes),'declared_source_changes':sorted(changes),'commands':[]}
try:
 for name,argv in [
 ('capture-fixture',['/Volumes/PRO-G40/Development/Flutter/flutter/bin/flutter','test','--no-pub','--concurrency=1','--reporter=expanded','test/admin_sender_retention_view_test.dart']),
 ('capture-analysis',['/Volumes/PRO-G40/Development/Flutter/flutter/bin/cache/dart-sdk/bin/dart','analyze','--fatal-infos','test/admin_sender_retention_view_test.dart']),
 ('authority-regressions',[sys.executable,'scripts/tests/revolut_design_authority_test.py']),
 ('design-authority',['make','revolut-design-authority'])]:
  started=datetime.now(timezone.utc).isoformat();c=subprocess.run(argv,cwd=root,capture_output=True,timeout=360,env={**os.environ,'COLLECT_RETENTION_CAPTURE_DIRECTORY':str(out/'captures')})
  (out/(name+'.stdout')).write_bytes(c.stdout);(out/(name+'.stderr')).write_bytes(c.stderr)
  result['commands'].append({'name':name,'argv':argv,'started_at':started,'exit_code':c.returncode,'stdout_sha256':hashlib.sha256(c.stdout).hexdigest(),'stderr_sha256':hashlib.sha256(c.stderr).hexdigest()});assert c.returncode==0,name
 drift=[p for p,s in before.items() if sha(pathlib.Path(p))!=s];linkdrift=[p for p,s in links.items() if not pathlib.Path(p).is_symlink() or os.readlink(p)!=s];assert not drift and not linkdrift,(drift,linkdrift)
 result.update(status='passed',captured_inputs=len(before),input_drift=drift,link_drift=linkdrift)
finally:(out/'result.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items() if k!='commands'}))
