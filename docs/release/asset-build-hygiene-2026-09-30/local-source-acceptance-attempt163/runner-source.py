import hashlib,json,os,subprocess,time,shutil,importlib.util
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
P=ROOT/'docs/release/asset-build-hygiene-2026-09-30/local-source-acceptance-attempt163'
EXPORT=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt163')
SDK=ROOT/'.cache/flutter-sdk-isolated-asset-attempt23'
FLUTTER=str(SDK/'bin/flutter');DART=str(SDK/'bin/cache/dart-sdk/bin/dart')
ENV={k:v for k,v in os.environ.items() if k in {'HOME','USER','LOGNAME','SHELL','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}}
ENV.update({'CI':'true','FLUTTER_SUPPRESS_ANALYTICS':'true','PUB_CACHE':str(ROOT/'.cache/pub-cache-hygiene-20260930'),'PATH':str(SDK/'bin')+':/Users/jeanbosco/.local/bin:'+ENV['PATH'],'DART':DART})
P.mkdir(parents=True,exist_ok=False);(P/'runner-source.py').write_bytes(Path(__file__).read_bytes())
commands=[];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def write(status,extra=None):
 (P/'execution.json').write_text(json.dumps({'kind':'isolated_current_source_tooling_acceptance','status':status,'commands':commands,'scope':'Current immutable source export, source-only QA without providers, credentials, signing or release acceptance',**(extra or {})},indent=2)+'\n')
def run(name,args,cwd=EXPORT):
 print('START',name,flush=True);start=time.time()
 with (P/(name+'.stdout')).open('wb') as out,(P/(name+'.stderr')).open('wb') as err:
  code=subprocess.run(args,cwd=cwd,env=ENV,stdout=out,stderr=err).returncode
 commands.append({'name':name,'command':args,'exit_code':code,'elapsed_seconds':round(time.time()-start,2),'stdout_sha256':sha(P/(name+'.stdout')),'stderr_sha256':sha(P/(name+'.stderr'))});write('running');print('END',name,code,flush=True);return code
assert run('source-export',['python3',str(ROOT/'scripts/qa/native_source_export.py'),'--destination',str(EXPORT),'--report',str(P/'source-export.json')],ROOT)==0
source=json.loads((P/'source-export.json').read_text())['source_sha256']
extras={}
names=subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard','-z','--','scripts/','Makefile','AGENTS.md','.gitignore'],cwd=ROOT).decode().split('\0')
for n in sorted(set(names)):
 if not n or not (ROOT/n).is_file():continue
 source_sha=sha(ROOT/n);assert n not in source or source[n]==source_sha,'Native/public-tooling overlapping input changed between copies: '+n
 target=EXPORT/n;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/n,target)
 assert sha(target)==source_sha and sha(ROOT/n)==source_sha,'Additional source changed during export: '+n
 extras[n]=source_sha
(P/'additional-public-tooling-source.json').write_text(json.dumps({'sha256':extras,'scope':'Actual scripts and declared public authority/build callers copied separately from native build inputs'},indent=2,sort_keys=True)+'\n')
assert run('export-git-init',['git','init','-q'])==0
assert run('flutter-version',[FLUTTER,'--version','--machine'])==0
version=json.loads((P/'flutter-version.stdout').read_text());assert version['frameworkVersion']=='3.44.4' and version['frameworkRevision']=='ad70ec4617166f1c38e5d2bfd388af71fda14f06' and version['dartSdkVersion']=='3.12.2'
critical=['bin/cache/dart-sdk/bin/dart','bin/cache/dart-sdk/bin/dartaotruntime','bin/cache/flutter_tools.snapshot','bin/cache/artifacts/engine/darwin-x64/flutter_tester','bin/cache/artifacts/engine/darwin-x64/FlutterMacOS.framework/Versions/A/FlutterMacOS']
sdk_hashes={n:sha(SDK/n) for n in critical if (SDK/n).is_file()};original_hashes={n:sha(Path('/Volumes/PRO-G40/Development/Flutter/flutter')/n) for n in sdk_hashes};assert sdk_hashes==original_hashes
(P/'sdk-isolation.json').write_text(json.dumps({'scope':'APFS copy-on-write SDK clone; actual Git revision/version and listed tool executable/snapshot bytes match the installed pinned tree; full SDK/cache attestation not claimed','critical_sha256':sdk_hashes,'version':version,'shared_sdk_mutated':False},indent=2)+'\n')
assert run('pub-enforce-offline',[FLUTTER,'pub','get','--offline','--enforce-lockfile'])==0
assert sha(EXPORT/'pubspec.lock')==source['pubspec.lock']
format_code=run('format-check',['ruby','scripts/qa/dart_format.rb','--check'])
analyze_code=run('fatal-analyzer',[FLUTTER,'analyze','--no-pub','--fatal-infos','--fatal-warnings'])
landing_code=run('public-copy-responsive-regressions',[FLUTTER,'test','--no-pub','--reporter','expanded','test/landing_page_test.dart'])
export_changes={n:{'before':h,'after':sha(EXPORT/n) if (EXPORT/n).is_file() else None} for n,h in source.items() if not (EXPORT/n).is_file() or sha(EXPORT/n)!=h}
spec=importlib.util.spec_from_file_location('bound_native_export',EXPORT/'scripts/qa/native_source_export.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
current_names=subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard','-z'],cwd=ROOT).decode().split('\0')
current={n:sha(ROOT/n) for n in sorted(set(current_names)) if n and (module.selected(n) or n.startswith('scripts/') or n in {'Makefile','.gitignore'}) and (ROOT/n).is_file() and not (ROOT/n).is_symlink()}
combined={**source,**extras}
checkout_drift={n:{'before':combined.get(n),'after':current.get(n)} for n in sorted(combined.keys()|current.keys()) if combined.get(n)!=current.get(n)}
extra_changes={n:{'before':h,'after':sha(EXPORT/n) if (EXPORT/n).is_file() else None} for n,h in extras.items() if not (EXPORT/n).is_file() or sha(EXPORT/n)!=h}
write('pass' if format_code==analyze_code==landing_code==0 and not export_changes and not extra_changes else 'fail',{'native_source_file_count':len(source),'public_tooling_source_count':len(extras),'export_source_changes':export_changes,'export_tooling_source_changes':extra_changes,'original_checkout_drift':checkout_drift,'entire_declared_application_and_tooling_scope_current':not checkout_drift,'scope_drift_includes_additions_and_deletions':True,'generated_package_binding_sha256':sha(EXPORT/'.dart_tool/package_config.json'),'generated_plugin_binding_sha256':sha(EXPORT/'.flutter-plugins-dependencies')})
print('DONE',flush=True)
