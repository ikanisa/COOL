#!/usr/bin/env python3
"""Fresh JVM termination/reopen tests on synthetic host directories, NOT device power loss."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--jar', type=Path, required=True)
    args = parser.parse_args()
    jar = args.jar.resolve()
    assert jar.is_file()
    checks: list[str] = []

    def run(*argv: str, expected: int = 0) -> dict:
        result = subprocess.run(['java', '-jar', str(jar), *argv], capture_output=True, text=True, timeout=30)
        assert result.returncode == expected, (argv, result.returncode, result.stdout, result.stderr)
        return json.loads(result.stdout) if result.stdout.strip() else {}

    def inventory(root: Path) -> dict[str, str]:
        return {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in root.iterdir() if p.is_file()}

    for phase in ('pending_created', 'pending_written', 'pending_forced', 'pending_directory_forced',
                  'published', 'published_directory_forced'):
        with tempfile.TemporaryDirectory(prefix='storage-process-fixture-') as folder:
            root = Path(folder)
            start = run('seed', folder)
            assert start['phase'] == 'ACTIVE'
            before = inventory(root)
            run('child', folder, phase, expected=73)
            after = inventory(root)
            assert all(after[name] == digest for name, digest in before.items())
            if phase.startswith('published'):
                status = run('status', folder)
                assert status['phase'] == 'WRITE_PENDING' and status['revision'] == start['revision'] + 1
            else:
                status = run('status', folder, expected=3)
                assert status['code'] == 'journal_pending_requires_recovery'
                if phase == 'pending_created':
                    refusal = run('inspect', folder, expected=3)
                    assert refusal['code'] == 'journal_record_size'
                    assert inventory(root) == after
                else:
                    candidate = run('inspect', folder)
                    assert candidate['phase'] == 'WRITE_PENDING'
                    promoted = run('promote', folder, candidate['sha256'])
                    assert promoted == candidate == run('status', folder)
            checks.append(f'fresh-jvm-halt-{phase}-reopen')

    with tempfile.TemporaryDirectory(prefix='storage-process-lock-') as folder:
        start = run('seed', folder)
        children = [subprocess.Popen(['java','-jar',str(jar),'race',folder,f'writer-{i}',start['sha256']],
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) for i in range(4)]
        results = []
        for child in children:
            try:
                stdout, stderr = child.communicate(timeout=30)
            except subprocess.TimeoutExpired:
                child.kill(); child.communicate(); raise
            assert not stderr, stderr
            results.append((child.returncode,json.loads(stdout)))
        assert sum(code == 0 for code, _ in results) == 1, results
        assert sum(code == 3 and value.get('code') == 'lifecycle_stale_checkpoint' for code,value in results) == 3, results
        final = run('status',folder)
        assert final['revision'] == start['revision']+1 and final['phase'] == 'WRITE_PENDING'
        checks.append('four-jvm-processes-exactly-one-checkpoint-winner')

    print(json.dumps({'status':'passed','checks':len(checks),'names':checks}))

if __name__ == '__main__':
    main()
