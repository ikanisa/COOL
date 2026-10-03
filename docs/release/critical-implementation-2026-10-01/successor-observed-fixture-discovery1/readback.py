#!/usr/bin/env python3
"""Independent read-only provenance reconciliation; writes only this NEW packet.

No imports of repository runners, fixture copies, runtime tests or external calls.
"""
import ast
import collections
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess

ROOT = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
OUT = Path(__file__).resolve().parent / 'readback-attempt4'
OUT.mkdir(exist_ok=False)
BASE = ROOT / '.cache/receipt-successor-workflows-20261001'
PACKETS = {
    'first_job': ('accepted-successor-first-job-execution-current1', 'attempt8'),
    'callback_archive': ('accepted-successor-observations-archive-current1', 'attempt4'),
    'edge': ('accepted-successor-edge-current1', 'attempt3'),
    'index': ('accepted-successor-edge-index-current1', 'attempt1'),
}
seen = {}
errors = []


def sha(data):
    return hashlib.sha256(data).hexdigest()


def ident(s):
    return [s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns,
            stat.S_IMODE(s.st_mode), s.st_nlink]


def read(path, single_link=True):
    path = Path(path).absolute()
    for part in [path, *path.parents]:
        if part.is_symlink():
            raise ValueError('Symlink refused: ' + str(part))
        if part == ROOT:
            break
    before = path.lstat()
    if not stat.S_ISREG(before.st_mode) or (single_link and before.st_nlink != 1):
        raise ValueError('Single-link regular file required: ' + str(path))
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        opened = os.fstat(fd)
        if ident(before) != ident(opened):
            raise ValueError('Busy input before read: ' + str(path))
        chunks = []
        while True:
            b = os.read(fd, 1024 * 1024)
            if not b:
                break
            chunks.append(b)
        data = b''.join(chunks)
        after = os.fstat(fd)
    finally:
        os.close(fd)
    if ident(opened) != ident(after) or ident(path.lstat()) != ident(after):
        raise ValueError('Busy input during read: ' + str(path))
    record = {'sha256': sha(data), 'identity': ident(after)}
    key = str(path.relative_to(ROOT))
    if key in seen and seen[key] != record:
        raise ValueError('Busy input across reads: ' + key)
    seen[key] = record
    return data


def obj(path):
    return json.loads(read(path))


def write(name, value):
    with (OUT / name).open('x') as stream:
        json.dump(value, stream, indent=2, ensure_ascii=False)
        stream.write('\n')


def require(condition, message):
    if not condition:
        errors.append(message)


def contained(parent, relative):
    p = Path(relative)
    if p.is_absolute() or '..' in p.parts:
        raise ValueError('Escaping path: ' + relative)
    return parent / p


started = dt.datetime.now(dt.timezone.utc).isoformat()
test_path = ROOT / 'supabase/functions/collect-receipt-successor-gateway/handler_test.ts'
test_text = read(test_path).decode()
names = re.findall(r'from\s+["\']\./fixtures/(observed[^"\']+\.json)["\']', test_text)
require(len(names) == len(set(names)) == 10, 'Expected exact ten unique imported observations')
fixture_prefix = 'supabase/functions/collect-receipt-successor-gateway/fixtures/'
destination_absent = {fixture_prefix + n: not os.path.lexists(ROOT / fixture_prefix / n) for n in names}
require(all(destination_absent.values()), 'A maintained destination appeared; refuse import preparation')

# Exact name discovery includes ignored evidence, within only these repo roots.
roots = ['.cache', 'docs/release', 'tools', 'scripts/tests', 'supabase', 'test', 'contracts']
args = ['rg', '--files', '--hidden', '--no-ignore', '--null']
for name in names:
    args += ['-g', name]
args += roots
scan = subprocess.run(args, cwd=ROOT, capture_output=True, timeout=45)
paths = sorted(x.decode() for x in scan.stdout.split(b'\0') if x)
discovered_path_count = len(paths)
discovery = {n: [] for n in names}
for rel in paths:
    p = ROOT / rel
    try:
        data = read(p, single_link=False)
        discovery[p.name].append({'path': rel, 'sha256': sha(data), 'bytes': len(data),
                                 'link_count': p.lstat().st_nlink})
    except Exception as exc:
        errors.append('Discovery read refused: ' + rel + ': ' + str(exc))
write('exact-filename-discovery.json', {
    'argv': args, 'exit_code': scan.returncode, 'stderr': scan.stderr.decode(),
    'roots': roots, 'paths': discovery,
    'scope': 'Contained repo filename scan including ignored regular files; no symlink traversal, archive interiors, external computer roots or other chats.'})
require(scan.returncode == 0 and not scan.stderr, 'Contained filename discovery reported errors')

manifest_reports = {}
results = {}
for family, (packet, attempt) in PACKETS.items():
    directory = BASE / packet
    manifest = obj(directory / 'MANIFEST.json')
    files = {}
    for rel, expected in manifest.items():
        p = contained(directory, rel)
        data = read(p)
        files[rel] = {'expected_sha256': expected, 'actual_sha256': sha(data),
                      'bytes': len(data), 'matches': sha(data) == expected}
        require(sha(data) == expected, 'Sealed artifact mismatch: ' + str(p))
    extra = sorted(str(p.relative_to(directory)) for p in directory.rglob('*')
                   if p.is_file() and str(p.relative_to(directory)) not in manifest
                   and p.name != 'MANIFEST.json')
    require(not extra, 'Unmanifested regular files in sealed packet: ' + packet)
    manifest_reports[family] = {'packet': str(directory.relative_to(ROOT)),
        'manifest_sha256': seen[str((directory / 'MANIFEST.json').relative_to(ROOT))]['sha256'],
        'artifact_count': len(files), 'all_hashes_match': all(x['matches'] for x in files.values()),
        'extra_regular_files': extra, 'files': files}
    results[family] = obj(directory / 'proof' / attempt / 'result.json')
write('sealed-packet-readback.json', manifest_reports)

# Verify producer execution receipts against retained raw outputs and source copies.
producer_reports = {}
commands_by_family = {}
for family in ('first_job', 'callback_archive'):
    packet, attempt = PACKETS[family]
    proof = BASE / packet / 'proof' / attempt
    result = results[family]
    commands = []
    require(result['status'] == 'passed' and result['source_unchanged'] is True,
            'Producer did not complete with stable original source: ' + family)
    require(all(c['passed'] is True for c in result['checks']), 'Producer failed check: ' + family)
    require(result['started_at'] < result['finished_at'], 'Invalid producer completion ordering: ' + family)
    copied_bindings = {}
    for rel, expected in result['source_bindings'].items():
        p = proof / 'inputs/migrations' / Path(rel).name
        if not p.exists() and Path(rel).name in (
                '20261002040000_receipt_unarmed_closure.sql',
                '20261002041000_receipt_successor_approvals.sql'):
            p = proof / 'inputs' / Path(rel).name
        copied_bindings[rel] = {'copy': str(p.relative_to(ROOT)), 'sha256': sha(read(p)),
                                'expected_sha256': expected}
        require(copied_bindings[rel]['sha256'] == expected, 'Producer migration input mismatch: ' + rel)
    fields = {'executed-runner.py': result['runner_sha256'],
              'executed-helper.py': result['helper_sha256'],
              'row-free-platform.sql': result['baseline_sha256'],
              '20261002040000_receipt_unarmed_closure.sql': result['closure_sha256'],
              '20261002041000_receipt_successor_approvals.sql': result['approval_sha256'],
              result['migration_filename']: result['migration_sha256'],
              'foundation-publication.sql': result['foundation_sha256'],
              'reused-predecessor-setup.sql': result['setup_sha256'],
              'python-runtime': result['tools']['python_sha256'],
              'docker-runtime': result['tools']['docker_sha256']}
    for name, expected in fields.items():
        require(sha(read(proof / 'inputs' / name)) == expected, 'Producer input/tool binding mismatch: ' + name)

    # The original helper logs each exact SQL text; commands bind its prefixed stdin.
    sql_text = read(proof / 'successorexecution/queries.sql').decode()
    chunks = re.split(r'^-- Offline synthetic target: ([^\n]*)\n', sql_text, flags=re.M)
    sql_by_hash = collections.defaultdict(list)
    prefix = "set search_path=public,extensions,auth;set timezone='UTC';\n"
    for i in range(1, len(chunks), 2):
        label, body = chunks[i], chunks[i+1]
        if body.endswith('\n'):
            body = body[:-1]
        sql_by_hash[sha((prefix + body).encode())].append({'label': label, 'sql': body})
    # The retained predecessor setup itself includes original query markers, so
    # an outer marker split cannot delimit it. Bind these exact input snapshots.
    for name in fields:
        if name.endswith('.sql'):
            body = read(proof / 'inputs' / name).decode()
            sql_by_hash[sha((prefix + body).encode())].append(
                {'label': 'exact producer input snapshot: ' + name, 'sql': body})
    for p in sorted((proof / 'commands').glob('*.json')):
        c = obj(p)
        stem = p.with_suffix('')
        stdout = read(stem.with_suffix('.stdout'))
        stderr = read(stem.with_suffix('.stderr'))
        require(sha(stdout) == c['stdout_sha256'] and sha(stderr) == c['stderr_sha256'],
                'Command raw output mismatch: ' + str(p))
        cleanup_after_test_finish = c['finished_at'] > result['finished_at']
        if cleanup_after_test_finish:
            require(c['exit_code'] == 0 and c['argv'][1] in ('logs','rm')
                    and result['target']['container_name'] in c['argv']
                    and result['target']['task_container_removed'] is True,
                    'Unclosed non-cleanup command after producer test finish: ' + str(p))
        else:
            require(result['started_at'] <= c['started_at'] <= c['finished_at'] <= result['finished_at'],
                    'Command outside producer test interval: ' + str(p))
        last = stdout.decode().strip().splitlines()
        data = None
        if last:
            try:
                data = json.loads(last[-1])
            except ValueError:
                pass
        row = {'receipt_path': str(p.relative_to(ROOT)), 'command_id': p.stem,
               'receipt_sha256': sha(read(p)), 'exit_code': c['exit_code'],
               'started_at': c['started_at'], 'finished_at': c['finished_at'],
               'argv': c['argv'], 'input_sha256': c['input_sha256'],
               'stdout_sha256': c['stdout_sha256'], 'stderr_sha256': c['stderr_sha256'],
               'cleanup_after_recorded_test_finish': cleanup_after_test_finish,
               'sql_bound': c['input_sha256'] in sql_by_hash,
               'sql_candidates': sql_by_hash.get(c['input_sha256'], []), 'last_json': data}
        commands.append(row)
    require(len(commands) == result['command_count'], 'Producer command count mismatch: ' + family)
    psql = [c for c in commands if 'psql' in c['argv']]
    require(all(c['sql_bound'] for c in psql), 'Unbound original SQL command stdin: ' + family)
    commands_by_family[family] = commands
    # Raw SQL and response data stay in their original packet; expose only bindings here.
    redacted_commands = [{k:v for k,v in c.items() if k not in ('sql_candidates','last_json')} for c in commands]
    producer_reports[family] = {
        'packet': packet, 'attempt': attempt, 'result_sha256': sha(read(proof / 'result.json')),
        'status': result['status'], 'started_at': result['started_at'], 'finished_at': result['finished_at'],
        'checks_passed': len(result['checks']), 'checks': result['checks'],
        'source_bindings_count': len(result['source_bindings']), 'source_copy_bindings': copied_bindings,
        'input_bindings': fields, 'migration_filename': result['migration_filename'],
        'migration_sha256': result['migration_sha256'], 'tools': result['tools'], 'target': result['target'],
        'external_boundary': {k:result[k] for k in ('hosted_written','sms_sent','device_used')},
        'command_count': len(commands), 'successful_commands': sum(c['exit_code'] == 0 for c in commands),
        'cleanup_completed_at': max(c['finished_at'] for c in commands),
        'recorded_finished_at_meaning': 'Last assertion/test finish occurs inside Target context; the two retained Docker logs/rm cleanup commands finish afterward. Final result source fence and target.task_container_removed are written after context exit.',
        'expected_refusal_commands': [c['command_id'] for c in commands if c['exit_code'] != 0],
        'all_psql_stdin_bound_to_retained_queries_sql': all(c['sql_bound'] for c in psql),
        'psql_not_logged_by_Target_sql': [c['command_id'] for c in psql if not c['sql_bound']],
        'commands': redacted_commands}
write('actual-producer-readback.json', producer_reports)

# Every imported byte-identical observed file must bind actual successful producer stdout.
association = obj(BASE / PACKETS['edge'][0] / 'source-association-current.json')
first = {Path(p).name:h for p,h in association['actual_SQL_producer']['observations'].items()}
other = association['callback_archive_producer']['files']
require(producer_reports['first_job']['result_sha256'] == association['actual_SQL_producer']['result_sha256'],
        'First-job association result mismatch')
require(producer_reports['callback_archive']['result_sha256'] == association['callback_archive_producer']['result_sha256'],
        'Callback archive association result mismatch')
require(manifest_reports['callback_archive']['manifest_sha256'] == association['callback_archive_producer']['packet_manifest_sha256'],
        'Callback archive association packet mismatch')
fixture_reports = []
literal = r"'((?:''|[^'])*)'"
for name in names:
    family = 'first_job' if name in first else 'callback_archive'
    expected = first.get(name, other.get(name))
    require(expected is not None, 'Imported observation absent from producer association: ' + name)
    packet, attempt = PACKETS[family]
    original = BASE / packet / 'proof' / attempt / name
    edge_copy = BASE / PACKETS['edge'][0] / fixture_prefix / name
    edge_proof_copy = BASE / PACKETS['edge'][0] / 'proof/attempt3/source' / fixture_prefix / name
    raw = read(original)
    data = json.loads(raw)
    require(sha(raw) == expected == sha(read(edge_copy)) == sha(read(edge_proof_copy)),
            'Original/consumer/association fixture mismatch: ' + name)
    linked = []
    items = data if name == 'observed-multipart-callbacks.json' else [data]
    for index, item in enumerate(items):
        target = item['result'] if name == 'observed-multipart-callbacks.json' else item
        matches = [c for c in commands_by_family[family]
                   if c['exit_code'] == 0 and c['last_json'] == target and c['sql_bound']]
        require(bool(matches), 'No successful bound raw command output for observation: ' + name)
        links = []
        for c in matches:
            bound = c['sql_candidates']
            if name == 'observed-multipart-callbacks.json':
                found = []
                pattern = r'public\.gateway_receipt_successor_callback_v1\(' + literal + ',' + literal + ',' + literal + ',' + literal + r'::jsonb\)'
                for query in bound:
                    for m in re.finditer(pattern, query['sql']):
                        device, request, request_hash, payload = [x.replace("''", "'") for x in m.groups()]
                        if request == item['request_id'] and json.loads(payload) == item['payload']:
                            found.append({'device_id': device, 'request_id': request, 'request_sha256': request_hash,
                                          'payload_exactly_matches_observed_wrapper': True})
                require(bool(found), 'Callback wrapper not bound to actual SQL input: ' + name)
            else:
                found = None
            links.append({k:c[k] for k in ('receipt_path','command_id','receipt_sha256','input_sha256','stdout_sha256',
                                          'stderr_sha256','started_at','finished_at','exit_code')})
            links[-1]['callback_request_payload_sql_binding'] = found
        linked.append({'observation_index': index, 'actual_successful_output_links': links})
    fixture_reports.append({'name': name, 'family': family, 'sha256': sha(raw), 'bytes': len(raw),
        'original_path': str(original.relative_to(ROOT)), 'sealed_consumer_copy': str(edge_copy.relative_to(ROOT)),
        'sealed_consumer_proof_copy': str(edge_proof_copy.relative_to(ROOT)),
        'destination': fixture_prefix + name, 'destination_absent': destination_absent[fixture_prefix + name],
        'producer_result_sha256': producer_reports[family]['result_sha256'],
        'producer_packet_manifest_sha256': manifest_reports[family]['manifest_sha256'],
        'producer_migration_sha256': producer_reports[family]['migration_sha256'],
        'source_association_sha256': sha(read(BASE / PACKETS['edge'][0] / 'source-association-current.json')),
        'actual_output_links': linked,
        'all_discovered_copies_identical': all(p['sha256'] == expected for p in discovery[name])})
write('ten-observation-bindings.json', fixture_reports)

# Capture earlier actual boundaries. Never sum separate/partial runs into acceptance.
history = []
for family, attempts in [('first_job', ('attempt1','attempt2','attempt3','attempt4','attempt5','attempt6','attempt7','attempt8')),
                         ('callback_archive', ('attempt1','attempt2','attempt3','attempt4'))]:
    packet, _ = PACKETS[family]
    for attempt in attempts:
        path = BASE / packet / 'proof' / attempt / 'result.json'
        if not path.exists():
            history.append({'family':family,'attempt':attempt,'retained_result':False})
            continue
        r = obj(path)
        history.append({'family':family,'attempt':attempt,'path':str(path.relative_to(ROOT)),
            'result_sha256':sha(read(path)), 'status':r.get('status'), 'finished_at':r.get('finished_at'),
            'checks_passed':sum(c.get('passed') is True for c in r.get('checks',[])),
            'checks_failed':sum(c.get('passed') is False for c in r.get('checks',[])),
            'command_count':r.get('command_count'), 'error':r.get('error'),
            'migration_sha256':r.get('migration_sha256'), 'source_unchanged':r.get('source_unchanged')})
for attempt in ('attempt2','attempt3'):
    proof = BASE / PACKETS['edge'][0] / 'proof' / attempt
    r = obj(proof / 'result.json')
    stdout = read(proof / 'stdout.txt')
    stderr = read(proof / 'stderr.txt')
    require(sha(stdout) == r['stdout_sha256'] and sha(stderr) == r['stderr_sha256'], 'Edge raw log binding mismatch')
    plain = re.sub(r'\x1b\[[0-9;]*m','',stdout.decode())
    summaries = re.findall(r'^(ok|FAILED) \| (\d+) passed \| (\d+) failed[^\n]*$',plain,re.M)
    history.append({'family':'edge','attempt':attempt,'status':r['status'],'exit_code':r['exit_code'],
        'result_sha256':sha(read(proof/'result.json')),'stdout_sha256':sha(stdout),'stderr_sha256':sha(stderr),
        'actual_stdout_summaries':summaries, 'command':r['command'], 'deno_sha256':r['deno_sha256'],
        'completion_limit':'No wall-clock started/finished fields in original edge receipt; completed process exit and stdout summary retained.'})
write('historical-pass-fail-boundaries.json', history)

# Current canonical source inventory, mirroring source_paths without loading runners.
paths = list((ROOT/'supabase/functions').rglob('*.ts'))
paths += list((ROOT/'supabase/functions').rglob('fixtures/*.json'))
for pattern in ('*.py','requirements.*','Dockerfile'):
    paths += list((ROOT/'tools/roster-decoder').glob(pattern))
for rel in ('contracts/collect-android-attempt-archive-v3/fixtures','contracts/collect-android-dispatch-v2/fixtures'):
    paths += list((ROOT/rel).glob('*.json'))
worker = ROOT/'scripts/tests/fixtures/receipt_worker_observation_v1'
manifest = obj(worker/'manifest.json')
require(sha(read(worker/'manifest.json')) == 'e5ed738a0aa4dc6cf870bf33352610074a6e46ab82705dd82440571b58a6a657', 'Worker immutable manifest mismatch')
paths.append(worker/'manifest.json')
for rel, expected in manifest['files'].items():
    p = contained(worker, rel)
    require(sha(read(p)) == expected, 'Worker immutable source mismatch: ' + rel)
    paths.append(p)
wresult = obj(worker/'result.json')
require(wresult.get('status') == 'pass' and wresult['finished_at'] == manifest['origin_finished_at']
        and all(wresult.get(k) is True for k in ('sources_unchanged','runner_unchanged','support_unchanged')), 'Worker provenance mismatch')
for name, key in {'executed-runner.py':'runner_sha256','authority-support.py':'support_sha256','executed-helper.py':'helper_sha256'}.items():
    require(sha(read(worker/'inputs'/name)) == wresult[key], 'Worker input binding mismatch: '+name)
for name, expected in wresult['migration_sha256'].items():
    require(sha(read(worker/'inputs'/name)) == expected, 'Worker migration binding mismatch: '+name)
linux = read(ROOT/'scripts/tests/verify_roster_decoder.py').decode()
node = ast.parse(linux)
source_assignment = next(n for n in node.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='SOURCES' for t in n.targets))
source_segment = ast.get_source_segment(linux,source_assignment)
# SOURCE globs duplicate the decoder globs above; read all literals in its assignment.
paths += [ROOT/'scripts/tests/verify_roster_decoder.py']
paths += [ROOT/n.value for n in ast.walk(source_assignment.value) if isinstance(n,ast.Constant)
          and isinstance(n.value,str) and '/' in n.value and '*' not in n.value
          and (Path(n.value).suffix or n.value.endswith('/Dockerfile'))]
ci = read(ROOT/'scripts/qa/run_edge_ci.py').decode()
ci_node = ast.parse(ci)
source_fn = next(n for n in ci_node.body if isinstance(n,ast.FunctionDef) and n.name=='source_paths')
last_list = next(n.value for n in source_fn.body if isinstance(n,ast.AugAssign) and isinstance(n.value,ast.ListComp))
unit_ast = ast.parse(read(ROOT/'scripts/qa/run_edge_unit_tests.py').decode())
actual_handler = next(ast.literal_eval(n.value) for n in unit_ast.body if isinstance(n,ast.Assign)
    and any(isinstance(t,ast.Name) and t.id=='ACTUAL_HANDLER_TEST' for t in n.targets))
require(actual_handler == 'scripts/tests/play_integrity_handler_test.ts', 'Unexpected actual handler test name')
for value in last_list.generators[0].iter.elts:
    if isinstance(value, ast.Name) and value.id == 'ACTUAL_HANDLER_TEST':
        paths.append(ROOT/actual_handler)
    else:
        paths.append(ROOT/ast.literal_eval(value))
paths += [ROOT/'scripts/tests/play_integrity_handler_test.ts']
paths = sorted(set(p.absolute() for p in paths))
current = {}
for path in paths:
    current[str(path.relative_to(ROOT))] = {'sha256':sha(read(path)), 'bytes':path.stat().st_size}
write('current-canonical-source-inventory.json', {'count':len(current),'files':current,
    'inventory_method':'Static AST and glob mirror of actual run_edge_ci.source_paths; repository runners not imported or executed.',
    'source_paths_sha256':sha(ci.encode()),'linux_sources_assignment':source_segment,
    'current_ts_count':sum(p.suffix=='.ts' and str(p.relative_to(ROOT)).startswith('supabase/functions/') for p in paths),
    'proposed_exact_ten_added_count':len(names),'proposed_combined_count':len(current)+len(names)})

end_drift = []
for rel, original in list(seen.items()):
    try:
        p = ROOT / rel
        s = p.lstat()
        if ident(s) != original['identity'] or sha(read(p, single_link=False)) != original['sha256']:
            end_drift.append(rel)
    except Exception as exc:
        end_drift.append(rel + ': ' + str(exc))
for rel in destination_absent:
    if os.path.lexists(ROOT/rel):
        end_drift.append('Destination appeared: '+rel)
write('read-input-identities.json', seen)
write('summary.json', {'started_at':started,'finished_at':dt.datetime.now(dt.timezone.utc).isoformat(),
    'status':'readback_pass' if not errors and not end_drift else 'refuse_busy_or_invalid',
    'errors':errors,'drift':end_drift,'read_input_count':len(seen),'observations_imported':0,
    'runtime_tests_executed':0,'contained_exact_filename_match_count':discovered_path_count,
    'discovered_file_count':sum(map(len,discovery.values())),
    'sealed_packet_artifact_counts':{k:v['artifact_count']for k,v in manifest_reports.items()},
    'producer_checks':{k:v['checks_passed']for k,v in producer_reports.items()},
    'producer_command_counts':{k:v['command_count']for k,v in producer_reports.items()},
    'current_canonical_source_count':len(current),'proposed_source_count':len(current)+len(names),
    'maintained_destinations_all_absent':all(destination_absent.values()),
    'permission_boundary':'Read only original packets and maintained inputs; writes only this NEW discovery directory.'})
print(json.dumps({'errors':errors,'drift':end_drift,'read_inputs':len(seen),
    'manifest_counts':{k:v['artifact_count']for k,v in manifest_reports.items()},
    'fixture_count':len(fixture_reports),'current_source_count':len(current),'candidate_source_count':len(current)+len(names)}))
