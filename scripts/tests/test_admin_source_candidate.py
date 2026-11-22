import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'qa'))
import admin_source_candidate as candidate


class AdminSourceCandidateTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='collect-admin-source-test-')
        self.addCleanup(temporary.cleanup)
        self.parent = Path(temporary.name).resolve()
        self.root = self.parent / 'source'
        self.root.mkdir()
        candidate.git(self.root, 'init', '-q', '--template=')
        objects = candidate.oid(candidate.ROOT, 'rev-parse', '--path-format=absolute', '--git-path', 'objects')
        (self.root / '.git/objects/info/alternates').write_text(objects + '\n')
        self.base = candidate.oid(candidate.ROOT, 'rev-parse', 'HEAD^{commit}')
        candidate.git(self.root, 'update-ref', '--no-deref', 'HEAD', self.base)
        self.write(candidate.INPUTS, json.dumps({'build': ['admin-web', 'deploy/platform-admin/transport.js'], 'qualification': []}))
        self.write('admin-web/src/main.tsx', 'export const original = true;\n')
        self.write('deploy/platform-admin/transport.js', 'export const upstream = true;\n')
        self.write('admin-web/.env.local', 'local')
        self.write('admin-web/node_modules/local-only.js', 'dependency')
        self.write('outside.txt', 'user edit')
        candidate.git(self.root, 'add', '--', 'outside.txt')

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    def test_reproducible_tree_preserves_user_index_and_detached_base(self):
        index = self.root / '.git/index'
        before = index.read_bytes()
        first = candidate.admit(self.root)
        self.assertEqual(first, candidate.admit(self.root))
        self.assertEqual(index.read_bytes(), before)
        self.assertEqual(candidate.oid(self.root, 'rev-parse', 'HEAD'), self.base)
        self.assertEqual(candidate.oid(self.root, 'for-each-ref', '--format=%(refname)', 'refs/heads'), '')
        self.write('admin-web/src/main.tsx', 'changed since admission')
        self.assertNotEqual(first['product_tree'], candidate.admit(self.root)['product_tree'])
        fresh = self.parent / 'materialized'
        state = candidate.checkout(self.root, first['ref'], fresh)
        self.assertTrue(state['index_matches_tree'])
        self.assertEqual((fresh / 'admin-web/src/main.tsx').read_text(), 'export const original = true;\n')
        self.assertEqual((fresh / 'deploy/platform-admin/transport.js').read_text(), 'export const upstream = true;\n')
        for path in ['outside.txt', 'admin-web/.env.local', 'admin-web/node_modules']:
            self.assertFalse((fresh / path).exists())
        self.assertEqual(index.read_bytes(), before)
        with self.assertRaises(FileExistsError):
            candidate.checkout(self.root, first['ref'], fresh)

    def test_missing_declared_transport_blocks_admission(self):
        (self.root / 'deploy/platform-admin/transport.js').unlink()
        with self.assertRaisesRegex(candidate.ReleaseError, 'ADMIN_SOURCE_INPUT_MISSING'):
            candidate.admit(self.root)

    def test_symlink_source_and_private_token_are_refused(self):
        path = self.root / 'admin-web/src/link.ts'
        path.symlink_to(self.root / 'outside.txt')
        with self.assertRaisesRegex(candidate.ReleaseError, 'CANDIDATE_SYMLINK_REFUSED'):
            candidate.admit(self.root)
        path.unlink()
        self.write('admin-web/src/link.ts', 'ghp_' + 'x' * 40)
        with self.assertRaisesRegex(candidate.ReleaseError, 'CANDIDATE_CREDENTIAL_PATTERN'):
            candidate.admit(self.root)
        self.assertEqual(candidate.oid(self.root, 'for-each-ref', '--format=%(refname)', candidate.REF_PREFIX), '')


if __name__ == '__main__':
    unittest.main()
