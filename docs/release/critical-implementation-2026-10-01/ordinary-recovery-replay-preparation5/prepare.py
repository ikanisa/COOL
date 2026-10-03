"""Freeze candidate5 without executing any SQL, Docker or provider operation."""
from pathlib import Path
import ast
import copy
import difflib
import hashlib
import importlib.util
import json
import stat

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
PRIOR = HERE.parent / 'ordinary-recovery-replay-preparation4'
CANDIDATE = Path('/Users/jeanbosco/Library/Caches/COOL-ORDINARY-RECOVERY/20261002-candidate5')
ACTUAL4 = Path('/Users/jeanbosco/Library/Caches/COOL-ORDINARY-RECOVERY/20261002-candidate4/docs/release/committed-recovery4')
RESULT4_SHA = 'c45b2065e944992dde7d26e03715d5eae27e254fa0058c1f34c988450ffecf4f'


def sha(body):
    return hashlib.sha256(body).hexdigest()


def regular(path):
    if any(p.is_symlink() for p in (path, *path.parents)):
        raise ValueError('Unsubstituted input required: ' + str(path))
    before = path.lstat()
    if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
        raise ValueError('Regular single-link input required: ' + str(path))
    body = path.read_bytes(); after = path.lstat()
    if (before.st_ino, before.st_size, before.st_mtime_ns) != (after.st_ino, after.st_size, after.st_mtime_ns):
        raise ValueError('Input changed during read')
    return body


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


def save(name, value):
    with (HERE / name).open('x') as stream:
        stream.write(json.dumps(value, indent=2) + '\n')


def preservation():
    previous = load('preserved_preparation4', PRIOR / 'prepare.py')
    rows = previous.preservation()
    seal = json.loads(regular(PRIOR / 'packet-files.json'))
    for entry in seal['files']:
        body = regular(PRIOR / entry['path'])
        if sha(body) != entry['sha256'] or len(body) != entry['bytes']:
            raise ValueError('Prior4 seal drift')
    rows.update({str(path): sha(regular(path)) for path in sorted(PRIOR.iterdir()) if path.is_file()})
    rows.update({str(path): sha(regular(path)) for path in sorted(ACTUAL4.rglob('*')) if path.is_file()})
    if rows[str(ACTUAL4 / 'result.json')] != RESULT4_SHA:
        raise ValueError('Actual4 result drift')
    prior = json.loads(regular(PRIOR / 'inputs.json'))
    for name, digest in {**prior['sources'], **prior['references']}.items():
        path = Path(prior['candidate']) / name
        if sha(regular(path)) != digest or (name in prior['sources'] and regular(ROOT / name) != regular(path)):
            raise ValueError('Original222 input drift: ' + name)
        rows[str(path)] = digest
    return rows


def ast_nodes(path):
    return {node.name: ast.dump(node, include_attributes=False) for node in ast.parse(regular(path)).body
            if isinstance(node, (ast.FunctionDef, ast.ClassDef))}


def tests(path):
    return {node.name: ast.dump(node, include_attributes=False) for node in ast.walk(ast.parse(regular(path)))
            if isinstance(node, ast.FunctionDef) and node.name.startswith('test_')}


def main():
    if CANDIDATE.exists() or (HERE / 'inputs.json').exists():
        raise ValueError('Fresh private candidate5 and manifest required')
    before = preservation()
    previous = json.loads(regular(PRIOR / 'inputs.json'))
    result = json.loads(regular(ACTUAL4 / 'result.json'))
    if (result['status'] != 'failed' or len(result['cases']) != 22 or
            any(row['status'] != 'pass' for row in result['cases']) or
            result['failure'] != '[Errno 35] Resource temporarily unavailable' or
            not result['all_task_containers_removed'] or result['cleanup_errors'] or
            not all(target['task_container_removed'] for target in result['targets'].values()) or
            result['input_binding']['code_sha256'] != sha(regular(PRIOR / 'rehearsal.py')) or
            result['input_binding']['inputs_sha256'] != sha(regular(PRIOR / 'inputs.json'))):
        raise ValueError('Exact actual4 failure and completed cleanup required')
    old = regular(PRIOR / 'rehearsal.py').decode(); new = regular(HERE / 'rehearsal.py').decode()
    expected = old.replace('import datetime\n', 'import datetime\nimport errno\n', 1)
    expected = expected.replace(
        '                            except BrokenPipeError:\n',
        '                            except BlockingIOError as error:\n'
        '                                if error.errno not in (errno.EAGAIN, errno.EWOULDBLOCK):\n'
        '                                    raise\n'
        '                                continue\n'
        '                            except BrokenPipeError:\n', 1)
    expected = expected.replace(
        '                            chunk = os.read(key.fileobj.fileno(), 16384)\n',
        '                            try:\n'
        '                                chunk = os.read(key.fileobj.fileno(), 16384)\n'
        '                            except BlockingIOError as error:\n'
        '                                if error.errno not in (errno.EAGAIN, errno.EWOULDBLOCK):\n'
        '                                    raise\n'
        '                                continue\n', 1)
    expected = expected.replace('20261002-candidate4', '20261002-candidate5')
    if expected != new:
        raise ValueError('Only exact bounded Runner retry and candidate path delta allowed')
    old_nodes, new_nodes = ast_nodes(PRIOR / 'rehearsal.py'), ast_nodes(HERE / 'rehearsal.py')
    changed = sorted(name for name in old_nodes if old_nodes[name] != new_nodes.get(name))
    if changed != ['Runner', 'main'] or set(old_nodes) != set(new_nodes):
        raise ValueError('Unexpected AST delta')
    if regular(PRIOR / 'test_rehearsal.py') != regular(HERE / 'test_rehearsal.py') or len(tests(HERE / 'test_rehearsal.py')) != 34:
        raise ValueError('All original34 test bytes and ASTs required')
    bodies = {name: regular(Path(previous['candidate']) / name) for name in {**previous['sources'], **previous['references']}}
    if len(previous['sources']) != 216 or len(previous['references']) != 6 or len(bodies) != 222:
        raise ValueError('Exact216+6/222 scope required')
    CANDIDATE.mkdir(parents=True, mode=0o700)
    for name, body in bodies.items():
        path = CANDIDATE / name; path.parent.mkdir(parents=True, exist_ok=True)
        with path.open('xb') as stream: stream.write(body)
        path.chmod(0o600)
    inputs = copy.deepcopy(previous)
    inputs['candidate'] = str(CANDIDATE)
    inputs['lineage'].update(candidate4_inputs_sha256=sha(regular(PRIOR / 'inputs.json')),
        candidate4_packet_sha256=sha(regular(PRIOR / 'packet-files.json')),
        failed_execution4_result_sha256=RESULT4_SHA, failed_execution4_actual_files=sum(path.is_file() for path in ACTUAL4.rglob('*')))
    save('inputs.json', inputs)
    rows = [json.loads(line) for line in regular(ACTUAL4 / 'commands.jsonl').decode().splitlines()]
    refused = [row for row in rows if row.get('status') == 'refused']
    save('retained-failure4-readback.json', dict(status='actual_failure_retained', actual_result_path=str(ACTUAL4 / 'result.json'),
        actual_result_sha256=RESULT4_SHA, actual_pass_cases=len(result['cases']), cases=result['cases'], failure=result['failure'],
        elapsed_seconds=result['elapsed_seconds'], whole_pass=False, actual_replay_migrations=len(result['targets']['restore']['migrations']),
        last_replayed_version=result['targets']['restore']['migrations'][-1]['version'],
        all_task_containers_removed=result['all_task_containers_removed'], cleanup_errors=result['cleanup_errors'],
        recorded_target_removed={key: value['task_container_removed'] for key, value in result['targets'].items()},
        cleanup_is_retained_readback_not_new_docker_probe=True, refused_commands=refused,
        actual_commands_sha256=sha(regular(ACTUAL4 / 'commands.jsonl')), actual_original_files=sum(path.is_file() for path in ACTUAL4.rglob('*')),
        hosted_called=result['hosted_called'], provider_called=result['provider_called'], maintained_source_mutations=result['maintained_source_mutations']))
    save('preservation-before.json', before)
    save('preparation-readback.json', dict(status='prepared_only', original222_input_hashes={**inputs['sources'], **inputs['references']},
        original_sources216_unchanged=True, references6_unchanged=True, original34_test_bytes_AST_unchanged=True,
        changed_prior_nodes=changed, unchanged_node_AST_sha256={name: sha(value.encode()) for name, value in old_nodes.items() if name not in changed},
        Runner_text_method_AST_unchanged=True, exact_source_delta_checked=True, whole_deadline_seconds=600,
        execution_budget_seconds=540, cleanup_budget_seconds=60, docker_executed=False, execution_done=False,
        preserved_files=len(before), candidate=str(CANDIDATE)))
    matrix = json.loads(regular(PRIOR / 'command-scope-matrix.json'))

    def replace(value):
        if isinstance(value, str):
            return value.replace('ordinary-recovery-replay-preparation4', 'ordinary-recovery-replay-preparation5').replace('20261002-candidate4', '20261002-candidate5').replace('committed-recovery4', 'committed-recovery5')
        if isinstance(value, list): return [replace(item) for item in value]
        if isinstance(value, dict): return {key: replace(item) for key, item in value.items()}
        return value
    matrix = replace(matrix)
    for document in [matrix, matrix['review_record_schema']]:
        document['code_sha256'] = sha(regular(HERE / 'rehearsal.py'))
        document['inputs_sha256'] = sha(regular(HERE / 'inputs.json'))
    matrix['retained_failure4_result_sha256'] = RESULT4_SHA
    matrix['Runner_IO_change'] = dict(nonblocking_read_and_write_retry_only=['EAGAIN', 'EWOULDBLOCK'],
        offset_only_changes_after_successful_write=True, streams_remain_registered_on_retry=True,
        original_monotonic_bounds_unchanged=True, BrokenPipe_and_other_IO_and_output_and_process_group_guards_unchanged=True)
    save('command-scope-matrix.json', matrix)
    with (HERE / 'rehearsal.py.diff').open('x') as stream:
        stream.write(''.join(difflib.unified_diff(old.splitlines(True), new.splitlines(True), fromfile='preparation4/rehearsal.py', tofile='preparation5/rehearsal.py')))
    after = preservation()
    if after != before:
        raise ValueError('Preserved prior evidence changed during preparation')
    save('preservation-after-prepare.json', after)
    print(json.dumps(dict(status='prepared_only', inputs=222, original34_preserved=True, changed_nodes=changed,
        candidate=str(CANDIDATE), code_sha256=sha(regular(HERE / 'rehearsal.py')), inputs_sha256=sha(regular(HERE / 'inputs.json')), docker_executed=False)))


if __name__ == '__main__': main()
