#!/usr/bin/env python3
"""Exact owner-authorized physical expansion. No Flutter/Git/bootstrap is run."""
import datetime
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ADMISSION = HERE.parent / 'kotlin-sdk-expansion-admission-batch1'
REVIEW = HERE.parent / 'root-sdk-foundation-review-batch1/exact-expansion-admission-review.json'
CODE_SHA = '938591c4396092ac7cffe0081d656dd7be92d3a100232ee4867f5f5cdda3b0c5'
ADMISSION_SHA = '9d22ab7c56ffdeb8d0b3b9c64022bd481403f86ff449ff4c257e8124ffcc3749'
MANIFEST_SHA = '5129232e7b15d12f0483d5a6832e512002b91bf905d191413b228c94b15ad8ed'
FREEZE_SHA = 'c76eabe879a58408a87a70828933e849fd73820fcf8ebcd6ffac05f2b100baba'
REVIEW_SHA = 'fb47cf9ba888163d2b764bbc4509962ae87b8ac9bffe24d7584e2e6a36acacec'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(name, value):
    path = HERE / name
    if path.exists(): raise ValueError('evidence destination exists; no silent repeat/reuse')
    with path.open('x') as output:
        json.dump(value, output, indent=2, sort_keys=True); output.write('\n')
        output.flush(); os.fsync(output.fileno())


def checked_module():
    if (sha(ADMISSION / 'authenticated_sdk_expansion.py') != CODE_SHA
            or sha(ADMISSION / 'exact-archive-admission.json') != ADMISSION_SHA
            or sha(ADMISSION / 'packet-files.json') != MANIFEST_SHA
            or sha(ADMISSION / 'source-freeze.json') != FREEZE_SHA
            or sha(REVIEW) != REVIEW_SHA):
        raise ValueError('reviewed writer/admission/authorization identity drift')
    for name, digest in json.loads((ADMISSION / 'packet-files.json').read_text())['files'].items():
        if sha(ADMISSION / name) != digest: raise ValueError('sealed admission leaf drift')
    spec = importlib.util.spec_from_file_location('exact_authorized_sdk_writer', ADMISSION / 'authenticated_sdk_expansion.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


if __name__ == '__main__':
    if sys.argv[1:] == ['--child']:
        module = checked_module()
        result = module.expand_after_separate_authorization(
            ADMISSION / 'exact-archive-admission.json', ADMISSION_SHA,
            lambda value: print(json.dumps(value), flush=True))
        save('physical-expansion-result.json', result)
        print(json.dumps({'status':'PHYSICAL_FOUNDATION_VERIFIED__NO_SDK_EXECUTION',
                          'elapsed_seconds':result['elapsed_seconds'],
                          'members':result['full_independent_readback']['member_count'],
                          'source_leaves':result['full_independent_readback']['source_entries_readback'],
                          'shared_installed_inodes':result['full_independent_readback']['shared_installed_SDK_inodes']}), flush=True)
    elif not sys.argv[1:]:
        checked_module()
        started = datetime.datetime.now(datetime.timezone.utc).isoformat(); tick = time.monotonic()
        save('authorized-run-start.json', {'recorded_utc':started,'writer_code_sha256':CODE_SHA,
            'exact_admission_sha256':ADMISSION_SHA,'root_authorization_sha256':REVIEW_SHA,
            'caller_sha256':sha(__file__),'actual_process_timeout_seconds':600,
            'scope':'Fresh independent expansion/full physical verification only. No SDK/bootstrap/patch/selection.'})
        terminal = {'recorded_utc':started,'actual_process_timeout_seconds':600,'timed_out':False}
        with (HERE / 'physical-expansion.stdout').open('x') as stdout, (HERE / 'physical-expansion.stderr').open('x') as stderr:
            try:
                complete = subprocess.run([sys.executable,'-I','-B',str(Path(__file__).resolve()),'--child'],
                    stdout=stdout,stderr=stderr,timeout=600,check=False)
                terminal['exit_code'] = complete.returncode
            except subprocess.TimeoutExpired:
                terminal.update({'timed_out':True,'exit_code':None,'status':'ACTUAL_600_SECOND_PROCESS_DEADLINE_FAILURE__NO_ACCEPTANCE'})
        terminal['actual_elapsed_seconds'] = round(time.monotonic()-tick,3)
        terminal['physical_result_present'] = (HERE / 'physical-expansion-result.json').exists()
        terminal['terminal_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        if terminal.get('exit_code') == 0 and terminal['physical_result_present']:
            terminal['status']='PHYSICAL_FOUNDATION_VERIFIED__NO_SDK_EXECUTION'
        elif not terminal['timed_out']:
            terminal['status']='ACTUAL_PHYSICAL_EXPANSION_FAILURE__PARTIAL_OUTPUT_PRESERVED__NO_ACCEPTANCE'
        terminal.update({'SDK_executed':False,'source_patch_applied':False,'candidate_promoted':False,'production_release_approval':False})
        save('physical-expansion-terminal.json',terminal)
        print(json.dumps(terminal),flush=True)
        sys.exit(0 if terminal.get('exit_code') == 0 else 1)
    else:
        raise ValueError('unexpected caller arguments')
