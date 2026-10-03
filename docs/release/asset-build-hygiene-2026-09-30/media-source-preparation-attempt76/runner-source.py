import hashlib,json,os,shutil,subprocess,time
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
P=ROOT/'docs/release/asset-build-hygiene-2026-09-30/media-source-preparation-attempt76'
EXPORT=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt76-public-graph')
SDK=ROOT/'.cache/flutter-sdk-isolated-asset-attempt28'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert json.loads((ROOT/'docs/release/asset-build-hygiene-2026-09-30/public-browser-graph-current-attempt75/validation.json').read_text())['status']=='pass'
env={k:v for k,v in os.environ.items() if k in {'HOME','USER','LOGNAME','SHELL','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}}
env.update({'CI':'true','FLUTTER_SUPPRESS_ANALYTICS':'true','PUB_CACHE':str(ROOT/'.cache/pub-cache-hygiene-20260930'),'PATH':str(SDK/'bin')+':/Users/jeanbosco/.local/bin:'+env['PATH']})
P.mkdir(exist_ok=False);EXPORT.mkdir(exist_ok=False);(P/'runner-source.py').write_bytes(Path(__file__).read_bytes())
def snapshot(directory):
 return json.loads(subprocess.check_output(['ruby','-r','./scripts/public_app_media','-e','puts JSON.generate(PublicAppMedia.new(Dir.pwd).browser_source_snapshot)'],cwd=directory,env=env,text=True))
source=snapshot(ROOT)
assert 'tool/public_app_media_capture.dart' in source and not any(n.startswith(('lib/admin/','lib/gateway/')) for n in source)
extras=['.metadata','scripts/qa/public_browser_app_media.mjs','scripts/assets/publish_public_app_media.py']
inputs={**source,**{n:sha(ROOT/n) for n in extras}}
for n,h in inputs.items():
 target=EXPORT/n;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/n,target)
 assert sha(target)==h and sha(ROOT/n)==h,n
assert snapshot(ROOT)==source and snapshot(EXPORT)==source
(P/'source-export.json').write_text(json.dumps({'kind':'independent_browser_reachable_source_export','destination':str(EXPORT),'browser_entrypoint':'tool/public_app_media_capture.dart','source_sha256':source,'additional_caller_sha256':{n:inputs[n] for n in extras},'scope':'Complete conservative fixture Dart closure, local fork Dart sources/provenance, declared assets and web scaffold; no unrelated Admin/native source is compiled or certified'},indent=2,sort_keys=True)+'\n')
commands=[]
def run(name,args):
 print('START',name,flush=True);start=time.monotonic()
 with (P/(name+'.stdout')).open('wb') as out,(P/(name+'.stderr')).open('wb') as err:
  r=subprocess.run(args,cwd=EXPORT,env=env,stdout=out,stderr=err)
 commands.append({'name':name,'command':args,'exit_code':r.returncode,'elapsed_seconds':round(time.monotonic()-start,2),'stdout_sha256':sha(P/(name+'.stdout')),'stderr_sha256':sha(P/(name+'.stderr'))})
 (P/'execution.json').write_text(json.dumps({'status':'running' if r.returncode==0 else 'fail','commands':commands},indent=2)+'\n')
 print('END',name,r.returncode,flush=True);assert r.returncode==0,name
run('export-git-init',['git','init','-q'])
run('flutter-version',[str(SDK/'bin/flutter'),'--version','--machine'])
v=json.loads((P/'flutter-version.stdout').read_text());assert v['frameworkVersion']=='3.44.4' and v['frameworkRevision']=='ad70ec4617166f1c38e5d2bfd388af71fda14f06' and v['dartSdkVersion']=='3.12.2'
critical=['bin/cache/dart-sdk/bin/dart','bin/cache/dart-sdk/bin/dartaotruntime','bin/cache/flutter_tools.snapshot']
sdk={n:sha(SDK/n) for n in critical};assert sdk=={n:sha(Path('/Volumes/PRO-G40/Development/Flutter/flutter')/n) for n in critical}
(P/'sdk-isolation.json').write_text(json.dumps({'critical_sha256':sdk,'version':v,'scope':'Pinned revision/version and critical Dart/tool snapshot bytes checked; no complete installed SDK/cache attestation'},indent=2)+'\n')
run('pub-enforce-offline',[str(SDK/'bin/flutter'),'pub','get','--offline','--enforce-lockfile'])
assert sha(EXPORT/'pubspec.lock')==source['pubspec.lock']
project_dart=[n for n in source if n.endswith('.dart') and not n.startswith('third_party/')]
run('reachable-format-check',[str(SDK/'bin/cache/dart-sdk/bin/dart'),'format','--output=none','--set-exit-if-changed',*project_dart])
run('reachable-fatal-analysis',[str(SDK/'bin/flutter'),'analyze','--no-pub','--fatal-infos','--fatal-warnings'])
assert all(sha(EXPORT/n)==h for n,h in inputs.items())
current=snapshot(ROOT);assert current==source,'Reachable browser source changed before capture'
(P/'execution.json').write_text(json.dumps({'status':'pass','commands':commands,'source_file_count':len(source),'project_dart_file_count':len(project_dart),'export_inputs_unchanged':True,'checkout_browser_graph_matches_export':True,'generated_package_binding_sha256':sha(EXPORT/'.dart_tool/package_config.json'),'generated_plugin_binding_sha256':sha(EXPORT/'.flutter-plugins-dependencies'),'scope':'Current independent reachable browser preview source and scoped formatting/analysis; no whole-application/native acceptance'},indent=2)+'\n')
print('PUBLIC GRAPH SOURCE READY',flush=True)
