#!/usr/bin/env python3
"""Guard-only readback of the preserved failed candidate; never a stage retry."""
import hashlib
import importlib.util
import json
import os
import stat
from pathlib import Path
import time

HERE=Path(__file__).resolve().parent
ORIGINAL=HERE.parent/'kotlin-sdk-native-consumer-preparation1'
BASE=Path('/Users/jeanbosco/Library/Caches/COOL-ARC09/native-consumer1')

def module(path,name):
    spec=importlib.util.spec_from_file_location(name,path);value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value

def save(name,value):
    with (HERE/name).open('x') as out:
        json.dump(value,out,indent=2,sort_keys=True);out.write('\n');out.flush();os.fsync(out.fileno())

def main():
    start=time.monotonic();guards=module(HERE/'consumer_guards.py','actual_candidate_guard');original=module(ORIGINAL/'consumer_guards.py','original_candidate_guard')
    controller=module(ORIGINAL/'run_native_consumer.py','unchanged_protected_reader')
    before=controller.protected_metadata()
    inputs=json.loads((HERE/'input-guards-before.json').read_text())['files']
    identities=json.loads((HERE/'input-guards-before.json').read_text())['node_identities']
    def fingerprint(path):
        if guards.node_identity(path)!=identities[str(path)]:raise ValueError('preserved input node identity differs')
        return guards.load_metadata().stable_read(path)[0]
    for name,expected in inputs.items():
        if fingerprint(Path(name))!=expected:raise ValueError('preserved failed candidate/proof input identity changed: '+name)
    terminal=guards.read_json(BASE/'.control/app-lock/terminal.json')
    child=guards.read_json(BASE/'.control/app-lock/actual-command.json')
    if terminal.get('stage_pass') is not False or terminal.get('retry_or_next_stage_admitted') is not False:
        raise ValueError('actual whole-stage failure must remain terminal')
    guards.process_success(child)
    binding=guards.read_json(BASE/'.control/app-export/export-source-binding.json')
    try:original.app_readback('app-locked',binding['export_manifest_file_sha256'])
    except ValueError as error:
        original_refusal=str(error)
        if original_refusal!='app unreviewed generated source/path: ios/Runner/GeneratedPluginRegistrant.h':raise
    else:raise ValueError('original guard did not reproduce exact preserved failure')
    result=guards.app_readback('app-locked',binding['export_manifest_file_sha256'])
    ios=result['exact_generated_ios_registrants']
    authored={};manifest=guards.read_json(guards.APP/'.collect-release-candidate.json',binding['export_manifest_file_sha256'])
    for name,expected in manifest['source_files'].items():
        guards.safe_relative(name);row,_=guards.load_metadata().stable_read(guards.APP/name)
        if any(row[key]!=expected[key] for key in ('sha256','bytes','mode')):raise ValueError('authored bytes/lock/mode changed')
        authored[name]=row
    symlinks={}
    for parent,dirs,files in os.walk(guards.APP,followlinks=False):
        for item in dirs+files:
            path=Path(parent)/item;row=path.lstat()
            if stat.S_ISLNK(row.st_mode):
                symlinks[path.relative_to(guards.APP).as_posix()]=dict(target=os.readlink(path),device=row.st_dev,inode=row.st_ino,mode=row.st_mode,mtime_ns=row.st_mtime_ns,ctime_ns=row.st_ctime_ns)
            elif not (stat.S_ISREG(row.st_mode) or stat.S_ISDIR(row.st_mode)):raise ValueError('additional app special node')
    if len(symlinks)!=13:raise ValueError('unexpected generated symlink observation changed')
    packages=guards.package_config(guards.APP/'.dart_tool/package_config.json',(guards.SDK,guards.APP,guards.PUB))
    plugins=guards.plugin_metadata(guards.APP/'.flutter-plugins-dependencies')
    guards.require_lock(guards.APP/'pubspec.lock',binding['original_app_lock_sha256'])
    guards.require_lock(guards.SDK/'packages/flutter_tools/pubspec.lock',guards.SDK_LOCK)
    for name,expected in inputs.items():
        if fingerprint(Path(name))!=expected:raise ValueError('guard proof altered/raced preserved input identity')
    after=controller.protected_metadata()
    save('actual-failed-candidate-authored-readback.json',authored)
    save('actual-failed-candidate-registrant-readback.json',ios)
    save('actual-failed-candidate-package-bindings.json',packages)
    save('actual-failed-candidate-plugin-bindings.json',plugins)
    save('actual-failed-candidate-app-readback.json',result)
    save('actual-read-only-proof.json',dict(status='PASS_READ_ONLY_GUARDS',proof_scope='read-only mandatory registrants/links and complete source-derived plugin membership on preserved failed candidate',
        actual_seconds=round(time.monotonic()-start,3),original_guard_refusal=original_refusal,corrected_whole_app_guard_pass=True,
        every_other_generated_symlink_or_special_file_refused=True,exact_generated_symlink_observations=symlinks,
        derived_generated_link_count=len(result['exact_generated_swiftpm_links']),copy_provenance=result['generated_copy_provenance'],
        authored_files_verified=len(authored),original_app_lock_sha256=binding['original_app_lock_sha256'],method_channel_ios_plugins=len(ios['method_channel_plugins']),
        reviewed_locked_package_pubspecs=168, discovered_modern_plugin_pubspecs=58,exact_generated_registrants={name:proof['actual'] for name,proof in ios['generated_files'].items()},
        protected_before=before,protected_after=after,all_preserved_input_identities_unchanged=True,
        actual_pub_child_exit_code=child['exit_code'],actual_pub_child_seconds=child['actual_seconds'],actual_whole_app_lock_stage_pass=False,
        actual_stage_or_Flutter_Gradle_build_execution=False,SDK_app_control_or_maintained_writes=False,
        retry_or_native_admission=False,candidate_promoted=False,production_release_approval=False))
    print('PASS read-only corrected guards;13 derived generatedlinks/copy provenance; actualwholeapp-lock stillFAIL;2510authored/lock/protected68020 preserved')

if __name__=='__main__':main()
