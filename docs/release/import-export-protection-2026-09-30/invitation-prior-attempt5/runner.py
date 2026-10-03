import hashlib,json,os,subprocess,sys,time
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL');name=sys.argv[1];tests=sys.argv[2:];prior='--prior-invitation-methods' in tests
if prior:tests.remove('--prior-invitation-methods')
P=ROOT/'docs/release/import-export-protection-2026-09-30'/name
EXPORT=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930')/('export-'+name)
SDK=ROOT/'.cache/flutter-sdk-isolated-asset-attempt28';FLUTTER=str(SDK/'bin/flutter')
ENV=os.environ.copy();ENV.update({'CI':'true','FLUTTER_SUPPRESS_ANALYTICS':'true','PUB_CACHE':str(ROOT/'.cache/pub-cache-hygiene-20260930'),'PATH':str(SDK/'bin')+':'+ENV['PATH']})
P.mkdir(parents=True,exist_ok=False);(P/'runner.py').write_bytes(Path(__file__).read_bytes());commands=[]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def run(n,args,cwd=EXPORT):
 print('START',n,flush=True);start=time.time()
 with (P/(n+'.stdout')).open('wb') as out,(P/(n+'.stderr')).open('wb') as err:
  try:code=subprocess.run(args,cwd=cwd,env=ENV,stdout=out,stderr=err,timeout=600).returncode
  except subprocess.TimeoutExpired:code=124
 commands.append({'name':n,'argv':args,'exit_code':code,'elapsed_seconds':round(time.time()-start,2),'stdout_sha256':sha(P/(n+'.stdout')),'stderr_sha256':sha(P/(n+'.stderr'))});print('END',n,code,flush=True);return code
assert run('source-export',['python3',str(ROOT/'scripts/qa/native_source_export.py'),'--destination',str(EXPORT),'--report',str(P/'source-export.json')],ROOT)==0
source=json.loads((P/'source-export.json').read_text())['source_sha256']
if prior:
 old=(ROOT/'docs/release/import-export-protection-2026-09-30/invitation-prior-attempt4/source-export.json')
 old_report=json.loads(old.read_text())
 prior_source=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-invitation-prior-attempt4/lib/shared/repositories/collect_repository.dart')
 raw=prior_source.read_text();assert sha(prior_source)==old_report['source_sha256']['lib/shared/repositories/collect_repository.dart']
 a=raw.index('  Future<String> getGroupShareCode(');b=raw.index('\n  PaymentIntentModel intentById(',a);methods=raw[a:b]
 target=EXPORT/'lib/shared/repositories/collect_repository.dart';current=target.read_text();a=current.index('  Future<String> getGroupShareCode(');b=current.index('\n  PaymentIntentModel intentById(',a);target.write_text(current[:a]+methods+current[b:])
 (P/'prior-methods.dart').write_text(methods);(P/'prior-overrides.json').write_text(json.dumps({'prior_source_sha256':sha(prior_source),'prior_methods_sha256':sha(P/'prior-methods.dart'),'scope':'Only prior invitation methods substituted; fixture fixes/current shared co-resident source preserved'},indent=2)+'\n')
 source['lib/shared/repositories/collect_repository.dart']=sha(target)
(P/'tested-source-sha256.json').write_text(json.dumps(source,indent=2,sort_keys=True)+'\n')
assert run('git-init',['git','init','-q'])==0
assert run('pub-offline',[FLUTTER,'pub','get','--offline','--enforce-lockfile'])==0
code=run('tests',[FLUTTER,'test','--no-pub','--reporter','expanded',*tests])
analyze=run('analysis',[FLUTTER,'analyze','--no-pub','--fatal-infos','--fatal-warnings',*tests])
changes={n for n,h in source.items() if not (EXPORT/n).is_file() or sha(EXPORT/n)!=h}
drift={n for n,h in source.items() if not (ROOT/n).is_file() or sha(ROOT/n)!=h}
(P/'validation.json').write_text(json.dumps({'status':'pass' if code==analyze==0 and not changes else 'fail','commands':commands,'source_inputs':len(source),'export_source_changes':sorted(changes),'checkout_drift':sorted(drift),'export':str(EXPORT),'scope':'Actual Flutter production methods/widgets and locked SDK using synthetic local HTTP/platform transports; no database/provider/native build/capture executed'},indent=2)+'\n')
print('DONE',code,analyze,flush=True)
