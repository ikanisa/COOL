"""Root readback of the completed first native failure; never executes a build."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import types

HERE = Path(__file__).resolve().parent
RELEASE = HERE.parent
ROOT = RELEASE.parents[2]
BASE = Path('/Users/jeanbosco/Library/Caches/COOL-ARC09/native-consumer1')
PREP = RELEASE / 'kotlin-sdk-native-native-stage-preparation1'


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def module(name, path, expected):
    raw = path.read_bytes()
    if sha(raw) != expected:
        raise ValueError('reviewed module bytes differ')
    result = types.ModuleType(name)
    result.__file__ = str(path)
    exec(compile(raw, str(path), 'exec'), result.__dict__)
    return result


reader = module('root_native_reader', PREP / 'publisher_metadata.py', 'c21a475eae55b78997dbd944e6c97de1bd8e1df92f4f8696ede8ece198140b25')
guards = module('root_native_guards', PREP / 'consumer_guards.py', 'f38cbad5ab95c7aa9adfa0b9ddae5cf5902666c89aa6548525edb75be3465e4a')
controller = module('root_native_controller', PREP / 'run_native_consumer.py', '167d48b4e756043a87621feffcabccb41aca108232cfb943914b69fc5b090fe7')


def read(path):
    return reader.stable_read(path, True)


def save(path, value):
    with path.open('x') as handle:
        json.dump(value, handle, sort_keys=True, indent=2)
        handle.write('\n')
        handle.flush()
        os.fsync(handle.fileno())


def check_packet(name, expected):
    directory = RELEASE / name
    row, raw = read(directory / 'packet-files.json')
    if row['sha256'] != expected:
        raise ValueError('prior packet changed')
    for leaf in json.loads(raw)['files']:
        p = Path(leaf['path'])
        if p.is_absolute() or '..' in p.parts:
            raise ValueError('unsafe prior packet path')
        observed, _ = read(directory / p)
        if (observed['sha256'], observed['bytes']) != (leaf['sha256'], leaf['bytes']):
            raise ValueError('prior packet leaf changed')
    return {'path': str((directory / 'packet-files.json').relative_to(ROOT)), 'sha256': expected}


def main():
    if (HERE / 'readback.json').exists():
        raise ValueError('one-shot readback already exists')
    priors = {
        'app-export': check_packet('kotlin-sdk-native-consumer-app-export4', 'aac0d7c95f1d23e9d2a3e69402df09134114437079fc7a917718cf1e86ec7e6f'),
        'app-lock': check_packet('kotlin-sdk-native-app-lock2', '00317892d64de0e0966963801ee553c25f5eb25d758c811c2929a76df7528b5b'),
    }
    stages = {}
    for stage in ('app-export', 'app-lock', 'native'):
        row, raw = read(BASE / '.control' / stage / 'terminal.json')
        value = json.loads(raw)
        if value['stage'] != stage or type(value['stage_pass']) is not bool:
            raise ValueError('stage identity/outcome absent')
        stages[stage] = dict(value, actual_terminal_sha256=row['sha256'])
    if (stages['app-export']['actual_terminal_sha256'] != '0972133ee11e44e831e1cbd229fae8680524b7fc056944b08c031c4f19f2a960'
            or stages['app-lock']['actual_terminal_sha256'] != '42519f99f1fc439f0a0c72039dc21977afeaaba920059b0259af62c0f45a8f6c'):
        raise ValueError('current predecessors differ from root-bound actual originals')
    if not stages['app-export']['stage_pass'] or not stages['app-lock']['stage_pass'] or stages['native']['stage_pass']:
        raise ValueError('this readback requires exact export/lock pass and genuine native failure')
    control = BASE / '.control/native'
    process = json.loads(read(control / 'actual-command.json')[1])
    if process['exit_code'] != 1 or process['timed_out'] or process['headroom_failure'] or not process['owned_process_group_absent']:
        raise ValueError('unexpected actual native terminal process')
    try:
        os.killpg(process['pid'], 0)
    except ProcessLookupError:
        pass
    else:
        raise ValueError('actual owned native group remains')
    stdout_row, stdout = read(control / 'actual-command.stdout')
    stderr_row, stderr = read(control / 'actual-command.stderr')
    if (stdout_row['sha256'], stderr_row['sha256']) != (process['stdout_sha256'], process['stderr_sha256']):
        raise ValueError('actual retained streams differ')
    if b"Execution failed for task ':app:processProductionDebugGoogleServices'." not in stderr or b'File google-services.json is missing.' not in stderr:
        raise ValueError('actual failure diagnosis differs')
    sdk = json.loads(read(control / 'actual-failure-SDK-source.json')[1])
    if sdk['status'] != 'EXACT_CANDIDATE_SOURCE_DELTA_AND_PHYSICAL_READBACK_PASS' or sdk['source_entries'] != 15660 or not sdk['zero_pristine_installed_failed_candidate_shared_inodes']:
        raise ValueError('actual failure SDK source diagnostic differs')
    app = guards.app_readback('built', json.loads(read(BASE / '.control/app-export/export-source-binding.json')[1])['export_manifest_file_sha256'])
    save(HERE / 'app-source-readback.json', app)
    current = json.loads((RELEASE / 'root-tooling-source-integration1/current-source-after-drop-correction.json').read_text())['after_sha256']
    for name, expected in current.items():
        if read(ROOT / name)[0]['sha256'] != expected:
            raise ValueError('maintained source changed before readback: ' + name)
    graph_text = stdout.decode('utf-8')
    graphs = [json.loads(body) for body in re.findall(r'COLLECT_NATIVE_PRODUCTION_GRAPH_BEGIN\n(.*?)\nCOLLECT_NATIVE_PRODUCTION_GRAPH_END', graph_text, re.S)]
    if {g['configuration'] for g in graphs} != {'productionReleaseCompileClasspath', 'productionReleaseRuntimeClasspath'} or len(graphs) != 2:
        raise ValueError('actual two Production graphs missing')
    originals = HERE / 'actual-control'
    originals.mkdir()
    for source in sorted(control.iterdir()):
        if not stat.S_ISREG(source.lstat().st_mode) or source.lstat().st_nlink != 1:
            raise ValueError('unsafe actual control leaf')
        row, body = read(source)
        (originals / source.name).write_bytes(body)
        if read(source)[0] != row:
            raise ValueError('actual control leaf raced')
    save(HERE / 'readback.json', {
        'status': 'failed', 'at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'kind': 'root_actual_first_native_failure_readback', 'stages': stages,
        'native_admitted': True, 'native_packages_built': False, 'production_release_approval': False,
        'source_lock_attested': False, 'current12_unchanged': True, 'prior_packets_verified': priors,
        'actual_native_process': process, 'actual_failure': 'processProductionDebugGoogleServices requires absent google-services.json in unsigned local QA',
        'actual_sdk_source_diagnostic_pass': True, 'actual_authored_app_source_readback_pass': True,
        'actual_production_graphs': [{'configuration': g['configuration'], 'modules': len(g['modules']), 'artifacts': len(g['artifacts'])} for g in graphs],
        'production_release_kotlin_task_observed': '> Task :app:compileProductionReleaseKotlin' in graph_text,
        'production_debug_JVM_not_reached': '> Task :app:testProductionDebugUnitTest' not in graph_text,
        'retry_authorized_by_this_readback': False, 'all_flavor_ABI_complete': False, 'ARC09_closed': False,
        'protected_original_metadata': controller.protected_metadata(),
    })
    files = [{'path': p.relative_to(HERE).as_posix(), 'bytes': p.stat().st_size, 'sha256': sha(p.read_bytes())}
             for p in sorted(HERE.rglob('*')) if p.is_file() and p.name != 'packet-files.json']
    save(HERE / 'packet-files.json', {'status': 'sealed', 'files': files})
    print(json.dumps({'status': 'failed_native_preserved_readback_pass', 'leaves': len(files), 'packet_sha256': sha((HERE / 'packet-files.json').read_bytes())}))


if __name__ == '__main__':
    main()
