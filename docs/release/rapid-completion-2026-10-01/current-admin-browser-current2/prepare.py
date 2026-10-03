from pathlib import Path
import hashlib,json,shutil
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL');OUT=ROOT/'docs/release/rapid-completion-2026-10-01/current-admin-browser-current2';ACCEPTED=ROOT/'docs/release/rapid-completion-2026-10-01/principal-integration-current2';PRIOR=ROOT/'docs/release/rapid-completion-2026-10-01/current-admin-browser-current1';META=json.loads((ACCEPTED/'inputs.json').read_text());VALID=json.loads((ACCEPTED/'validation.json').read_text());assert VALID['status']=='pass'and VALID['current_changed_inputs_match']and VALID['sdk_unchanged']and not VALID['export_drift']
SOURCE=Path(META['export']);DEST=ROOT/'.cache/current-admin-browser-build-current2';SDK=ROOT/'.cache/flutter-sdk-isolated-admin-browser-current1';assert not DEST.exists()
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
compiled={n:d for n,d in META['inputs_sha256'].items()if n.startswith(('lib/','web/','assets/','third_party/'))or n in ['pubspec.yaml','pubspec.lock','.fvmrc']};assert all((ROOT/n).is_file()and sha(ROOT/n)==d for n,d in compiled.items())
for n,d in META['inputs_sha256'].items():
 p=SOURCE/n;assert sha(p)==d,n
 q=DEST/n;q.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,q)
# Exact runtime/legal and alreadyaccepted Public provenance closure, reused by
# content hash; neither visuals nor source are regenerated here.
old=json.loads((PRIOR/'copied-inputs.json').read_text());extras={**old['supplemental_legal_inputs'],**json.loads((PRIOR/'supplemental-public-provenance.json').read_text())}
for n,d in extras.items():
 p=ROOT/n;assert sha(p)==d,n
 q=DEST/n;q.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,q)
HARNESS='scripts/qa/current_browser_lifecycle.mjs';harness_before=sha(ROOT/HARNESS);shutil.copy2(ROOT/HARNESS,DEST/HARNESS)
assert sha(ROOT/HARNESS)==sha(DEST/HARNESS)==harness_before
assert all(sha(ROOT/n)==d and sha(DEST/n)==d for n,d in compiled.items())
assert all(sha(ROOT/n)==d and sha(DEST/n)==d for n,d in extras.items())
sdk={n:sha(SDK/n)for n in META['sdk_before']};assert sdk==META['sdk_before']
(OUT/'copied-inputs.json').write_text(json.dumps({'source':str(SOURCE),'source_inputs_receipt':str(ACCEPTED/'inputs.json'),'source_inputs_sha256':sha(ACCEPTED/'inputs.json'),'affected_acceptance_receipt':str(ACCEPTED/'validation.json'),'affected_acceptance_sha256':sha(ACCEPTED/'validation.json'),'build_root':str(DEST),'sdk_root':str(SDK),'sdk_before':sdk,'copied_inputs':{n:sha(DEST/n)for n in META['inputs_sha256']},'supplemental_inputs':extras,'executed_harness_sha256':harness_before,'before_copy_after_compiler_inputs_stable':True,'scope':'ONE actual production current Admin bundle; current principal runtime +root guarded format, using accepted component/source proofs. All89 actual browser/PWA checks execute once.'},indent=2)+'\n')
print('PREPARED current production browser source',DEST,flush=True)
