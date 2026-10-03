import hashlib,json,os,subprocess,time
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL');P=ROOT/'docs/release/asset-build-hygiene-2026-09-30/native-observed-inventory-attempt33';EXPORT=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt23')
P.mkdir(exist_ok=False);(P/'runner-source.py').write_bytes(Path(__file__).read_bytes());sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
ENV={k:v for k,v in os.environ.items() if k in {'HOME','USER','LOGNAME','SHELL','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}};ENV.update({'JAVA_HOME':'/Volumes/PRO-G40/Applications/Android Studio.app/Contents/jbr/Contents/Home','CI':'true','FLUTTER_SUPPRESS_ANALYTICS':'true','PUB_CACHE':str(ROOT/'.cache/pub-cache-hygiene-20260930')})
inputs=['pubspec.yaml','pubspec.lock','android/app/build.gradle.kts','android/app/gradle.lockfile','android/gradle/wrapper/gradle-wrapper.properties','android/gradle/wrapper/gradle-wrapper.jar','scripts/supply_chain/gradle_runtime_inventory.init.gradle','.dart_tool/package_config.json','.flutter-plugins-dependencies']
before={n:sha(EXPORT/n) for n in inputs};assert all(sha(ROOT/n)==h for n,h in before.items() if not n.startswith('.'))
commands=[]
def save(status,extra=None):
 (P/'verification.json').write_text(json.dumps({'status':status,'commands':commands,'input_sha256':before,'scope':'Actual observed offline locked dependency graphs from the retained Android source export; full current checkout and signed-artifact acceptance remain separate',**(extra or {})},indent=2)+'\n')
def run(name,args,cwd=ROOT):
 print('START',name,flush=True);start=time.time()
 with (P/(name+'.stdout')).open('wb') as out,(P/(name+'.stderr')).open('wb') as err:code=subprocess.run(args,cwd=cwd,env=ENV,stdout=out,stderr=err).returncode
 commands.append({'name':name,'command':args,'exit_code':code,'elapsed_seconds':round(time.time()-start,2),'stdout_sha256':sha(P/(name+'.stdout')),'stderr_sha256':sha(P/(name+'.stderr'))});save('running' if code==0 else 'fail');assert code==0,name;print('END',name,code,flush=True)
for label,config in [('runtime','productionReleaseRuntimeClasspath'),('compile','productionReleaseCompileClasspath')]:
 run(label,['./gradlew','-I','../scripts/supply_chain/gradle_runtime_inventory.init.gradle',':app:collectRuntimeGraph','-PcollectInventoryConfiguration='+config,'--offline','--no-daemon'],EXPORT/'android')
 text=(P/(label+'.stdout')).read_text();assert text.count('COLLECT_RUNTIME_GRAPH_BEGIN')==text.count('COLLECT_RUNTIME_GRAPH_END')==1
 graph=json.loads(text.split('COLLECT_RUNTIME_GRAPH_BEGIN\n')[1].split('\nCOLLECT_RUNTIME_GRAPH_END')[0]);assert graph['configuration']==config
 (P/(label+'-graph.json')).write_text(json.dumps(graph,indent=2,sort_keys=True)+'\n')
python='/Volumes/PRO-G40/Development/Python/codex-agents-venv/bin/python3'
args=[python,'scripts/supply_chain/gradle_observed_sbom.py','--runtime-graph',str(P/'runtime-graph.json'),'--compile-graph',str(P/'compile-graph.json'),'--output',str(P/'observed-sbom.cdx.json'),'--inventory',str(P/'observed-inventory.json')]
run('observed-sbom',args);run('reproduction',args+['--check']);run('schema',[python,'scripts/supply_chain/validate_source_sbom.py',str(P/'observed-sbom.cdx.json')])
assert all(sha(EXPORT/n)==h for n,h in before.items())
save('pass',{'actual_dependency_inputs_unchanged':True,'observed_inventory_sha256':sha(P/'observed-inventory.json'),'observed_sbom_sha256':sha(P/'observed-sbom.cdx.json'),'current_graph_input_binding_matches':all(sha(ROOT/n)==h for n,h in before.items() if not n.startswith('.'))});print('NATIVE OBSERVED INVENTORY PASS',flush=True)
