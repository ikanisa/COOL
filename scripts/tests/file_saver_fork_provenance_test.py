#!/usr/bin/env python3
"""Actual retained-fork/cache mutations must fail before arbitrary delta blessing."""
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('file_saver_fork', ROOT / 'scripts/supply_chain/verify_file_saver_fork.py')
fork = importlib.util.module_from_spec(spec); spec.loader.exec_module(fork)


class FileSaverForkProvenanceTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.source = self.root / 'file_saver'; shutil.copytree(fork.FORK, self.source)
        self.cache = self.root / 'official-cache'; shutil.copytree(fork.CACHE, self.cache)
        for name,value in [('FORK',self.source),('CACHE',self.cache),('METADATA',self.cache/'metadata.json'),
                           ('ARCHIVE',self.cache/'file_saver-0.4.0.tar.gz')]:
            self.enterContext(patch.object(fork,name,value))

    def test_actual_official_archive_and_retained_delta_pass(self):
        result=fork.build()
        self.assertTrue(result['upstream_license_unchanged'])
        self.assertTrue(result['mime_source_format_equivalent'])
        self.assertEqual(result['reviewed_exact_byte_delta_sha256'],fork.REVIEWED_DELTA_SHA256)

    def test_non_authoritative_global_cache_does_not_change_canonical_proof(self):
        with patch.object(fork.Path, 'home', return_value=self.root):
            cold = fork.build()
            global_cache = self.root / '.pub-cache/hosted/pub.dev/file_saver-0.4.0'
            global_cache.mkdir(parents=True)
            (global_cache/'untrusted.dart').write_text('// foreign cache source')
            self.assertEqual(cold, fork.build())

    def test_mutating_already_allowed_runtime_file_cannot_be_auto_approved(self):
        p=self.source/'android/src/main/kotlin/com/incrediblezayed/file_saver/FileSaverPlugin.kt'
        p.write_bytes(p.read_bytes()+b'\n// unreviewed implementation mutation\n')
        with self.assertRaisesRegex(SystemExit,'Reviewed fork byte drift'):
            fork.build()

    def test_already_allowed_gradle_file_reverted_to_unsafe_version_is_rejected(self):
        p=self.source/'android/build.gradle';p.write_bytes(p.read_bytes().replace(b"'2.4.20'",b"'2.1.0'"))
        with self.assertRaisesRegex(SystemExit,'Reviewed fork byte drift'):
            fork.build()

    def test_new_runtime_file_and_removed_retained_file_are_rejected(self):
        p=self.source/'lib/unreviewed.dart';p.write_text('// unreviewed addition')
        with self.assertRaisesRegex(SystemExit,'delta differs'):
            fork.build()
        p.unlink();(self.source/'lib/src/utils/mime_types.dart').unlink()
        with self.assertRaises(SystemExit):fork.build()

    def test_license_loss_or_mutation_is_rejected(self):
        p=self.source/'LICENSE';original=p.read_bytes();p.write_bytes(b'replacement license')
        with self.assertRaisesRegex(SystemExit,'licence text changed'):fork.build()
        p.write_bytes(original);p.unlink()
        with self.assertRaises(SystemExit):fork.build()

    def test_changed_manifest_bytes_do_not_bless_arbitrary_changed_source(self):
        p=self.source/'COLLECT_FORK_DELTA.json';p.write_bytes(p.read_bytes()+b' ')
        with self.assertRaisesRegex(SystemExit,'delta manifest drift'):fork.build()

    def test_governance_doc_bytes_are_bound(self):
        p=self.source/'COLLECT_FORK.md';p.write_bytes(p.read_bytes()+b'\nUnreviewed claim\n')
        with self.assertRaisesRegex(SystemExit,'Reviewed fork byte drift'):fork.build()

    def test_actual_official_archive_and_metadata_origin_mutation_are_rejected(self):
        p=self.cache/'file_saver-0.4.0.tar.gz';before=p.read_bytes();p.write_bytes(before+b'mutation')
        with self.assertRaisesRegex(SystemExit,'archive changed'):fork.build()
        p.write_bytes(before)
        import json
        p=self.cache/'metadata.json';d=json.loads(p.read_text());d['archive_url']='https://foreign.invalid/archive';p.write_text(json.dumps(d))
        with self.assertRaisesRegex(ValueError,'metadata origin'):fork.build()

    def test_retained_symlink_and_fifo_are_rejected(self):
        import os
        p=self.source/'lib/aliased.dart';p.symlink_to(self.source/'LICENSE')
        with self.assertRaisesRegex(SystemExit,'Symlink fork input'):fork.build()
        p.unlink();os.mkfifo(p)
        with self.assertRaisesRegex(ValueError,'bounded regular file'):fork.build()

    def test_source_changed_during_real_format_comparison_is_rejected(self):
        original_format = fork.formatted_source_equal
        def change_after_format(upstream, path):
            result = original_format(upstream, path)
            p = self.source/'android/build.gradle'
            p.write_bytes(p.read_bytes()+b'\n// concurrent unreviewed change\n')
            return result
        with patch.object(fork, 'formatted_source_equal', side_effect=change_after_format):
            with self.assertRaisesRegex(SystemExit,'input drift during comparison'):
                fork.build()


    def export_root(self):
        root = self.root / 'selected-source'
        shutil.copytree(self.source, root / 'third_party/file_saver')
        return root

    def cli(self, root, *args):
        return subprocess.run([sys.executable, '-B', str(ROOT / 'scripts/supply_chain/verify_file_saver_fork.py'),
                               '--root', str(root), '--cache-dir', str(self.cache), *map(str,args)],
                              cwd=self.root, capture_output=True, text=True, timeout=30)

    def test_portable_cli_uses_selected_root_and_current_default_report(self):
        root = self.export_root()
        before = fork.tree_files(root / 'third_party/file_saver')
        result = self.cli(root)
        self.assertEqual(result.returncode, 0, result.stderr)
        report = root / 'docs/implementation/dependency-provenance/file_saver-0.4.0-comparison.json'
        self.assertEqual(json.loads(report.read_text()), fork.build())
        self.assertEqual(self.cli(root, '--check').returncode, 0)
        self.assertEqual(fork.tree_files(root / 'third_party/file_saver'), before)

    def test_portable_cli_default_cache_is_relative_to_selected_root(self):
        root = self.export_root()
        shutil.copytree(self.cache, root / '.cache/file-saver-upstream-0.4.0')
        result = subprocess.run([sys.executable, '-B', str(ROOT / 'scripts/supply_chain/verify_file_saver_fork.py'),
                                 '--root', str(root)], cwd=self.root, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_portable_cli_output_does_not_overwrite_source_or_support(self):
        root = self.export_root()
        support = root / 'scripts/supply_chain/helper.py'
        support.parent.mkdir(parents=True); support.write_bytes(b'protected support source\n')
        for path in [root / 'third_party/file_saver/LICENSE', support]:
            original = path.read_bytes()
            result = self.cli(root, '--output', path)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('verification inputs', result.stderr)
            self.assertEqual(path.read_bytes(), original)

    def test_portable_cli_hardlink_output_cannot_modify_licence(self):
        root = self.export_root(); licence=root / 'third_party/file_saver/LICENSE'
        output=self.root/'alias.json';os.link(licence,output);original=licence.read_bytes()
        result=self.cli(root,'--output',output)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('unaliased regular file',result.stderr)
        self.assertEqual(licence.read_bytes(),original)

    def test_portable_cli_symlink_root_cache_and_output_are_rejected(self):
        root=self.export_root();alias=self.root/'alias';alias.symlink_to(root,target_is_directory=True)
        self.assertNotEqual(self.cli(alias).returncode,0)
        alias.unlink();alias.symlink_to(self.cache,target_is_directory=True)
        result=self.cli(root,'--cache-dir',alias)
        self.assertNotEqual(result.returncode,0);self.assertIn('Symlink',result.stderr)
        alias.unlink();alias.symlink_to(root/'third_party/file_saver/LICENSE')
        self.assertNotEqual(self.cli(root,'--output',alias).returncode,0)

    def test_cache_inside_fork_is_rejected_before_fetch(self):
        root=self.export_root()
        with patch.object(fork,'fetch') as fetch,patch.object(sys,'argv',['verify','--root',str(root),'--cache-dir',str(root/'third_party/file_saver/cache'),'--fetch']):
            with self.assertRaisesRegex(SystemExit,'Cache may not modify'):
                fork.main()
            fetch.assert_not_called()

    def test_fetch_cache_hardlink_is_rejected_before_any_download(self):
        root=self.export_root();cache=self.root/'new-cache';cache.mkdir()
        licence=root/'third_party/file_saver/LICENSE';os.link(licence,cache/'metadata.json');original=licence.read_bytes()
        with patch.object(fork.origin,'public_download') as download,patch.object(sys,'argv',['verify','--root',str(root),'--cache-dir',str(cache),'--fetch']):
            with self.assertRaisesRegex(ValueError,'unaliased regular file'):
                fork.main()
            download.assert_not_called()
        self.assertEqual(licence.read_bytes(),original)

    def test_metadata_container_is_still_unreviewed_fork_input(self):
        (self.source/'._LICENSE').write_bytes(b'AppleDouble-looking unreviewed bytes')
        with self.assertRaisesRegex(SystemExit,'delta differs'):
            fork.build()

    def test_portable_check_refuses_stale_report_without_rewriting_it(self):
        root=self.export_root();self.assertEqual(self.cli(root).returncode,0)
        report=root/'docs/implementation/dependency-provenance/file_saver-0.4.0-comparison.json'
        original=report.read_bytes()+b' '
        report.write_bytes(original)
        result=self.cli(root,'--check')
        self.assertNotEqual(result.returncode,0);self.assertIn('report is stale',result.stderr)
        self.assertEqual(report.read_bytes(),original)


if __name__ == '__main__':unittest.main(verbosity=2)
