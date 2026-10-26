import hashlib
import json
from pathlib import Path
import tempfile
import subprocess
import unittest
from datetime import datetime, timezone
from scripts.supabase.cutover_gate import REQUIRED, PROJECT, acceptance, source_identity

class CutoverGateTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.path = self.root / 'acceptance.json'
        self.artifact = self.root / 'evidence.json'
        self.artifact.write_text('{"synthetic_gate_test":true}\n')
        self.sha = 'a' * 64
        self.record = {'project_ref': PROJECT, 'backend': 'supabase', 'fixture': False, 'status': 'pass',
                       'source_sha256': self.sha, 'expires_at': '2099-01-01T00:00:00Z',
                       'data_mismatches': 0, 'object_mismatches': 0, 'writer_authority': 'supabase_only',
                       'recovery_strategy': 'accepted_tested_forward_only',
                       'release_owner': {'decision': 'approve', 'identity': 'synthetic_test_only', 'source_sha256': self.sha},
                       'checks': {k: {'status': 'pass', 'fixture': False, 'evidence': {'path': 'evidence.json', 'sha256': hashlib.sha256(self.artifact.read_bytes()).hexdigest()}} for k in REQUIRED}}

    def tearDown(self):
        self.temp.cleanup()

    def check(self):
        self.path.write_text(json.dumps(self.record))
        return acceptance(self.path, self.sha, datetime(2026, 10, 20, tzinfo=timezone.utc))

    def test_missing_does_not_authorize_cutover(self):
        self.assertEqual(acceptance(self.path, self.sha)['decision'], 'NO-GO')

    def test_gate_evaluates_supplied_evidence_without_changing_routing(self):
        result = self.check()
        self.assertEqual(result['decision'], 'GO')
        self.assertFalse(result['routing_changed'])

    def test_each_missing_phase_blocks_cutover(self):
        for name in REQUIRED:
            previous = self.record['checks'].pop(name)
            self.assertIn(name + '_unverified', self.check()['blockers'])
            self.record['checks'][name] = previous

    def test_fixture_expiry_wrong_project_dual_writer_source_and_recovery(self):
        for key, value, blocker in [('fixture', True, 'nonproduction_or_unaccepted_evidence'),
                                    ('expires_at', '2020-01-01T00:00:00Z', 'evidence_expired'),
                                    ('project_ref', 'other', 'wrong_backend_or_project'),
                                    ('writer_authority', 'both', 'single_writer_not_proven'),
                                    ('source_sha256', 'b' * 64, 'source_changed'),
                                    ('recovery_strategy', 'dns_only', 'postwrite_recovery_not_accepted')]:
            previous = self.record[key]
            self.record[key] = value
            self.assertIn(blocker, self.check()['blockers'])
            self.record[key] = previous

    def test_changed_evidence_and_missing_owner_rejected(self):
        self.artifact.write_text('changed')
        self.record['release_owner'] = {}
        result = self.check()
        self.assertIn('data_unverified', result['blockers'])
        self.assertIn('release_owner_not_approved', result['blockers'])

    def test_operator_client_changes_invalidate_source_acceptance(self):
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        migration = self.root / 'supabase/migrations/baseline.sql'
        migration.parent.mkdir(parents=True)
        migration.write_text('synthetic fixture baseline')
        operator = self.root / 'tools/collect-admin-mcp/client.mjs'
        operator.parent.mkdir(parents=True)
        operator.write_text('original synthetic client')
        before = source_identity(self.root)
        operator.write_text('changed synthetic client')
        self.assertNotEqual(before, source_identity(self.root))

if __name__ == '__main__':
    unittest.main()
