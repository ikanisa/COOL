#!/usr/bin/env python3
"""Reviewed exact eight-file RAM reconstruction; apply only after authorization."""
import hashlib
import importlib.util
import json
import os
import stat
from pathlib import Path

HERE = Path(__file__).resolve().parent
PHYSICAL = HERE.parent / 'kotlin-sdk-physical-foundation-batch1'
PLAN1 = HERE.parent / 'kotlin-sdk-candidate-plan1'
PLAN2 = HERE.parent / 'kotlin-sdk-task-compatibility-plan2'
VALIDATOR_SHA = 'f9306d4eef77f280df62f713087af0df4b28643501a7f6434bea40929ca61487'
PHYSICAL_MANIFEST_SHA = '15fbf2bdda4a5f69b77d9e5eb945217528e63edbef1c372366ceceb33a12e126'
PLAN2_MANIFEST_SHA = '6ec617a0925bf719670e308f51d8ce19728f975500aaabf8fe1958cd29ac3fb3'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def parse_exact(body):
    parsed = {}
    current = None
    hunk = None
    lines = body.decode().splitlines(keepends=True)
    index = 0
    while index < len(lines):
        line = lines[index]
        if line.startswith('--- a/'):
            current = line[len('--- a/'):].rstrip('\n')
            index += 1
            if current in parsed or index >= len(lines) or lines[index] != '+++ b/' + current + '\n':
                raise ValueError('reviewed exact patch path pair differs')
            parsed[current] = []
            hunk = None
        elif line.startswith('@@ '):
            if current is None:
                raise ValueError('hunk without exact file')
            hunk = [line, []]
            parsed[current].append(hunk)
        else:
            if hunk is None:
                raise ValueError('unexpected exact reviewed patch data')
            hunk[1].append(line)
        index += 1
    return parsed


def reviewed_inputs():
    validator_path = HERE / 'verify_native_consumer_source.py'
    if sha(validator_path) != VALIDATOR_SHA:
        raise ValueError('cumulative eight-source validator drift')
    validator = module(validator_path, 'exact_cumulative8_validator')
    writer, admission, preview = validator.anchors()
    for directory, expected in [(PHYSICAL, PHYSICAL_MANIFEST_SHA), (PLAN2, PLAN2_MANIFEST_SHA)]:
        if sha(directory / 'packet-files.json') != expected:
            raise ValueError('independently reviewed source proposal packet drift')
        for name, expected_leaf in json.loads((directory / 'packet-files.json').read_text())['files'].items():
            if sha(directory / name) != expected_leaf:
                raise ValueError('reviewed source proposal packet leaf drift')
    parser = module(PHYSICAL / 'bind_three_file_preview.py', 'sealed_exact_ram_reconstruction')
    patches = [(PLAN1 / 'proposed-collect-only-sdk.patch', '3b1e88e8291541a4a955eebe17fb576c05e2f1ef73fcc55b68d041c04256fe68'), (PLAN2 / 'proposed-five-file-task-test-compatibility.patch', '1e8afbbacd725d9f0578e69cff2c5c81f6c65a2ac00dca1a7c675c9097d4318e')]
    parsed = {}
    for path, expected in patches:
        if sha(path) != expected:
            raise ValueError('exact reviewed patch body drift')
        rows = parse_exact(path.read_bytes())
        if set(parsed) & set(rows):
            raise ValueError('overlapping reviewed patch file')
        parsed.update(rows)
    if set(parsed) != set(preview['files']) or len(parsed) != 8:
        raise ValueError('not exact cumulative eight reviewed source paths')
    return validator, admission, preview, parser, parsed


def prepare_ram_delta(root):
    validator, admission, preview, parser, parsed = reviewed_inputs()
    prepared = {}
    for name, hunks in parsed.items():
        path = root / name
        if path.is_symlink() or path.resolve() != path:
            raise ValueError('source patch target has link path')
        observed = path.stat()
        if not stat.S_ISREG(observed.st_mode) or observed.st_nlink != 1:
            raise ValueError('source patch target is not exclusive regular file')
        metadata = module(HERE / 'publisher_metadata.py', 'exact_application_reader')
        fenced, original = metadata.stable_read(path, True)
        if (observed.st_dev, observed.st_ino, observed.st_mtime_ns) != (fenced['device'], fenced['inode'], fenced['mtime_ns']):
            raise ValueError('source patch baseline raced before RAM reconstruction')
        validator.check_regular_bytes('flutter/' + name, original, admission['members']['flutter/' + name], preview, 'pristine')
        after = parser.reconstruct(original, hunks)
        validator.check_regular_bytes('flutter/' + name, after, admission['members']['flutter/' + name], preview, 'patched')
        if original[:original.find(b'package ')] != after[:after.find(b'package ')] and name.endswith('.kt'):
            raise ValueError('original copyright/license header changed')
        prepared[name] = {'before_sha256': hashlib.sha256(original).hexdigest(), 'after_sha256': hashlib.sha256(after).hexdigest(), 'after_bytes': after, 'mode': observed.st_mode & 0o777}
    return validator, prepared


def apply_after_separate_authorization(root):
    validator, prepared = prepare_ram_delta(root)
    if root != validator.CANDIDATE or root in (validator.PRISTINE, validator.INSTALLED, validator.FAILED_CANDIDATE, validator.COMPLETED_CANDIDATE):
        raise ValueError('application restricted to exact new independent native consumer')
    for name, row in prepared.items():
        path = root / name
        if path.is_symlink() or path.resolve() != path or sha(path) != row['before_sha256'] or path.stat().st_nlink != 1:
            raise ValueError('actual source target drift before exact commit')
        temporary = path.with_name(path.name + '.collect-exact-reviewed-cumulative8.tmp')
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, 'O_NOFOLLOW', 0), 0o600)
        with os.fdopen(fd, 'wb') as output:
            output.write(row['after_bytes'])
            output.flush()
            os.fchmod(output.fileno(), row['mode'])
            os.fsync(output.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY | getattr(os, 'O_DIRECTORY', 0) | getattr(os, 'O_NOFOLLOW', 0))
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    return {'status': 'EXACT_REVIEWED_CUMULATIVE8_APPLICATION_PASS', 'actual_destination': str(root), 'source_files_changed': 8, 'files': {name: {key: value for key, value in row.items() if key != 'after_bytes'} for name, row in prepared.items()}, 'failed_candidate1_pristine_shared_SDK_and_repo_pins_locks_modified': False}


if __name__ == '__main__':
    raise SystemExit('Controller/root authorization required; standalone application refused.')
