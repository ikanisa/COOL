#!/usr/bin/env python3
"""Freeze the essential source candidate once; execute no test or build."""
from pathlib import Path
import argparse
import datetime
import hashlib
import importlib.util
import json
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
DEST = Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/collect-essential-source-candidate-20261001')
ZIP = DEST.with_suffix('.zip')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def finalize(native_manifest, native_directory, evidence_index):
    """Seal captured source plus reviewed native corrections, not a moving checkout."""
    destination = DEST.with_name(DEST.name + '-final')
    archive_path = destination.with_suffix('.zip')
    if destination.exists() or archive_path.exists():
        raise ValueError('Refusing to replace a final candidate')
    sources = json.loads((DEST / 'CANDIDATE_SOURCE_SHA256.json').read_text())
    native = json.loads(native_manifest.read_text())
    evidence = json.loads(evidence_index.read_text())
    if evidence.get('native_final_acceptance_pass') is not True:
        raise ValueError('Final native acceptance is required before sealing')
    for row in evidence['bindings']:
        path = ROOT / row['path']
        if path.is_symlink() or sha(path) != row['sha256']:
            raise ValueError('Handover evidence changed: ' + row['path'])
    # Preserve the stronger captured SIM/expiry fences and V2 fixture. Only the
    # marker ordering and test-only JSON Gradle corrections may change here.
    overlays = {'android/app/build.gradle.kts'}
    for name, digest in sources.items():
        original = DEST / name
        if original.is_symlink() or sha(original) != digest:
            raise ValueError('Captured source is not immutable: ' + name)
        if name.startswith('android/') and name not in overlays:
            if native.get(name) != digest:
                raise ValueError('Native acceptance and candidate disagree: ' + name)
    for name in overlays:
        path = native_directory / name
        if path.is_symlink() or sha(path) != native.get(name):
            raise ValueError('Native correction lacks an exact binding: ' + name)
    for name, digest in evidence['candidate_acceptance_sources'].items():
        actual = native[name] if name in overlays else sources.get(name)
        if actual != digest:
            raise ValueError('Affected acceptance does not bind candidate: ' + name)
    destination.mkdir(parents=True)
    delta = {}
    for name, digest in sources.items():
        source = native_directory / name if name in overlays else DEST / name
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        actual = sha(target)
        expected = native[name] if name in overlays else digest
        if actual != expected or sha(source) != expected:
            raise ValueError('Final candidate source changed: ' + name)
        if actual != digest:
            delta[name] = {'captured_sha256': digest, 'final_sha256': actual}
        sources[name] = actual
    manifest = destination / 'CANDIDATE_SOURCE_SHA256.json'
    manifest.write_text(json.dumps(sources, indent=2, sort_keys=True) + '\n')
    shutil.copy2(evidence_index, destination / 'CANDIDATE_EVIDENCE_INDEX.json')
    for row in evidence['bindings']:
        target = destination / row['path']
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / row['path'], target)
        if sha(target) != row['sha256']:
            raise ValueError('Copied evidence changed: ' + row['path'])
    (destination / 'CANDIDATE_README.md').write_text(
        '# Collect essential source candidate\n\n'
        'Frozen captured source plus verified Gateway marker/test-runtime corrections. '
        'SIM, fresh-expiry and V2 protocol safeguards are preserved. The evidence index '
        'names the accepted scopes and retained failures; it does not assert a new '
        'whole-suite pass or equality to the concurrently edited shared checkout.\n\n'
        'Inter and its OFL notice are included. Provider credentials, signing inputs, '
        'caches and proprietary website font binaries are excluded.\n\n'
        'Production remains NO-GO. Hosted activation, provider, signing, physical '
        'device/carrier, store and full design acceptance remain separate.\n'
    )
    with zipfile.ZipFile(archive_path, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(p for p in destination.rglob('*') if p.is_file()):
            archive.write(path, 'collect-essential-source/' + path.relative_to(destination).as_posix())
    with zipfile.ZipFile(archive_path) as archive:
        assert archive.testzip() is None
        for name, digest in sources.items():
            assert hashlib.sha256(archive.read('collect-essential-source/' + name)).hexdigest() == digest
        for row in evidence['bindings']:
            assert hashlib.sha256(archive.read('collect-essential-source/' + row['path'])).hexdigest() == row['sha256']
    result = {
        'status': 'frozen_scoped_source_candidate',
        'created_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'directory': str(destination), 'zip': str(archive_path),
        'zip_sha256': sha(archive_path), 'zip_bytes': archive_path.stat().st_size,
        'source_file_count': len(sources), 'source_manifest_sha256': sha(manifest),
        'reviewed_native_delta': delta, 'all_declared_archive_source_bytes_verified': True,
        'evidence_index_sha256': sha(evidence_index),
        'bound_evidence_file_count': len(evidence['bindings']),
        'shared_checkout_equality_claimed': False,
        'stronger_captured_runtime_fences_preserved': True,
        'production_release_authorized': False, 'builds_or_tests_executed_by_packager': False,
    }
    (OUT / 'source-candidate-final.json').write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps(result))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--final-native-manifest', type=Path)
    parser.add_argument('--final-native-directory', type=Path)
    parser.add_argument('--evidence-index', type=Path)
    args = parser.parse_args()
    if args.final_native_manifest:
        if not args.final_native_directory or not args.evidence_index:
            raise ValueError('Final native directory and evidence index are required')
        return finalize(args.final_native_manifest, args.final_native_directory, args.evidence_index)
    if DEST.exists() or ZIP.exists():
        raise ValueError('Refusing to replace a frozen candidate')
    module_path = ROOT / 'scripts/qa/native_source_export.py'
    spec = importlib.util.spec_from_file_location('native_export', module_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    export = module.export(ROOT, DEST)
    files = export['source_sha256']
    names = subprocess.check_output(
        ['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=ROOT,
    ).decode().split('\0')
    extra_roots = ('supabase/', 'tools/', 'scripts/', '.github/')
    extra_files = {
        'Makefile', 'README.md', 'Gemfile', 'Gemfile.lock', '.gitleaks.toml',
        'docs/PRODUCT.md',
    }
    for name in sorted(set(names)):
        if not name or name in files or not (name.startswith(extra_roots) or name in extra_files):
            continue
        path = Path(name)
        if path.name in module.PRIVATE_NAMES or path.name.startswith('.env') or path.suffix.lower() in {
            '.jks', '.keystore', '.p12', '.pfx', '.p8', '.pem', '.key', '.mobileprovision',
        }:
            continue
        source = ROOT / path
        if not source.is_file():
            continue
        if source.is_symlink() or ROOT not in source.resolve().parents:
            raise ValueError('Candidate source must be a regular checkout file: ' + name)
        digest = sha(source)
        target = DEST / path
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        if sha(target) != digest or sha(source) != digest:
            raise ValueError('Source changed during candidate export: ' + name)
        files[name] = digest
    assert not any('AeonikPro-' in name for name in files)
    assert 'assets/typefaces/Inter-Variable.ttf' in files
    assert 'assets/typefaces/OFL-Inter.txt' in files
    assert 'android/gradle/CollectPluginRegistrant.java' in files
    assert 'supabase/migrations/20261001120000_operational_exception_lifecycle.sql' in files
    manifest = DEST / 'CANDIDATE_SOURCE_SHA256.json'
    manifest.write_text(json.dumps(files, indent=2, sort_keys=True) + '\n')
    (DEST / 'CANDIDATE_README.md').write_text(
        '# Collect essential source candidate\n\n'
        'Frozen local source, including member, Admin, public and internal Gateway '
        'entrypoints, server migrations/functions and operations tooling.\n\n'
        'Inter and its OFL notice are bundled. Website-derived proprietary font '
        'binaries, ignored caches, provider secrets and signing material are excluded.\n\n'
        'Use the lockfiles and pinned SDK. Provider configuration, database deployment, '
        'signing, physical-device/carrier and store acceptance require their own release '
        'evidence. This is a source candidate, not an authorized production release.\n'
    )
    with zipfile.ZipFile(ZIP, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(p for p in DEST.rglob('*') if p.is_file()):
            archive.write(path, 'collect-essential-source/' + path.relative_to(DEST).as_posix())
    drift = {name: sha(ROOT / name) if (ROOT / name).is_file() else None
             for name, digest in files.items() if not (ROOT / name).is_file() or sha(ROOT / name) != digest}
    if drift:
        raise ValueError('Source changed after freeze: ' + json.dumps(drift))
    with zipfile.ZipFile(ZIP) as archive:
        assert archive.testzip() is None
        for name, digest in files.items():
            assert hashlib.sha256(archive.read('collect-essential-source/' + name)).hexdigest() == digest
    result = {
        'status': 'frozen_source_candidate',
        'created_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'source_file_count': len(files), 'source_manifest_sha256': sha(manifest),
        'directory': str(DEST), 'zip': str(ZIP), 'zip_sha256': sha(ZIP),
        'zip_bytes': ZIP.stat().st_size, 'source_drift': drift,
        'ignored_or_private_provider_signing_inputs_copied': False,
        'proprietary_website_font_binaries_included': False,
        'all_declared_archive_source_bytes_verified': True,
        'builds_or_tests_executed_by_packager': False,
        'production_release_authorized': False,
    }
    (OUT / 'source-candidate.json').write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
