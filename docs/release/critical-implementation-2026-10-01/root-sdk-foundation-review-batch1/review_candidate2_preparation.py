#!/usr/bin/env python3
"""Root readback of the sealed, manually reviewed candidate2 preparation only."""
import datetime
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
PREP = HERE.parent / 'kotlin-sdk-candidate2-preparation-batch1'
OLD = HERE.parent / 'kotlin-sdk-candidate-preparation-batch1'
EXPECTED = '433aa82ca5a79f5ced1a4129583b74ca737da470dcf2617cb8adbe6ca70ab5f6'
OLD_ROOT = '/Volumes/PRO-G40/Development/Codex-Candidates/COOL-ARC09/flutter-3.44.4-collect-kotlin-2.4.20-candidate1'
NEW_ROOT = OLD_ROOT.removesuffix('1') + '2'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    assert digest(PREP / 'packet-files.json') == EXPECTED
    manifest = json.loads((PREP / 'packet-files.json').read_text())
    assert manifest['file_count'] == len(manifest['files']) == 14
    checked = {}
    for name, expected in manifest['files'].items():
        path = PREP / name
        assert path.is_file() and not path.is_symlink() and path.resolve() == path
        assert path.stat().st_nlink == 1 and digest(path) == expected
        checked[name] = expected
    for before, after in [
        ('authenticated_candidate_expansion.py', 'authenticated_candidate2_expansion.py'),
        ('observe-candidate-runtime.init.gradle', 'observe-candidate2-runtime.init.gradle'),
    ]:
        original = (OLD / before).read_bytes()
        assert original.count(OLD_ROOT.encode()) == 1
        assert (PREP / after).read_bytes() == original.replace(OLD_ROOT.encode(), NEW_ROOT.encode())
    old_command = json.loads((OLD / 'candidate-next-command.json').read_text())
    command = json.loads((PREP / 'candidate2-next-command.json').read_text())
    expected_argv = [arg.replace(OLD_ROOT, NEW_ROOT) for arg in old_command['argv']]
    old_observer = str(OLD / 'observe-candidate-runtime.init.gradle')
    new_observer = str(PREP / 'observe-candidate2-runtime.init.gradle')
    expected_argv = [new_observer if arg == old_observer else arg for arg in expected_argv]
    assert command['argv'] == expected_argv
    assert command['environment'] == old_command['environment']
    assert command['cwd'] == old_command['cwd'].replace(OLD_ROOT, NEW_ROOT)
    assert command['fixed_actual_process_timeout_seconds'] == old_command['fixed_actual_process_timeout_seconds'] == 2700
    assert len(command['all14_sdk_test_classes']) == 14
    observation = json.loads((PREP / 'preparation-negatives-observation.json').read_text())
    assert observation['observed_unified_exec_exit_code'] == 0
    assert observation['actual_test_methods'] == 15
    assert observation['test_code_SHA256'] == checked['candidate2_preparation_negative_tests.py']
    assert observation['validator_SHA256'] == checked['verify_candidate2_source.py']
    assert not Path(NEW_ROOT).exists()
    assert not (HERE.parent / 'kotlin-sdk-candidate2-execution-batch1').exists()
    receipt = {
        'checked_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'packet_manifest_sha256': EXPECTED,
        'checked_packet_leaves': len(checked),
        'checked_leaves': checked,
        'errors': [],
        'local_execution_admitted': True,
        'manual_review': [
            'Read complete controller, cumulative validator, exact-eight application and fifteen preparation tests.',
            'Read exact writer/observer derivatives and source proposal; both derivatives differ only in candidate2 root.',
            'Validator binds official complete source, exact eight byte changes and final FD/named-leaf read fence.',
            'Controller requires this independent exact review, fresh absent destination, disk reserve, idle owned cache, fixed actual deadlines and full source readback after compiler terminal.',
            'Full compiler, all fourteen SDK test classes, strict plugin validation, JAR and observed runtime graph remain required.',
        ],
        'scope': 'One fresh independent candidate2 expansion, exact reviewed eight source changes and unchanged strict 2700-second standalone SDK recipe. Retain all terminal failures; no candidate1/pristine/shared SDK mutation or app/bootstrap/selection/release operation.',
        'candidate_selection': False,
        'production_release_approval': False,
    }
    output = HERE / 'candidate2-preparation-readback.json'
    with output.open('x') as stream:
        json.dump(receipt, stream, indent=2, sort_keys=True)
        stream.write('\n')
    print(json.dumps({'receipt': str(output), 'sha256': digest(output), 'checked_leaves': len(checked), 'local_execution_admitted': True}))


if __name__ == '__main__':
    main()
