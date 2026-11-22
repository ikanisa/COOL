"""Real cryptographic positive/negative tests, never product qualifications."""
from pathlib import Path
import copy
import datetime as dt
import json
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'src'))
import release_guard as g
import release_provenance as p
from fixtures import Fixture
from provenance_fixtures import SignedFixture

class ProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.base=Path(self.tmp.name);self.f=SignedFixture(self.base)
    def tearDown(self):self.tmp.cleanup()
    def reject(self,code=None,**kwargs):
        r=self.f.gate(**kwargs);self.assertFalse(r['gate_open'],r);self.assertFalse(r['production_authorized']);self.assertFalse(r['provenance_authenticated'])
        if code:self.assertIn(code,r['errors'],r)
    def change_bundle(self,fn,code):
        fn(self.f.bundle);self.f.write_bundle();self.reject(code)
    def change_policy(self,fn,code):
        fn(self.f.trust);self.f.commit_trust();self.f.sign_all();self.reject(code)
    def test_real_signatures_open_synthetic_candidate_gate(self):
        r=self.f.gate();self.assertTrue(r['gate_open'],r);self.assertTrue(r['provenance_authenticated']);self.assertFalse(r['production_authorized'])
        self.assertEqual(r['provenance']['role_count'],len(self.f.m['qualifications'])+1)
    def test_missing_trust(self):self.reject('TRUST_CONFIGURATION_MISSING',trust_policy=None)
    def test_missing_pin(self):self.reject('TRUST_CONFIGURATION_MISSING',trust_sha256=None)
    def test_missing_bundle(self):self.reject('PROVENANCE_MISSING',attestations=None)
    def test_wrong_pin(self):self.reject('TRUST_POLICY_HASH_MISMATCH',trust_sha256='0'*64)
    def test_malformed_pin(self):self.reject('INVALID_SHA256',trust_sha256='not-a-digest')
    def test_trust_file_missing(self):self.f.trust_path.unlink();self.reject('FILE_UNAVAILABLE')
    def test_trust_inside_source(self):
        q=self.f.source/'build'/'trust.json';q.parent.mkdir();q.write_bytes(self.f.trust_path.read_bytes())
        self.reject('TRUST_POLICY_MUST_BE_EXTERNAL',trust_policy=q)
    def test_trust_inside_evidence(self):
        q=self.f.evidence/'trust.json';q.write_bytes(self.f.trust_path.read_bytes());self.reject('TRUST_POLICY_MUST_BE_EXTERNAL',trust_policy=q)
    def test_relative_trust(self):self.reject('TRUST_POLICY_MUST_BE_EXTERNAL',trust_policy=Path('trust.json'))
    def test_symlink_trust(self):
        q=self.base/'alias.json';q.symlink_to(self.f.trust_path);self.reject('SYMLINK_REFUSED',trust_policy=q)
    def test_duplicate_policy_json_key(self):
        raw=self.f.trust_path.read_bytes();raw=raw.replace(b'"schema_version": 1',b'"schema_version": 1, "schema_version": 1')
        self.f.trust_path.write_bytes(raw);self.reject('DUPLICATE_JSON_KEY',trust_sha256=g.sha(raw))
    def test_policy_extra_field(self):self.change_policy(lambda x:x.update(allow_unsigned=True),'INVALID_TRUST_POLICY')
    def test_policy_bool_schema(self):self.change_policy(lambda x:x.update(schema_version=True),'UNSUPPORTED_TRUST_POLICY')
    def test_policy_wrong_product(self):self.change_policy(lambda x:x.update(product='BuriMunsi'),'TRUST_POLICY_SCOPE_MISMATCH')
    def test_policy_wrong_phase(self):self.change_policy(lambda x:x.update(phase='promotion'),'TRUST_POLICY_SCOPE_MISMATCH')
    def test_policy_expired(self):self.change_policy(lambda x:x.update(expires_at=self.f.t(-1)),'TRUST_POLICY_EXPIRED_OR_FUTURE')
    def test_policy_future(self):self.change_policy(lambda x:x.update(issued_at=self.f.t(1)),'TRUST_POLICY_EXPIRED_OR_FUTURE')
    def test_policy_excessive_lifetime(self):self.change_policy(lambda x:x.update(expires_at=self.f.t(32*86400)),'TRUST_POLICY_EXPIRED_OR_FUTURE')
    def test_key_revoked(self):self.change_policy(lambda x:x['keys'][0].update(status='revoked'),'SIGNER_REVOKED')
    def test_key_expired(self):self.change_policy(lambda x:x['keys'][0].update(not_after=self.f.t(-1)),'SIGNER_EXPIRED_OR_NOT_YET_VALID')
    def test_key_not_yet_valid(self):self.change_policy(lambda x:x['keys'][0].update(not_before=self.f.t(1)),'SIGNER_EXPIRED_OR_NOT_YET_VALID')
    def test_key_status_unknown(self):self.change_policy(lambda x:x['keys'][0].update(status='pending'),'INVALID_KEY_STATUS')
    def test_key_bad_window(self):self.change_policy(lambda x:x['keys'][0].update(not_before=self.f.t(8000)),'INVALID_KEY_WINDOW')
    def test_key_fingerprint_wrong(self):self.change_policy(lambda x:x['keys'][0].update(public_key_hex='0'*64),'PUBLIC_KEY_ID_MISMATCH')
    def test_key_format_invalid(self):self.change_policy(lambda x:x['keys'][0].update(public_key_hex='00'),'INVALID_PUBLIC_KEY')
    def test_key_duplicate(self):self.change_policy(lambda x:x['keys'].append(copy.deepcopy(x['keys'][0])),'DUPLICATE_TRUST_KEY')
    def test_role_missing(self):
        self.f.trust['roles'].pop('manifest');self.f.commit_trust();self.f.sign_all();self.reject('TRUST_ROLES_INCOMPLETE')
    def test_extra_role(self):
        self.f.trust['roles']['extra']=copy.deepcopy(self.f.trust['roles']['manifest']);self.f.commit_trust();self.reject('TRUST_ROLES_INCOMPLETE')
    def test_role_extra_field(self):self.change_policy(lambda x:x['roles']['manifest'].update(allow_missing=True),'INVALID_TRUST_ROLE')
    def test_threshold_zero(self):self.change_policy(lambda x:x['roles']['manifest'].update(threshold=0),'INVALID_SIGNATURE_THRESHOLD')
    def test_threshold_boolean(self):self.change_policy(lambda x:x['roles']['manifest'].update(threshold=True),'INVALID_SIGNATURE_THRESHOLD')
    def test_role_duplicate_key(self):self.change_policy(lambda x:x['roles']['manifest']['key_ids'].append(x['keys'][0]['id']),'DUPLICATE_ROLE_KEY')
    def test_unknown_role_key(self):
        self.f.trust['roles']['manifest']['key_ids']=['0'*64];self.f.commit_trust();self.reject('ROLE_KEY_UNKNOWN')
    def test_no_signatures(self):self.change_bundle(lambda x:x.update(signatures=[]),'PROVENANCE_SIGNATURES_MISSING')
    def test_qualification_signature_missing(self):self.change_bundle(lambda x:x['signatures'].pop(),'SIGNATURE_THRESHOLD_NOT_MET')
    def test_duplicate_signature(self):self.change_bundle(lambda x:x['signatures'].append(copy.deepcopy(x['signatures'][0])),'DUPLICATE_SIGNATURE')
    def test_unknown_signer(self):self.change_bundle(lambda x:x['signatures'][0].update(key_id='0'*64),'SIGNER_UNKNOWN')
    def test_unknown_signature_role(self):self.change_bundle(lambda x:x['signatures'][0].update(role='extra'),'SIGNATURE_ROLE_UNKNOWN')
    def test_signature_extra_field(self):self.change_bundle(lambda x:x['signatures'][0].update(algorithm='none'),'INVALID_SIGNATURE_FIELDS')
    def test_signature_bad_length(self):self.change_bundle(lambda x:x['signatures'][0].update(signature_hex='00'),'INVALID_SIGNATURE_ENCODING')
    def test_signature_bad_hex(self):self.change_bundle(lambda x:x['signatures'][0].update(signature_hex='z'*128),'INVALID_SIGNATURE_ENCODING')
    def test_signature_tampering(self):self.change_bundle(lambda x:x['signatures'][0].update(signature_hex='00'*64),'SIGNATURE_INVALID_OR_CRYPTO_UNSUPPORTED')
    def test_signature_before_subject(self):self.change_bundle(lambda x:x['signatures'][0].update(signed_at=self.f.t(-11)),'SIGNATURE_PRECEDES_SUBJECT')
    def test_signature_future(self):self.change_bundle(lambda x:x['signatures'][0].update(signed_at=self.f.t(1)),'FUTURE_EVIDENCE')
    def test_signature_stale(self):self.change_bundle(lambda x:x['signatures'][0].update(signed_at=self.f.t(-86401)),'STALE_EVIDENCE')
    def test_signature_timestamp_tampering(self):self.change_bundle(lambda x:x['signatures'][0].update(signed_at=self.f.t(-4)),'SIGNATURE_INVALID_OR_CRYPTO_UNSUPPORTED')
    def test_bundle_extra_field(self):self.change_bundle(lambda x:x.update(allow_unsigned=True),'INVALID_PROVENANCE_BUNDLE')
    def test_bundle_bool_schema(self):self.change_bundle(lambda x:x.update(schema_version=True),'UNSUPPORTED_PROVENANCE')
    def test_bundle_other_product(self):self.change_bundle(lambda x:x.update(product='BuriMunsi'),'PROVENANCE_SCOPE_MISMATCH')
    def test_bundle_other_version(self):self.change_bundle(lambda x:x.update(source_version='other'),'PROVENANCE_SCOPE_MISMATCH')
    def test_bundle_other_run(self):self.change_bundle(lambda x:x.update(run_id='other'),'PROVENANCE_SCOPE_MISMATCH')
    def test_bundle_other_phase(self):self.change_bundle(lambda x:x.update(phase='promotion'),'PROVENANCE_SCOPE_MISMATCH')
    def test_bundle_wrong_manifest(self):self.change_bundle(lambda x:x.update(manifest_sha256='0'*64),'PROVENANCE_MANIFEST_MISMATCH')
    def test_bundle_wrong_trust(self):self.change_bundle(lambda x:x.update(trust_policy_sha256='0'*64),'PROVENANCE_TRUST_MISMATCH')
    def test_rehashed_manifest_cannot_reuse_signatures(self):
        self.f.m['created_at']=self.f.t(-9);self.f.bundle['manifest_sha256']=g.sha(g.canonical(self.f.m));self.f.write_bundle()
        self.reject('SIGNATURE_INVALID_OR_CRYPTO_UNSUPPORTED')
    def test_rehashed_log_cannot_reuse_signatures(self):
        qid=next(iter(self.f.results));self.f.change_result(lambda x:x.update(log=self.f.store('logs/'+qid+'.txt',b'new log')),qid)
        self.f.bundle['manifest_sha256']=g.sha(g.canonical(self.f.m));self.f.write_bundle();self.reject('SIGNATURE_INVALID_OR_CRYPTO_UNSUPPORTED')
    def test_source_mutation_still_blocked_with_signatures(self):
        (self.f.source/'main.py').write_text('changed\n');self.reject('SOURCE_INVENTORY_MISMATCH')
    def test_no_crypto_executable(self):
        with mock.patch.object(p.shutil,'which',return_value=None):self.reject('CRYPTO_PREREQUISITE_MISSING')
    def test_crypto_timeout(self):
        with mock.patch.object(p.subprocess,'run',side_effect=subprocess.TimeoutExpired(['openssl'],10)):self.reject('CRYPTO_EXECUTION_BLOCKED')
    def test_crypto_process_missing(self):
        with mock.patch.object(p.subprocess,'run',side_effect=FileNotFoundError):self.reject('CRYPTO_EXECUTION_BLOCKED')
    def test_crypto_crash(self):
        with mock.patch.object(p.subprocess,'run',return_value=subprocess.CompletedProcess([], -9)):self.reject('SIGNATURE_INVALID_OR_CRYPTO_UNSUPPORTED')
    def test_crypto_nonzero(self):
        with mock.patch.object(p.subprocess,'run',return_value=subprocess.CompletedProcess([], 1)):self.reject('SIGNATURE_INVALID_OR_CRYPTO_UNSUPPORTED')
    def test_trust_change_during_verification(self):
        old=p.verify_ed25519
        def run(*a):
            old(*a);self.f.trust_path.write_bytes(self.f.trust_path.read_bytes()+b' ')
        with mock.patch.object(p,'verify_ed25519',side_effect=run):self.reject('TRUST_POLICY_CHANGED_DURING_VERIFICATION')
    def test_bundle_change_during_verification(self):
        old=p.verify_ed25519
        def run(*a):
            old(*a);self.f.bundle_path.write_bytes(self.f.bundle_path.read_bytes()+b' ')
        with mock.patch.object(p,'verify_ed25519',side_effect=run):self.reject('PROVENANCE_CHANGED_DURING_VERIFICATION')
    def test_source_change_during_verification(self):
        old=p.verify_ed25519
        def run(*a):
            old(*a);(self.f.source/'main.py').write_text('changed during verification\n')
        with mock.patch.object(p,'verify_ed25519',side_effect=run):self.reject('EVIDENCE_CHANGED_DURING_AUTHENTICATION')
    def test_two_producer_threshold_passes(self):
        kid=self.f.add_key('synthetic-second-producer');self.f.trust['roles']['manifest']={'key_ids':[self.f.trust['keys'][0]['id'],kid],'threshold':2}
        self.f.commit_trust();self.f.sign_all();self.assertTrue(self.f.gate()['gate_open'])
    def test_threshold_missing_second_signer(self):
        kid=self.f.add_key('synthetic-second-producer');self.f.trust['roles']['manifest']={'key_ids':[self.f.trust['keys'][0]['id'],kid],'threshold':2}
        self.f.commit_trust();self.f.sign_all();self.f.bundle['signatures']=[s for s in self.f.bundle['signatures'] if s['key_id']!=kid];self.f.write_bundle();self.reject('SIGNATURE_THRESHOLD_NOT_MET')
    def test_two_keys_one_producer_not_two_votes(self):
        kid=self.f.add_key('synthetic-builder');self.f.trust['roles']['manifest']={'key_ids':[self.f.trust['keys'][0]['id'],kid],'threshold':2}
        self.f.commit_trust();self.f.sign_all();self.reject('INVALID_SIGNATURE_THRESHOLD')
    def test_wrong_role_key(self):
        kid=self.f.add_key('synthetic-other');self.f.commit_trust();self.f.sign_all()
        self.f.bundle['signatures'][0]=self.f.sign_one('manifest',kid);self.f.write_bundle();self.reject('SIGNER_NOT_AUTHORIZED_FOR_ROLE')
    def test_rotated_key_old_signature_rejected(self):
        kid=self.f.add_key('synthetic-rotated');self.f.trust['roles']['manifest']['key_ids']=[kid]
        self.f.commit_trust();self.f.sign_all();self.assertTrue(self.f.gate()['gate_open'])
        self.f.bundle['signatures'][0]=self.f.sign_one('manifest',self.f.trust['keys'][0]['id']);self.f.write_bundle();self.reject('SIGNER_NOT_AUTHORIZED_FOR_ROLE')
    def test_source_only_packaging_does_not_claim_authentication(self):
        with tempfile.TemporaryDirectory() as td:
            f=Fixture(Path(td),'release-safeguards','source');r=g.validate(f.source,f.evidence,f.m,product=f.product,version=f.version,phase=f.phase,now=f.now)
            self.assertTrue(r['gate_open']);self.assertFalse(r['provenance_authenticated'])

class PromotionProvenanceTests(unittest.TestCase):
    def test_both_products_synthetic_promotion_and_separation(self):
        for product in ('M-Money','BuriMunsi'):
            with self.subTest(product=product),tempfile.TemporaryDirectory() as td:
                f=SignedFixture(Path(td),product,'promotion');r=f.gate();self.assertTrue(r['gate_open'],r);self.assertFalse(r['production_authorized'])
                owner=f.trust['roles']['qualification:operations_authorization']['key_ids'][0]
                builder=f.trust['roles']['manifest']['key_ids'][0]
                for k in f.trust['keys']:
                    if k['id']==owner:k['producer_id']=next(k['producer_id'] for k in f.trust['keys'] if k['id']==builder)
                f.commit_trust();f.sign_all();r=f.gate();self.assertIn('PRODUCER_SEPARATION_REQUIRED',r['errors'])
    def test_security_identity_must_be_independent(self):
        with tempfile.TemporaryDirectory() as td:
            f=SignedFixture(Path(td),'BuriMunsi','build')
            f.trust['roles']['qualification:security_acceptance']=copy.deepcopy(f.trust['roles']['manifest'])
            f.commit_trust();f.sign_all();self.assertIn('PRODUCER_SEPARATION_REQUIRED',f.gate()['errors'])
    def test_unsigned_public_gates_cannot_open(self):
        for product in ('M-Money','BuriMunsi'):
            for phase in ('build','promotion'):
                with self.subTest(product=product,phase=phase),tempfile.TemporaryDirectory() as td:
                    f=Fixture(Path(td),product,phase)
                    r=g.validate(f.source,f.evidence,f.m,product=product,version=f.version,phase=phase,now=f.now)
                    self.assertEqual(r['errors'],['TRUST_CONFIGURATION_MISSING']);self.assertFalse(r['gate_open'])

if __name__=='__main__':unittest.main()
