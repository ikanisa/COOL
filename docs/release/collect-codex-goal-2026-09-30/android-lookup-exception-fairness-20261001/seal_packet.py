from pathlib import Path
import hashlib,json,shutil
repo=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL');stage=repo/'.cache/android-lookup-exception-fairness-20261001';private=Path('/Users/jeanbosco/.cache/collect-android-lookup-exception-fairness-20261001');run=private/'attempt-2';old=private/'attempt-1';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
result=json.loads((run/'validation.json').read_text());association=json.loads((stage/'final-source-association.json').read_text());base=json.loads((stage/'base-association.json').read_text());base_packet=Path(base['base_packet'])
assert result['status']=='pass' and result['junit_tests_passed']==33 and association['status']=='pass'
assert len({r['method'] for r in result['case_results']})==33 and all(r['status']=='pass' for r in result['case_results'])
assert all(r['status']=='terminal' and r['exit_code']==0 and r['owned_child_reaped'] for r in result['commands'])
assert not any(result['source_changes'].values())
for name,digest in association['final_source_sha256'].items():assert sha(stage/'source'/name)==digest
assert sha(base_packet/'MANIFEST.json')==base['manifest_sha256']
for name,item in json.loads((base_packet/'MANIFEST.json').read_text()).items():assert sha(base_packet/name)==item['sha256']
packet=stage/'accepted-packet';assert not packet.exists();packet.mkdir()
def write(path,value):path.write_text(json.dumps(value,indent=2)+'\n')
shutil.copytree(stage/'source',packet/'source');shutil.copytree(run/'shims',packet/'shims')
for name in ['validation.json','commands.json','reused-baseline-association.json','composed-source-association.json','CurrentCases.kt','BuildConfig.kt','jdk-runtime-closure.json']:shutil.copyfile(run/name,packet/name)
for p in list(run.glob('*.stdout'))+list(run.glob('*.stderr')):shutil.copyfile(p,packet/p.name)
for name in ['proof.py','resume_proof.py','seal_packet.py','base-association.json','final-source-association.json','corrupt-control-fixture.diff','ACCEPTANCE.md']:shutil.copyfile(stage/name,packet/name)
failed=packet/'failed-attempt-1';failed.mkdir()
for name in ['validation.json','commands.json','compiled-artifacts-closure.json','affected-product-compile.stdout','affected-product-compile.stderr','affected-test-compile.stdout','affected-test-compile.stderr','tests-GatewayLookupFairnessTest.stdout','tests-GatewayLookupFairnessTest.stderr']:shutil.copyfile(old/name,failed/name)
fixture='android/app/src/testInternal_gateway_archiveJvm/kotlin/app/cool/mobile/gateway/GatewayLookupFairnessTest.kt';shutil.copyfile(old/'source'/fixture,failed/'GatewayLookupFairnessTest.before-fixture.kt')
artifacts={str(p.relative_to(run)):{'path':str(p),'sha256':sha(p),'bytes':p.stat().st_size} for folder in ['classes','test-classes','runner-classes','api-classes'] for p in sorted((run/folder).rglob('*')) if p.is_file()}
write(packet/'compiled-artifacts.json',artifacts)
runtime=json.loads(Path('/Users/jeanbosco/.cache/collect-android-native-proof-20261001/staging.json').read_text());write(packet/'dependency-runtime-binding.json',{'staged_binaries':runtime['staged_binaries'],'java':runtime['java'],'jdk_root':runtime['jdk_root'],'jdk_runtime_closure_sha256':result['jdk_runtime_closure_sha256'],'jdk_runtime_entries':result['jdk_runtime_entries']})
changes=[]
for name,digest in sorted(association['final_source_sha256'].items()):
 prior=base['source_sha256'].get(name);canonical=repo/name
 if prior!=digest:
  assert (sha(canonical) if canonical.exists() else None)==prior
  changes.append({'path':name,'old_sha256':prior,'new_sha256':digest,'staged_source':str(packet/'source'/name)})
assert len(changes)==4
write(packet/'promotion-manifest.json',{'status':'staged_only_root_promotion_required','canonical_root':str(repo),'files':changes,'native_validation_sha256':sha(packet/'validation.json'),'final_source_association_sha256':sha(packet/'final-source-association.json'),'composed_case_count':33,'whole_current_new_suite_rerun':False})
manifest={str(p.relative_to(packet)):{'sha256':sha(p),'bytes':p.stat().st_size} for p in sorted(packet.rglob('*')) if p.is_file()};write(packet/'MANIFEST.json',manifest)
assert not [p for p,item in manifest.items() if sha(packet/p)!=item['sha256']]
print(json.dumps({'packet':str(packet),'manifest_sha256':sha(packet/'MANIFEST.json'),'members':len(manifest),'validation_sha256':sha(packet/'validation.json'),'promotion_sha256':sha(packet/'promotion-manifest.json'),'final_source_association_sha256':sha(packet/'final-source-association.json'),'artifacts':len(artifacts),'promotion_files':len(changes),'cases':33}))
