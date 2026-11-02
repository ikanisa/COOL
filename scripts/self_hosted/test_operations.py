import copy
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import uuid
from scripts.self_hosted.prepare import PROVIDER_SETTINGS,dotenv,build_compose,verify_vendor,caddyfile
from scripts.self_hosted.configure import validated_settings,read_env,private_file,TURNSTILE_TEST_SITE_KEYS,TURNSTILE_TEST_SECRET_KEYS
from scripts.self_hosted.database import transaction_sql,migrations
from scripts.self_hosted.recovery import safe_member
from scripts.self_hosted.assets import tree
from scripts.self_hosted.health import evaluate
from scripts.self_hosted.frontend_manifest import inventory

PROFILE={'format':'collect.deployment.v1','id':'test','mode':'self_hosted','environment':'qualification','supabase_origin':'https://supabase.collect.example','admin_origin':'https://admin.collect.example','member_api_origin':'https://api.collect.example','public_origin':'https://collect.example','google_callback_origin':'https://admin.collect.example'}

def healthy_capacity_fence():
    return {'mode':'open','sourceSha256':'a'*64,'retainedUnknownObligations':0,
        'retainedUnquantifiedUnknownObligations':0,'schedulerStatus':{'coverageVerified':True},
        'stoppedLifecycleProofs':0,'resourceLimits':{'admissionBudgetVersion':4,
            'workingAdmissions':0,'workingAdmissionLimit':100000,
            'activeAndUnresolvedAdmissions':0,'activeWorkLimit':8,
            'operationReceipts':0,'operationReceiptLimit':10000,'operationReceiptSaturated':False,
            'schedulerLifecycleProofs':0,'schedulerLifecycleProofLimit':10000,'capacityBlocked':False}}

def health_codes(fence):
    return evaluate(fence,[{'service':'db','state':'running','health':'healthy'}],
        {'free_bytes':20*1024**3,'free_ratio':.5},90,'a'*64,{'db'})

class Configuration(unittest.TestCase):
    def test_health_reports_unconfirmed_capacity_and_never_assumes_missing_zero(self):
        fence=healthy_capacity_fence();self.assertEqual(health_codes(fence),[])
        for name,bad in [('workingAdmissions',None),('activeAndUnresolvedAdmissions',True),
            ('operationReceipts',-1),('schedulerLifecycleProofs',0.0),('workingAdmissionLimit',100001),
            ('admissionBudgetVersion',3),('capacityBlocked','false'),('operationReceiptSaturated',0)]:
            with self.subTest(name=name,bad=bad):
                candidate=healthy_capacity_fence();candidate['resourceLimits'][name]=bad
                self.assertIn('capacity_unconfirmed',{a['code'] for a in health_codes(candidate)})
        for name in ('resourceLimits','stoppedLifecycleProofs'):
            with self.subTest(missing=name):
                candidate=healthy_capacity_fence();del candidate[name]
                self.assertIn('capacity_unconfirmed',{a['code'] for a in health_codes(candidate)})
        candidate=healthy_capacity_fence();candidate['stoppedLifecycleProofs']=False
        self.assertIn('capacity_unconfirmed',{a['code'] for a in health_codes(candidate)})

    def test_health_reports_active_saturation_and_inconsistent_capacity_flag(self):
        candidate=healthy_capacity_fence();candidate['resourceLimits'].update(activeAndUnresolvedAdmissions=7,workingAdmissions=7)
        self.assertEqual(health_codes(candidate),[])
        candidate['resourceLimits'].update(activeAndUnresolvedAdmissions=8,workingAdmissions=8,capacityBlocked=True)
        self.assertIn('finite_capacity_blocked',{a['code'] for a in health_codes(candidate)})
        candidate['resourceLimits']['capacityBlocked']=False
        self.assertEqual({a['code'] for a in health_codes(candidate)},{'finite_capacity_blocked','capacity_unconfirmed'})
        candidate=healthy_capacity_fence();candidate['resourceLimits']['capacityBlocked']=True
        self.assertEqual({a['code'] for a in health_codes(candidate)},{'finite_capacity_blocked','capacity_unconfirmed'})
        candidate=healthy_capacity_fence();candidate['resourceLimits']['activeAndUnresolvedAdmissions']=1
        self.assertEqual({a['code'] for a in health_codes(candidate)},{'capacity_unconfirmed'})

    def test_health_warns_at_each_current_finite_capacity_threshold(self):
        for name,location,before,warning,blocked in [
            ('workingAdmissions','resourceLimits',79999,80000,100000),
            ('operationReceipts','resourceLimits',7998,7999,9998),
            ('schedulerLifecycleProofs','resourceLimits',7999,8000,10000),
            ('stoppedLifecycleProofs',None,7999,8000,10000)]:
            for value,expect_warning in ((before,False),(warning,True),(blocked,True)):
                with self.subTest(name=name,value=value):
                    candidate=healthy_capacity_fence();target=candidate[location] if location else candidate
                    target[name]=value
                    if location and value==blocked:candidate['resourceLimits']['capacityBlocked']=True
                    alarms=health_codes(candidate)
                    near=[a for a in alarms if a['code']=='finite_capacity_near_limit' and a['resource']==name]
                    self.assertEqual(bool(near),expect_warning)
                    if name=='operationReceipts' and near:
                        self.assertEqual(near[0],{'code':'finite_capacity_near_limit','resource':'operationReceipts','used':value,'limit':10000})
                    if value==blocked:self.assertIn('finite_capacity_blocked',{a['code'] for a in alarms})
                    self.assertNotIn('capacity_unconfirmed',{a['code'] for a in alarms})

    def test_health_distinguishes_receipt_admission_cutoff_from_hard_limit(self):
        for value,blocked in ((9997,False),(9998,True),(9999,True),(10000,True)):
            with self.subTest(value=value):
                candidate=healthy_capacity_fence();candidate['resourceLimits'].update(
                    operationReceipts=value,capacityBlocked=blocked,operationReceiptSaturated=value>=10000)
                alarms=health_codes(candidate);codes={a['code'] for a in alarms}
                self.assertEqual('finite_capacity_blocked' in codes,blocked)
                self.assertNotIn('capacity_unconfirmed',codes)
                self.assertEqual(next(a['limit'] for a in alarms if a.get('resource')=='operationReceipts'),10000)
        candidate=healthy_capacity_fence();candidate['resourceLimits']['operationReceiptSaturated']=True
        self.assertIn('capacity_unconfirmed',{a['code'] for a in health_codes(candidate)})

    def test_member_package_and_gateway_wake_identity_are_separate(self):
        self.assertEqual(PROVIDER_SETTINGS['FCM_ANDROID_PACKAGE'],'app.cool.mobile')
        with self.assertRaises(ValueError):validated_settings({**PROVIDER_SETTINGS,'FCM_ANDROID_PACKAGE':'com.ikanisa.collect'},PROFILE,'a'*64)
        with self.assertRaises(ValueError):validated_settings({**PROVIDER_SETTINGS,'FCM_ANDROID_PACKAGE':'app.cool.mobile.dev'},{**PROFILE,'environment':'production'},'a'*64)
        settings={**PROVIDER_SETTINGS,'COLLECT_SMS_ENABLED':'true','COLLECT_SMS_APPROVAL_SHA256':'b'*64,'FCM_ENABLED':'true','FCM_PROJECT_ID':'member-fixture'}
        with self.assertRaises(ValueError):validated_settings(settings,PROFILE,'a'*64)
        key='-----BEGIN PRIVATE KEY-----\n'+('YQ=='*8)+'\n-----END PRIVATE KEY-----\n'
        gateway={**settings,'OPENSMS_FCM_PROJECT_ID':'gateway-fixture','OPENSMS_FCM_CLIENT_EMAIL':'fixture@gateway-fixture.iam.gserviceaccount.com','OPENSMS_FCM_PRIVATE_KEY':key}
        validated_settings(gateway,PROFILE,'a'*64)
        with self.assertRaises(ValueError):validated_settings({**gateway,'OPENSMS_FCM_CLIENT_EMAIL':'fixture@member-fixture.iam.gserviceaccount.com'},PROFILE,'a'*64)
        with self.assertRaises(ValueError):validated_settings({**gateway,'REQUIRE_ACTUAL_PARTS':'false'},{**PROFILE,'environment':'production'},'a'*64)
        for change in ({'OTP_SEGMENT_INTERVAL_MS':'999'},{'MESSAGE_RETENTION_DAYS':'3651'},{'CALLBACK_ALLOWED_HOSTS':'https://callback.example'}):
            with self.assertRaises(ValueError):validated_settings({**PROVIDER_SETTINGS,**change},PROFILE,'a'*64)
    def test_test_captcha_keys_are_qualification_only_and_pair_is_required(self):
        production={**PROFILE,'environment':'production'}
        valid={**PROVIDER_SETTINGS,'TURNSTILE_SITE_KEY':'opaque-synthetic-site','TURNSTILE_SECRET_KEY':'opaque-synthetic-secret'}
        validated_settings(valid,production,'a'*64)
        for key in TURNSTILE_TEST_SITE_KEYS:
            settings={**valid,'TURNSTILE_SITE_KEY':key}
            validated_settings(settings,PROFILE,'a'*64)
            with self.subTest(site=key),self.assertRaises(ValueError):validated_settings(settings,production,'a'*64)
        for key in TURNSTILE_TEST_SECRET_KEYS:
            settings={**valid,'TURNSTILE_SECRET_KEY':key}
            validated_settings(settings,PROFILE,'a'*64)
            with self.subTest(secret=key),self.assertRaises(ValueError):validated_settings(settings,production,'a'*64)
        for change in ({'TURNSTILE_SITE_KEY':''},{'TURNSTILE_SECRET_KEY':''}):
            with self.assertRaises(ValueError):validated_settings({**valid,**change},PROFILE,'a'*64)
    def test_disabled_default_and_truthful_phone_modes(self):
        self.assertTrue(validated_settings(dict(PROVIDER_SETTINGS),PROFILE,'a'*64)['configuration_only'])
        sms={**PROVIDER_SETTINGS,'AUTH_SMS_ENABLED':'true','AUTH_PHONE_DELIVERY_MODE':'twilio','GOTRUE_SMS_TWILIO_ACCOUNT_SID':'AC'+'a'*32,'GOTRUE_SMS_TWILIO_AUTH_TOKEN':'b'*32,'GOTRUE_SMS_TWILIO_MESSAGE_SERVICE_SID':'MG'+'c'*32}
        validated_settings(sms,PROFILE,'a'*64);validated_settings({**sms,'AUTH_WHATSAPP_ENABLED':'true'},PROFILE,'a'*64)
        with self.assertRaises(ValueError):validated_settings({**sms,'AUTH_PHONE_DELIVERY_MODE':'opensms_hook','AUTH_WHATSAPP_ENABLED':'true'},PROFILE,'a'*64)
        with self.assertRaises(ValueError):validated_settings({**PROVIDER_SETTINGS,'AUTH_PHONE_DELIVERY_MODE':'custom'},PROFILE,'a'*64)
    def test_receipt_credentials_and_gateway_are_independent(self):
        settings={**PROVIDER_SETTINGS,'COLLECT_RECEIPT_SMS_ENABLED':'true','OPENSMS_RECEIPT_BASE_URL':PROFILE['supabase_origin']+'/functions/v1/collect-sms','OPENSMS_RECEIPT_APPLICATION_ID':'receipt','OPENSMS_RECEIPT_APPLICATION_TOKEN':'r'*48,'COLLECT_RECEIPT_SMS_APPROVAL_SHA256':'a'*64,'COLLECT_SMS_ENABLED':'true','COLLECT_SMS_APPROVAL_SHA256':'b'*64}
        validated_settings(settings,PROFILE,'c'*64)
        for change in ({'COLLECT_SMS_ENABLED':'false'},{'OPENSMS_APPLICATION_TOKEN':'r'*48},{'OPENSMS_APPLICATION_ID':'receipt'}):
            with self.assertRaises(ValueError):validated_settings({**settings,**change},PROFILE,'c'*64)
    def test_dotenv_is_roundtrippable_and_never_shell_interpreted(self):
        values={'SYNTHETIC':'$literal\nwith "quotes" and `ticks` and $(text)','EMPTY':''}
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'settings';p.write_text(dotenv(values));p.chmod(0o600);private_file(p);self.assertEqual(read_env(p),values)
            p.chmod(0o644)
            with self.assertRaises(ValueError):private_file(p)
    def test_compose_has_only_tls_ingress_and_pinned_images(self):
        compose=build_compose(PROFILE,verify_vendor());self.assertEqual(len(compose['services']),13)
        self.assertEqual([k for k,v in compose['services'].items() if v.get('ports')],['proxy'])
        self.assertTrue(all('@sha256:' in v['image'] for v in compose['services'].values()))
        auth=compose['services']['auth']['environment'];self.assertEqual(auth['GOTRUE_SMS_AUTOCONFIRM'],'false');self.assertEqual(auth['GOTRUE_HOOK_SEND_SMS_ENABLED'],'${GOTRUE_HOOK_SEND_SMS_ENABLED}')
        self.assertIn('reverse_proxy web:8080',caddyfile(PROFILE,'internal',None))
        with self.assertRaises(ValueError):caddyfile({**PROFILE,'environment':'production'},'internal',None)

class MigrationAndArchive(unittest.TestCase):
    def test_frontend_diagnostic_outputs_do_not_redefine_bound_source(self):
        with tempfile.TemporaryDirectory() as d,patch('scripts.self_hosted.frontend_manifest.ROOTS',('test',)):
            root=Path(d);golden=root/'test/goldens/baseline.png';golden.parent.mkdir(parents=True);golden.write_bytes(b'original golden')
            test=root/'test/goldens/golden_test.dart';test.write_text('original test source')
            before=inventory(root)
            diagnostics=root/'test/goldens/failures';diagnostics.mkdir();(diagnostics/'difference.png').write_bytes(b'generated difference')
            self.assertEqual(inventory(root),before)
            golden.write_bytes(b'changed golden');self.assertNotEqual(inventory(root)['sha256'],before['sha256'])
            golden.write_bytes(b'original golden');test.write_text('changed test source');self.assertNotEqual(inventory(root)['sha256'],before['sha256'])
    def test_every_reviewed_migration_has_an_admitted_transaction_envelope(self):
        root=Path(__file__).resolve().parents[2]
        for record in migrations(root):
            sql=(root/'supabase/migrations'/record['name']).read_text()
            with self.subTest(migration=record['name']):
                actual=transaction_sql(sql,record,'a'*64,uuid.uuid4())
                self.assertIn('INSERT INTO supabase_migrations.collect_installation_steps',actual)
                self.assertEqual(actual.count('INSERT INTO supabase_migrations.collect_installation_steps'),1)
    def test_health_alarms_use_real_controller_fields_and_keep_unknown_obligations(self):
        fence=healthy_capacity_fence();fence['retainedUnquantifiedUnknownObligations']=1;fence['resourceLimits']['workingAdmissions']=80000
        alarms=evaluate(fence,[{'service':'db','state':'running','health':'healthy'}],{'free_bytes':20*1024**3,'free_ratio':.5},90,'a'*64,{'db'})
        self.assertEqual({a['code'] for a in alarms},{'finite_capacity_near_limit','unresolved_external_effects'})
        self.assertIn('source_mismatch',{a['code'] for a in evaluate(fence,[],{'free_bytes':20*1024**3,'free_ratio':.5},90,'b'*64,{'db'})})
    def test_original_transaction_statements_and_receipt_commit_together(self):
        sql='-- migration\nBEGIN;\nCREATE TABLE example(id integer);\nCOMMIT;\n';record={'name':'20261101000000_example.sql','sha256':hashlib.sha256(sql.encode()).hexdigest(),'transaction':'outer'}
        rendered=transaction_sql(sql,record,'a'*64,uuid.uuid4());self.assertLess(rendered.index('INSERT INTO supabase_migrations'),rendered.rindex('COMMIT;'));self.assertIn('CREATE TABLE example(id integer);',rendered)
        raw='CREATE TABLE example(id integer);\n';wrapped=transaction_sql(raw,{**record,'transaction':'wrap'},'a'*64,uuid.uuid4());self.assertTrue(wrapped.startswith('BEGIN;'));self.assertTrue(wrapped.endswith('COMMIT;\n'))
        with self.assertRaises(ValueError):transaction_sql(sql,{**record,'transaction':'wrap'},'a'*64,uuid.uuid4())
    def test_restore_rejects_path_escape_links_special_files_and_duplicate_paths(self):
        for name in ('../escape','/absolute','safe/../../escape','safe\\escape'):
            with self.subTest(name=name),self.assertRaises(ValueError):safe_member(tarfile.TarInfo(name),set(),0,1024,10,1000,1000)
        for kind in (tarfile.SYMTYPE,tarfile.LNKTYPE,tarfile.CHRTYPE,tarfile.FIFOTYPE):
            item=tarfile.TarInfo('item');item.type=kind
            with self.assertRaises(ValueError):safe_member(item,set(),0,1024,10,1000,1000)
        item=tarfile.TarInfo('safe');seen=set();safe_member(item,seen,0,1024,10,1000,1000)
        with self.assertRaises(ValueError):safe_member(item,seen,0,1024,10,1000,1000)
    def test_restore_preserves_data_uid_and_bounds_privileges_and_volume(self):
        data=tarfile.TarInfo('data/db/base/file');data.uid=777;data.gid=888;data.size=50
        copied,total=safe_member(data,set(),0,100,10,1000,1000);self.assertEqual((copied.uid,copied.gid,total),(777,888,50))
        config=tarfile.TarInfo('private/keys.json');config.uid=777;copied,_=safe_member(config,set(),0,100,10,1000,1000);self.assertEqual(copied.uid,1000)
        data.mode=0o4755
        with self.assertRaises(ValueError):safe_member(data,set(),0,100,10,1000,1000)
        data.mode=0o600
        with self.assertRaises(ValueError):safe_member(data,set(),51,100,10,1000,1000)
    def test_frontend_association_files_allowed_but_hidden_payload_denied(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);(root/'index.html').write_text('index');(root/'.well-known').mkdir();(root/'.well-known/assetlinks.json').write_text('[]')
            self.assertEqual(len(tree(root)),2);(root/'.env').write_text('secret')
            with self.assertRaises(ValueError):tree(root)
    def test_real_age_encrypt_decrypt_and_corruption_refusal(self):
        with tempfile.TemporaryDirectory() as d:
            identity=Path(d)/'identity';subprocess.run(['age-keygen','-o',str(identity)],capture_output=True,check=True,timeout=15)
            recipient=subprocess.run(['age-keygen','-y',str(identity)],capture_output=True,check=True,timeout=15).stdout.decode().strip()
            plain=b'collect synthetic Auth, Storage, private keys and database stream\0\n'
            encrypted=subprocess.run(['age','-r',recipient],input=plain,capture_output=True,check=True,timeout=15).stdout
            self.assertNotIn(plain,encrypted);self.assertEqual(subprocess.run(['age','-d','-i',str(identity)],input=encrypted,capture_output=True,check=True,timeout=15).stdout,plain)
            corrupted=bytearray(encrypted);corrupted[-2]^=1
            self.assertNotEqual(subprocess.run(['age','-d','-i',str(identity)],input=bytes(corrupted),capture_output=True,timeout=15).returncode,0)

if __name__=='__main__':unittest.main()
