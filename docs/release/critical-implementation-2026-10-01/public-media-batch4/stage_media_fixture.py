#!/usr/bin/env python3
"""Copy the complete maintained browser media graph as unapproved QA evidence.

This is never a broad release candidate. Uses the maintained release tooling's
regular reads and credential screening, and refuses source drift or exclusions.
"""
import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
import shutil
from datetime import datetime, timezone
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[4]
PACKET = Path(__file__).resolve().parent
SUPPORT = [
    'content/product/collect_capabilities.json',
    'scripts/product_capabilities.rb',
    'scripts/generate_product_capability_content.rb',
    'scripts/public_static_site_build.rb',
]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def cohort(directory):
    raw = subprocess.check_output([
        'ruby', '-r', './scripts/public_app_media', '-e',
        'puts JSON.generate(PublicAppMedia.new(Dir.pwd).browser_source_snapshot)',
    ], cwd=directory)
    return json.loads(raw)


def write(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def main():
    destination = Path(sys.argv[1]).absolute()
    receipt = PACKET / (sys.argv[2] if len(sys.argv) > 2 else 'media-fixture-stage.json')
    if receipt.parent != PACKET:
        raise ValueError('Fixture receipt must stay in the existing evidence packet')
    if destination.exists() or destination == ROOT or ROOT in destination.parents:
        raise ValueError('Fresh outside-checkout media fixture required')
    if any(path.is_symlink() for path in [destination, *destination.parents]):
        raise ValueError('Media fixture destination aliases refused')
    source_tool = ROOT / 'scripts/qa/collect_release_candidate.py'
    spec = importlib.util.spec_from_file_location('safe_release_source_reads', source_tool)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    before = cohort(ROOT)
    source_names = sorted(set(before) | set(SUPPORT))
    destination.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix='.collect-media-fixture-', dir=destination.parent))
    record = {
        'kind': 'unapproved_current_media_fixture_source_stage',
        'scope': 'Complete maintained browser fixture source closure, plus four explicitly separate product-content review inputs. This is not a broad release export or full-app/source acceptance.',
        'started_at_utc': datetime.now(timezone.utc).isoformat(),
        'source_root': str(ROOT),
        'destination': str(destination),
        'copy_safety_tool': 'scripts/qa/collect_release_candidate.py',
        'copy_safety_tool_sha256': digest(source_tool.read_bytes()),
        'status': 'running',
        'browser_sources_before': before,
        'support_inputs': SUPPORT,
        'source_files': {},
        'approvals': dict(module.NO_APPROVAL),
        'broad_strict_release_export_required': True,
        'private_or_ignored_inputs_copied': False,
    }
    try:
        for name in source_names:
            if module.exclusion(name) is not None:
                raise ValueError('Required media input excluded: ' + name)
            data, mode = module.regular_bytes(ROOT, name)
            module.screen_credentials(data, name)
            expected = before.get(name)
            if expected is not None and digest(data) != expected:
                raise ValueError('Media source changed during copy: ' + name)
            record['source_files'][name] = {'sha256': digest(data), 'bytes': len(data), 'mode': mode}
            target = stage / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            target.chmod(mode)
            copied, copied_mode = module.regular_bytes(stage, name)
            if digest(copied) != digest(data) or copied_mode != mode:
                raise ValueError('Media copy readback differs: ' + name)
        after = cohort(ROOT)
        staged = cohort(stage)
        if before != after or before != staged:
            raise ValueError('Complete media source cohort changed during staging')
        for name, expected in record['source_files'].items():
            current, mode = module.regular_bytes(ROOT, name)
            if digest(current) != expected['sha256'] or mode != expected['mode']:
                raise ValueError('Media/support source changed before final readback: ' + name)
        record.update({
            'status': 'pass',
            'finished_at_utc': datetime.now(timezone.utc).isoformat(),
            'browser_sources_after': after,
            'staged_browser_sources': staged,
            'browser_sources_unchanged': True,
            'copied_source_file_count': len(record['source_files']),
            'browser_source_file_count': len(before),
            'runtime_sha256': digest(''.join(name + '\0' + value + '\n' for name, value in before.items()).encode()),
        })
        write(stage / '.collect-media-fixture-source.json', record)
        stage.rename(destination)
        record['stage_manifest_sha256'] = digest((destination / '.collect-media-fixture-source.json').read_bytes())
        write(receipt, record)
        print(json.dumps({key: record[key] for key in ['status', 'kind', 'destination', 'browser_source_file_count', 'copied_source_file_count', 'runtime_sha256', 'stage_manifest_sha256']}))
    except Exception as error:
        record.update({'status': 'blocked', 'error': str(error), 'partial_stage_preserved': str(stage)})
        write(receipt, record)
        raise
    finally:
        # A failed attempt's safe partial fixture and receipt remain retained.
        # Successful stages have already been atomically renamed.
        pass


if __name__ == '__main__':
    main()
