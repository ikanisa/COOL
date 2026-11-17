"""Protected synthetic retained-key input only; no actual runtime or provider."""
import base64
import copy
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

from scripts.self_hosted import prepare as module
from scripts.self_hosted.configure import read_env
from scripts.self_hosted import test_prepare_source_safety as source_safety


def synthetic_keys():
    # Generation belongs only to this test fixture, before exercising retained
    # input. The retained preparation branch must never call this generator.
    uri=(module.ROOT/'deploy/self-hosted/generate-keys.mjs').as_uri()
    program=('import {generateDeploymentKeys} from '+json.dumps(uri)+';'
        'const k=generateDeploymentKeys();k.ANON_KEY=k.ANON_KEY_ASYMMETRIC;'
        'k.SERVICE_ROLE_KEY=k.SERVICE_ROLE_KEY_ASYMMETRIC;'
        'k.JWT_KEYS=JSON.stringify(JSON.parse(k.JWT_KEYS).filter(x=>x.kty==="EC"));'
        'k.JWT_JWKS=JSON.stringify({keys:JSON.parse(k.JWT_JWKS).keys.filter(x=>x.kty==="EC")});'
        'process.stdout.write(JSON.stringify(k));')
    result=subprocess.run(['node','--input-type=module','-e',program],capture_output=True,timeout=30)
    if result.returncode:raise RuntimeError('Synthetic signing fixture unavailable')
    return json.loads(result.stdout)


def encode_json(value):
    return base64.urlsafe_b64encode(json.dumps(value,separators=(',',':')).encode()).decode().rstrip('=')


def changed_claim(token,field,value):
    head,body,signature=token.split('.')
    payload=json.loads(base64.urlsafe_b64decode(body+'='*(-len(body)%4)))
    payload[field]=value
    return head+'.'+encode_json(payload)+'.'+signature


class RetainedKeyInput(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original=synthetic_keys()
        cls.other=synthetic_keys()

    def setUp(self):
        area=tempfile.TemporaryDirectory();self.addCleanup(area.cleanup)
        self.base=Path(area.name).resolve();self.private=self.base/'input';self.private.mkdir(mode=0o700)
        self.path=self.private/'retained.json';self.keys=copy.deepcopy(self.original)

    def write(self,keys=None,raw=None):
        value=(json.dumps(self.keys if keys is None else keys,indent=2)+'\n').encode() if raw is None else raw
        self.path.write_bytes(value);self.path.chmod(0o600)
        return value

    def refused(self,keys):
        raw=self.write(keys)
        with self.assertRaises(ValueError) as caught:module.read_retained_keys(self.path)
        self.assertTrue(all(value not in str(caught.exception) for value in keys.values()
                            if isinstance(value,str) and len(value)>32))
        self.assertEqual(hashlib.sha256(self.path.read_bytes()).digest(),hashlib.sha256(raw).digest())

    def test_complete_es256_contract_preserves_original_bytes_and_format(self):
        raw=self.write();captured,keys=module.read_retained_keys(self.path)
        self.assertEqual(set(keys),module.RETAINED_KEY_FIELDS)
        self.assertEqual(hashlib.sha256(captured).digest(),hashlib.sha256(raw).digest())
        self.assertEqual(stat.S_IMODE(self.path.stat().st_mode),0o600)

    def test_original_short_and_legacy_internal_credentials_are_not_regenerated(self):
        self.keys.update(POSTGRES_PASSWORD='old-local',REALTIME_DB_ENC_KEY='legacy-16-text!!',
                         SECRET_KEY_BASE='legacy internal secret with spaces $literal')
        raw=self.write();captured,keys=module.read_retained_keys(self.path)
        self.assertEqual(hashlib.sha256(captured).digest(),hashlib.sha256(raw).digest())
        self.assertTrue(keys['POSTGRES_PASSWORD']==self.keys['POSTGRES_PASSWORD'])

    def test_owned0600_and_parent0700_are_required(self):
        self.write();self.path.chmod(0o644)
        with self.assertRaises(ValueError):module.read_retained_keys(self.path)
        self.path.chmod(0o600);self.private.chmod(0o755)
        with self.assertRaises(ValueError):module.read_retained_keys(self.path)

    def test_file_owned_by_another_user_is_refused(self):
        self.write();original_stat=os.stat
        def other_owner(path,*args,**kwargs):
            value=original_stat(path,*args,**kwargs)
            if path==self.path.name and kwargs.get('dir_fd') is not None:
                fields=list(value);fields[4]=os.geteuid()+1
                return os.stat_result(fields)
            return value
        with patch.object(module.os,'stat',side_effect=other_owner):
            with self.assertRaises(ValueError):module.read_retained_keys(self.path)

    def test_file_and_parent_symlinks_are_refused(self):
        self.write();link=self.private/'link';link.symlink_to(self.path)
        with self.assertRaises(ValueError):module.read_retained_keys(link)
        directory=self.base/'linked-parent';directory.symlink_to(self.private,target_is_directory=True)
        with self.assertRaises(ValueError):module.read_retained_keys(directory/self.path.name)

    def test_hardlinks_and_special_files_are_refused(self):
        self.write();os.link(self.path,self.private/'hardlink')
        with self.assertRaises(ValueError):module.read_retained_keys(self.path)
        fifo=self.private/'fifo';os.mkfifo(fifo,0o600)
        with self.assertRaises(ValueError):module.read_retained_keys(fifo)

    def test_oversized_and_non_utf8_files_are_refused(self):
        self.write(raw=b'x'*(module.MAX_RETAINED_KEYS_BYTES+1))
        with self.assertRaises(ValueError):module.read_retained_keys(self.path)
        self.write(raw=b'\xff')
        with self.assertRaises(ValueError):module.read_retained_keys(self.path)

    def test_duplicate_outer_and_string_encoded_jwk_fields_are_refused(self):
        self.write(raw=(json.dumps(self.keys)[:-1]+',"format":"collect.selfhost.private-keys.v1"}').encode())
        with self.assertRaises(ValueError):module.read_retained_keys(self.path)
        for name in ('JWT_KEYS','JWT_JWKS'):
            keys=copy.deepcopy(self.keys)
            keys[name]=keys[name].replace('"kty":"EC"','"kty":"EC","kty":"EC"',1)
            self.refused(keys)

    def test_missing_extra_and_non_string_fields_fail_closed(self):
        for change in ('missing','extra','number','control'):
            keys=copy.deepcopy(self.keys)
            if change=='missing':del keys['ROOT_ADMIN_TOKEN']
            elif change=='extra':keys['UNREVIEWED_KEY']='not accepted'
            elif change=='number':keys['JWT_SECRET']=123
            else:keys['POSTGRES_PASSWORD']='invalid\x00credential'
            self.refused(keys)

    def test_unknown_format_and_invalid_opaque_keys_fail_closed(self):
        for name,value in [('format','unknown'),('SUPABASE_SECRET_KEY','not-a-key'),
                           ('SUPABASE_PUBLISHABLE_KEY','sb_secret_'+'x'*32)]:
            self.refused({**self.keys,name:value})

    def test_collect_keys_need_canonical_material_and_separate_purposes(self):
        cases=[('DATA_ENCRYPTION_KEY',self.keys['SESSION_ENCRYPTION_KEY']),
               ('BURIMUNSI_PIN_PEPPER_BASE64',self.keys['DATA_ENCRYPTION_KEY']),
               ('COLLECT_NATIVE_INGRESS_KEY_BASE64',self.keys['BURIMUNSI_CURSOR_KEY_BASE64']),
               ('BURIMUNSI_CURSOR_KEY_BASE64',self.keys['BURIMUNSI_CURSOR_KEY_BASE64'].rstrip('=')),
               ('SESSION_ENCRYPTION_KEY',base64.b64encode(b's'*31).decode())]
        for name,value in cases:self.refused({**self.keys,name:value})

    def test_hs_fallback_or_multiple_authorities_are_not_admitted(self):
        for name in ('JWT_KEYS','JWT_JWKS'):
            keys=copy.deepcopy(self.keys);value=json.loads(keys[name])
            ring=value if name=='JWT_KEYS' else value['keys']
            ring.append({'kty':'oct','k':'c3ludGhldGlj','alg':'HS256'})
            keys[name]=json.dumps(value);self.refused(keys)

    def test_public_key_may_not_include_private_material(self):
        keys=copy.deepcopy(self.keys);value=json.loads(keys['JWT_JWKS'])
        value['keys'][0]['d']=json.loads(keys['JWT_KEYS'])[0]['d']
        keys['JWT_JWKS']=json.dumps(value);self.refused(keys)

    def test_private_scalar_must_actually_match_the_public_point(self):
        keys=copy.deepcopy(self.keys);value=json.loads(keys['JWT_KEYS'])
        value[0]['d']=json.loads(self.other['JWT_KEYS'])[0]['d']
        keys['JWT_KEYS']=json.dumps(value);self.refused(keys)

    def test_public_and_private_coordinates_and_metadata_must_match(self):
        for field in ('x','kid'):
            keys=copy.deepcopy(self.keys);value=json.loads(keys['JWT_JWKS'])
            value['keys'][0][field]=json.loads(self.other['JWT_JWKS'])['keys'][0][field]
            keys['JWT_JWKS']=json.dumps(value);self.refused(keys)

    def test_wrong_role_kid_and_algorithm_are_refused(self):
        keys=copy.deepcopy(self.keys);keys['ANON_KEY']=keys['SERVICE_ROLE_KEY'];self.refused(keys)
        for field,value in [('kid','different-authority'),('alg','HS256')]:
            keys=copy.deepcopy(self.keys);head,body,signature=keys['ANON_KEY'].split('.')
            header=json.loads(base64.urlsafe_b64decode(head+'='*(-len(head)%4)));header[field]=value
            keys['ANON_KEY']=encode_json(header)+'.'+body+'.'+signature;self.refused(keys)

    def test_all_four_token_signatures_are_verified(self):
        for name in ('ANON_KEY','SERVICE_ROLE_KEY','ANON_KEY_ASYMMETRIC','SERVICE_ROLE_KEY_ASYMMETRIC'):
            keys=copy.deepcopy(self.keys);keys[name]=changed_claim(keys[name],'iss','changed-synthetic-issuer')
            self.refused(keys)

    def test_expired_future_and_invalid_numeric_claims_are_refused(self):
        for field,value in [('exp',time.time()-1),('exp',True),('exp',10**1000),
                            ('nbf',time.time()+3600),('iat',float('inf'))]:
            keys=copy.deepcopy(self.keys);keys['ANON_KEY']=changed_claim(keys['ANON_KEY'],field,value)
            self.refused(keys)

    def test_duplicate_jwt_claims_are_not_silently_overwritten(self):
        keys=copy.deepcopy(self.keys);head,body,signature=keys['ANON_KEY'].split('.')
        decoded=base64.urlsafe_b64decode(body+'='*(-len(body)%4)).decode()
        duplicate=decoded[:-1]+',"role":"anon"}'
        keys['ANON_KEY']=head+'.'+base64.urlsafe_b64encode(duplicate.encode()).decode().rstrip('=')+'.'+signature
        self.refused(keys)

    def test_path_swap_between_stat_and_open_is_refused(self):
        self.write();other=self.private/'other';other.write_bytes(b'{}');other.chmod(0o600)
        original_open=os.open;swapped=[]
        def changed(path,flags,*args,**kwargs):
            if path==self.path.name and kwargs.get('dir_fd') is not None and not swapped:
                other.replace(self.path);swapped.append(True)
            return original_open(path,flags,*args,**kwargs)
        with patch.object(module.os,'open',side_effect=changed):
            with self.assertRaises(ValueError):module.read_retained_keys(self.path)
        self.assertTrue(swapped)

    def test_crypto_child_has_no_preload_options_or_private_argv(self):
        self.write();original_run=subprocess.run;seen=[]
        def checked(argv,**kwargs):
            self.assertNotIn('NODE_OPTIONS',kwargs['env'])
            self.assertNotIn('NODE_PATH',kwargs['env'])
            self.assertIsInstance(kwargs['input'],bytes)
            self.assertNotIn(self.keys['JWT_KEYS'],repr(argv));seen.append(True)
            return original_run(argv,**kwargs)
        with patch.dict(os.environ,{'NODE_OPTIONS':'synthetic-never-forwarded'}), \
                patch.object(module.subprocess,'run',side_effect=checked):
            module.read_retained_keys(self.path)
        self.assertTrue(seen)


class RetainedPreparation(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.keys=synthetic_keys()

    def setUp(self):
        self.fixture=source_safety.PreparationSourceSafety('test_v1_manifest_and_staged_vendor_modes_match_captured_bytes')
        self.fixture.setUp();self.addCleanup(self.fixture.doCleanups)
        self.base=self.fixture.base
        private=self.base/'retained-input';private.mkdir(mode=0o700)
        self.path=private/'keys.json';self.raw=(json.dumps(self.keys,indent=2)+'\n').encode()
        self.path.write_bytes(self.raw);self.path.chmod(0o600)
        self.profile={'format':'collect.deployment.v1','id':'retained-fixture','mode':'self_hosted',
            'environment':'qualification','supabase_origin':'https://identity.example',
            'member_api_origin':'https://api.example','admin_origin':'https://admin.example',
            'public_origin':'https://public.example','google_callback_origin':'https://api.example'}
        self.profile_path=self.base/'profile.json';self.profile_path.write_text(json.dumps(self.profile))

    def prepare(self,output):
        original_run=subprocess.run;calls=[]
        def validator_only(argv,**kwargs):
            if argv[:3]!=['node','--input-type=module','-e']:
                self.fail('Retained input must not invoke key generation or any other child')
            calls.append('crypto-validator');return original_run(argv,**kwargs)
        def tls(path):
            path.mkdir(mode=0o700);(path/'ca.crt').write_text('synthetic-ca')
            (path/'server.crt').write_text('synthetic-server-certificate')
        old=os.umask(0o077);os.umask(old)
        try:
            with patch.object(module,'ROOT',self.fixture.root),patch.object(module,'SOURCE_ROOTS',self.fixture.names), \
                 patch.object(module,'frontend_inventory',return_value={'sha256':'b'*64,'complete':True}), \
                 patch.object(module,'tls_keys',side_effect=tls),patch.object(module,'build_compose',return_value={'services':{}}), \
                 patch.object(module.subprocess,'run',side_effect=validator_only):
                result=module.prepare(self.profile_path,output,tls_mode='internal',retained_keys_file=self.path)
        finally:os.umask(old)
        return result,calls

    def test_retained_preparation_copies_bytes_and_derives_exact_private_and_public_projection(self):
        output=self.base/'release';result,calls=self.prepare(output)
        self.assertFalse(result['started']);self.assertEqual(calls,['crypto-validator'])
        self.assertEqual(hashlib.sha256((output/'private/keys.json').read_bytes()).digest(),hashlib.sha256(self.raw).digest())
        self.assertEqual(hashlib.sha256(self.path.read_bytes()).digest(),hashlib.sha256(self.raw).digest())
        self.assertEqual(stat.S_IMODE((output/'private/keys.json').stat().st_mode),0o600)
        stack=read_env(output/'private/stack.env');functions=read_env(output/'private/functions.env')
        public=read_env(output/'public.env');client=json.loads((output/'client.json').read_text())
        for name,value in self.keys.items():
            if name!='format':self.assertTrue(stack[name]==value,name)
        for name in module.PRIVATE_KEYS:self.assertTrue(functions[name]==self.keys[name],name)
        self.assertTrue(functions['SUPABASE_SECRET_KEY']==self.keys['SUPABASE_SECRET_KEY'])
        self.assertTrue(public['SUPABASE_PUBLISHABLE_KEY']==self.keys['SUPABASE_PUBLISHABLE_KEY'])
        self.assertTrue(client['SUPABASE_PUBLISHABLE_KEY']==self.keys['SUPABASE_PUBLISHABLE_KEY'])
        self.assertEqual([key['kty'] for key in json.loads(stack['JWT_JWKS'])['keys']],['EC'])
        self.assertTrue(all(name not in public and name not in client for name in module.PRIVATE_KEYS))
        for name,default in module.PRIVATE_FEATURE_CONTROLS.items():
            self.assertEqual(default,'false')
            self.assertEqual(stack[name],default)
            self.assertEqual(functions[name],default)
            self.assertNotIn(name,public)
            self.assertNotIn(name,client)
        self.assertNotIn('SUPABASE_SECRET_KEY',public);self.assertNotIn('SUPABASE_SECRET_KEY',client)

    def test_existing_release_cannot_be_overwritten(self):
        output=self.base/'release';output.mkdir();sentinel=output/'sentinel';sentinel.write_bytes(b'preserved')
        with patch.object(module,'read_retained_keys') as reader,patch.object(module.subprocess,'run') as command:
            with self.assertRaises(ValueError):
                module.prepare(self.profile_path,output,retained_keys_file=self.path)
        reader.assert_not_called();command.assert_not_called();self.assertEqual(sentinel.read_bytes(),b'preserved')

    def test_invalid_retained_input_fails_before_release_or_source_export(self):
        self.path.write_bytes(b'{}');output=self.base/'release'
        with patch.object(module,'_capture_inputs') as capture,patch.object(module.subprocess,'run') as command:
            with self.assertRaises(ValueError):
                module.prepare(self.profile_path,output,retained_keys_file=self.path)
        capture.assert_not_called();command.assert_not_called();self.assertFalse(output.exists())

    def test_retained_key_input_cannot_enter_public_source_export(self):
        protected=self.fixture.root/'supabase/functions/private';protected.mkdir(mode=0o700)
        target=protected/'keys.json';target.write_bytes(self.raw);target.chmod(0o600);self.path=target
        output=self.base/'release'
        with self.assertRaisesRegex(ValueError,'cannot be exported'):self.prepare(output)
        self.assertFalse(output.exists())


if __name__=='__main__':unittest.main()
