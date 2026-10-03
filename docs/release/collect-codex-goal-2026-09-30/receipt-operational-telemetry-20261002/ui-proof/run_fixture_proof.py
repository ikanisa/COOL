from pathlib import Path
import datetime,hashlib,json,re,shutil,subprocess,sys
s=Path(__file__).resolve().parent;v=s/'validation-app';source=Path(sys.argv[1]).resolve()
i=1
while(s/('sql-fixtures-attempt'+str(i))).exists():i+=1
r=s/('sql-fixtures-attempt'+str(i));r.mkdir();f=r/'fixtures';f.mkdir()
index=json.loads((source/'fixture-index.json').read_text())
assert set(index)=={'telemetry','exception_inbox','workflow'}
files=['fixture-index.json']
for group in index.values():
 assert isinstance(group,list)and group
 for name in group:
  assert isinstance(name,str)and re.fullmatch(r'[a-z0-9_-]+\.json',name)
  files.append(name)
files=list(dict.fromkeys(files));bindings=[]
for name in files:
 src=source/name;dst=f/name;dst.write_bytes(src.read_bytes());bindings.append({'source':str(src),'copy':str(dst),'sha256':hashlib.sha256(dst.read_bytes()).hexdigest()})
(r/'sql-source-bindings.json').write_text(json.dumps(bindings,indent=2)+'\n')
dart=Path('/Volumes/PRO-G40/Development/Flutter/flutter/bin/cache/dart-sdk/bin/dart')
def snapshot():
 roots=[v,s/'validation-packages',dart.parent.parent,f]
 return {str(p):hashlib.sha256(p.read_bytes()).hexdigest()for root in roots for p in sorted(root.rglob('*'))if p.is_file()}
before=snapshot();(r/'inputs-before.json').write_text(json.dumps(before,indent=2)+'\n')
cmd=[str(dart),'--packages='+str(v/'.dart_tool/package_config.json'),str(v/'scripts/tests/admin_receipt_operational_telemetry_test.dart'),str(f)]
p=subprocess.run(cmd,cwd=v,text=True,capture_output=True,timeout=120)
(r/'stdout.txt').write_text(p.stdout);(r/'stderr.txt').write_text(p.stderr)
after=snapshot();(r/'inputs-after.json').write_text(json.dumps(after,indent=2)+'\n')
result={'command':cmd,'cwd':str(v),'exit_code':p.returncode,'inputs_unchanged':before==after,'frozen_file_count':len(before),'fixture_source':str(source),'source_binding_sha256':hashlib.sha256((r/'sql-source-bindings.json').read_bytes()).hexdigest(),'compiled_widget_claim':False,'checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat()}
(r/'result.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result));print(p.stdout);print(p.stderr)
raise SystemExit(p.returncode if p.returncode else (0 if before==after else 1))
