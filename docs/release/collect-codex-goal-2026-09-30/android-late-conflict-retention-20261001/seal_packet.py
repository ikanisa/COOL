from pathlib import Path
import json, hashlib, shutil
repo=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL');stage=repo/'.cache/android-late-conflict-retention-20261001';private=Path('/Users/jeanbosco/.cache/collect-android-late-conflict-retention-20261001')
run=Path(json.loads((stage/'latest-proof.json').read_text())['path']);result=json.loads((run/'validation.json').read_text());sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
if result['status']!='pass' or result['junit_tests_passed']!=109 or any(result['source_changes'].values()):raise RuntimeError('Incomplete acceptance')
for row in result['commands']:
 if row['status']!='terminal' or row['exit_code']!=0 or not row['owned_child_reaped']:raise RuntimeError('Missing command terminal')
for path,digest in result['source_sha256'].items():
 if sha(run/'source'/path)!=digest or sha(stage/'source'/path)!=digest:raise RuntimeError('Source drift '+path)
before=json.loads((stage/'canonical-before.json').read_text())
for path,digest in before.items():
 if sha(repo/path)!=digest:raise RuntimeError('Canonical drift '+path)
packet=stage/'accepted-packet'
if packet.exists():raise RuntimeError('Preserve existing packet')
packet.mkdir()
def write(path,value):path.write_text(json.dumps(value,indent=2)+'\n')
shutil.copytree(run/'source',packet/'source');shutil.copytree(run/'shims',packet/'shims')
for name in ['validation.json','commands.json','reused-product-association.json','CurrentCases.kt','BuildConfig.kt','jdk-runtime-closure.json']:
 shutil.copyfile(run/name,packet/name)
for path in sorted(run.glob('*.stdout'))+sorted(run.glob('*.stderr')):shutil.copyfile(path,packet/path.name)
for name in ['proof.py','resume_proof.py','canonical-before.json','source-base-proof.json','seal_packet.py','fresh-behind-digest-fixture.diff','predecessor-readback.json']:shutil.copyfile(stage/name,packet/name)
old=private/'attempt-1';(packet/'interrupted-attempt-1').mkdir()
for name in ['commands.json','interrupted-observation.json','product.stdout','product.stderr','test-compile.stdout','test-compile.stderr','runner-compile.stdout','runner-compile.stderr','tests-GatewayLateRetentionTest.stdout','tests-GatewayLateRetentionTest.stderr']:
 shutil.copyfile(old/name,packet/'interrupted-attempt-1'/name)
fixture='android/app/src/testInternal_gateway_archiveJvm/kotlin/app/cool/mobile/gateway/GatewayLateBackendTest.kt'
shutil.copyfile(old/'source'/fixture,packet/'interrupted-attempt-1'/'GatewayLateBackendTest.before-fixture.kt')
write(packet/'attempt-2-setup-failure.json',json.loads((private/'attempt-2'/'validation.json').read_text()))
artifacts={}
for group in ['classes','test-classes','runner-classes','api-classes']:
 for path in sorted((run/group).rglob('*')):
  if path.is_file():artifacts[str(path.relative_to(run))]={'path':str(path),'sha256':sha(path),'bytes':path.stat().st_size}
write(packet/'compiled-artifacts.json',artifacts)
base=json.loads(Path('/Users/jeanbosco/.cache/collect-android-native-proof-20261001/staging.json').read_text())
write(packet/'dependency-runtime-binding.json',{'staged_binaries':base['staged_binaries'],'binary_sha256':base['binary_sha256'],'java':base['java'],'jdk_root':base['jdk_root'],'jdk_runtime_closure_sha256':result['jdk_runtime_closure_sha256'],'jdk_runtime_entries':result['jdk_runtime_entries']})
changes=[]
for path,digest in sorted(result['source_sha256'].items()):
 canonical=repo/path;oldhash=sha(canonical) if canonical.exists() else None
 if oldhash!=digest:changes.append({'path':path,'old_sha256':oldhash,'new_sha256':digest,'staged_source':str(packet/'source'/path)})
write(packet/'promotion-manifest.json',{'status':'staged_only_root_promotion_required','canonical_root':str(repo),'files':changes,'canonical_before_sha256':sha(stage/'canonical-before.json'),'validation_sha256':sha(packet/'validation.json')})
shutil.copyfile(stage/'ACCEPTANCE.md',packet/'ACCEPTANCE.md')
manifest={str(p.relative_to(packet)):{'sha256':sha(p),'bytes':p.stat().st_size} for p in sorted(packet.rglob('*')) if p.is_file()}
write(packet/'MANIFEST.json',manifest)
errors=[name for name,item in manifest.items() if sha(packet/name)!=item['sha256']]
if errors:raise RuntimeError('Packet readback failures '+str(errors))
print(json.dumps({'packet':str(packet),'manifest_sha256':sha(packet/'MANIFEST.json'),'members':len(manifest),'validation_sha256':sha(packet/'validation.json'),'promotion_manifest_sha256':sha(packet/'promotion-manifest.json'),'promotion_files':len(changes),'artifact_files':len(artifacts),'tests':result['junit_tests_passed']}))
