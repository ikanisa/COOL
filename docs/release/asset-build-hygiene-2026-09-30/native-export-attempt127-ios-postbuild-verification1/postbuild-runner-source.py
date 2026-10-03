from pathlib import Path
import hashlib,json,shutil,subprocess
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
ORIGINAL=ROOT/'docs/release/asset-build-hygiene-2026-09-30/native-export-attempt127-ios-continuation4'
P=ROOT/'docs/release/asset-build-hygiene-2026-09-30/native-export-attempt127-ios-postbuild-verification1'
PROOF=ROOT/'docs/release/asset-build-hygiene-2026-09-30/swift-cached-artifact-inputs-root177-workspace-order/validation.json'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
proof=json.loads(PROOF.read_text());assert proof['status']=='pass' and proof['passed_tests']==35
for n,h in proof['source_sha256'].items():assert sha(ROOT/n)==h,n
execution=json.loads((ORIGINAL/'execution.json').read_text());assert [v['name'] for v in execution['commands']]==['swift-pinned-inputs-prebuild','unsigned-ios-build','swift-pinned-inputs-afterbuild']
for row in execution['commands']:
 assert row['exit_code']==0
 for stream in ('stdout','stderr'):assert sha(ORIGINAL/(row['name']+'.'+stream))==row[stream+'_sha256']
assert '** BUILD SUCCEEDED **' in (ORIGINAL/'unsigned-ios-build.stdout').read_text()
assert json.loads((ORIGINAL/'wrapper-failure-root.json').read_text())['actual_unsigned_ios_build_exit_code']==0
P.mkdir(exist_ok=False)
(P/'postbuild-runner-source.py').write_bytes(Path(__file__).read_bytes())
for name in ['source-export.json','resolved-native-package-inputs.json','resolved-package-inputs-before.json','resolved_native_package_inputs.py','generated-compiler-inputs-before.json','swift_generated_plugin_inputs.py','cached-binary-inputs-before.json']:
 origin=ORIGINAL/name
 if origin.exists():shutil.copy2(origin,P/name)
# Keep the exact rejected verifier and the exact corrected verifier independently.
shutil.copy2(ORIGINAL/'swift_cached_artifact_inputs.py',P/'prior_rejected_swift_cached_artifact_inputs.py')
shutil.copy2(ROOT/'scripts/qa/swift_cached_artifact_inputs.py',P/'swift_cached_artifact_inputs.py')
for row in execution['commands']:
 for stream in ('stdout','stderr'):shutil.copy2(ORIGINAL/(row['name']+'.'+stream),P/(row['name']+'.'+stream))
(P/'execution.json').write_text(json.dumps({**execution,'status':'pass','kind':'observed_completed_compilation_commands','parent_execution_sha256':sha(ORIGINAL/'execution.json'),'scope':'Observed original compilation and pinned source observations all exited zero; postbuild artifact and input verification follows independently.'},indent=2)+'\n')
(P/'postbuild-control-binding.json').write_text(json.dumps({'original_packet':str(ORIGINAL),'original_wrapper_failure_sha256':sha(ORIGINAL/'wrapper-failure-root.json'),'actual_compilation_log_sha256':sha(ORIGINAL/'unsigned-ios-build.stdout'),'before_binding_sha256':sha(ORIGINAL/'cached-binary-inputs-before.json'),'original_verifier_sha256':sha(ORIGINAL/'swift_cached_artifact_inputs.py'),'corrected_verifier_sha256':sha(P/'swift_cached_artifact_inputs.py'),'accepted_pure35_controls_sha256':sha(PROOF),'compiler_or_artifact_inputs_mutated':False,'compilation_reexecuted':False,'permitted_verifier_change':'Compare the same complete unique dependency/artifact rows independent of resolver serialization order; full metadata and binary-tree checks remain.'},indent=2)+'\n')
source=(ROOT/'.cache/verify-native-ios-attempt127-continuation4.py').read_text()
source=source.replace('native-export-attempt127-ios-continuation4','native-export-attempt127-ios-postbuild-verification1')
source=source.replace("(P/'artifact-verification.json').write_text", "report.update({'postbuild_control_binding_sha256':sha(P/'postbuild-control-binding.json'),'actual_compilation_reused_without_input_changes':True,'original_failed_postbuild_verifier_retained':True,'corrected_verifier_source_sha256':sha(P/'swift_cached_artifact_inputs.py')})\n(P/'artifact-verification.json').write_text")
runner=P/'artifact-verifier-source.py';runner.write_text(source)
print('START actual-ios-artifact-and-input-verification',flush=True)
result=subprocess.run(['python3',str(runner)],cwd=ROOT,capture_output=True)
(P/'artifact-verifier.stdout').write_bytes(result.stdout);(P/'artifact-verifier.stderr').write_bytes(result.stderr)
(P/'validation.json').write_text(json.dumps({'status':'pass' if result.returncode==0 else 'fail','exit_code':result.returncode,'actual_build_exit_code':0,'control_binding_sha256':sha(P/'postbuild-control-binding.json'),'artifact_verification_sha256':sha(P/'artifact-verification.json') if (P/'artifact-verification.json').exists() else None,'stdout_sha256':sha(P/'artifact-verifier.stdout'),'stderr_sha256':sha(P/'artifact-verifier.stderr'),'scope':'Completed real unsigned iOS build with independently corrected pure-tested postbuild verifier; no signed release, device/provider, visual fidelity or whole repository completion claim.'},indent=2)+'\n')
print(result.stdout.decode(),flush=True)
if result.returncode:print(result.stderr.decode()[-5000:],flush=True)
raise SystemExit(result.returncode)
