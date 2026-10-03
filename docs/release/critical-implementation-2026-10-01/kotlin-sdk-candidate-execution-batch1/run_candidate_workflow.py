#!/usr/bin/env python3
"""Owner-authorized candidate-only workflow; no shared SDK/pin/lock/bootstrap."""
import datetime
import hashlib
import importlib.util
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

HERE=Path(__file__).resolve().parent
PREP=HERE.parent/'kotlin-sdk-candidate-preparation-batch1'
PHYSICAL=HERE.parent/'kotlin-sdk-physical-foundation-batch1'
PLAN=HERE.parent/'kotlin-sdk-candidate-plan1'
CANDIDATE=Path('/Volumes/PRO-G40/Development/Codex-Candidates/COOL-ARC09/flutter-3.44.4-collect-kotlin-2.4.20-candidate1')
GRADLE_HOME=Path('/Volumes/PRO-G40/Development/Codex-Candidates/COOL-ARC09/private-gradle/sdk-kotlin-2.4.20-candidate1')
PREP_MANIFEST_SHA='1a788b56e4c61299f1981bdc83dff5201f8d742880c987f0f8c49dd22c06f551'
PREP_FREEZE_SHA='b03196be782aa6991955af13547ca3304fbe3143f75744c11a2d19b89e2af2c7'
COMMAND_SHA='a1caea5efe1886f2740e76c61b85e8dbec6a895ee60243aeddbaee7ba011176d'
AUTH=HERE.parent/'root-sdk-foundation-review-batch1/candidate-preparation-readback.json'
AUTH_SHA='d7e90aa36f58ec39cdc062b6dcbf16fe7d141e679525a5333aa172a296510e04'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(name,value):
    with (HERE/name).open('x') as output:
        json.dump(value,output,indent=2,sort_keys=True);output.write('\n');output.flush();os.fsync(output.fileno())


def checked_prep():
    if sha(PREP/'packet-files.json')!=PREP_MANIFEST_SHA or sha(PREP/'source-freeze.json')!=PREP_FREEZE_SHA or sha(AUTH)!=AUTH_SHA:
        raise ValueError('reviewed preparation/authorization drift')
    for name,digest in json.loads((PREP/'packet-files.json').read_text())['files'].items():
        if sha(PREP/name)!=digest:raise ValueError('sealed preparation leaf drift')
    if sha(PREP/'candidate-next-command.json')!=COMMAND_SHA:raise ValueError('exact frozen command drift')


def load_module(path,name):
    spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module


def patch_exact3():
    # Uses the already sealed, independently reviewed RAM reconstruction; no
    # patch context fuzz, automatic learning or fourth source file is permitted.
    for name,digest in json.loads((PHYSICAL/'packet-files.json').read_text())['files'].items():
        if sha(PHYSICAL/name)!=digest:raise ValueError('sealed pristine physical packet drift')
    preview=json.loads((PHYSICAL/'three-file-physical-preview-binding.json').read_text())
    body=(PLAN/'proposed-collect-only-sdk.patch').read_bytes()
    if hashlib.sha256(body).hexdigest()!=preview['reviewed_patch_sha256']:raise ValueError('exact reviewed patch drift')
    parser=load_module(PHYSICAL/'bind_three_file_preview.py','sealed_ram_patch_reconstruction')
    parsed={};current=None;hunk=None;lines=body.decode().splitlines(keepends=True);index=0
    while index<len(lines):
        line=lines[index]
        if line.startswith('--- a/'):
            current=line[len('--- a/'):].rstrip('\n');index+=1
            if lines[index]!='+++ b/'+current+'\n' or current in parsed:raise ValueError('exact patch path pair drift')
            parsed[current]=[];hunk=None
        elif line.startswith('@@ '):hunk=[line,[]];parsed[current].append(hunk)
        else:
            if hunk is None:raise ValueError('unexpected reviewed patch data')
            hunk[1].append(line)
        index+=1
    if set(parsed)!=set(preview['files']) or len(parsed)!=3:raise ValueError('not exact reviewed3 source paths')
    prepared={}
    for name,hunks in parsed.items():
        path=CANDIDATE/name;original=path.read_bytes();after=parser.reconstruct(original,hunks);row=preview['files'][name]
        if hashlib.sha256(original).hexdigest()!=row['actual_physical_original_sha256'] or hashlib.sha256(after).hexdigest()!=row['RAM_reconstructed_reviewed_after_sha256']:
            raise ValueError('exact reviewed before/after patch byte drift')
        if path.is_symlink() or path.stat().st_nlink!=1:raise ValueError('patch target not independent regular file')
        prepared[name]=(path,after,path.stat().st_mode&0o777)
    for name,(path,after,mode) in prepared.items():
        temporary=path.with_name(path.name+'.collect-exact-reviewed-patch.tmp')
        fd=os.open(temporary,os.O_WRONLY|os.O_CREAT|os.O_EXCL|getattr(os,'O_NOFOLLOW',0),0o600)
        with os.fdopen(fd,'wb') as output:
            output.write(after);output.flush();os.fchmod(output.fileno(),mode);os.fsync(output.fileno())
        os.replace(temporary,path)
        directory=os.open(path.parent,os.O_RDONLY|getattr(os,'O_DIRECTORY',0)|getattr(os,'O_NOFOLLOW',0))
        try:os.fsync(directory)
        finally:os.close(directory)
    save('exact3-patch-result.json',{'passed':True,'reviewed_patch_sha256':preview['reviewed_patch_sha256'],'files':{n:{'after_sha256':sha(path),'after_bytes':len(after),'mode':mode} for n,(path,after,mode) in prepared.items()},'pristine_or_shared_SDK_modified':False,'source_files_changed':3})


def run_stage(name,argv,timeout,cwd=None,env=None):
    tick=time.monotonic();started=datetime.datetime.now(datetime.timezone.utc).isoformat()
    print(json.dumps({'stage':name,'status':'started','actual_deadline_seconds':timeout}),flush=True)
    result={'argv':argv,'started_utc':started,'actual_deadline_seconds':timeout,'timed_out':False,'headroom_failure':False}
    with (HERE/(name+'.stdout')).open('xb') as stdout,(HERE/(name+'.stderr')).open('xb') as stderr:
        process=subprocess.Popen(argv,cwd=cwd,env=env,stdout=stdout,stderr=stderr,start_new_session=True)
        result['pid']=process.pid;deadline=tick+timeout
        while process.poll() is None:
            if time.monotonic()>=deadline or shutil.disk_usage(CANDIDATE.parent).free<2*1024**3:
                result['timed_out']=time.monotonic()>=deadline;result['headroom_failure']=not result['timed_out']
                try:os.killpg(process.pid,signal.SIGTERM)
                except ProcessLookupError:pass
                try:process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    try:os.killpg(process.pid,signal.SIGKILL)
                    except ProcessLookupError:pass
                    process.wait(timeout=10)
                break
            time.sleep(min(1,max(0.01,deadline-time.monotonic())))
        result['exit_code']=process.wait()
    result.update({'terminal_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'actual_seconds':round(time.monotonic()-tick,3),'stdout_sha256':sha(HERE/(name+'.stdout')),'stderr_sha256':sha(HERE/(name+'.stderr')),'runner_sha256':sha(__file__)})
    save(name+'.json',result)
    print(json.dumps({'stage':name,'exit_code':result['exit_code'],'timed_out':result['timed_out'],'headroom_failure':result['headroom_failure'],'actual_seconds':result['actual_seconds']}),flush=True)
    if result['exit_code']!=0 or result['timed_out'] or result['headroom_failure']:
        raise RuntimeError('actual stage failure retained: '+name)


if __name__=='__main__':
    checked_prep()
    if sys.argv[1:]==['--expand-child']:
        writer=load_module(PREP/'authenticated_candidate_expansion.py','exact_candidate_expansion')
        result=writer.expand_after_separate_authorization(HERE.parent/'kotlin-sdk-expansion-admission-batch1/exact-archive-admission.json','9d22ab7c56ffdeb8d0b3b9c64022bd481403f86ff449ff4c257e8124ffcc3749',lambda v:print(json.dumps(v),flush=True))
        save('candidate-physical-expansion-result.json',result)
        print(json.dumps({'physical_verified':True,'paths':result['full_independent_readback']['member_count'],'seconds':result['elapsed_seconds']}),flush=True)
    elif not sys.argv[1:]:
        if CANDIDATE.exists() or GRADLE_HOME.exists() or CANDIDATE.is_symlink() or GRADLE_HOME.is_symlink():raise ValueError('new destinations are not absent; no reuse')
        free=shutil.disk_usage(CANDIDATE.parent).free
        if free<4244148641+2*1024**3:raise ValueError('actual expansion headroom prerequisite unavailable')
        save('workflow-start.json',{'recorded_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'authorization_sha256':AUTH_SHA,'prep_manifest_sha256':PREP_MANIFEST_SHA,'command_sha256':COMMAND_SHA,'actual_free_bytes':free,'candidate':str(CANDIDATE),'owned_gradle_home':str(GRADLE_HOME),'runner_sha256':sha(__file__),'no_pristine_shared_SDK_or_repo_pin_lock_write':True})
        try:
            run_stage('candidate-expansion-attempt1',[sys.executable,'-I','-B',str(Path(__file__).resolve()),'--expand-child'],600)
            run_stage('pristine-source-attempt1',[sys.executable,'-I','-B',str(PREP/'verify_candidate_source.py'),'pristine','--output',str(HERE/'candidate-pristine-source-readback.json')],300)
            patch_exact3()
            run_stage('patched-source-attempt1',[sys.executable,'-I','-B',str(PREP/'verify_candidate_source.py'),'patched','--output',str(HERE/'candidate-patched-source-readback.json')],300)
            command=json.loads((PREP/'candidate-next-command.json').read_text())
            original=json.loads((PHYSICAL/'independent-three-file-validation-plan.json').read_text())
            if sha(original['java_executable'])!=original['java_executable_sha256']:raise ValueError('reviewed JDK executable identity drift')
            wrapper=Path(command['argv'][1])
            if sha(wrapper)!=original['gradle_wrapper_script_sha256'] or sha(wrapper.parent/'gradle/wrapper/gradle-wrapper.jar')!=original['gradle_wrapper_jar_sha256'] or sha(wrapper.parent/'gradle/wrapper/gradle-wrapper.properties')!=original['gradle_wrapper_properties_sha256']:raise ValueError('reviewed Gradle wrapper identity drift')
            if GRADLE_HOME.parent.resolve()!=GRADLE_HOME.parent or any(parent.is_symlink() for parent in GRADLE_HOME.parents):raise ValueError('owned Gradlehome link ancestor')
            GRADLE_HOME.mkdir(parents=True,mode=0o700)
            environment={key:os.environ[key] for key in ('PATH','HOME','TMPDIR','LANG','LC_ALL') if key in os.environ};environment.update(command['environment'])
            run_stage('sdk-compiler-runtime-attempt1',command['argv'],2700,cwd=command['cwd'],env=environment)
            run_stage('built-source-attempt1',[sys.executable,'-I','-B',str(PREP/'verify_candidate_source.py'),'built','--output',str(HERE/'candidate-built-source-readback.json')],300)
            save('workflow-terminal.json',{'status':'ALL_ACTUAL_STAGES_TERMINAL_PASS__JUNIT_AND_PUBLISHER_REVIEW_PENDING','source_patch_applied':True,'SDK_Gradle_compiler_runtime_executed':True,'Flutter_script_bootstrap_Dart_app_build_executed':False,'candidate_promoted':False,'production_release_approval':False})
        except Exception as error:
            save('workflow-terminal.json',{'status':'ACTUAL_WORKFLOW_FAILURE_RETAINED__NO_ACCEPTANCE','exception_type':type(error).__name__,'public_error':str(error),'partial_candidate_and_owned_cache_preserved':True,'candidate_promoted':False,'production_release_approval':False})
            raise
    else:raise ValueError('unexpected workflow arguments')
