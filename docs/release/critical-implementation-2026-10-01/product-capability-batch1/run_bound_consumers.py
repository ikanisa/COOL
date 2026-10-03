#!/usr/bin/env python3
"""Record current-input proof for PD-07; it grants no acceptance or approval."""
from pathlib import Path
import hashlib,json,subprocess,time,datetime,shutil
ROOT=Path.cwd(); OUT=ROOT/'docs/release/critical-implementation-2026-10-01/product-capability-batch1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def snapshot():
    paths=set()
    for prefix in ['lib','test','assets']:
        paths.update(p for p in (ROOT/prefix).rglob('*') if p.is_file() and not p.name.startswith('.'))
    paths.update(ROOT/p for p in ['.fvmrc','pubspec.yaml','pubspec.lock','analysis_options.yaml','.dart_tool/package_config.json','.dart_tool/package_graph.json','scripts/public_static_site_build.rb','scripts/product_capabilities.rb','scripts/generate_product_capability_content.rb','scripts/qa/public_content_contract.rb','scripts/tests/product_capability_content_test.rb','scripts/tests/public_legal_rendering_test.rb','scripts/tests/public_static_routes_test.rb','scripts/tests/public_content_contract_test.rb'])
    registry=json.loads((ROOT/'content/product/collect_capabilities.json').read_text())
    paths.add(ROOT/'content/product/collect_capabilities.json')
    paths.update(ROOT/p for p in registry['source_inputs'])
    paths.update(ROOT/p for p in registry['store_metadata'])
    paths.update((ROOT/'content/legal').glob('*.yaml'))
    return {str(p.relative_to(ROOT)):sha(p) for p in sorted(paths) if p.is_file()}
flutter=Path(shutil.which('flutter')).resolve();dart=Path(shutil.which('dart')).resolve()
proof={'schema_version':1,'started_at':now(),'scope':'PD-07 current canonical capability facts, generated consumers, real Flutter public UI/navigation/320px 200-percent text, strict whole-tree analysis and direct Ruby content contracts; no visual or publication acceptance','sources_before':snapshot(),'toolchain':{'flutter':str(flutter),'flutter_sha256':sha(flutter),'dart':str(dart),'dart_sha256':sha(dart)},'checks':[]}
checks=[('bound-analysis',[str(flutter),'analyze','--no-pub','--fatal-infos','--fatal-warnings']),('bound-flutter-content',[str(flutter),'test','--no-pub','--reporter','expanded','--file-reporter=json:'+str(OUT/'bound-flutter-content.events.jsonl'),'test/features/public_capability_content_test.dart','test/landing_page_test.dart']),('bound-generated-content',['ruby','scripts/generate_product_capability_content.rb','--check']),('bound-ruby-capability',['ruby','scripts/tests/product_capability_content_test.rb']),('bound-ruby-legal',['ruby','scripts/tests/public_legal_rendering_test.rb']),('bound-ruby-routes',['ruby','scripts/tests/public_static_routes_test.rb']),('bound-ruby-current-contract',['ruby','scripts/tests/public_content_contract_test.rb'])]
for name,cmd in checks:
    log=OUT/(name+'.log');started=time.monotonic()
    with log.open('w') as handle:result=subprocess.run(cmd,cwd=ROOT,stdout=handle,stderr=subprocess.STDOUT)
    proof['checks'].append({'name':name,'command':cmd,'exit_code':result.returncode,'elapsed_seconds':round(time.monotonic()-started,3),'log':str(log.relative_to(ROOT)),'log_sha256':sha(log)})
    print(name+' exit '+str(result.returncode),flush=True)
proof['sources_after']=snapshot();proof['source_unchanged']=proof['sources_before']==proof['sources_after'];proof['finished_at']=now()
proof['status']='pass_scoped_local' if proof['source_unchanged'] and all(c['exit_code']==0 for c in proof['checks']) else 'fail'
proof.update(owner_approved=False,publication_approved=False,legal_release_approved=False,provider_approved=False,hosted_conversion_verified=False,visual_acceptance=False)
(OUT/'bound-consumers.json').write_text(json.dumps(proof,indent=2)+'\n')
print(json.dumps({'status':proof['status'],'input_count':len(proof['sources_before']),'unchanged':proof['source_unchanged']}),flush=True)
raise SystemExit(0 if proof['status']=='pass_scoped_local' else 1)
