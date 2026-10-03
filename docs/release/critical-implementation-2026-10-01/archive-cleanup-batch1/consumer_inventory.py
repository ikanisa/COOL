#!/usr/bin/env python3
"""Index release references in maintained code without reproducing file bodies."""
import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
PACKET = Path(__file__).resolve().parent
roots = [name for name in ['scripts', 'lib', 'test', 'test_driver', 'tool', 'tools', '.github', 'android', 'ios', 'packages'] if (ROOT / name).is_dir()]
listed = subprocess.check_output(['rg', '--files', '--hidden', *roots], cwd=ROOT).decode().splitlines()
listed += [name for name in ['Makefile', '.gitignore', 'AGENTS.md'] if (ROOT / name).is_file()]
extensions = {'.py', '.rb', '.sh', '.mjs', '.cjs', '.js', '.ts', '.dart', '.yml', '.yaml', '.gradle', '.kt', '.swift', '.json'}
rows = []
skips = []
files_checked = 0
for name in sorted(set(listed)):
    path = ROOT / name
    if path.suffix not in extensions and path.name not in {'Makefile', '.gitignore', 'AGENTS.md'}:
        continue
    try:
        if path.is_symlink() or path.stat().st_size > 1048576:
            skips.append({'path': name, 'reason': 'alias_or_larger_than_1MiB'})
            continue
        before = path.stat()
        data = path.read_bytes()
        after = path.stat()
        if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
            skips.append({'path': name, 'reason': 'changed_during_read'})
            continue
        files_checked += 1
        text = data.decode('utf-8')
    except (OSError, UnicodeError) as error:
        skips.append({'path': name, 'reason': type(error).__name__})
        continue
    matches = []
    for line_number, line in enumerate(text.splitlines(), 1):
        if 'docs/release' not in line:
            continue
        references = re.findall(r'docs/release/[A-Za-z0-9_./{}$+*?%=-]*', line)
        for reference in references or ['docs/release']:
            target = ROOT / reference
            dynamic = any(char in reference for char in '{}$+*?%=') or reference == 'docs/release' or reference.endswith('/')
            nearby = '\n'.join(text.splitlines()[max(0, line_number-3):line_number+2])
            role = 'potential_reader_or_validation_contract' if re.search(r'read|load|fetch|verify|validate|fixture|expect|SOURCE|BASELINE|CURRENT|contract', nearby, re.I) else 'writer_or_other_reference_needs_review'
            matches.append({'line': line_number, 'reference': reference, 'dynamic_or_directory': dynamic,
                            'exact_target_exists': target.exists() if not dynamic else None, 'role': role})
    if matches:
        rows.append({'consumer': name, 'consumer_sha256': hashlib.sha256(data).hexdigest(), 'references': matches})
result = {'schema_version': 1, 'scope': 'Maintained source/test/runtime/CI release references; path/line inventory only, no file/customer/credential bodies copied.',
          'source_roots': roots, 'source_files_checked': files_checked, 'consumer_file_count': len(rows), 'consumers': rows,
          'skips': skips, 'limits': ['Static literal/directory reference scan; dynamic concatenation, indirectly imported metadata and arbitrary text-only report links need explicit review.', 'rg default ignore rules retained; ignored dependencies and generated builds are not maintained-code consumers.', 'Potential writer/reader labels are heuristics; deletion cannot proceed from them alone.'], 'removed_files': 0}
(PACKET / 'maintained-consumers.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({'source_files_checked': files_checked, 'consumer_file_count': len(rows), 'references': sum(len(row['references']) for row in rows), 'skips': len(skips)}))
