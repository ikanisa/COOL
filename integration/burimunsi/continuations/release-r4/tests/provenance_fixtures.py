"""Fresh temporary Ed25519 identities for tests only; no keys are delivered."""
from pathlib import Path
import copy
import subprocess
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'src'))
import release_guard as g
import release_provenance as p
from fixtures import Fixture

class SignedFixture(Fixture):
    def __init__(self,base,product='M-Money',phase='build'):
        super().__init__(base,product,phase)
        self.private=base/'ephemeral';self.private.mkdir()
        self.trust_path=base/'external-trust.json';self.bundle_path=self.evidence/'provenance.json'
        self.private_paths={}
        self.trust={'schema_version':1,'kind':'release-trust-policy','product':product,'phase':phase,
            'issued_at':self.t(-120),'expires_at':self.t(3600),'keys':[],'roles':{}}
        general=self.add_key('synthetic-builder')
        for role in sorted(p.roles_for(self.m)):
            kid=self.add_key('synthetic-'+role) if role in {'qualification:security_acceptance','qualification:security_dependencies','qualification:operations_authorization'} else general
            self.trust['roles'][role]={'key_ids':[kid],'threshold':1}
        self.commit_trust();self.sign_all()

    def add_key(self,producer):
        path=self.private/('ephemeral-'+str(len(self.private_paths))+'.bin')
        subprocess.run([p.openssl_path(),'genpkey','-algorithm','ED25519','-out',str(path)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        pub=subprocess.run([p.openssl_path(),'pkey','-in',str(path),'-pubout','-outform','DER'],capture_output=True,check=True).stdout
        assert pub.startswith(p.SPKI_ED25519) and len(pub)==len(p.SPKI_ED25519)+32
        public=pub[len(p.SPKI_ED25519):];kid=g.sha(public);self.private_paths[kid]=path
        self.trust['keys'].append({'id':kid,'producer_id':producer,'public_key_hex':public.hex(),'status':'active','not_before':self.t(-180),'not_after':self.t(7200)})
        return kid

    def commit_trust(self):
        raw=g.pretty(self.trust);self.trust_path.write_bytes(raw);self.trust_hash=g.sha(raw)

    def sign_one(self,role,kid,signed_at=None):
        when=signed_at or self.t(-5)
        message=p.statement(self.m,role,self.trust_hash,kid,when)
        msg=self.private/'statement.bin';msg.write_bytes(message)
        sig=subprocess.run([p.openssl_path(),'pkeyutl','-sign','-rawin','-inkey',str(self.private_paths[kid]),'-in',str(msg)],capture_output=True,check=True).stdout
        return {'role':role,'key_id':kid,'signed_at':when,'signature_hex':sig.hex()}

    def sign_all(self):
        self.bundle={'schema_version':1,'kind':'release-provenance','trust_policy_sha256':self.trust_hash,
            'manifest_sha256':g.sha(g.canonical(self.m)),'product':self.product,'phase':self.phase,'source_version':self.version,
            'run_id':self.m['run_id'],'signatures':[self.sign_one(role,k) for role,r in sorted(self.trust['roles'].items()) for k in r['key_ids'][:r['threshold']]]}
        self.write_bundle()

    def write_bundle(self):self.bundle_path.write_bytes(g.pretty(self.bundle))
    def gate(self,**kwargs):
        opts={'product':self.product,'version':self.version,'phase':self.phase,'now':self.now,
              'trust_policy':self.trust_path,'trust_sha256':self.trust_hash,'attestations':self.bundle_path}
        opts.update(kwargs)
        return g.validate(self.source,self.evidence,self.m,**opts)
