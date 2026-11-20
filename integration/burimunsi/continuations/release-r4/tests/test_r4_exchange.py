"""Signing-request exchange tests using temporary synthetic key material only."""
from pathlib import Path
import copy
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'src'))
import release_guard as g
import release_provenance as p
import provenance_exchange as ex
from provenance_fixtures import SignedFixture

class ExchangeTests(unittest.TestCase):
    def setUp(self):
        self.t=tempfile.TemporaryDirectory();self.base=Path(self.t.name);self.f=SignedFixture(self.base)
        self.manifest=self.f.evidence/'release-manifest.json';self.manifest.write_bytes(g.pretty(self.f.m))
        self.args=(self.f.source,self.f.evidence,self.manifest,self.f.trust_path,self.f.trust_hash)
    def tearDown(self):self.t.cleanup()
    def prepare(self,role='manifest',output=None):
        kid=self.f.trust['roles'][role]['key_ids'][0]
        return ex.prepare(*self.args,role,kid,output or self.base/'request',now=self.f.now)
    def signed(self):
        pairs=[]
        for n,role in enumerate(sorted(p.roles_for(self.f.m))):
            d=self.base/('request-'+str(n));self.prepare(role,d)
            kid=self.f.trust['roles'][role]['key_ids'][0];sig=self.base/('signature-'+str(n)+'.bin')
            subprocess.run([p.openssl_path(),'pkeyutl','-sign','-rawin','-inkey',str(self.f.private_paths[kid]),'-in',str(d/'statement.bin'),'-out',str(sig)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            pairs.append((d,sig))
        return pairs
    def test_prepare_does_not_sign_or_authorize(self):
        r=self.prepare();self.assertEqual(r['status'],'prepared_unsigned');self.assertFalse(r['gate_open'])
        self.assertEqual(set(x.name for x in (self.base/'request').iterdir()),{'request.json','statement.bin'})
    def test_prepare_exact_statement(self):
        r=self.prepare()['request'];raw=(self.base/'request/statement.bin').read_bytes()
        self.assertEqual(raw,p.statement(self.f.m,r['role'],self.f.trust_hash,r['key_id'],r['signed_at']))
        self.assertEqual(r['statement_sha256'],g.sha(raw))
    def test_prepare_refuses_overwrite(self):
        self.prepare()
        with self.assertRaisesRegex(g.Rejected,'OUTPUT_EXISTS'):self.prepare()
    def test_prepare_refuses_in_source(self):
        with self.assertRaisesRegex(g.Rejected,'OUTPUT_ALIASES_INPUT'):self.prepare(output=self.f.source/'out')
    def test_prepare_refuses_in_evidence(self):
        with self.assertRaisesRegex(g.Rejected,'OUTPUT_ALIASES_INPUT'):self.prepare(output=self.f.evidence/'out')
    def test_prepare_invalid_role(self):
        with self.assertRaisesRegex(g.Rejected,'SIGNATURE_ROLE_UNKNOWN'):
            ex.prepare(*self.args,'unknown',self.f.trust['keys'][0]['id'],self.base/'req',now=self.f.now)
    def test_prepare_revoked_signer(self):
        self.f.trust['keys'][0]['status']='revoked';self.f.commit_trust();self.args=(*self.args[:4],self.f.trust_hash)
        with self.assertRaisesRegex(g.Rejected,'SIGNER_REVOKED'):self.prepare()
    def test_prepare_invalid_consistency(self):
        (self.f.source/'main.py').write_text('changed')
        with self.assertRaisesRegex(g.Rejected,'CONSISTENCY_GATE_CLOSED'):self.prepare()
    def test_assemble_complete_verified_bundle_and_public_gate(self):
        pairs=self.signed();out=self.base/'assembled.json';r=ex.assemble(*self.args,pairs,out,now=self.f.now)
        self.assertFalse(r['gate_open']);self.assertFalse(r['production_authorized'])
        self.assertTrue(self.f.gate(attestations=out)['provenance_authenticated'])
    def test_assemble_rejects_missing_signature(self):
        pairs=self.signed();out=self.base/'assembled.json'
        with self.assertRaisesRegex(g.Rejected,'SIGNATURE_THRESHOLD_NOT_MET'):ex.assemble(*self.args,pairs[:-1],out,now=self.f.now)
        self.assertFalse(out.exists())
    def test_assemble_rejects_tampered_payload(self):
        pairs=self.signed();(pairs[0][0]/'statement.bin').write_bytes(b'changed')
        with self.assertRaisesRegex(g.Rejected,'SIGNING_PAYLOAD_MISMATCH'):ex.assemble(*self.args,pairs,self.base/'out.json',now=self.f.now)
    def test_assemble_rejects_tampered_request(self):
        pairs=self.signed();r=g.load(pairs[0][0]/'request.json');r['manifest_sha256']='0'*64;(pairs[0][0]/'request.json').write_bytes(g.pretty(r))
        with self.assertRaisesRegex(g.Rejected,'SIGNING_REQUEST_BINDING_MISMATCH'):ex.assemble(*self.args,pairs,self.base/'out.json',now=self.f.now)
    def test_assemble_rejects_tampered_signature(self):
        pairs=self.signed();pairs[0][1].write_bytes(b'\0'*64)
        with self.assertRaisesRegex(g.Rejected,'SIGNATURE_INVALID_OR_CRYPTO_UNSUPPORTED'):ex.assemble(*self.args,pairs,self.base/'out.json',now=self.f.now)
    def test_assemble_refuses_overwrite(self):
        out=self.base/'out.json';out.write_bytes(b'old')
        with self.assertRaisesRegex(g.Rejected,'OUTPUT_EXISTS'):ex.assemble(*self.args,self.signed(),out,now=self.f.now)
        self.assertEqual(out.read_bytes(),b'old')
    def test_assemble_duplicate_signature(self):
        pairs=self.signed();pairs.append(pairs[0])
        with self.assertRaisesRegex(g.Rejected,'DUPLICATE_SIGNATURE'):ex.assemble(*self.args,pairs,self.base/'out.json',now=self.f.now)
    def test_assemble_no_signature_does_not_publish(self):
        out=self.base/'out.json'
        with self.assertRaisesRegex(g.Rejected,'PROVENANCE_SIGNATURES_MISSING'):ex.assemble(*self.args,[],out,now=self.f.now)
        self.assertFalse(out.exists())
    def test_crypto_total_budget(self):
        with patch.object(p.time,'monotonic',side_effect=[0,31]):
            self.assertEqual(self.f.gate()['errors'],['CRYPTO_TIME_BUDGET_EXCEEDED'])
    def test_cli_prepare_missing_inputs_closed(self):
        run=subprocess.run([sys.executable,'-B',str(Path(ex.__file__)),'prepare','--source',str(self.f.source),'--evidence-root',str(self.f.evidence),
            '--manifest',str(self.manifest),'--trust-policy',str(self.base/'missing.json'),'--trust-sha256',self.f.trust_hash,
            '--role','manifest','--key-id',self.f.trust['keys'][0]['id'],'--output',str(self.base/'cli-output')],capture_output=True)
        self.assertEqual(run.returncode,2);self.assertFalse(g.strict_json(run.stdout)['gate_open']);self.assertFalse((self.base/'cli-output').exists())

if __name__=='__main__':unittest.main()
