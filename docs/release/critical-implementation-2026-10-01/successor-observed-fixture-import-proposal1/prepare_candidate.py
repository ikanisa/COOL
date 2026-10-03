#!/usr/bin/env python3
"""UNEXECUTED preparation proposal. Root must review/authorize before invocation.

Copies only into a new private child stage. Never runs tests, providers, Docker,
SQL or deployment, and never changes maintained inputs or substitutes fixtures.
"""
import hashlib
import json
import os
from pathlib import Path
import stat

PACKET = Path(__file__).resolve().parent
ROOT = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
STAGE = PACKET / 'candidate-stage1'
seen = {}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def identity(s):
    return [s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns,
            stat.S_IMODE(s.st_mode), s.st_nlink]


def read_guard(row):
    p = Path(row['path'])
    for part in [p, *p.parents]:
        if part.is_symlink():
            raise ValueError('BUSY/UNSAFE symlink input: ' + str(part))
    s = p.lstat()
    if not stat.S_ISREG(s.st_mode) or s.st_nlink != 1:
        raise ValueError('Single-link regular input required: ' + str(p))
    if identity(s) != row['identity']:
        raise ValueError('BUSY input identity changed since proposal: ' + str(p))
    fd = os.open(p, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        if identity(os.fstat(fd)) != row['identity']:
            raise ValueError('BUSY input before read: ' + str(p))
        pieces = []
        while True:
            data = os.read(fd, 1024 * 1024)
            if not data:
                break
            pieces.append(data)
        data = b''.join(pieces)
        if identity(os.fstat(fd)) != row['identity']:
            raise ValueError('BUSY input during read: ' + str(p))
    finally:
        os.close(fd)
    if identity(p.lstat()) != row['identity'] or sha(data) != row['sha256']:
        raise ValueError('BUSY input changed during read: ' + str(p))
    seen[str(p)] = row
    return data


def exclusive_write(path, data, mode):
    if not path.is_relative_to(STAGE):
        raise ValueError('Private stage containment required')
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    for part in [path.parent, *path.parent.parents]:
        if part.is_symlink():
            raise ValueError('Unsafe stage parent')
        if part == STAGE:
            break
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, mode)
    try:
        with os.fdopen(fd, 'wb', closefd=False) as stream:
            stream.write(data)
            stream.flush()
            os.fsync(fd)
        os.fchmod(fd, mode)
    finally:
        os.close(fd)
    if sha(path.read_bytes()) != sha(data):
        raise ValueError('Private physical copy readback mismatch: ' + str(path))


def dynamic_membership():
    paths = list((ROOT/'supabase/functions').rglob('*.ts'))
    paths += list((ROOT/'supabase/functions').rglob('fixtures/*.json'))
    for pattern in ('*.py','requirements.*','Dockerfile'):
        paths += list((ROOT/'tools/roster-decoder').glob(pattern))
    for rel in ('contracts/collect-android-attempt-archive-v3/fixtures',
                'contracts/collect-android-dispatch-v2/fixtures'):
        paths += list((ROOT/rel).glob('*.json'))
    return sorted(str(p.relative_to(ROOT)) for p in set(paths))


def require_absent(plan):
    for row in plan['tool_guards']:
        requested = Path(row['requested_path'])
        if requested.resolve(strict=True) != Path(row['resolved_path']):
            raise ValueError('BUSY requested tool resolution changed')
        if identity(requested.lstat()) != row['requested_identity']:
            raise ValueError('BUSY requested tool link/file identity changed')
    for row in plan['ten_exact_imports']:
        if os.path.lexists(ROOT/row['destination']):
            raise ValueError('BUSY maintained fixture destination appeared: ' + row['destination'])
    if dynamic_membership() != plan['dynamic_membership']:
        raise ValueError('BUSY source membership changed since proposal')


def main():
    plan = json.loads((PACKET/'preparation-plan.json').read_bytes())
    if os.path.lexists(STAGE):
        raise ValueError('Exclusive NEW stage required; leave any prior result intact')
    for part in [PACKET, *PACKET.parents]:
        if part.is_symlink():
            raise ValueError('Unsafe packet parent')
    require_absent(plan)
    # Preflight every source, ten origin/corroborating copies, tools and13inputs.
    data = {row['path']: read_guard(row) for row in plan['all_read_guards']}
    require_absent(plan)
    STAGE.mkdir(mode=0o700)
    try:
        source_before = {}
        for rel, row in plan['current_source144'].items():
            body = data[row['path']]
            exclusive_write(STAGE/'baseline-source'/rel, body, row['identity'][5])
            proposed = data[plan['loader_candidate']['path']] if rel == plan['loader_destination'] else body
            exclusive_write(STAGE/'source'/rel, proposed, row['identity'][5])
            source_before[rel] = row['sha256']
        for row in plan['ten_exact_imports']:
            # Exact producer bytes; no JSON parsing, serialization or transformation.
            body = data[row['original']['path']]
            if any(data[c['path']] != body for c in row['corroborating_copies']):
                raise ValueError('Source/consumer fixture byte disagreement')
            exclusive_write(STAGE/'source'/row['destination'], body, 0o644)
        for row in plan['offline_inputs13']:
            exclusive_write(STAGE/'inputs'/row['destination'], data[row['guard']['path']], row['guard']['identity'][5])
        require_absent(plan)
        for row in seen.values():
            read_guard(row)
        expected = {rel:row['sha256'] for rel,row in plan['current_source144'].items()}
        expected[plan['loader_destination']] = plan['loader_candidate']['sha256']
        expected.update({row['destination']:row['original']['sha256'] for row in plan['ten_exact_imports']})
        actual = {str(p.relative_to(STAGE/'source')):sha(p.read_bytes())
                  for p in (STAGE/'source').rglob('*') if p.is_file()}
        if actual != expected or len(actual) != plan['proposed_source_count']:
            raise ValueError('Candidate exact154 source/hash/membership disagreement')
        receipt = {'status':'prepared_only','maintained_source_before_after_equal':True,
                   'maintained_mutations':0,'runtime_tests_executed':0,'current_source_count':len(source_before),
                   'proposed_source_count':len(actual),'exact_observations_copied':len(plan['ten_exact_imports']),
                   'offline_inputs_copied':len(plan['offline_inputs13']),
                   'source_before':source_before,'candidate_source':actual,
                   'current_sql_executed':False,'external_operations':False}
        exclusive_write(STAGE/'preparation-result.json',(json.dumps(receipt,indent=2)+'\n').encode(),0o600)
    except BaseException as exc:
        # Keep bounded private partial output for review; never roll back others.
        exclusive_write(STAGE/'REFUSED.json',(json.dumps({'status':'refused_busy_or_invalid',
            'error':str(exc),'maintained_mutations':0,'runtime_tests_executed':0})+'\n').encode(),0o600)
        raise


if __name__ == '__main__':
    main()
