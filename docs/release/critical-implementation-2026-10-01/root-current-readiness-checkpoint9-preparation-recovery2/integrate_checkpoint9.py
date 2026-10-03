"""Exact seven-file checkpoint proposal; root alone chooses --apply.

--verify-only reads the named inputs and prints preservation invariants. It writes
nothing. No compilation, tests, cache, processes, network or release calls.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import time

ROOT = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
HERE = Path(__file__).absolute().parent
OUTPUT = ROOT / 'docs/release/critical-implementation-2026-10-01/root-current-readiness-integration9'
LEDGER = 'docs/release/critical-implementation-2026-10-01/implementation-ledger.json'
CONTRACT_KEYS = ('id', 'title', 'report', 'status', 'review_status', 'acceptance_requirement_from_report')


def sha(data):
    return hashlib.sha256(data).hexdigest()


def physical(path):
    for p in (path, *path.parents):
        if p.exists() and stat.S_ISLNK(p.lstat().st_mode):
            raise ValueError('symlink refused: ' + str(p))


def read(path):
    physical(path)
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        before = os.fstat(fd)
        if not stat.S_ISREG(before.st_mode):
            raise ValueError('regular file required: ' + str(path))
        chunks = []
        while True:
            block = os.read(fd, 1024 * 1024)
            if not block:
                break
            chunks.append(block)
        after = os.fstat(fd)
        keys = ('st_dev', 'st_ino', 'st_size', 'st_mode', 'st_mtime_ns', 'st_ctime_ns')
        if any(getattr(before, k) != getattr(after, k) for k in keys):
            raise ValueError('read identity drift: ' + str(path))
        return b''.join(chunks), before
    finally:
        os.close(fd)


def contracts(value):
    return [[item.get(key) for key in CONTRACT_KEYS] for item in value['items']]


def validate(admission):
    rows = admission['canonical_files']
    expected = {LEDGER,
                'docs/release/critical-implementation-2026-10-01/IMPLEMENTATION_REGISTER.md',
                'docs/release/critical-implementation-2026-10-01/CURRENT_OPEN_FINDINGS_2026-10-02.md',
                'docs/release/LOCAL_IMPLEMENTATION_REGISTER_2026-09-30.md',
                'docs/release/PRODUCTION_REMAINING_TASKS_2026-09-30.md',
                'docs/release/local-implementation-register-2026-09-30.json',
                'docs/release/production-remaining-tasks-2026-09-30.json'}
    if len(rows) != 7 or {row['path'] for row in rows} != expected:
        raise ValueError('seven exact canonical files required')
    old, proposed = {}, {}
    for row in rows:
        n = row['path']
        if row['proposal_path'] != 'proposed/' + n:
            raise ValueError('proposal path is not the exact selected path')
        data, info = read(ROOT / n)
        saved, _ = read(HERE / 'before' / n)
        future, _ = read(HERE / row['proposal_path'])
        if sha(data) != row['before_sha256'] or len(data) != row['before_bytes'] or stat.S_IMODE(info.st_mode) != row['mode'] or saved != data:
            raise ValueError('current canonical fence drift: ' + n)
        if sha(future) != row['after_sha256'] or len(future) != row['after_bytes']:
            raise ValueError('proposal fence drift: ' + n)
        old[n], proposed[n] = data, future
    for row in admission['evidence_refs']:
        data, _ = read(ROOT / row['path'])
        if sha(data) != row['sha256']:
            raise ValueError('named evidence fence drift: ' + row['path'])
    for row in admission['live_guards']:
        data, info = read(Path(row['path']))
        if sha(data) != row['sha256'] or len(data) != row['bytes'] or stat.S_IMODE(info.st_mode) != row['mode']:
            raise ValueError('affected live input guard drift: ' + row['path'])
    original = json.loads(old[LEDGER])
    final = json.loads(proposed[LEDGER])
    if len(final['items']) != 40 or contracts(final) != contracts(original):
        raise ValueError('40 original contracts changed')
    if final['previous_checkpoint_before_update9'] != original['latest_checkpoint']:
        raise ValueError('prior checkpoint not preserved')
    for key, value in original.items():
        if key.startswith('previous_checkpoint_') and final[key] != value:
            raise ValueError('older checkpoint changed: ' + key)
    closed = [item['id'] for item in final['items'] if item['full_finding_closed']]
    original_closed = [item['id'] for item in original['items'] if item['full_finding_closed']]
    cp = final['latest_checkpoint']
    if closed != original_closed or len(closed) != 7 or set(closed) != set(cp['closed_ids']) or cp['full_findings_open'] != 33:
        raise ValueError('closure count/status changed')
    if cp['checkpoint_number'] != 9 or cp['current_source_epoch'] != admission['source_epoch'] or cp['current_source_fence_sha256'] != admission['source_fence_sha256']:
        raise ValueError('source epoch binding changed')
    if final['release_decision'] != 'NO-GO' or final['goal_status'] != 'active' or cp['release_decision'] != 'NO-GO' or cp['goal_status'] != 'active' or cp['production_release_approval'] is not False:
        raise ValueError('release/goal boundary changed')
    legacy_counts = {}
    for n in expected:
        if n.endswith('.json') and n != LEDGER:
            before, after = json.loads(old[n]), json.loads(proposed[n])
            if before['items'] != after['items'] or {k: v for k, v in before.items() if k != 'critical_review_implementation_extension'} != {k: v for k, v in after.items() if k != 'critical_review_implementation_extension'}:
                raise ValueError('legacy arrays or non-extension fields changed')
            ex = after['critical_review_implementation_extension']
            if ex['sha256'] != sha(proposed[LEDGER]) or ex['latest_checkpoint'] != cp or ex['previous_checkpoint_before_update9'] != before['critical_review_implementation_extension']['latest_checkpoint']:
                raise ValueError('legacy extension ledger/checkpoint binding mismatch')
            legacy_counts[n] = len(after['items'])
        elif n.endswith('.md'):
            first, second = old[n].decode(), proposed[n].decode()
            marker = 'Historical checkpoint —'
            if marker in first and (marker not in second or first[first.index(marker):] != second[second.index(marker):]):
                raise ValueError('historical Markdown body changed')
    if sorted(legacy_counts.values()) != [24, 102]:
        raise ValueError('original 102/24 arrays not preserved')
    open_md = proposed['docs/release/critical-implementation-2026-10-01/CURRENT_OPEN_FINDINGS_2026-10-02.md'].decode()
    if sum(line.startswith(('| BE-', '| ARC-', '| PD-')) for line in open_md.splitlines()) != 33:
        raise ValueError('current open table does not contain 33 original rows')
    return old, proposed, {'contracts40_unchanged': True, 'legacy102_24_arrays_and_non_extension_fields_unchanged': True,
                           'all_previous_checkpoints_preserved': True, 'historical_markdown_bodies_unchanged': True,
                           'closed_ids': closed, 'full_open': 33, 'release_decision': 'NO-GO',
                           'goal_status': 'active', 'production_release_approval': False,
                           'named_evidence_refs': len(admission['evidence_refs']),
                           'live_affected_input_guards': len(admission['live_guards'])}


def save(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('xb') as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())
    path.chmod(0o400)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--controller-sha256', required=True)
    parser.add_argument('--admission-sha256', required=True)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument('--verify-only', action='store_true')
    modes.add_argument('--apply', action='store_true')
    parser.add_argument('--output')
    args = parser.parse_args()
    start = time.monotonic()
    if Path.cwd() != ROOT or ROOT.resolve() != ROOT:
        raise ValueError('exact physical repository cwd required')
    if sha(read(Path(__file__))[0]) != args.controller_sha256:
        raise ValueError('controller hash mismatch')
    raw, _ = read(HERE / 'admission.json')
    if sha(raw) != args.admission_sha256:
        raise ValueError('admission hash mismatch')
    admission = json.loads(raw)
    old, proposed, invariants = validate(admission)
    receipt = {'kind': 'checkpoint9_exact_private_proposal_validation' if args.verify_only else 'root_checkpoint9_exact_integration',
               'admission_sha256': args.admission_sha256, 'invariants': invariants,
               'source_epoch': admission['source_epoch'], 'source_fence_sha256': admission['source_fence_sha256'],
               'before_sha256': {n: sha(data) for n, data in old.items()},
               'proposed_after_sha256': {n: sha(data) for n, data in proposed.items()},
               'attempted_canonical_paths': [], 'written_canonical_paths': [], 'canonical_apply_executed': False,
               'cache_build_test_network_process_or_provider_calls': False}
    if args.verify_only:
        if args.output is not None:
            raise ValueError('--verify-only writes nothing; --output refused')
        receipt['actual_seconds'] = time.monotonic() - start
        print(json.dumps(receipt, indent=2))
        return
    if args.output != str(OUTPUT):
        raise ValueError('exact root-owned fresh integration9 output required')
    physical(OUTPUT.parent)
    OUTPUT.mkdir(mode=0o700)
    try:
        for n, data in old.items():
            save(OUTPUT / 'before' / n, data)
        # Recheck every named input after preservation, before the first write.
        validate(admission)
        for row in admission['canonical_files']:
            n = row['path']
            path = ROOT / n
            data, info = read(path)
            if data != old[n]:
                raise ValueError('canonical input changed before its write: ' + n)
            receipt['attempted_canonical_paths'].append(n)
            fd = os.open(path, os.O_WRONLY | os.O_NOFOLLOW)
            try:
                current = os.fstat(fd)
                if (current.st_dev, current.st_ino, current.st_mode, current.st_size, current.st_mtime_ns, current.st_ctime_ns) != (info.st_dev, info.st_ino, info.st_mode, info.st_size, info.st_mtime_ns, info.st_ctime_ns):
                    raise ValueError('write identity drift: ' + n)
                os.ftruncate(fd, 0)
                with os.fdopen(fd, 'wb', closefd=False) as stream:
                    stream.write(proposed[n])
                    stream.flush()
                    os.fsync(fd)
            finally:
                os.close(fd)
            receipt['written_canonical_paths'].append(n)
            after, new_info = read(path)
            if after != proposed[n] or stat.S_IMODE(new_info.st_mode) != row['mode']:
                raise ValueError('actual after readback mismatch: ' + n)
        receipt['canonical_apply_executed'] = True
        receipt['actual_after_sha256'] = {n: sha(read(ROOT / n)[0]) for n in proposed}
        for row in admission['live_guards']:
            data, info = read(Path(row['path']))
            if sha(data) != row['sha256'] or len(data) != row['bytes'] or stat.S_IMODE(info.st_mode) != row['mode']:
                raise ValueError('affected live input drift after integration: ' + row['path'])
        receipt['affected_live_input_guards_unchanged_after'] = True
        receipt['actual_seconds'] = time.monotonic() - start
        save(OUTPUT / 'receipt.json', (json.dumps(receipt, indent=2) + '\n').encode())
        print(json.dumps(receipt, indent=2))
    except BaseException as error:
        receipt['error'] = {'type': type(error).__name__, 'message': str(error)}
        receipt['actual_current_hashes_after_failure'] = {}
        for n in proposed:
            try:
                receipt['actual_current_hashes_after_failure'][n] = sha(read(ROOT / n)[0])
            except BaseException as read_error:
                receipt['actual_current_hashes_after_failure'][n] = {'read_error': str(read_error)}
        receipt['actual_seconds'] = time.monotonic() - start
        save(OUTPUT / 'partial-write-failure.json', (json.dumps(receipt, indent=2) + '\n').encode())
        raise


if __name__ == '__main__':
    main()
