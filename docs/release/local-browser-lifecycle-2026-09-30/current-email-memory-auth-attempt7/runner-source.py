import json,hashlib,os,subprocess,shutil,time
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
BASE=ROOT/'docs/release/asset-build-hygiene-2026-09-30/local-source-acceptance-attempt167'
BOUND=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt167')
EXPORT=BOUND.parent/'export-attempt174-current-browser'
P=ROOT/'docs/release/local-browser-lifecycle-2026-09-30/current-email-memory-auth-attempt7'
CACHE=ROOT/'.cache/local-browser-lifecycle-20261001/current-email-memory-auth-attempt7'
SDK=ROOT/'.cache/flutter-sdk-isolated-asset-attempt136'
NODE=Path('/Users/jeanbosco/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert json.loads((BASE/'execution.json').read_text())['status']=='pass'
assert not EXPORT.exists() and not CACHE.exists()
P.mkdir(parents=True,exist_ok=False)
(P/'runner-source.py').write_bytes(Path(__file__).read_bytes())
source=json.loads((BASE/'source-export.json').read_text())['source_sha256']
extras=json.loads((BASE/'additional-public-tooling-source.json').read_text())['sha256']
inputs={**source,**extras}
overrides=['scripts/qa/current_browser_lifecycle.mjs','scripts/qa/local_browser_api_fixture.mjs','scripts/tests/local_browser_email_fixture_test.mjs','scripts/qa/swift_cached_artifact_inputs.py','scripts/tests/swift_cached_artifact_inputs_test.py','test/admin_platform_access_test.dart','test/admin_sensitive_permission_test.dart']
for name,digest in sorted(inputs.items()):
 origin=BOUND/name;assert origin.is_file() and sha(origin)==digest,name
 if name not in overrides:assert (ROOT/name).is_file() and sha(ROOT/name)==digest,name
 target=EXPORT/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(origin,target)
for name in overrides:
 target=EXPORT/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/name,target);inputs[name]=sha(ROOT/name)
(P/'source-binding.json').write_text(json.dumps({'accepted_parent_source_export_sha256':sha(BASE/'source-export.json'),'accepted_parent_execution_sha256':sha(BASE/'execution.json'),'isolated_export':str(EXPORT),'inputs_sha256':inputs,'fresh_qa_only_overrides':overrides,'application_and_native_inputs_changed':False,'scope':'Exact accepted167 application and build callers, with separately captured current email/memory-auth synthetic transport and browser tests'},indent=2,sort_keys=True)+'\n')
env={k:v for k,v in os.environ.items() if k in {'HOME','USER','LOGNAME','SHELL','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}}
env.update({'CI':'true','FLUTTER_SUPPRESS_ANALYTICS':'true','PUB_CACHE':str(ROOT/'.cache/pub-cache-hygiene-20260930'),'COLLECT_BROWSER_BUILD_ROOT':str(EXPORT),'COLLECT_BROWSER_FLUTTER':str(SDK/'bin/flutter'),'ADMIN_PWA_CHROME':'/Users/jeanbosco/.cache/selenium/chrome/mac-arm64/151.0.7922.34/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing','PLAYWRIGHT_CORE_PATH':'/Users/jeanbosco/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright-core/index.js','PATH':str(SDK/'bin')+':/Users/jeanbosco/.local/bin:'+env['PATH']})
commands=[]
def run(name,args,cwd):
 print('START',name,flush=True);started=time.monotonic()
 with (P/(name+'.stdout')).open('wb') as out,(P/(name+'.stderr')).open('wb') as err:r=subprocess.run(args,cwd=cwd,env=env,stdout=out,stderr=err)
 commands.append({'name':name,'command':args,'cwd':str(cwd),'exit_code':r.returncode,'elapsed_seconds':round(time.monotonic()-started,2),'stdout_sha256':sha(P/(name+'.stdout')),'stderr_sha256':sha(P/(name+'.stderr'))})
 (P/'execution.json').write_text(json.dumps({'status':'running' if r.returncode==0 else 'failed','commands':commands},indent=2)+'\n')
 print('END',name,r.returncode,flush=True)
 return r.returncode
assert run('export-git-init',['git','init','-q'],EXPORT)==0
assert run('pub-enforce-offline',[str(SDK/'bin/flutter'),'pub','get','--offline','--enforce-lockfile'],EXPORT)==0
assert sha(EXPORT/'pubspec.lock')==inputs['pubspec.lock']
code=run('actual-current-browser',[str(NODE),str(ROOT/'scripts/qa/current_browser_lifecycle.mjs'),str(CACHE)],ROOT)
report=json.loads((CACHE/'report.json').read_text()) if (CACHE/'report.json').exists() else None
if report:shutil.copy2(CACHE/'report.json',P/'report.json')
for name in ['signed-out-admin.png','public-isolation.png','installed-signed-out.png']:
 if (CACHE/name).is_file():shutil.copy2(CACHE/name,P/name)
export_drift={n:{'before':h,'after':sha(EXPORT/n) if (EXPORT/n).is_file() else None} for n,h in inputs.items() if not (EXPORT/n).is_file() or sha(EXPORT/n)!=h}
root_drift={n:{'before':h,'after':sha(ROOT/n) if (ROOT/n).is_file() else None} for n,h in inputs.items() if not (ROOT/n).is_file() or sha(ROOT/n)!=h}
passed=code==0 and report is not None and report['status']=='pass' and report['source_inputs_stable'] and not export_drift and not root_drift
(P/'validation.json').write_text(json.dumps({'status':'pass' if passed else 'fail','actual_browser_return_code':code,'report_sha256':sha(P/'report.json') if report else None,'commands':commands,'export_drift':export_drift,'checkout_input_drift':root_drift,'actual_browser_report':str(CACHE/'report.json'),'retained_source_binding_sha256':sha(P/'source-binding.json'),'coverage':report['coverage'] if report else None,'checks':len(report['checks']) if report else 0,'errors':len(report['errors']) if report else None,'synthetic_browser_profile_excluded_from_repo':True,'database_calls':0,'hosted_calls':0,'provider_calls':0,'whole_L01_complete':False,'whole_L18_complete':False,'scope':'Actual current normal Admin/Public build and local browser lifecycle; saved149 recovery, current SQL authorization and broader final-source integration retain their separate evidence'},indent=2)+'\n')
print('BROWSER RESULT',passed,flush=True)
raise SystemExit(0 if passed else 1)
