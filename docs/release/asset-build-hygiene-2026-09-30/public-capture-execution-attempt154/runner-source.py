import json,os,subprocess,hashlib,datetime
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
P=ROOT/'docs/release/asset-build-hygiene-2026-09-30/public-capture-execution-attempt154'
PREP=ROOT/'docs/release/asset-build-hygiene-2026-09-30/media-source-preparation-attempt153'
assert json.loads((PREP/'execution.json').read_text())['status']=='pass'
P.mkdir(exist_ok=False);(P/'runner-source.py').write_bytes(Path(__file__).read_bytes())
SDK=ROOT/'.cache/flutter-sdk-isolated-asset-attempt23'
EXPORT=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt153-public-graph')
ENV={k:v for k,v in os.environ.items() if k in {'HOME','USER','LOGNAME','SHELL','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}}
ENV.update({'CI':'true','FLUTTER_SUPPRESS_ANALYTICS':'true','PUB_CACHE':str(ROOT/'.cache/pub-cache-hygiene-20260930'),'FLUTTER':str(SDK/'bin/flutter'),'COLLECT_MEDIA_SOURCE':str(EXPORT),'COLLECT_MEDIA_CHROME':'/Volumes/PRO-G40/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'})
command=['/Volumes/PRO-G40/Development/Node/bin/node',str(ROOT/'scripts/qa/public_browser_app_media.mjs'),str(ROOT/'.cache/public-app-media-attempt154')]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
manifest=json.loads((PREP/'source-export.json').read_text());extras=manifest['additional_caller_sha256']
assert all(sha(ROOT/n)==h for n,h in extras.items())
base={'kind':'current_graph_scoped_public_route_capture_execution','started_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'command':command,'caller_sha256':sha(ROOT/'scripts/qa/public_browser_app_media.mjs'),'source_preparation_sha256':sha(PREP/'execution.json'),'source_root':str(EXPORT),'scope':'Seven fresh actual browser images from unchanged accepted current Public graph; actual fresh release compilation from copied hosted package source and exact current graph/bindings/SDK. No provider, hosted, SQL, native visual or whole-application acceptance.'}
(P/'execution.json').write_text(json.dumps({**base,'status':'running'},indent=2)+'\n')
print('START fresh release compile and seven current route captures',flush=True)
with (P/'capture.stdout').open('wb') as out,(P/'capture.stderr').open('wb') as err: code=subprocess.run(command,cwd=ROOT,env=ENV,stdout=out,stderr=err).returncode
report=ROOT/'.cache/public-app-media-attempt154/capture-report.json'
import importlib.util
helper=EXPORT/'scripts/qa/resolved_native_package_inputs.py';sp=importlib.util.spec_from_file_location('actual_public_package_verification',helper);pm=importlib.util.module_from_spec(sp);sp.loader.exec_module(pm)
pb=json.loads((PREP/'resolved-package-inputs-before.json').read_text());pc=pm.verify(pb,EXPORT)
(P/'resolved-package-inputs-after-capture.json').write_text(json.dumps(pc,indent=2,sort_keys=True)+'\n')
if pc['status']!='pass':code=1
base.update({'actual_pub_compiler_binding_sha256':sha(PREP/'resolved-package-inputs-before.json'),'actual_pub_compiler_after_verification_sha256':sha(P/'resolved-package-inputs-after-capture.json'),'actual_resolved_pub_compiler_inputs_unchanged':pc['status']=='pass'})
extra_drift={n:{'before':h,'root_after':sha(ROOT/n) if (ROOT/n).is_file() else None} for n,h in extras.items() if not (ROOT/n).is_file() or sha(ROOT/n)!=h}
if extra_drift: code=1
(P/'execution.json').write_text(json.dumps({**base,'status':'pass' if code==0 else 'fail','exit_code':code,'stdout_sha256':sha(P/'capture.stdout'),'stderr_sha256':sha(P/'capture.stderr'),'capture_report_sha256':sha(report) if report.is_file() else None,'additional_current_caller_drift':extra_drift,'finished_at':datetime.datetime.now(datetime.timezone.utc).isoformat()},indent=2)+'\n')
print('END capture',code,flush=True)
raise SystemExit(code)
