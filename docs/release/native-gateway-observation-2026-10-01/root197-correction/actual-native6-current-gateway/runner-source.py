#!/usr/bin/env python3
"""Actual native regression using retained task-owned caches and a fresh declared source capture."""
import os,sys,json,hashlib,shutil,subprocess,time,importlib.util,xml.etree.ElementTree as ET,zipfile,datetime as dt
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL');EXPORT=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt126-gateway');BASE=ROOT/'docs/release/asset-build-hygiene-2026-09-30/native-export-attempt126-gateway';OUT=ROOT/'docs/release/native-gateway-observation-2026-10-01/root197-correction/actual-native6-current-gateway';SDK=ROOT/'.cache/flutter-sdk-isolated-asset-attempt136';ANDROID=Path('/Users/jeanbosco/Library/Android/sdk');sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def save(p,v):p.write_text(json.dumps(v,indent=2,sort_keys=True)+'\n')
assert not OUT.exists();OUT.mkdir(mode=0o700);(OUT/'runner-source.py').write_bytes(Path(__file__).read_bytes());parent=json.loads((BASE/'execution.json').read_bytes());assert any(r['name']=='unsigned-gateway-build'and r['exit_code']==0 for r in parent['commands']);assert any(r['name']=='gateway-native-lint'and r['exit_code']==1 for r in parent['commands']);save(OUT/'parent-failure-binding.json',dict(parent_sha256=sha(BASE/'execution.json'),scope='Prior unsigned compilation succeeded; full lint refused four real API/permission defects. Reuse only the task-owned isolated cache, not prior source acceptance.'))
for p in(EXPORT/'build/app/outputs').rglob('*production*release*.apk'):
 target=OUT/('prior-'+p.name);subprocess.run(['cp','-c',str(p),str(target)],check=True);save(OUT/'prior-artifact.json',dict(path=str(target.relative_to(ROOT)),sha256=sha(target),bytes=target.stat().st_size,prior_compilation_only=True,signature_or_manifest_acceptance_claimed=False))
spec=importlib.util.spec_from_file_location('native_export',ROOT/'scripts/qa/native_source_export.py');native=importlib.util.module_from_spec(spec);spec.loader.exec_module(native)
names=subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard','-z'],cwd=ROOT).decode().split('\0');inputs={n:sha(ROOT/n)for n in sorted(set(names))if n and(native.selected(n)or n.startswith('scripts/')or n in {'Makefile','.gitignore'})and(ROOT/n).is_file()and not(ROOT/n).is_symlink()};save(OUT/'source-before.json',inputs)
old=json.loads((BASE/'source-export.json').read_bytes());oldinputs=old.get('clone_inputs_sha256',old.get('source_sha256',{}));removed=[n for n in oldinputs if n not in inputs];relocations=json.loads((ROOT/'docs/release/native-gateway-observation-2026-10-01/flavor-boundary-relocation-root206.json').read_text())['files'];assert set(removed)==({r['old'] for r in relocations}&set(oldinputs));retained_source={}
for row in relocations:
 n=row['old'];oldpath=EXPORT/n;target=EXPORT/'.qa_retained_source_parent126'/n
 if n not in oldinputs:
  assert not oldpath.exists()and not target.exists();continue
 if target.exists():
  assert not oldpath.exists()and sha(target)==oldinputs[n]
 else:
  assert oldpath.is_file()and sha(oldpath)==oldinputs[n];target.parent.mkdir(parents=True,exist_ok=True);oldpath.rename(target)
 retained_source[n]=dict(sha256=sha(target),path=str(target),parent_hash_match=True)
save(OUT/'retained-parent-source-relocations.json',retained_source)
for n,h in inputs.items():
 target=EXPORT/n;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/n,target);assert sha(target)==h and sha(ROOT/n)==h,n
save(OUT/'source-export.json',dict(destination=str(EXPORT),inputs_sha256=inputs,scope='Fresh declared source overlay after preserved failed build; generated SDK/package/build cache retained separately, no ignored provider/signing input copied'))
env={k:v for k,v in os.environ.items()if k in {'HOME','USER','LOGNAME','SHELL','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}};env.update(CI='true',FLUTTER_SUPPRESS_ANALYTICS='true',JAVA_HOME='/Volumes/PRO-G40/Applications/Android Studio.app/Contents/jbr/Contents/Home',PUB_CACHE=str(ROOT/'.cache/pub-cache-hygiene-20260930'),PATH=str(SDK/'bin')+':/Users/jeanbosco/.local/bin:'+env['PATH']);commands=[];result=dict(status='running',commands=commands,source_file_count=len(inputs),provider_credentials_supplied=False)
def run(name,argv,cwd=EXPORT/'android',expected=0):
 print('START',name,flush=True);start=time.monotonic()
 with(OUT/(name+'.stdout')).open('wb')as out,(OUT/(name+'.stderr')).open('wb')as err:r=subprocess.run(argv,cwd=cwd,env=env,stdout=out,stderr=err,timeout=7200)
 commands.append(dict(name=name,command=argv,exit_code=r.returncode,expected_exit=expected,elapsed_seconds=round(time.monotonic()-start,2),stdout_sha256=sha(OUT/(name+'.stdout')),stderr_sha256=sha(OUT/(name+'.stderr'))));save(OUT/'execution.json',result);print('END',name,r.returncode,flush=True);assert r.returncode==expected,name
try:
 old_dependencies=EXPORT/'.qa_native_dependencies';retained=EXPORT/'.qa_native_dependencies.parent126-retained'
 assert old_dependencies.is_dir()and not old_dependencies.is_symlink()and not retained.exists()
 assert json.loads((BASE/'execution.json').read_text())['status']=='fail'
 old_dependencies.rename(retained)
 save(OUT/'retained-parent-dependency-cache.json',dict(path=str(retained),preserved=True,reason='Prior task-owned dependency copy retained before fresh current resolution; earlier gate refused reuse as designed'))
 run('pub-enforce-offline',[str(SDK/'bin/flutter'),'pub','get','--offline','--enforce-lockfile'],EXPORT);assert sha(EXPORT/'pubspec.lock')==inputs['pubspec.lock']
 spec=importlib.util.spec_from_file_location('packages',ROOT/'scripts/qa/resolved_native_package_inputs.py');packages=importlib.util.module_from_spec(spec);spec.loader.exec_module(packages);binding=packages.bind(EXPORT,SDK,ROOT/'.cache/pub-cache-hygiene-20260930');save(OUT/'resolved-package-inputs-before.json',binding)
 run('current-gateway-native-lint',['./gradlew',':app:lintInternal_gatewayRelease','-Ptarget=lib/main_gateway.dart','--offline','--no-daemon'])
 for flavor,target in [('internal_gateway','lib/main_gateway.dart')]:
  gradle='Production'if flavor=='production'else'Internal_gateway';prefix=flavor
  run(prefix+'-unsigned-assemble',['./gradlew',':app:assemble'+gradle+'Release','-Ptarget='+target,'-PcollectUnsignedLocalQa=true','--offline','--no-daemon'])

  run(prefix+'-jvm',['./gradlew',':app:test'+gradle+'DebugUnitTest','-Ptarget='+target,'--offline','--no-daemon'])
  apk=EXPORT/f'build/app/outputs/apk/{flavor}/release/app-{flavor}-release-unsigned.apk';assert apk.is_file()
  with zipfile.ZipFile(apk)as z:assert z.testzip()is None
  run(prefix+'-signature',[str(ANDROID/'build-tools/37.0.0/apksigner'),'verify','--verbose',str(apk)],EXPORT,expected=1);assert 'DOES NOT VERIFY'in(OUT/(prefix+'-signature.stderr')).read_text()+(OUT/(prefix+'-signature.stdout')).read_text()
  run(prefix+'-manifest',[str(ANDROID/'build-tools/37.0.0/aapt2'),'dump','badging',str(apk)],EXPORT)
  text=(OUT/(prefix+'-manifest.stdout')).read_text();assert("name='app.cool.mobile'"if flavor=='production'else"name='app.cool.mobile.gateway'")in text
  for perm in ['READ_EXTERNAL_STORAGE','WRITE_EXTERNAL_STORAGE']:assert 'android.permission.'+perm not in text
  if flavor=='production':assert 'android.permission.SEND_SMS'not in text and 'android.permission.READ_PHONE_STATE'not in text
  else:
   for perm in ['SEND_SMS','READ_PHONE_STATE','ACCESS_NETWORK_STATE']:assert 'android.permission.'+perm in text
   for perm in ['RECEIVE_SMS','CALL_PHONE','CAMERA','POST_NOTIFICATIONS','ACCESS_COARSE_LOCATION','ACCESS_FINE_LOCATION']:assert 'android.permission.'+perm not in text
  lint=EXPORT/f'build/app/reports/lint-results-{flavor}Release.xml';issues=[dict(id=i.get('id'),severity=i.get('severity'),message=i.get('message'),locations=[x.attrib for x in i.findall('location')])for i in ET.parse(lint).getroot().findall('issue')];assert not any(i['severity']in ['Error','Fatal']for i in issues);shutil.copy2(lint,OUT/lint.name);save(OUT/(prefix+'-lint-inventory.json'),issues)
  tests=list((EXPORT/f'build/app/test-results/test{gradle}DebugUnitTest').glob('TEST-*.xml'));totals=[ET.parse(p).getroot().attrib for p in tests];assert tests and all(r['failures']==r['errors']==r['skipped']=='0'for r in totals);testout=OUT/(prefix+'-jvm-results');testout.mkdir();
  for p in tests:shutil.copy2(p,testout/p.name)
  save(OUT/(prefix+'-artifact.json'),dict(status='pass',path=str(apk),sha256=sha(apk),bytes=apk.stat().st_size,unsigned_rejection_verified=True,jvm_test_count=sum(int(r['tests'])for r in totals),lint_warnings=len(issues),scope='Actual unsigned current source flavor compilation, permissions, lint and JVM semantics; no handset/carrier/provider/signing/store acceptance'))
 verify=packages.verify(binding,EXPORT);save(OUT/'resolved-package-inputs-after.json',verify);assert verify['status']=='pass'
 after={n:sha(ROOT/n)for n in inputs};drift={n:dict(before=h,after=after[n])for n,h in inputs.items()if h!=after[n]};export_drift=[n for n,h in inputs.items()if sha(EXPORT/n)!=h];result.update(status='pass'if not drift and not export_drift else'fail',source_drift=drift,export_drift=export_drift)
except BaseException as e:
 result.update(status='fail',failure=str(e));raise
finally:
 result['completed_at']=dt.datetime.now(dt.timezone.utc).isoformat();save(OUT/'execution.json',result)
