from pathlib import Path
import json,hashlib,shutil,subprocess
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
OUT=ROOT/'docs/release/rapid-completion-2026-10-01/current-admin-browser-current1'
manifest=json.loads((ROOT/'docs/release/rapid-completion-2026-10-01/full-flutter-current-resumption1/source-export.json').read_text())
source=Path(manifest['export']);dest=ROOT/'.cache/current-admin-browser-build-current1'
sdk_source=ROOT/'.cache/flutter-sdk-isolated-gateway-motion-root192';sdk_dest=ROOT/'.cache/flutter-sdk-isolated-admin-browser-current1'
assert not dest.exists()and not sdk_dest.exists()
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
for name,digest in manifest['inputs_sha256'].items():
 p=source/name
 assert sha(p)==digest,name
 q=dest/name;q.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,q)
# Exact additional legal runtime required by the separate Public artifact.
extra={}
for p in sorted((ROOT/'content/legal').rglob('*')):
 if p.is_file():
  name=str(p.relative_to(ROOT));extra[name]=sha(p)
  q=dest/name;q.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,q)
assert all(sha(ROOT/n)==d and sha(dest/n)==d for n,d in extra.items())
# A separate SDK prevents the browser build/test tools mutating fullVM SDK.
subprocess.run(['/bin/cp','-cR',str(sdk_source),str(sdk_dest)],check=True)
paths=['bin/cache/artifacts/engine/darwin-x64/flutter_tester','bin/cache/dart-sdk/bin/dart','bin/cache/dart-sdk/bin/dartaotruntime','bin/cache/flutter_tools.snapshot']
sdk={n:sha(sdk_source/n) for n in paths}
assert all(sha(sdk_dest/n)==d for n,d in sdk.items())
result={'status':'prepared','source_export':str(source),'source_manifest':str(ROOT/'docs/release/rapid-completion-2026-10-01/full-flutter-current-resumption1/source-export.json'),'source_export_sha256':sha(ROOT/'docs/release/rapid-completion-2026-10-01/full-flutter-current-resumption1/source-export.json'),'build_root':str(dest),'sdk_root':str(sdk_dest),'inputs':manifest['inputs_sha256'],'supplemental_legal_inputs':extra,'sdk_critical_before':sdk,'source_copy_matches':True,'shared_sdk_mutated':False}
(OUT/'copied-inputs.json').write_text(json.dumps(result,indent=2)+'\n')
print('PREPARED',dest,len(result['inputs']),len(extra),flush=True)
