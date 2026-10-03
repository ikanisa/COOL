import pathlib,hashlib,json,subprocess,datetime
root=pathlib.Path.cwd(); packet=root/'.cache/android-dispatch-edge-final'; stage=packet/'source'; stage.mkdir(exist_ok=True)
paths=list(pathlib.Path('supabase/functions/collect-android-gateway').glob('*.ts'))+[pathlib.Path('supabase/functions/_shared/test_assert.ts')]+list(pathlib.Path('contracts/collect-android-dispatch-v2/fixtures').glob('*.json'))
paths+=[pathlib.Path('.cache/android-dispatch-edge-final/run.py')]
sha=lambda b:hashlib.sha256(b).hexdigest()
hashes={}
for p in paths:
 b=p.read_bytes(); hashes[str(p)]=sha(b); dest=stage/p; dest.parent.mkdir(parents=True,exist_ok=True); dest.write_bytes(b); assert dest.read_bytes()==b
binary=pathlib.Path('/Users/jeanbosco/.local/bin/deno').resolve(); binary_hash=sha(binary.read_bytes())
evidence={'started_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source_sha256':hashes,'binary_sha256':binary_hash,'scope':'offline synthetic signed handler plus actual task-private SQL outputs; no network/provider/Auth/runtime acceptance','commands':[]}
(packet/'execution-binding.json').write_text(json.dumps(evidence,indent=2)+'\n')
commands=[('lint',[str(binary),'lint','supabase/functions/collect-android-gateway/handler.ts','supabase/functions/collect-android-gateway/handler_test.ts','supabase/functions/collect-android-gateway/dispatch_v2_test.ts','supabase/functions/collect-android-gateway/dispatch_observed_test.ts']),('tests',[str(binary),'test','--cached-only','--allow-read=contracts/collect-android-dispatch-v2/fixtures','supabase/functions/collect-android-gateway/handler_test.ts','supabase/functions/collect-android-gateway/dispatch_v2_test.ts','supabase/functions/collect-android-gateway/dispatch_observed_test.ts'])]
for label,cmd in commands:
 r=subprocess.run(cmd,cwd=stage,text=True,capture_output=True,timeout=120); (packet/(label+'.stdout')).write_text(r.stdout); (packet/(label+'.stderr')).write_text(r.stderr); evidence['commands'].append({'name':label,'argv':cmd,'exit_code':r.returncode}); print(label,r.returncode,flush=True)
 evidence['passed']=all(c['exit_code']==0 for c in evidence['commands']); (packet/'result.json').write_text(json.dumps(evidence,indent=2)+'\n')
 if r.returncode:break
evidence['source_changes']=[p for p,h in hashes.items()if sha((root/p).read_bytes())!=h]; evidence['binary_changed']=sha(binary.read_bytes())!=binary_hash; evidence['finished_at']=datetime.datetime.now(datetime.timezone.utc).isoformat();(packet/'result.json').write_text(json.dumps(evidence,indent=2)+'\n'); print(json.dumps({'passed':evidence['passed'],'source_changes':evidence['source_changes'],'binary_changed':evidence['binary_changed']}))
raise SystemExit(0 if evidence['passed'] else 1)
