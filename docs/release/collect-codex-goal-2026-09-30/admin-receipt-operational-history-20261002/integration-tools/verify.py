import hashlib,json,pathlib,subprocess,time,urllib.parse
root=pathlib.Path(__file__).resolve().parent
app=root/'validation-app'
proof=root/'proof'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def bindings():
 paths=set()
 for folder in ['lib','test','contracts','scripts/tests/fixtures/exception_inbox_audit_v2']:
  paths.update(p for p in (app/folder).rglob('*') if p.is_file())
 paths.update(app/x for x in ['pubspec.yaml','pubspec.lock','.dart_tool/package_config.json','.dart_tool/package_graph.json'])
 for folder in ['docs/release/collect-codex-goal-2026-09-30/safe-receipt-actions/backend-uat','docs/release/collect-codex-goal-2026-09-30/exception-reads-v2/backend-uat']:
  paths.update(p for p in (app/folder).rglob('*.json') if p.is_file())
 config=json.loads((app/'.dart_tool/package_config.json').read_text())
 for package in config['packages']:
  uri=package['rootUri']; base=pathlib.Path(urllib.parse.unquote(urllib.parse.urlparse(uri).path)) if uri.startswith('file:') else (app/'.dart_tool'/uri).resolve()
  paths.update(p for p in (base/package.get('packageUri','lib/')).rglob('*') if p.is_file())
  if (base/'pubspec.yaml').is_file(): paths.add(base/'pubspec.yaml')
 sdk=pathlib.Path('/Volumes/PRO-G40/Development/Flutter/flutter')
 for x in ['bin/flutter','bin/dart','bin/cache/dart-sdk/bin/dart','bin/cache/artifacts/engine/darwin-arm64/flutter_tester','bin/cache/flutter_tools.snapshot','bin/cache/dart-sdk/version','bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']:
  p=sdk/x
  if p.is_file(): paths.add(p)
 paths.add(app/'assets/typefaces/Inter-Variable.ttf')
 return {str(p):sha(p) for p in sorted(paths)}
before=bindings(); (proof/'bindings-before.json').write_text(json.dumps(before,indent=2)+'\n')
results=[]
for name,args in [('view-tests',['/Volumes/PRO-G40/Development/Flutter/flutter/bin/flutter','test','--no-pub','--concurrency=1','test/admin_receipt_operational_history_test.dart','test/admin_receipt_history_labels_capture_test.dart','test/admin_entity_audit_links_test.dart']),('analysis',['/Volumes/PRO-G40/Development/Flutter/flutter/bin/flutter','analyze','--no-pub','lib/admin/admin_router.dart','lib/admin/core/admin_receipt_operational_history_view.dart','lib/admin/core/admin_receipt_operational_history_models.dart','lib/admin/core/admin_receipt_operational_history_runtime.dart','lib/admin/core/admin_receipt_operational_history_sdk.dart','lib/admin/core/admin_entity_audit.dart','lib/admin/core/admin_entity_audit_page.dart','lib/admin/core/admin_receipt_repository.dart','lib/admin/core/admin_repository_base.dart','lib/admin/core/admin_runtime.dart','lib/admin/core/admin_automatic_gateway_view.dart','lib/admin/core/admin_automations_page.dart','test/admin_receipt_history_labels_capture_test.dart','test/admin_receipt_operational_history_test.dart','test/admin_entity_audit_links_test.dart'])]:
 with (proof/(name+'.stdout')).open('w') as stdout,(proof/(name+'.stderr')).open('w') as stderr:
  proc=subprocess.run(args,cwd=app,stdout=stdout,stderr=stderr)
 results.append({'name':name,'command':args,'cwd':str(app),'exit_code':proc.returncode})
 if proc.returncode:break
after=bindings();(proof/'bindings-after.json').write_text(json.dumps(after,indent=2)+'\n')
drift=[p for p in sorted(before.keys()|after.keys()) if before.get(p)!=after.get(p)]
result={'commands':results,'binding_count':len(before),'source_dependency_tool_drift':drift,'scope':'Current canonical history/capture/joined-audit consumers with actual SQL DTO fixtures and synthetic session; no hosted/actual reader/full comparator acceptance','status':'passed' if len(results)==2 and all(x['exit_code']==0 for x in results) and not drift else 'failed'}
(proof/'result.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result));raise SystemExit(0 if result['status']=='passed' else 1)
