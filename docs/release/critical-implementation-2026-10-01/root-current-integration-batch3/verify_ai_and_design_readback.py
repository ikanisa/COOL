#!/usr/bin/env python3
"""Independent readback; keeps whole-finding and whole-machine limits explicit."""
import datetime
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
BASE = HERE.parent
REPORT = Path('/Volumes/PRO-G40/Application Data/Codex/Codex-Home/reports/design-skill-removal-20261001')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def checked_row(row):
    path = Path(row['path'])
    if not path.is_absolute():
        path = REPO / path
    assert path.is_file() and not path.is_symlink(), str(path)
    assert path.stat().st_size == row['bytes'], str(path)
    assert sha(path) == row['sha256'], str(path)


def packet(name, expected):
    directory = BASE / name
    assert sha(directory / 'batch.json') == expected
    batch = json.loads((directory / 'batch.json').read_text())
    index = batch['evidence_index']
    assert sha(REPO / index['path']) == index['sha256']
    rows = json.loads((REPO / index['path']).read_text())['files']
    for row in rows:
        checked_row(row)
    return batch, len(rows)


def main():
    audit, audit_leaves = packet('ai-import-review-batch1', '0c385cc5cbcc1d4b95af547552c547ec5d55e03ab481f8bd25e268ffaf287933')
    fixed, fixed_leaves = packet('ai-import-minimization-batch1', 'b93aba57fc4910882b13eb17508d7242c9ad102b6c25b7aef1957cb178adcc7e')
    assert audit_leaves == 9 and fixed_leaves == 77
    for row in fixed['source_current']:
        checked_row(row)
    current = json.loads((BASE / 'ai-import-minimization-batch1/corrected-source/result.json').read_text())
    prior = json.loads((BASE / 'ai-import-minimization-batch1/old-source-negative-attempt2/result.json').read_text())
    assert current['test_summaries'] == [{'passed': 109, 'failed': 0}]
    assert prior['test_summaries'] == [{'passed': 107, 'failed': 2}]
    assert [phase['exit_code'] for phase in current['phases']] == [0, 0, 1]
    assert current['status'] == 'fail'  # The complete scoped recipe retained genuine baseline lint failure.
    assert current['source_unchanged'] and current['bindings_unchanged']
    assert current['external_cache_before'] == current['external_cache_after']
    assert len(current['external_cache_after']) == 87
    for path, row in current['external_cache_after'].items():
        checked_row({'path': path, **row})
    paths = json.loads((REPORT / 'cleanup-owner-request-readback.json').read_text())['removed_path_readbacks']
    assert len(paths) == 141
    remaining = [row['path'] for row in paths if Path(row['path']).exists() or Path(row['path']).is_symlink()]
    assert remaining == []
    selected = Path('/Volumes/PRO-G40/Application Data/Codex/Codex-Home/skills/revolut-design/SKILL.md')
    assert sha(selected) == '0941cf390b2e77d605ee4877f960440688166534341ae2a3239a990d40127c50'
    assert not (selected.parent / 'references/mobile-design-100.md').exists()
    assert sha(REPO / 'AGENTS.md') == '0160399e0988796783edb29da32732926fa0d569dc5edb718fc0ba3735288497'
    output = {
        'checked_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'ai_audit_leaves': audit_leaves,
        'ai_minimization_leaves': fixed_leaves,
        'current_local_import_closure': len(fixed['source_current']),
        'current_remote_dependency_bytes_checked': 87,
        'corrected_tests': {'passed': 109, 'failed': 0},
        'old_production_source_same_tests': {'passed': 107, 'failed': 2},
        'compile_and_test_exit_zero': True,
        'full_three_file_default_lint_exit': 1,
        'unchanged_baseline_require_await_errors': 3,
        'whole_BE13_closed': False,
        'provider_calls': 0,
        'design_removed_paths_checked': 141,
        'remaining_removed_paths': remaining,
        'selected_revolut_sha256': sha(selected),
        'retired_checklist_absent': True,
        'AGENTS_sha256': sha(REPO / 'AGENTS.md'),
        'scope_limits': 'Recorded competing design paths and current selected instruction only; existing broad scan protected/pruned/inaccessible limits remain. Current AI minimization regression proof is separate from vendor, region, retention, hosted, spend, semantic accuracy and Admin disclosure approval. No whole-machine or production acceptance claim.',
        'errors': [],
    }
    with (HERE / 'ai-design-independent-readback.json').open('x') as stream:
        json.dump(output, stream, indent=2, sort_keys=True)
        stream.write('\n')
    print(json.dumps({key: output[key] for key in ['ai_audit_leaves', 'ai_minimization_leaves', 'current_local_import_closure', 'current_remote_dependency_bytes_checked', 'design_removed_paths_checked', 'remaining_removed_paths', 'full_three_file_default_lint_exit', 'errors']}))


if __name__ == '__main__':
    main()
