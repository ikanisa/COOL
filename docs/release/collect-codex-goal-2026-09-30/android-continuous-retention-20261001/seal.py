from pathlib import Path
import json,hashlib,shutil,os
repo=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL');stage=repo/'.cache/android-continuous-retention-20261001'
latest=json.loads((stage/'latest-proof.json').read_text());run=Path(latest['path']);validation=json.loads((run/'validation.json').read_text())
if latest['status']!='pass' or validation['status']!='pass':raise SystemExit('No accepted complete proof')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
if len(validation['commands'])!=4 or validation['jvm_suite_count']!=10 or validation['native_source_count']!=23:raise SystemExit('Required proof coverage missing')
if any(c.get('status')!='terminal' or c.get('exit_code')!=0 or c.get('owned_child_reaped') is not True for c in validation['commands']):raise SystemExit('Nonterminal or failing command')
for rel,h in validation['source_sha256'].items():
 if sha(run/'source'/rel)!=h or sha(stage/'source'/rel)!=h:raise SystemExit('Source drift')
for c in validation['commands']:
 for stream in ('stdout','stderr'):
  if sha(run/(c['name']+'.'+stream))!=c[stream+'_sha256']:raise SystemExit('Proof output drift')
leaf=stage/'accepted-packet';leaf.mkdir(mode=0o700,exist_ok=False)
shutil.copytree(run/'source',leaf/'source');shutil.copytree(run/'shims',leaf/'shims')
for name in ['validation.json','commands.json','jdk-runtime-closure.json']:
 shutil.copyfile(run/name,leaf/name)
for p in sorted(run.glob('*.stdout'))+sorted(run.glob('*.stderr')):shutil.copyfile(p,leaf/p.name)
for name in ['proof.py','proof.before-finish.py','delta-proof.py','callback-v2-fixture-correction.diff','canonical-before.json','seal.py']:shutil.copyfile(stage/name,leaf/name)
prior=Path(validation['prior_proof']);prior_leaf=leaf/'retained-attempt-7';prior_leaf.mkdir()
for name in ['validation.json','commands.json']:
 shutil.copyfile(prior/name,prior_leaf/name)
for p in sorted(prior.glob('*.stdout'))+sorted(prior.glob('*.stderr')):shutil.copyfile(p,prior_leaf/p.name)
prior_test='android/app/src/testInternal_gateway_archiveJvm/kotlin/app/cool/mobile/gateway/GatewayAttemptArchiveTest.kt'
shutil.copyfile(prior/'source'/prior_test,prior_leaf/'GatewayAttemptArchiveTest.kt')
shutil.copyfile(run/'CorrectedCaseRunner.kt',leaf/'CorrectedCaseRunner.kt')
outputs={str(p.relative_to(run)):sha(p) for directory in ['classes','test-classes','api-classes','runner-classes'] for p in sorted((run/directory).rglob('*')) if p.is_file()}
(leaf/'compiled-artifacts.json').write_text(json.dumps(outputs,indent=2)+'\n')
promotion=[]
for rel,h in validation['source_sha256'].items():
 before=repo/rel;source=stage/'source'/rel
 oldhash=sha(before) if before.exists() else None
 if oldhash!=h:
  promotion.append({'path':rel,'operation':'replace' if before.exists() else 'add','canonical_before_sha256':oldhash,'staged_sha256':h,'canonical_before_mode':oct(before.stat().st_mode & 0o777) if before.exists() else None,'requested_mode':oct(before.stat().st_mode & 0o777) if before.exists() else '0o644','bytes':source.stat().st_size})
(leaf/'promotion-manifest.json').write_text(json.dumps({'canonical_promotion_performed':False,'proof':str(run),'source_scope':'38 selected source/config/runner inputs; 23 native Android files; 10 JVM suites','files':promotion},indent=2)+'\n')
(leaf/'ACCEPTANCE.md').write_text("""# Android continuous retention staged acceptance

This staged implementation retains every request UUID independently of its action, attempt or callback payload. Exact originals and authenticated acknowledgements live in encrypted objects with bounded fixed-depth index nodes. Hot admission stores its pending originals before permanent reservations; interrupted publication repairs only those originals. Successful heartbeat receipts no longer append to the finite legacy archive. Cold attempt terminal markers authorize compaction only after immutable acknowledged evidence and complete original identities have durable readback. Callback receipts remain hot until an actual bound terminal-attempt acknowledgement closes them.

The existing v1 callback path has observational archived evidence only. Its hot attempt and callback requests remain retained because v1 has no terminal-attempt authority. Observational conflicts stop processing and preserve evidence. Protocol and callback identity readers now use the retained original aliases after compaction. Legacy hot requests, acknowledgements and cold attempts migrate four objects per call with durable cursor and exact immutable readback; new identity admission remains closed while migration is incomplete.

Composed accepted proof covers 161 unique cases across 10 JVM suites: nine unchanged passing suites and 36 unchanged successful methods from terminal failed attempt 7, plus the one corrected v2 fixture case recompiled and executed on current source. The whole 37-case attempt suite was not repeated on current source. The retained terminal failure, exact fixture correction and source/runtime association are preserved. This coverage includes including 300 real signed-backend heartbeat iterations, 129 fully acknowledged attempts deliberately sharing the old hash shard, global UUID conflicts across actions and changed attempts, missing indexed objects, bounded legacy migration and restart, pending-hot publication recovery, all 21 first-publication interruption boundaries, v1 observational preservation, callback closure and retained protocol/callback identities. All 23 native files compile against pinned Android 36 APIs with the verified native ARM JDK 21. Exact counts and command results are in validation.json. This packet records staged acceptance; canonical promotion has not occurred.

Attempts 1 through 6 are preserved in the private proof workspace. Attempt 6 has incomplete stdout and no original terminal receipt; it is not an accepted pass and supplies no invented exit status. Attempt 7 completed all 37 attempt cases with one strict-validator refusal of a synthetic v1-shaped reply in the new v2 fixture. Attempt 8 corrects only that fixture, proves the other 36 methods and all other source/runtime inputs unchanged, executes the corrected named case and completes the pending Android API compile. No whole-current-suite pass is claimed. The timeout-aware runner records each actual child result and reaps owned children before publishing a failure receipt.

Remaining work: continuous late-conflict paging (the existing finite conflict journal is unchanged), portable export plus non-exportable Keystore recovery/re-enrollment, a backend-approved v1 terminal closure or governed migration route, physical-device filesystem/Keystore/quota checks, Gradle packaging, exact signed artifact and device/carrier acceptance. Offline filesystem, HTTP and Android API seams do not prove those gates.
""")
manifest={str(p.relative_to(leaf)):{'bytes':p.stat().st_size,'sha256':sha(p)} for p in sorted(leaf.rglob('*')) if p.is_file()}
(leaf/'MANIFEST.json').write_text(json.dumps({'scope':'immutable staged source-bound acceptance packet; no canonical promotion','files':manifest},indent=2)+'\n')
for rel,entry in manifest.items():
 if sha(leaf/rel)!=entry['sha256']:raise SystemExit('Packet readback failed')
print(json.dumps({'status':'pass','packet':str(leaf),'manifest_sha256':sha(leaf/'MANIFEST.json'),'proof_tests':validation['junit_tests_passed'],'source_inputs':len(validation['source_sha256']),'promotion_files':len(promotion),'compiled_artifacts':len(outputs)},indent=2))
