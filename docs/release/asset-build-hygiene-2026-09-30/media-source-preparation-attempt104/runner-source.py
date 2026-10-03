import hashlib,json,os,shutil,subprocess,datetime
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
P=ROOT/'docs/release/asset-build-hygiene-2026-09-30/media-source-preparation-attempt104'
EXPORT=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt81-public-graph')
SDK=ROOT/'.cache/flutter-sdk-isolated-asset-attempt28'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
TOOLING=ROOT/'docs/release/asset-build-hygiene-2026-09-30/public-browser-graph-current-attempt103'
assert json.loads((TOOLING/'validation.json').read_text())['status']=='pass'
PRIOR=ROOT/'docs/release/asset-build-hygiene-2026-09-30/media-source-preparation-attempt76'
PREPARED=ROOT/'docs/release/asset-build-hygiene-2026-09-30/media-source-preparation-attempt81'
REPORT=ROOT/'.cache/public-app-media-attempt82/capture-report.json'
accepted=json.loads((PRIOR/'execution.json').read_text());assert accepted['status']=='pass'
assert all(any(c['name']==n and c['exit_code']==0 for c in accepted['commands']) for n in ['reachable-format-check','reachable-fatal-analysis'])
assert json.loads((PREPARED/'execution.json').read_text())['status']=='pass'
P.mkdir(exist_ok=False);(P/'runner-source.py').write_bytes(Path(__file__).read_bytes())
env={k:v for k,v in os.environ.items() if k in {'HOME','USER','LOGNAME','SHELL','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}}
def snapshot(base):
 return json.loads(subprocess.check_output(['ruby','-r','./scripts/public_app_media','-e','puts JSON.generate(PublicAppMedia.new(Dir.pwd).browser_source_snapshot)'],cwd=base,env=env,text=True))
source=snapshot(ROOT)
assert source==snapshot(EXPORT)==json.loads((PRIOR/'source-export.json').read_text())['source_sha256']==json.loads((PREPARED/'source-export.json').read_text())['source_sha256']
previous=json.loads(REPORT.read_text());assert previous['source_root']==str(EXPORT) and previous['sources_before']==source
bindings={n:sha(EXPORT/n) for n in ['.dart_tool/package_config.json','.flutter-plugins-dependencies']}
assert bindings==previous['generated_bindings_before']
critical=json.loads((PREPARED/'sdk-isolation.json').read_text())['critical_sha256']
assert critical=={n:sha(SDK/n) for n in critical}
extras=['.metadata','scripts/qa/public_browser_app_media.mjs','scripts/assets/publish_public_app_media.py']
current_extras={n:sha(ROOT/n) for n in extras}
tooling_inputs=json.loads((TOOLING/'inputs.json').read_text())
assert all(tooling_inputs[n]==current_extras[n] for n in extras if n.startswith('scripts/'))
for n,h in current_extras.items():
 t=P/'current-caller-source'/n;t.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/n,t);assert sha(t)==h
assert source==snapshot(ROOT)==snapshot(EXPORT)
(P/'source-export.json').write_text(json.dumps({'kind':'unchanged_accepted_browser_export_with_separate_current_capture_callers','destination':str(EXPORT),'source_sha256':source,'additional_caller_sha256':current_extras,'generated_bindings_sha256':bindings,'scope':'Historical immutable export81 remains untouched. Its complete graph still equals current checkout and accepted76; newly accepted capture/publisher callers are bound separately, not substituted into old evidence.'},indent=2,sort_keys=True)+'\n')
(P/'execution.json').write_text(json.dumps({'status':'pass','checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'accepted_runtime_packet_sha256':sha(PRIOR/'execution.json'),'accepted_preparation_packet_sha256':sha(PREPARED/'execution.json'),'current_tooling_receipt_sha256':sha(TOOLING/'validation.json'),'prior_successful_compilation_report_sha256':sha(REPORT),'source_file_count':len(source),'complete_current_browser_graph_matches_accepted_export':True,'generated_bindings_match_actual_compilation':True,'critical_sdk_bytes_unchanged':True,'historical_export_mutated':False,'scope':'Current independent Public fixture graph acceptance and strict compiler reuse preconditions; no full application/native or visual acceptance'},indent=2)+'\n')
print('CURRENT PUBLIC GRAPH + SEPARATE CALLERS READY',len(source),flush=True)
