import json,os,subprocess,hashlib,datetime
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
P=ROOT/'docs/release/asset-build-hygiene-2026-09-30/public-capture-execution-attempt82'
prepared=json.loads((ROOT/'docs/release/asset-build-hygiene-2026-09-30/media-source-preparation-attempt81/execution.json').read_text());assert prepared['status']=='pass'
P.mkdir(exist_ok=False);(P/'runner-source.py').write_bytes(Path(__file__).read_bytes())
SDK=ROOT/'.cache/flutter-sdk-isolated-asset-attempt28'
EXPORT=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt81-public-graph')
ENV={k:v for k,v in os.environ.items() if k in {'HOME','USER','LOGNAME','SHELL','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}}
ENV.update({'CI':'true','FLUTTER_SUPPRESS_ANALYTICS':'true','PUB_CACHE':str(ROOT/'.cache/pub-cache-hygiene-20260930'),'FLUTTER':str(SDK/'bin/flutter'),'COLLECT_MEDIA_SOURCE':str(EXPORT),'COLLECT_MEDIA_CHROME':'/Volumes/PRO-G40/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'})
command=['/Volumes/PRO-G40/Development/Node/bin/node',str(ROOT/'scripts/qa/public_browser_app_media.mjs'),str(ROOT/'.cache/public-app-media-attempt82')]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
base={'kind':'current_graph_scoped_public_route_capture_execution','started_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'command':command,'caller_sha256':sha(ROOT/'scripts/qa/public_browser_app_media.mjs'),'source_preparation_sha256':sha(ROOT/'docs/release/asset-build-hygiene-2026-09-30/media-source-preparation-attempt81/execution.json'),'scope':'Actual immutable current runtime browser capture; no provider, hosted, database or native visual acceptance'}
(P/'execution.json').write_text(json.dumps({**base,'status':'running'},indent=2)+'\n')
print('START seven-route actual browser capture',flush=True)
export_manifest=json.loads((ROOT/'docs/release/asset-build-hygiene-2026-09-30/media-source-preparation-attempt81/source-export.json').read_text())
extras=export_manifest['additional_caller_sha256'];assert all(sha(ROOT/n)==h and sha(EXPORT/n)==h for n,h in extras.items())
with (P/'capture.stdout').open('wb') as out,(P/'capture.stderr').open('wb') as err: code=subprocess.run(command,cwd=ROOT,env=ENV,stdout=out,stderr=err).returncode
report=ROOT/'.cache/public-app-media-attempt82/capture-report.json'
extra_drift={n:{'before':h,'root_after':sha(ROOT/n),'export_after':sha(EXPORT/n)} for n,h in extras.items() if sha(ROOT/n)!=h or sha(EXPORT/n)!=h}
if extra_drift: code=1
(P/'execution.json').write_text(json.dumps({**base,'status':'pass' if code==0 else 'fail','exit_code':code,'stdout_sha256':sha(P/'capture.stdout'),'stderr_sha256':sha(P/'capture.stderr'),'capture_report_sha256':sha(report) if report.is_file() else None,'additional_source_drift':extra_drift,'finished_at':datetime.datetime.now(datetime.timezone.utc).isoformat()},indent=2)+'\n')
print('END capture',code,flush=True)
raise SystemExit(code)
