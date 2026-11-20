"""Qualification integrity failures; no network, signing, device or real SMS."""
import copy
import datetime as dt
import hashlib
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import qualify_production as q


class ProductionQualification(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.base = Path(temp.name).resolve()
        self.now = dt.datetime(2026, 11, 13, 18, tzinfo=dt.timezone.utc)
        self.artifact = self.base / 'executed-check.json'
        self.artifact.write_text('{"status":"PASS","scope":"synthetic-test-only"}')
        self.binding = {'source_sha256': 'a' * 64, 'backend_sha256': 'b' * 64,
                        'profile_sha256': 'c' * 64,
                        'apk_sha256': {'staff': 'd' * 64, 'internal_receiver': 'e' * 64}}
        self.doc = {'format': 'collect.burimunsi.production-uat.v1', 'checked_at': self.now.isoformat(),
                    **self.binding, 'checks': {name: {'status': 'PASS', 'scope': scope, 'evidence': [
                        {'path': self.artifact.name, 'sha256': q.digest(self.artifact.read_bytes())}]}
                        for name, scope in q.CHECKS.items()}}
        self.path = self.base / 'uat.json'

    def verify(self, doc=None):
        self.path.write_text(json.dumps(doc if doc is not None else self.doc))
        return q.live_evidence(self.path, q.digest(self.path.read_bytes()), self.binding, self.now)

    def test_bound_executed_checks_are_accepted(self):
        result = self.verify()
        self.assertEqual(len(result['artifacts']), len(q.CHECKS))
        self.assertEqual(result['manifest_sha256'], q.digest(self.path.read_bytes()))

    def test_mutated_artifact_cannot_reuse_a_pass(self):
        self.artifact.write_text('{"status":"FAIL"}')
        with self.assertRaisesRegex(ValueError, 'evidence_changed'):
            self.verify()

    def test_different_apk_backend_or_source_cannot_reuse_live_results(self):
        for field in self.binding:
            with self.subTest(field=field):
                doc = copy.deepcopy(self.doc)
                doc[field] = {'staff': 'f' * 64, 'internal_receiver': 'e' * 64} if field == 'apk_sha256' else 'f' * 64
                with self.assertRaisesRegex(ValueError, 'uat_identity_wrong'):
                    self.verify(doc)

    def test_unexecuted_or_partial_check_is_refused(self):
        for mutation in ('FAIL', 'PASS_WITH_LIMITATIONS', 'WRONG_SCOPE', 'NO_EVIDENCE', 'MISSING'):
            with self.subTest(mutation=mutation):
                doc = copy.deepcopy(self.doc)
                check = doc['checks']['sms_to_ledger']
                if mutation == 'WRONG_SCOPE':
                    check['scope'] = 'local_fixture'
                elif mutation == 'NO_EVIDENCE':
                    check['evidence'] = []
                elif mutation == 'MISSING':
                    del doc['checks']['sms_to_ledger']
                else:
                    check['status'] = mutation
                with self.assertRaises(ValueError):
                    self.verify(doc)

    def test_stale_and_future_uat_are_refused(self):
        for delta in (dt.timedelta(days=-2), dt.timedelta(seconds=1)):
            with self.subTest(delta=delta):
                doc = copy.deepcopy(self.doc)
                doc['checked_at'] = (self.now + delta).isoformat()
                with self.assertRaises(ValueError):
                    self.verify(doc)

    def test_symlink_evidence_and_parent_traversal_are_refused(self):
        link = self.base / 'linked.json'
        link.symlink_to(self.artifact)
        for path in (link.name, '../' + self.base.name + '/' + self.artifact.name):
            with self.subTest(path=path):
                doc = copy.deepcopy(self.doc)
                doc['checks']['sms_to_ledger']['evidence'][0]['path'] = path
                with self.assertRaises(ValueError):
                    self.verify(doc)

    def test_absolute_hash_bound_evidence_can_be_reused(self):
        doc = copy.deepcopy(self.doc)
        doc['checks']['shared_admin']['evidence'][0]['path'] = str(self.artifact)
        self.verify(doc)

    def test_manifest_hash_and_duplicate_json_fields_are_enforced(self):
        self.path.write_text(json.dumps(self.doc))
        with self.assertRaisesRegex(ValueError, 'evidence_changed'):
            q.live_evidence(self.path, '0' * 64, self.binding, self.now)
        raw = json.dumps(self.doc).replace('"checks":', '"format":"duplicate", "checks":')
        self.path.write_text(raw)
        with self.assertRaises(ValueError):
            q.live_evidence(self.path, q.digest(self.path.read_bytes()), self.binding, self.now)

    def test_snapshot_hash_covers_source_and_ignores_only_derived_outputs(self):
        source = self.base / 'source'
        native = source / 'native/burimunsi'
        upstream = source / 'upstream/collect'
        native.mkdir(parents=True)
        upstream.mkdir(parents=True)
        code = native / 'file.kt'
        code.write_text('first')
        upstream.joinpath('receiver.kt').write_text('upstream')
        original = q.fingerprint(source)
        expected_rows = [{'path': 'native/burimunsi/file.kt', 'sha256': q.digest(b'first')},
                         {'path': 'upstream/collect/receiver.kt', 'sha256': q.digest(b'upstream')}]
        self.assertEqual(original, {'files': expected_rows,
                                   'sha256': hashlib.sha256(json.dumps(expected_rows, sort_keys=True).encode()).hexdigest()})
        native.joinpath('local.properties').write_text('sdk.dir=synthetic')
        native.joinpath('build').mkdir()
        native.joinpath('build/output').write_text('derived')
        self.assertEqual(q.fingerprint(source), original)
        code.write_text('changed')
        self.assertNotEqual(q.fingerprint(source), original)

    def test_snapshot_symlink_and_relabelled_candidate_are_refused(self):
        source = self.base / 'source'
        native = source / 'native/burimunsi'
        native.mkdir(parents=True)
        source.joinpath('upstream/collect').mkdir(parents=True)
        native.joinpath('source.kt').symlink_to(self.artifact)
        with self.assertRaises(ValueError):
            q.fingerprint(source)
        receipt = self.base / 'signed.json'
        receipt.write_text(json.dumps({'format': 'collect.burimunsi.signed-testing-candidate.v1',
                                      'status': 'PASS', 'signing_executed': True,
                                      'purpose': 'testing-candidate-only',
                                      'production_authorized': True, 'distribution_authorized': True}))
        with self.assertRaisesRegex(ValueError, 'candidate_receipt_relabelled'):
            q.qualify(SimpleNamespace(signed_result=receipt, signed_result_sha256=q.digest(receipt.read_bytes())))

    def test_production_profile_requires_the_selected_cloud_project(self):
        cloud = 'https://rrlduytparvsjfmegalh.supabase.co'
        profile = {'format': 'collect.deployment.v1', 'id': 'collect-production', 'mode': 'managed',
                   'environment': 'production', 'supabase_origin': cloud, 'member_api_origin': cloud,
                   'admin_origin': cloud, 'public_origin': 'https://collect.example', 'google_callback_origin': cloud}
        expected = q.digest(q.signer.canonical(profile))
        self.assertEqual(q.production_profile(profile, expected), expected)
        for change in ({'mode': 'self_hosted'}, {'supabase_origin': 'https://different.supabase.co'},
                       {'admin_origin': 'https://other.example'}, {'environment': 'qualification'}):
            with self.subTest(change=change):
                altered = {**profile, **change}
                with self.assertRaises(ValueError):
                    q.production_profile(altered, q.digest(q.signer.canonical(altered)))


if __name__ == '__main__':
    unittest.main()
