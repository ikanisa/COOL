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
from unittest.mock import patch

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
        self.upgrade = {'format': 'collect.burimunsi.installed-update.v1',
                        'source_sha256': self.binding['source_sha256'], 'flavors': {}}
        signed = {'format': 'collect.burimunsi.signed-testing-candidate.v1', 'status': 'PASS',
                  'purpose': 'testing-candidate-only', 'signing_executed': True,
                  'production_authorized': False, 'distribution_authorized': False,
                  'certificate_sha256': q.readiness.UPGRADE_CERTIFICATE,
                  'source_sha256': self.binding['source_sha256'], 'artifacts': []}
        for flavor, (package, predecessor) in q.readiness.UPGRADE_PREDECESSOR.items():
            target = self.base / (flavor + '.apk')
            target.write_bytes(('synthetic ' + flavor).encode())
            digest = q.digest(target.read_bytes())
            self.binding['apk_sha256'][flavor] = digest
            signed['artifacts'].append({'flavor': flavor, 'package': package, 'version_code': q.signer.VERSION_CODE,
                                        'version_name': q.signer.VERSION_NAME, 'signature_verified': True,
                                        'certificate_sha256': q.readiness.UPGRADE_CERTIFICATE, 'path': target.name, 'sha256': digest})
            pair = {}
            for phase in ('before', 'after'):
                prior = phase == 'before'
                readback = {'format': 'collect.burimunsi.installed-package-observation.v1', 'phase': phase,
                            'package': package, 'version_code': 48 if prior else q.signer.VERSION_CODE,
                            'version_name': '0.23.0-collect.26' if prior else q.signer.VERSION_NAME,
                            'apk_sha256': predecessor if prior else digest, 'certificate_sha256': q.readiness.UPGRADE_CERTIFICATE,
                            'package_install_identity_sha256': '1' * 64, 'protected_state_sha256': '2' * 64,
                            'retained_held_requests': 1 if flavor == 'internal_receiver' else 0}
                pair[phase] = self.reference(flavor + '-' + phase + '.json', readback)
            self.upgrade['flavors'][flavor] = pair
        self.upgrade['candidate_signed_result'] = self.reference('signed-result.json', signed)
        self.doc['checks']['installed_update']['evidence'] = [self.reference('installed-update.json', self.upgrade)]

    def reference(self, name, value):
        path = self.base / name
        path.write_text(json.dumps(value))
        return {'path': name, 'sha256': q.digest(path.read_bytes())}

    def test_upgrade_refuses_other_predecessor_or_application_and_clean_install(self):
        for phase, key, value in [('before', 'apk_sha256', '0' * 64), ('before', 'version_code', 42),
                                  ('after', 'package', 'rw.ikanisa.burimunsi.gateway.cloud.nativeTest'),
                                  ('after', 'certificate_sha256', '0' * 64), ('after', 'apk_sha256', '0' * 64),
                                  ('after', 'package_install_identity_sha256', '9' * 64),
                                  ('after', 'protected_state_sha256', '9' * 64), ('after', 'retained_held_requests', 0)]:
            with self.subTest(phase=phase, key=key):
                doc = copy.deepcopy(self.upgrade)
                pair = doc['flavors']['internal_receiver']
                snapshot = json.loads((self.base / pair[phase]['path']).read_text())
                snapshot[key] = value
                pair[phase] = self.reference('changed-observation.json', snapshot)
                with self.assertRaises(ValueError):
                    q.readiness.installed_update(doc, self.base)

    def test_in_place_update_requires_the_candidate_artifacts_bound_to_qualification(self):
        for source, apks, cert in [('0'*64, self.binding['apk_sha256'], q.readiness.UPGRADE_CERTIFICATE),
                                  (self.binding['source_sha256'], {'staff': '8'*64}, q.readiness.UPGRADE_CERTIFICATE),
                                  (self.binding['source_sha256'], self.binding['apk_sha256'], '0'*64)]:
            with self.subTest(source=source, apks=apks, cert=cert), self.assertRaises(ValueError):
                q.readiness.installed_update(self.upgrade, self.base, source, apks, cert)
        (self.base / 'staff.apk').write_bytes(b'changed signed candidate')
        with self.assertRaises(ValueError):
            self.verify()

    def test_another_signed_channel_preserves_an_empty_queue_with_independent_apk_inspection(self):
        doc = copy.deepcopy(self.upgrade)
        del doc['candidate_signed_result']
        doc['apk_archives'] = {}
        identities = {}
        cert = '9' * 64
        for flavor, pair in doc['flavors'].items():
            archives = {}
            for phase in ('before', 'after'):
                raw = ('alternate-signed-archive-' + flavor + '-' + phase).encode()
                apk = self.base / (flavor + '-' + phase + '.apk')
                apk.write_bytes(raw)
                sha = q.digest(raw)
                snapshot = json.loads((self.base/pair[phase]['path']).read_bytes())
                snapshot.update(apk_sha256=sha, certificate_sha256=cert, retained_held_requests=0, installed_apk_count=1)
                if phase == 'before':
                    snapshot.update(version_code=45, version_name='0.23.0-collect.23')
                pair[phase] = self.reference('alternate-' + flavor + '-' + phase + '.json', snapshot)
                identities[raw] = {k: snapshot[k] for k in ('package', 'version_code', 'version_name', 'apk_sha256', 'certificate_sha256')}
                archives[phase] = {'path': apk.name, 'sha256': sha}
            doc['apk_archives'][flavor] = archives
        inspected = lambda raw, sdk, java_home: identities[raw]
        with patch.object(q.readiness, '_inspected_upgrade_apk', side_effect=inspected) as tool:
            approved = {k: v['after']['sha256'] for k, v in doc['apk_archives'].items()}
            with self.assertRaises(ValueError):
                q.readiness.installed_update(doc, self.base)
            targets = q.readiness.installed_update(doc, self.base, expected_apks=approved)
            self.assertEqual(targets, approved)
            self.assertEqual(tool.call_count, 4)
            pair=doc['flavors']['staff'];original=pair['after']
            snapshot=json.loads((self.base/original['path']).read_bytes())
            pair['after']=self.reference('split-after.json',{**snapshot,'installed_apk_count':2})
            with self.assertRaisesRegex(ValueError, 'UPGRADE_SPLIT_SET_UNVERIFIED'):
                q.readiness.installed_update(doc, self.base, expected_apks=approved)
            pair['after']=original
            identities[b'alternate-signed-archive-staff-after']['certificate_sha256'] = '8' * 64
            with self.assertRaisesRegex(ValueError, 'UPGRADE_TARGET_WRONG'):
                q.readiness.installed_update(doc, self.base, expected_apks=approved)

    def test_legacy_promotion_reads_the_independently_designated_distribution(self):
        approved=self.reference('approved-distribution.json',{'apk_sha256':self.binding['apk_sha256']})
        check={'status':'PASS','scope':'verified_release_artifacts',**approved}
        self.assertEqual(q.readiness._distribution_target_apks(self.base,check),self.binding['apk_sha256'])
        for changed in ({'scope':'local_fixture'},{'sha256':'f'*64}):
            with self.assertRaises(ValueError):
                q.readiness._distribution_target_apks(self.base,{**check,**changed})

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

    def test_build_and_qualification_exclude_compiler_sessions_and_bind_real_kotlin(self):
        # A checkout may itself be inside a directory named build.
        source = self.base / 'build/checkout'
        native = source / 'native/burimunsi'
        upstream = source / 'upstream/collect'
        native.mkdir(parents=True)
        upstream.mkdir(parents=True)
        code = native / 'Main.kt'
        code.write_text('one')
        (upstream / 'Receiver.kt').write_text('receiver')
        with patch.object(q.pipeline, 'ROOT', native), patch.object(q.pipeline, 'OVERLAY', source):
            def both():
                built = q.pipeline.source_fingerprint()
                self.assertEqual(q.fingerprint(source), built)
                return built

            original = both()
            self.assertEqual([r['path'] for r in original['files']],
                             ['native/burimunsi/Main.kt', 'upstream/collect/Receiver.kt'])
            for tree in (native, upstream):
                marker = tree / '.kotlin/sessions/compiler.salive'
                marker.parent.mkdir(parents=True)
                marker.write_text('running')
                self.assertEqual(both(), original)
                marker.write_text('next')
                self.assertEqual(both(), original)
                marker.unlink()
                self.assertEqual(both(), original)
            code.write_text('two')
            self.assertNotEqual(both(), original)

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
