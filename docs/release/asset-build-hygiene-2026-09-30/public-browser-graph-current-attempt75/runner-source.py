import hashlib,json,os,shutil,subprocess,time
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
PRIOR=ROOT/'docs/release/asset-build-hygiene-2026-09-30/public-browser-graph-prior-attempt71'
P=ROOT/'docs/release/asset-build-hygiene-2026-09-30/public-browser-graph-current-attempt75'
EXPORT=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt75-public-tooling')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
env={k:v for k,v in os.environ.items() if k in {'HOME','USER','LOGNAME','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}}
P.mkdir(exist_ok=False);EXPORT.mkdir(exist_ok=False)
(P/'runner-source.py').write_bytes(Path(__file__).read_bytes())
inputs={}
for f in sorted((ROOT/'scripts').rglob('*')):
 if f.is_file() and not f.is_symlink() and '__pycache__' not in f.parts:
  n=f.relative_to(ROOT).as_posix();h=sha(f);t=EXPORT/n;t.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(f,t);assert sha(t)==h;inputs[n]=h
(P/'inputs.json').write_text(json.dumps(inputs,indent=2,sort_keys=True)+'\n')
commands=[]
def run(name,args):
 print('START',name,flush=True);start=time.monotonic();r=subprocess.run(args,cwd=EXPORT,env=env,capture_output=True,timeout=300)
 (P/(name+'.stdout')).write_bytes(r.stdout);(P/(name+'.stderr')).write_bytes(r.stderr)
 commands.append({'name':name,'command':args,'exit_code':r.returncode,'elapsed_seconds':round(time.monotonic()-start,2),'stdout_sha256':sha(P/(name+'.stdout')),'stderr_sha256':sha(P/(name+'.stderr'))})
 (P/'validation.json').write_text(json.dumps({'status':'running' if r.returncode==0 else 'fail','commands':commands},indent=2)+'\n')
 print('END',name,r.returncode,flush=True);assert r.returncode==0,name
for name,argv in [
 ('graph-tests',['ruby','scripts/tests/public_browser_graph_test.rb']),
 ('legacy-media-tests',['ruby','scripts/tests/public_app_media_test.rb']),
 ('browser-source-binding-tests',['python3','scripts/tests/public_media_source_binding_test.py']),
 ('publication-tests',['python3','scripts/tests/public_media_publication_test.py']),
 ('native-publication-tests',['python3','scripts/tests/public_native_media_publisher_test.py']),
 ('native-provenance-tests',['ruby','scripts/tests/public_native_media_provenance_test.rb']),
 ('recorder-syntax',['/Volumes/PRO-G40/Development/Node/bin/node','--check','scripts/qa/public_browser_app_media.mjs'])]:run(name,argv)
assert all(sha(EXPORT/n)==h for n,h in inputs.items())
drift={n:{'before':h,'after':sha(ROOT/n) if (ROOT/n).is_file() else None} for n,h in inputs.items() if not (ROOT/n).is_file() or sha(ROOT/n)!=h}
(P/'validation.json').write_text(json.dumps({'status':'pass','commands':commands,'copied_tooling_inputs':len(inputs),'export_inputs_unchanged':True,'original_tooling_drift':drift,'scope':'Strict complete browser fixture graph, actual reachable/unrelated drift mutations, publication bindings and unchanged native/legacy contracts; no route/native/visual acceptance'},indent=2)+'\n')
print('PUBLIC GRAPH TOOLING PASS',flush=True)
