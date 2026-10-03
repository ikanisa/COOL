#!/usr/bin/env python3
"""Freeze the admitted 216 inputs and observed reference; no Docker calls."""
from pathlib import Path
import hashlib
import json
import shutil
import stat

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
CANDIDATE = Path('/Users/jeanbosco/Library/Caches/COOL-ORDINARY-RECOVERY/20261002-candidate1')
PRIOR = HERE.parent / 'ordinary-schema-catalog209-preparation1/candidate-inputs.json'
REFERENCE = HERE.parent / 'ordinary-schema-catalog209-execution1'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def regular(path):
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or path.is_symlink() or info.st_nlink != 1:
        raise ValueError('Regular single-link source required: ' + str(path))
    body = path.read_bytes()
    after = path.lstat()
    if (info.st_ino, info.st_size, info.st_mtime_ns) != (after.st_ino, after.st_size, after.st_mtime_ns):
        raise ValueError('Source changed during read')
    return body


def main():
    if CANDIDATE.exists() or (HERE / 'inputs.json').exists():
        raise ValueError('Fresh candidate and manifest required')
    prior = json.loads(regular(PRIOR))
    sources = {name: row['sha256'] for name, row in prior['sources'].items()}
    if len(sources) != 216 or sum(name.startswith('supabase/migrations/') for name in sources) != 209:
        raise ValueError('Exact admitted 216-input/209-migration cohort required')
    proof = json.loads(regular(REFERENCE / 'observed-output/result.json'))
    execution = json.loads(regular(REFERENCE / 'execution-result.json'))
    if proof['status'] != 'pass' or len(proof['cases']) != 37 or execution['status'] != 'pass':
        raise ValueError('Actual current209 proof must pass')
    if execution['source_before'] != sources or execution['source_after'] != sources:
        raise ValueError('Reference proof is not bound to the admitted inputs')
    captured = Path(prior['candidate'])
    CANDIDATE.mkdir(mode=0o700, parents=True)
    for name, digest in sources.items():
        body = regular(ROOT / name)
        if sha(body) != digest or regular(captured / name) != body:
            raise ValueError('Admitted input drift: ' + name)
        destination = CANDIDATE / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(body)
        destination.chmod(0o600)
    references = {}
    for name in ['observed-output/result.json', 'execution-result.json',
                 'observed-output/ordinary_populated/predecessor-effective-catalog.json',
                 'observed-output/ordinary_populated/final-effective-catalog.json']:
        body = regular(REFERENCE / name)
        destination = CANDIDATE / 'reference' / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(body)
        destination.chmod(0o600)
        references['reference/' + name] = sha(body)
    final = references['reference/observed-output/ordinary_populated/final-effective-catalog.json']
    if final != '4516b26ba34a426a2d97af40e7f2675d9a8f55de274f159b6da40fded1c0084c':
        raise ValueError('Exact observed current209 catalog required')
    manifest = dict(kind='collect_ordinary_recovery_frozen_inputs_v1', status='prepared_only',
        candidate=str(CANDIDATE), sources=sources, references=references,
        reference_packet=str(REFERENCE), reference_cases=37, migration_count=209,
        predecessor_count=124, forward_count=85, synthetic_projection_count=18,
        whole_deadline_seconds=600, execution_done=False, maintained_source_mutations=0,
        shipping_restore_admission=False)
    (HERE / 'inputs.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps({key: manifest[key] for key in ['status', 'migration_count', 'predecessor_count', 'forward_count', 'execution_done']}))


if __name__ == '__main__':
    main()
