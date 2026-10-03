#!/usr/bin/env python3
"""Rebuild current normal Public/Admin and repeat observed local browser lifecycle."""
import sys,json,hashlib,os,subprocess,shutil,time,datetime as dt
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL');sys.path.insert(0,str(ROOT/'scripts/tests'));import final_flutter_acceptance as F
EXPORT=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-root212-current-browser');P=ROOT/'docs/release/local-browser-lifecycle-2026-09-30/current-email-memory-auth-root212-attempt15';CACHE=ROOT/'.cache/local-browser-lifecycle-20261001/current-email-memory-auth-root212-attempt15';SDK=ROOT/'.cache/flutter-sdk-isolated-browser-root195';NODE=Path('/Users/jeanbosco/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node');CHROME=Path('/Users/jeanbosco/.cache/selenium/chrome/mac-arm64/151.0.7922.34/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def save(p,v):p.write_text(json.dumps(v,indent=2,sort_keys=True)+'\n')
assert not EXPORT.exists()and not CACHE.exists()and not P.exists();P.mkdir(parents=True,mode=0o700);(P/'runner-source.py').write_bytes(Path(__file__).read_bytes());inputs=F.declared_files();save(P/'source-before.json',inputs)
for n,h in inputs.items():
 target=EXPORT/n;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/n,target);assert sha(target)==h and sha(ROOT/n)==h,n
save(P/'source-binding.json',dict(isolated_export=str(EXPORT),inputs_sha256=inputs,source_count=len(inputs),native_private_files_excluded=True,scope='Exact declared current source after Gateway motion and receipt-v2 decoder changes; normal production Admin/Public entrypoints with synthetic loopback transport'))
critical=[SDK/'bin/cache/dart-sdk/bin/dart',SDK/'bin/cache/dart-sdk/bin/dartaotruntime',SDK/'bin/cache/flutter_tools.snapshot',NODE,CHROME];binary_inputs={str(p):sha(p)for p in critical};save(P/'runtime-before.json',binary_inputs)
env={k:v for k,v in os.environ.items()if k in {'HOME','USER','LOGNAME','SHELL','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}};env.update(CI='true',FLUTTER_SUPPRESS_ANALYTICS='true',PUB_CACHE=str(ROOT/'.cache/pub-cache-hygiene-20260930'),COLLECT_BROWSER_BUILD_ROOT=str(EXPORT),COLLECT_BROWSER_FLUTTER=str(SDK/'bin/flutter'),ADMIN_PWA_CHROME=str(CHROME),PLAYWRIGHT_CORE_PATH='/Users/jeanbosco/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright-core/index.js',PATH=str(SDK/'bin')+':/Users/jeanbosco/.local/bin:'+env['PATH']);commands=[]
def run(name,argv,cwd=EXPORT):
 print('START',name,flush=True);start=time.monotonic()
 with(P/(name+'.stdout')).open('wb')as out,(P/(name+'.stderr')).open('wb')as err:r=subprocess.run(argv,cwd=cwd,env=env,stdout=out,stderr=err,timeout=3600)
 commands.append(dict(name=name,command=argv,cwd=str(cwd),exit_code=r.returncode,elapsed_seconds=round(time.monotonic()-start,2),stdout_sha256=sha(P/(name+'.stdout')),stderr_sha256=sha(P/(name+'.stderr'))));save(P/'execution.json',dict(status='running',commands=commands));print('END',name,r.returncode,flush=True);return r.returncode
assert run('export-git-init',['git','init','-q'])==0
assert run('flutter-version',[str(SDK/'bin/flutter'),'--version','--machine'])==0
version=json.loads((P/'flutter-version.stdout').read_bytes());assert version['frameworkVersion']=='3.44.4'and version['frameworkRevision']=='ad70ec4617166f1c38e5d2bfd388af71fda14f06'and version['dartSdkVersion']=='3.12.2'
assert run('pub-enforce-offline',[str(SDK/'bin/flutter'),'pub','get','--offline','--enforce-lockfile'])==0;assert sha(EXPORT/'pubspec.lock')==inputs['pubspec.lock']
code=run('actual-current-browser',[str(NODE),str(ROOT/'scripts/qa/current_browser_lifecycle.mjs'),str(CACHE)],ROOT)
report=json.loads((CACHE/'report.json').read_bytes())if(CACHE/'report.json').exists()else None
if report:shutil.copy2(CACHE/'report.json',P/'report.json')
for n in ['signed-out-admin.png','public-isolation.png','installed-signed-out.png']:
 if(CACHE/n).is_file():shutil.copy2(CACHE/n,P/n)
after=F.declared_files();source_drift={n:dict(before=inputs.get(n),after=after.get(n))for n in inputs.keys()|after.keys()if inputs.get(n)!=after.get(n)};export_drift=[n for n,h in inputs.items()if not(EXPORT/n).is_file()or sha(EXPORT/n)!=h];runtime_after={str(p):sha(p)for p in critical};save(P/'source-after.json',after);save(P/'runtime-after.json',runtime_after)
passed=code==0 and report is not None and report['status']=='pass'and report['source_inputs_stable']and len(report['checks'])==26 and all(r['status']=='pass'for r in report['checks'])and len(report['coverage'])==16 and all(report['coverage'].values())and not report['errors']and not source_drift and not export_drift and binary_inputs==runtime_after
save(P/'validation.json',dict(status='pass'if passed else'fail',actual_browser_return_code=code,report_sha256=sha(P/'report.json')if report else None,commands=commands,export_drift=export_drift,checkout_input_drift=source_drift,actual_browser_report=str(CACHE/'report.json'),retained_source_binding_sha256=sha(P/'source-binding.json'),coverage=report['coverage']if report else None,checks=len(report['checks'])if report else 0,errors=len(report['errors'])if report else None,source_input_count=len(inputs),source_inputs_current=not source_drift,runtime_executables_unchanged=binary_inputs==runtime_after,synthetic_browser_profile_excluded_from_repo=True,provider_credentials_supplied=False,database_commands_executed=False,whole_L01_complete=False,whole_L18_original_local_criterion_complete=passed,scope='Actual current normal Admin/Public entrypoints and browser lifecycle including installed standalone PWA offline; no SQL/provider/physical-device/design or whole repository/release acceptance',completed_at=dt.datetime.now(dt.timezone.utc).isoformat()))
print('BROWSER RESULT',passed,flush=True);raise SystemExit(0 if passed else 1)
