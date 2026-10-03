from pathlib import Path
import json,hashlib,subprocess,datetime,sys
s=Path(__file__).resolve().parent;v=s/'validation-app'
i=1
while (s/('ui-attempt'+str(i))).exists():i+=1
r=s/('ui-attempt'+str(i));r.mkdir()
def snapshot():
 return {str(p.relative_to(v)):hashlib.sha256(p.read_bytes()).hexdigest() for root in [v/'lib',v/'test'] for p in sorted(root.rglob('*.dart'))}|{n:hashlib.sha256((v/n).read_bytes()).hexdigest() for n in ['pubspec.yaml','pubspec.lock','analysis_options.yaml','.dart_tool/package_config.json','.dart_tool/package_graph.json']}
before=snapshot();(r/'inputs-before.json').write_text(json.dumps(before,indent=2)+'\n')
cmd=['/Volumes/PRO-G40/Development/Flutter/flutter/bin/flutter','test','--no-pub','--reporter','expanded','test/admin_receipt_telemetry_test.dart']
with (r/'stdout.log').open('w') as out,(r/'stderr.log').open('w') as err:
 p=subprocess.run(cmd,cwd=v,stdout=out,stderr=err,timeout=180)
after=snapshot();result={'command':cmd,'cwd':str(v),'exit_code':p.returncode,'source_unchanged':before==after,'source_count':len(before),'finished_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'scope':'synthetic SDK and provider/widget fixtures; no actual SQL, hosted, browser or carrier acceptance'}
(r/'inputs-after.json').write_text(json.dumps(after,indent=2)+'\n');(r/'result.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result));print((r/'stdout.log').read_text()[-12000:]);print((r/'stderr.log').read_text()[-6000:]);sys.exit(p.returncode or (0 if before==after else 1))
