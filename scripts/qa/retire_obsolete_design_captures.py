#!/usr/bin/env python3
"""Move identified obsolete product renders outside the checkout, with hashes.

Current gallery images and source reference imagery are protected. This does
not remove executable test cases, acceptance findings or original references.
"""
import argparse
import hashlib
import json
import os
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--before', required=True)
    parser.add_argument('--current', required=True)
    parser.add_argument('--archive', required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    archive = Path(args.archive).resolve()
    if archive == ROOT or ROOT in archive.parents:
        raise ValueError('Retired captures must be outside the codebase')
    old = json.loads((ROOT / args.before).read_text())
    current = json.loads((ROOT / args.current).read_text())
    current_paths = {ROOT / card['evidence'] for card in current
                     if card.get('surface') == 'Mobile' and card.get('image')}
    protected = {sha(path) for path in current_paths if path.is_file()}
    protected |= {sha(path) for path in (ROOT / 'test/goldens/baselines').glob('*.png')}
    protected |= {sha(path) for path in (ROOT / 'assets').rglob('*') if path.is_file()}
    obsolete = {}
    for card in old:
        description = (card.get('check', '') + ' ' + card.get('variant', '')).lower()
        if card['surface'] != 'Mobile' or not (
                'historical' in description or card.get('kind') == 'Before correction'):
            continue
        path = ROOT / card['evidence']
        if path.is_file() and sha(path) not in protected:
            obsolete[sha(path)] = path.stat().st_size
    # Older native runs and pre-change golden folders may contain duplicate
    # versions that were no longer selected by the catalogue's latest-run rule.
    for manifest in (ROOT / '.cache').rglob('source-after.json'):
        if 'design' not in str(manifest.parent):
            continue
        for path in manifest.parent.rglob('*.png'):
            if 'reference' in str(path).lower() or path.is_symlink():
                continue
            digest = sha(path)
            if digest not in protected:
                obsolete[digest] = path.stat().st_size
    for folder in (ROOT / '.cache').rglob('goldens-before*'):
        for path in folder.glob('*.png'):
            digest = sha(path)
            if digest not in protected:
                obsolete[digest] = path.stat().st_size
    sizes = set(obsolete.values())
    retired = []
    for directory in ('.cache', 'test/goldens/failures', 'docs', 'build'):
        for parent, children, files in os.walk(ROOT / directory, followlinks=False):
            children[:] = [name for name in children
                           if name not in ('node_modules', '.git') and
                           not (Path(parent) / name).is_symlink()]
            for name in files:
                path = Path(parent) / name
                if path.is_symlink() or path.suffix.lower() not in ('.png', '.jpg', '.jpeg', '.webp'):
                    continue
                if '/references/' in str(path) or '/reference/' in str(path):
                    continue
                if path.stat().st_size not in sizes:
                    continue
                digest = sha(path)
                if digest not in obsolete:
                    continue
                relative = path.relative_to(ROOT)
                target = archive / relative
                retired.append({'path': str(relative), 'sha256': digest, 'archive_path': str(target)})
                if args.apply:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    if target.exists():
                        if sha(target) != digest:
                            raise ValueError('Archive collision: ' + str(target))
                        path.unlink()
                    else:
                        shutil.move(path, target)
    manifest = {'status': 'retired' if args.apply else 'preview', 'archive_root': str(archive),
                'files': retired, 'sha256': sorted(obsolete),
                'scope': 'Superseded product screenshots and duplicate bytes; current captures and reference imagery protected.'}
    if args.apply:
        (ROOT / 'docs/release/mobile-design/retired-design-assets.json').write_text(
            json.dumps(manifest, indent=2) + '\n')
    print(json.dumps({'status': manifest['status'], 'files': len(retired), 'unique_images': len(obsolete)}))


if __name__ == '__main__':
    main()
