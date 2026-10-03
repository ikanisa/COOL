from pathlib import Path
import json,hashlib,types,subprocess,datetime,os
B=Path(__file__).resolve().parent.parent;OUT=Path(__file__).resolve().parent
DRIVER=B/'arc09-aab-driver-preparation1/argv-unavailable-recovery3/run_selected_aab.py'
h=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert h(DRIVER)=='76f587c54d8cfcb91d0ce584f4ee69ac99905b1ad313402ac2c82ce2fa6ed4f8'
m=types.ModuleType('exact_desugar_resolver');m.__file__=str(DRIVER);exec(compile(DRIVER.read_bytes(),str(DRIVER),'exec'),m.__dict__)
a=B/'root-arc09-aab-admission4/admission.json';ctx=m.context(types.SimpleNamespace(admission=a,admission_sha256='9b557322112f9cd4ae350a253c413c3362c969d00ba86499c041c622981d400d'))
label='exact-publisher-cache-registration';project=OUT/'minimal-project';files={str(p):h(p) for p in project.iterdir()}
argv=['/bin/bash',str(m.APP/'android/gradlew'),'-p',str(project),'--no-daemon','--no-build-cache','--no-configuration-cache','--console=plain','--max-workers=1','resolveExactPublisherJar']
ctx.matrix={'commands':[{'label':label,'argv':argv}]}
tracker=m.DaemonTracker(ctx,OUT,label);original=ctx.controller.subprocess
for row in m.process_table().values():
 if tracker.private_identity(row) is not None:raise ValueError('Existing private Gradle daemon; no stop attempted')
def popen(*args,**kwargs):
 child=subprocess.Popen(*args,**kwargs)
 try:tracker.register(child)
 except BaseException:
  ctx.controller.stop_group(child);raise
 return child
ctx.controller.subprocess=types.SimpleNamespace(Popen=popen,TimeoutExpired=subprocess.TimeoutExpired)
command=None;daemon=None
try:command=ctx.controller.run_process(OUT,label,argv,180,project,ctx.config['environment_exact'])
finally:
 ctx.controller.subprocess=original;daemon=tracker.finish()
assert {str(p):h(p) for p in project.iterdir() if p.is_file()}==files
ctx.guards.process_success(command)
assert daemon['owned_daemons_absent'] and daemon['observer_error'] is None
admitted=json.loads((B/'root-desugar-configuration-private-cache-admission1/readback.json').read_text());assert h(Path(admitted['destination']))==admitted['sha256']
r={'utc':datetime.datetime.now(datetime.UTC).isoformat(),'status':'exact_dependency_repository_metadata_registered','command_exit_code':command['exit_code'],'command_seconds':command['actual_seconds'],'command_sha256':h(OUT/(label+'.json')),'daemon_readback_sha256':h(OUT/(label+'.daemon-readback.json')),'owned_daemons_absent':True,'private_cache_jar_sha256':admitted['sha256'],'private_cache_jar_bytes':admitted['bytes'],'dependency_scope':'com.android.tools:desugar_jdk_libs_configuration:2.1.4 only, transitive=false','repository_scope':'official Google Maven, exact module content filter','app_source_or_version_changes':False,'SDK_source_changes':False,'project_source_unchanged':True,'AAB_built':False,'production_release_approval':False}
m.save(OUT/'readback.json',r);print(json.dumps(r,indent=2))
