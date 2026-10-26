"""Exact Admin candidate bundle seals; local evidence never grants acceptance."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
sys.path.insert(0, str(ROOT / 'scripts/tests'))
import admin_cloudflare_artifact as artifact
import admin_cloudflare_source as source
from test_admin_cloudflare_source import MIGRATION, create_source_tree, freeze_source


def create_candidate(build, frozen):
    """A complete finite postprocessed output with honest candidate metadata."""
    build.mkdir(parents=True)
    files = {
        'main.dart.js': b'compiled actual Admin JS fixture',
        'index.html': b'<title>Collect Admin</title>',
        'flutter_bootstrap.js': b'actual bootstrap fixture',
        'custom-sw.js': b'no-fetch retirement fixture',
        'flutter_service_worker.js': b'no-fetch retirement fixture',
        '_headers': b'/*\n  Referrer-Policy: no-referrer\n',
        'robots.txt': b'User-agent: *\nDisallow: /\n',
        'assets/FontManifest.json': b'[]',
        'assets/AssetManifest.bin': b'\x0d\x00',
        'assets/AssetManifest.bin.json': b'"DQA="',
        'assets/assets/typefaces/Inter-Variable.ttf': b'original licensed Inter font bytes',
        'canvaskit/canvaskit.wasm': b'actual runtime bytes',
        '.well-known/bounded-metadata.json': b'{"public":true}',
    }
    for name, content in files.items():
        path = build / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
    version = {'backend': 'cloudflare', 'source_commit': frozen['source_commit'],
               'source_dirty': frozen['source_dirty'], 'source_manifest_sha256': frozen['source_manifest_sha256'],
               'main_dart_js_sha256': hashlib.sha256(files['main.dart.js']).hexdigest(),
               'minimum_core_schema_migration': MIGRATION,
               'source_release_status': artifact.CANDIDATE_STATUS, 'operational_migration_complete': False}
    (build / 'version.json').write_text(json.dumps(version))
    return build


class AdminArtifactSealTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='collect-admin-artifact-test-', dir=Path(tempfile.gettempdir()).resolve())
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.working = create_source_tree(self.directory / 'working-source')
        self.source_manifest = self.directory / 'source.json'
        self.frozen = freeze_source(self.working, self.source_manifest)
        self.build = create_candidate(self.directory / 'admin-output', self.frozen)
        self.manifest = self.directory / 'artifact.json'

    def seal(self):
        return artifact.record_artifact(self.build, self.source_manifest, self.manifest)

    def test_full_output_seal_preserves_all_bytes_and_records_no_hosted_acceptance(self):
        before = {path.relative_to(self.build).as_posix(): path.read_bytes() for path in self.build.rglob('*') if path.is_file()}
        value = self.seal()
        self.assertEqual(sorted(before), [row['path'] for row in value['files']])
        self.assertEqual(before, {path.relative_to(self.build).as_posix(): path.read_bytes() for path in self.build.rglob('*') if path.is_file()})
        self.assertEqual(value, artifact.verify_artifact(self.build, self.source_manifest, self.manifest))
        self.assertFalse(value['hosted_acceptance_verified'])
        self.assertEqual('candidate_requires_hosted_acceptance', value['source_release_status'])
        self.assertIn('.well-known/bounded-metadata.json', {row['path'] for row in value['files']})
        self.assertNotIn('artifact.json', {row['path'] for row in value['files']})
        for row in value['files']:
            self.assertEqual(hashlib.sha256(before[row['path']]).hexdigest(), row['sha256'])
            self.assertEqual(len(before[row['path']]), row['bytes'])

    def test_bootstrap_headers_fonts_manifests_runtime_and_extra_files_cannot_drift(self):
        self.seal()
        for name in ('flutter_bootstrap.js', 'index.html', '_headers', 'assets/FontManifest.json', 'assets/AssetManifest.bin',
                     'assets/AssetManifest.bin.json', 'assets/assets/typefaces/Inter-Variable.ttf', 'canvaskit/canvaskit.wasm', '.well-known/bounded-metadata.json'):
            with self.subTest(name=name):
                path = self.build / name
                previous = path.read_bytes()
                path.write_bytes(previous + b'unaccepted drift')
                with self.assertRaises(artifact.ArtifactError):
                    artifact.verify_artifact(self.build, self.source_manifest, self.manifest)
                path.write_bytes(previous)
        extra = self.build / 'unreviewed-output.bin'
        extra.write_bytes(b'extra deployed bytes')
        with self.assertRaises(artifact.ArtifactError):
            artifact.verify_artifact(self.build, self.source_manifest, self.manifest)
        extra.unlink()
        (self.build / 'canvaskit/canvaskit.wasm').unlink()
        with self.assertRaises(artifact.ArtifactError):
            artifact.verify_artifact(self.build, self.source_manifest, self.manifest)

    def test_version_source_main_and_minimum_migration_must_agree_before_record(self):
        path = self.build / 'version.json'
        original = path.read_text()
        mutations = {
            'backend': 'unsupported', 'source_commit': 'b' * 40, 'source_dirty': 0,
            'source_manifest_sha256': '0' * 64, 'main_dart_js_sha256': '0' * 64,
            'minimum_core_schema_migration': '9999_unfrozen_schema.sql',
            'source_release_status': 'production_ready', 'operational_migration_complete': True,
        }
        for key, replacement in mutations.items():
            with self.subTest(key=key):
                value = json.loads(original)
                value[key] = replacement
                path.write_text(json.dumps(value))
                with self.assertRaises(artifact.ArtifactError):
                    self.seal()
                self.assertFalse(self.manifest.exists())
        path.write_text(original)
        (self.build / 'main.dart.js').write_bytes(b'changed JS without matching metadata')
        with self.assertRaises(artifact.ArtifactError):
            self.seal()

    def test_source_manifest_digest_is_recomputed_not_compared_as_two_strings(self):
        original = self.source_manifest.read_text()
        value = json.loads(original)
        value['files'][0]['sha256'] = '0' * 64
        self.source_manifest.write_text(json.dumps(value))
        with self.assertRaises(source.SourceError):
            self.seal()
        self.source_manifest.write_text(original)
        self.seal()
        value = json.loads(original)
        value['source_commit'] = 'b' * 40
        self.source_manifest.write_text(json.dumps(value))
        with self.assertRaises(artifact.ArtifactError):
            artifact.verify_artifact(self.build, self.source_manifest, self.manifest)

    def test_artifact_digest_sorted_inventory_hashes_and_acceptance_flags_are_strict(self):
        original = self.seal()
        mutations = [
            lambda value: value.update(artifact_manifest_sha256='0' * 64),
            lambda value: value.update(hosted_acceptance_verified=True),
            lambda value: value.update(source_release_status='production_ready'),
            lambda value: value.update(schema_version=True),
            lambda value: value['files'].reverse(),
            lambda value: value['files'].append(value['files'][-1]),
            lambda value: value['files'][0].update(path='../unrelated'),
            lambda value: value['files'][0].update(bytes=True),
            lambda value: value['files'][0].update(sha256='invalid-hash'),
        ]
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                value = json.loads(json.dumps(original))
                mutation(value)
                with self.assertRaises((artifact.ArtifactError, source.SourceError)):
                    artifact.validate_artifact_manifest(value)

    def test_recomputed_artifact_digest_cannot_hide_current_file_drift(self):
        value = self.seal()
        value['files'][0]['sha256'] = '0' * 64
        body = {key: item for key, item in value.items() if key != 'artifact_manifest_sha256'}
        value['artifact_manifest_sha256'] = hashlib.sha256(source.canonical(body)).hexdigest()
        source.write_json(self.manifest, value)
        with self.assertRaises(artifact.ArtifactError):
            artifact.verify_artifact(self.build, self.source_manifest, self.manifest)

    def test_manifest_cannot_be_inside_output_or_overwrite_source_record(self):
        for destination in (self.build / 'artifact.json', self.source_manifest):
            with self.subTest(destination=destination), self.assertRaises(artifact.ArtifactError):
                artifact.record_artifact(self.build, self.source_manifest, destination)
        with self.assertRaises(artifact.ArtifactError):
            artifact.record_artifact(self.build / '..' / self.build.name, self.source_manifest, self.manifest)

    def test_symlinks_directories_hardlinks_and_external_manifest_targets_are_refused(self):
        self.seal()
        original = self.directory / 'untouched-original'
        original.write_bytes(b'outside byte evidence')
        path = self.build / 'output-link.bin'
        path.symlink_to(original)
        with self.assertRaises(source.SourceError):
            artifact.verify_artifact(self.build, self.source_manifest, self.manifest)
        path.unlink()
        path.symlink_to(self.directory, target_is_directory=True)
        with self.assertRaises(source.SourceError):
            self.seal()
        path.unlink()
        os.link(original, path)
        with self.assertRaises(source.SourceError):
            self.seal()
        path.unlink()
        self.manifest.unlink()
        self.manifest.symlink_to(original)
        with self.assertRaises(source.SourceError):
            self.seal()
        self.assertEqual(b'outside byte evidence', original.read_bytes())

    def test_missing_control_file_or_malformed_version_is_not_complete_output(self):
        control = self.build / 'index.html'
        original = control.read_bytes()
        control.unlink()
        with self.assertRaises(source.SourceError):
            self.seal()
        control.write_bytes(original)
        for raw in ('{', '{"backend":"cloudflare","backend":"unsupported"}'):
            (self.build / 'version.json').write_text(raw)
            with self.assertRaises(source.SourceError):
                self.seal()

    def test_verifier_is_read_only_and_uses_no_subprocess_or_network(self):
        value = self.seal()
        with patch.object(source.subprocess, 'run', side_effect=AssertionError('No external calls')), patch.object(source.subprocess, 'check_output', side_effect=AssertionError('No external calls')):
            self.assertEqual(value, artifact.verify_artifact(self.build, self.source_manifest, self.manifest))

    def test_partial_build_race_cannot_seal_old_validated_identity_with_new_bytes(self):
        original = artifact._files

        def mutate_before_inventory(build):
            (build / 'main.dart.js').write_bytes(b'changed during postprocessing')
            return original(build)

        with patch.object(artifact, '_files', side_effect=mutate_before_inventory), self.assertRaises(artifact.ArtifactError):
            self.seal()
        self.assertFalse(self.manifest.exists())

    def test_file_directory_punctuation_uses_relative_string_order(self):
        (self.build / 'assets/a').mkdir()
        (self.build / 'assets/a/file.bin').write_bytes(b'nested bytes')
        (self.build / 'assets/a-z.bin').write_bytes(b'sibling bytes')
        value = self.seal()
        paths = [row['path'] for row in value['files']]
        self.assertEqual(sorted(paths), paths)
        self.assertEqual(value, artifact.verify_artifact(self.build, self.source_manifest, self.manifest))

    def test_cli_record_verify_and_nonzero_drift_refusal(self):
        command = [sys.executable, str(ROOT / 'scripts/admin_cloudflare_artifact.py')]
        args = [str(self.build), str(self.source_manifest), str(self.manifest)]
        for mode in ('record', 'verify'):
            completed = subprocess.run([*command, mode, *args], text=True, capture_output=True, check=False)
            self.assertEqual(0, completed.returncode, completed.stderr)
            receipt = json.loads(completed.stdout)
            self.assertEqual(mode, receipt['mode'])
            self.assertFalse(receipt['hosted_acceptance_verified'])
        (self.build / 'flutter_bootstrap.js').write_bytes(b'changed bootstrap')
        refused = subprocess.run([*command, 'verify', *args], text=True, capture_output=True, check=False)
        self.assertEqual(1, refused.returncode)
        self.assertEqual('', refused.stdout)
        self.assertIn('differ from the sealed candidate', refused.stderr)


if __name__ == '__main__':
    unittest.main()
