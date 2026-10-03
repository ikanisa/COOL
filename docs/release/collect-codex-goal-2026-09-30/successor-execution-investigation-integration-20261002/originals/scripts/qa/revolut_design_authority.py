#!/usr/bin/env python3
"""Check sole-authority hygiene without awarding visual acceptance."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
from pathlib import Path

DEFAULT_SKILL = Path(
    '/Volumes/PRO-G40/Application Data/Codex/Codex-Home/skills/revolut-design'
)
SCOPES = {'member_app', 'admin', 'public_website'}
RETIRED_FILES = {
    'design-qa.md',
    'ADMIN_DESIGN_QA_2026-09-03.md',
    'LEGACY_DESIGN_ERADICATION_AUDIT_2026-08-05.md',
    'mobile-parity-contract.json',
    'collect-design-contract.json',
    'public-design-contract.json',
}
RETIRED_IMAGE_PATHS = {
    'output/admin-redesign/concepts/01.png',
    'output/admin-redesign/concepts/02.png',
    'output/admin-redesign/concepts/03.png',
    'output/admin-redesign/qa/reference-normalized-1440x1024.png',
    'output/admin-redesign/qa/reference-vs-implementation-final.png',
    'output/admin-redesign/qa/reference-vs-implementation-focus.png',
}
PRUNED = {'.git', 'node_modules', '.dart_tool', '.gradle', 'build', 'Pods',
          'third_party', '__pycache__'}


def check(root: Path, skill: Path | None = None) -> dict:
    failures = []
    authority_file = root / 'docs/release/revolut-design/authority.json'
    try:
        adapter = json.loads(authority_file.read_text())
    except (OSError, ValueError):
        adapter = {}
        failures.append('missing_or_invalid_authority_adapter')
    if adapter.get('design_authority') != 'revolut-design':
        failures.append('competing_design_authority')
    if set(adapter.get('scope', [])) != SCOPES:
        failures.append('incomplete_surface_scope')
    for key in ['authority_sha256']:
        if not re.fullmatch(r'[0-9a-f]{64}', str(adapter.get(key, ''))):
            failures.append('invalid_' + key)
    # The source package owns these references. An adapter cannot silently
    # redirect a platform to another repository or a generated mockup.
    expected_references = {
        'member_app': ['references/mobile-patterns.md',
                       'references/screen-typologies.md',
                       'references/current-native-atlas.md'],
        'admin': ['references/web-patterns.md',
                  'references/component-contracts.md',
                  'references/source-and-mac-validation.md'],
        'public_website': ['references/web-patterns.md',
                           'references/tokens.md',
                           'references/state-theme-desktop-followup.md'],
    }
    if adapter.get('surface_references') != expected_references:
        failures.append('invalid_platform_reference_adapter')
    try:
        rules = (root / 'AGENTS.md').read_text()
    except OSError:
        rules = ''
    if '`revolut-design`' not in rules or 'sole design authority' not in rules:
        failures.append('missing_sole_authority_working_rule')

    observed_skill = 'not_requested'
    if skill is not None:
        observed_skill = 'verified'
        for relative, key in [('SKILL.md', 'authority_sha256')]:
            try:
                actual = hashlib.sha256((skill / relative).read_bytes()).hexdigest()
            except OSError:
                failures.append('unavailable_skill_file:' + relative)
                observed_skill = 'unverified'
                continue
            if actual != adapter.get(key):
                failures.append('authority_revision_changed:' + relative)
                observed_skill = 'unverified'

    retired = []
    competing = []
    files = 0
    # Include ignored local exports: deletion of a tracked report alone must
    # not leave its competing reference copy available in this checkout.
    for folder, dirs, names in os.walk(root, followlinks=False):
        dirs[:] = [name for name in dirs if name not in PRUNED and
                   not (Path(folder) / name).is_symlink()]
        for name in names:
            path = Path(folder) / name
            relative = path.relative_to(root).as_posix()
            if name in RETIRED_FILES or relative in RETIRED_IMAGE_PATHS:
                retired.append(relative)
            if path.suffix.lower() not in {'.md', '.json', '.yaml', '.yml'}:
                continue
            if relative.startswith(('scripts/tests/', 'test/', 'tools/')):
                continue
            if path.is_symlink():
                competing.append(relative + ':symlinked_reference')
                continue
            files += 1
            try:
                if path.stat().st_size > 8 * 1024 * 1024:
                    continue
                text = path.read_text(errors='strict')
            except (OSError, UnicodeError):
                failures.append('unreadable_reference:' + relative)
                continue
            # Toolkit names, product screenshots and provenance citations are
            # legitimate. Detect declarations of another authority, rather
            # than rejecting every occurrence of the word "design".
            for match in re.finditer(
                r'"design_authority"\s*:\s*"([^"]+)"', text
            ):
                if match.group(1) != 'revolut-design':
                    competing.append(relative + ':design_authority')
            if 'adaptive-product-design' in text:
                competing.append(relative + ':retired_design_skill')
    if retired:
        failures.append('retired_design_references_present')
    if competing:
        failures.append('competing_reference_declarations_present')
    return {
        'status': 'pass' if not failures else 'fail',
        'design_authority': 'revolut-design',
        'scope': sorted(SCOPES),
        'skill_revision_check': observed_skill,
        'reference_files_scanned': files,
        'retired_references': sorted(retired),
        'competing_declarations': sorted(set(competing)),
        'failures': sorted(set(failures)),
        'visual_acceptance': 'unverified',
        'meaning': 'Reference hygiene only; no route/state fidelity percentage.',
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--skill-root', type=Path)
    parser.add_argument('--verify-skill', action='store_true')
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args()
    skill = args.skill_root or (DEFAULT_SKILL if args.verify_skill else None)
    result = check(args.root.resolve(), skill)
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print('[revolut-design-authority] ' + result['status'])
        for failure in result['failures']:
            print('  ' + failure)
        for path in result['retired_references'] + result['competing_declarations']:
            print('  ' + path)
    raise SystemExit(0 if result['status'] == 'pass' else 1)


if __name__ == '__main__':
    main()
