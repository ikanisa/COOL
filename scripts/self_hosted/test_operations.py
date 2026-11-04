import copy
from contextlib import redirect_stdout,redirect_stderr
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import uuid
from scripts.self_hosted.prepare import PROVIDER_SETTINGS,dotenv,build_compose,verify_vendor,caddyfile,prepare
from scripts.self_hosted.configure import validated_settings,read_env,private_file,TURNSTILE_TEST_SITE_KEYS,TURNSTILE_TEST_SECRET_KEYS
from scripts.self_hosted.database import transaction_sql,migrations
from scripts.self_hosted.recovery import safe_member
from scripts.self_hosted.assets import tree
from scripts.self_hosted.health import evaluate,capacity_detail,health,main as health_main
from scripts.self_hosted.frontend_manifest import inventory

PROFILE={'format':'collect.deployment.v1','id':'test','mode':'self_hosted','environment':'qualification','supabase_origin':'https://supabase.collect.example','admin_origin':'https://admin.collect.example','member_api_origin':'https://api.collect.example','public_origin':'https://collect.example','google_callback_origin':'https://admin.collect.example'}

def healthy_capacity_fence():
    return {'contractVersion':3,'mode':'open','sourceSha256':'a'*64,'effectiveUnresolvedAdmissions':0,'retainedUnknownObligations':0,
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
    def test_service_health_requires_confirmed_docker_health(self):
        fence=healthy_capacity_fence();disk={'free_bytes':20*1024**3,'free_ratio':.5}
        cases=[({'service':'db','state':'running','health':'healthy'},None),
            ({'service':'db','state':'running','health':'starting'},'service_unavailable'),
            ({'service':'db','state':'running','health':'unhealthy'},'service_unavailable'),
            ({'service':'db','state':'exited','health':None},'service_unavailable'),
            ({'service':'db','state':'running','health':None},'service_health_unconfirmed'),
            ({'service':'db','state':'running','health':''},'service_health_unconfirmed'),
            ({'service':'db','state':'running','health':'unexpected'},'service_health_unconfirmed'),
            ({'service':'db','state':'running'},'service_health_unconfirmed')]
        for service,expected in cases:
            with self.subTest(service=service):
                alarms=evaluate(fence,[service],disk,90,'a'*64,{'db'})
                self.assertEqual(alarms,[] if expected is None else [{'code':expected,'service':'db'}])
        self.assertEqual(evaluate(fence,[],disk,90,'a'*64,{'db'}),
            [{'code':'service_missing','service':'db'}])

    def test_prepare_refuses_colliding_frontend_origins_before_output_or_vendor_work(self):
        profile={**PROFILE,'public_origin':PROFILE['admin_origin']}
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);source=root/'profile.json';output=root/'release'
            source.write_text(json.dumps(profile))
            with patch('scripts.self_hosted.prepare.verify_vendor') as vendor, \
                 patch('scripts.self_hosted.prepare.subprocess.run') as command:
                with self.assertRaisesRegex(ValueError,'Admin and public origins must differ'):
                    prepare(source,output)
            self.assertFalse(output.exists())
            vendor.assert_not_called();command.assert_not_called()
            cli=subprocess.run([sys.executable,'-B','-m','scripts.self_hosted.prepare',
                '--profile',str(source),'--output',str(output)],capture_output=True,text=True,timeout=15)
            self.assertNotEqual(cli.returncode,0)
            self.assertEqual(cli.stdout,'')
            self.assertIn('FrontendOriginsMustDiffer',cli.stderr)
            self.assertNotIn(profile['admin_origin'],cli.stderr)
            self.assertFalse(output.exists())

    def test_capacity_detail_reports_owner_status_counts_including_stopped_proofs(self):
        fence=healthy_capacity_fence()
        fence['resourceLimits'].update(workingAdmissions=17,activeAndUnresolvedAdmissions=3,
            operationReceipts=9997,schedulerLifecycleProofs=9999)
        fence['stoppedLifecycleProofs']=9999
        detail=capacity_detail(fence,'a'*64)
        self.assertEqual(detail['status'],'confirmed')
        self.assertEqual(detail['observation'],'owner_status_read')
        self.assertIs(detail['authorizes_operations'],False)
        resources={item['resource']:item for item in detail['resources']}
        self.assertEqual(resources['workingAdmissions']['remaining'],99983)
        self.assertEqual(resources['activeAndUnresolvedAdmissions']['remaining'],5)
        self.assertEqual(resources['operationReceipts'],{'resource':'operationReceipts',
            'used':9997,'threshold':9998,'remaining':1,'hard_limit':10000})
        self.assertEqual(resources['schedulerLifecycleProofs']['remaining'],1)
        self.assertEqual(resources['stoppedLifecycleProofs']['remaining'],1)
        # Counts beyond the cutoff never turn into negative headroom.
        fence['resourceLimits'].update(operationReceipts=10000,operationReceiptSaturated=True,capacityBlocked=True)
        detail=capacity_detail(fence,'a'*64)
        self.assertEqual(next(r['remaining'] for r in detail['resources'] if r['resource']=='operationReceipts'),0)

    def test_capacity_detail_withholds_counts_for_unconfirmed_inputs(self):
        for mutation in ('missing','invalid','inconsistent','wrong_source','invalid_source'):
            with self.subTest(mutation=mutation):
                fence=healthy_capacity_fence();source='a'*64
                if mutation=='missing':del fence['stoppedLifecycleProofs']
                if mutation=='invalid':fence['resourceLimits']['operationReceipts']=True
                if mutation=='inconsistent':fence['resourceLimits']['activeAndUnresolvedAdmissions']=1
                if mutation=='wrong_source':fence['sourceSha256']='b'*64
                if mutation=='invalid_source':source='not-a-source';fence['sourceSha256']=source
                self.assertEqual(capacity_detail(fence,source),{'status':'unconfirmed','resources':[]})

    def test_capacity_detail_is_opt_in_on_existing_health_operator(self):
        class FakeOperator:
            meta={'profile_sha256':'b'*64,'source_sha256':'a'*64}
            def __init__(self,root):self.root=root
            def status(self):return {'services':[{'service':'db','state':'running','health':'healthy'}]}
            def sql(self,query):
                self.query=query
                return ('t\n'+json.dumps(healthy_capacity_fence())+'\n').encode()
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);(root/'images.lock.json').write_text(json.dumps({'services':{'db':{},'backup':{}}}))
            op=FakeOperator(root)
            usage=type('Usage',(),{'free':20*1024**3,'total':40*1024**3})()
            with patch('scripts.self_hosted.health.shutil.disk_usage',return_value=usage), \
                 patch('scripts.self_hosted.health.ssl._ssl._test_decode_cert',return_value={'notAfter':'future'}), \
                 patch('scripts.self_hosted.health.ssl.cert_time_to_seconds',return_value=4102444800):
                default=health(op);detailed=health(op,include_capacity_detail=True)
                with patch.object(op,'status',return_value={'services':[{'service':'db','state':'running','health':''}]}):
                    unconfirmed=health(op)
            self.assertNotIn('capacity_detail',default)
            self.assertEqual(default['format'],'collect.selfhost.health.v1')
            self.assertEqual(detailed['format'],default['format'])
            self.assertEqual(detailed['capacity_detail']['status'],'confirmed')
            self.assertEqual(unconfirmed['status'],'attention_required')
            self.assertIn({'code':'service_health_unconfirmed','service':'db'},unconfirmed['alarms'])
            self.assertIn("private.collect_assert_deployment('"+'b'*64+"')",op.query)
            self.assertIn('private.collect_fence_owner_status_v3()',op.query)

    def test_health_cli_routes_optional_detail_and_fails_closed_for_missing_release(self):
        out=io.StringIO();err=io.StringIO()
        with patch('scripts.self_hosted.health.Operator',return_value=object()), \
             patch('scripts.self_hosted.health.health',return_value={'status':'healthy'}) as call, \
             redirect_stdout(out),redirect_stderr(err):
            self.assertEqual(health_main(['--release','/synthetic/release','--capacity-detail']),0)
        self.assertTrue(call.call_args.kwargs['include_capacity_detail'])
        self.assertEqual(json.loads(out.getvalue()),{'status':'healthy'})
        self.assertEqual(err.getvalue(),'')
        missing=subprocess.run([sys.executable,'-B','-m','scripts.self_hosted.health',
            '--release','/definitely-absent-collect-release','--capacity-detail'],capture_output=True,text=True)
        self.assertEqual(missing.returncode,3)
        self.assertEqual(json.loads(missing.stderr)['status'],'health_unconfirmed')
        self.assertNotIn('/definitely-absent-collect-release',missing.stderr)

    def test_health_cli_redacts_empty_or_non_object_controller_status(self):
        class FakeOperator:
            meta={'profile_sha256':'b'*64,'source_sha256':'a'*64}
            root=Path('/synthetic')
            def __init__(self,raw):self.raw=raw
            def status(self):return {'services':[]}
            def sql(self,query):return self.raw
        for raw in (b'',b'[]\n',b'null\n'):
            with self.subTest(raw=raw):
                out=io.StringIO();err=io.StringIO()
                with patch('scripts.self_hosted.health.Operator',return_value=FakeOperator(raw)), \
                     redirect_stdout(out),redirect_stderr(err):
                    self.assertEqual(health_main(['--release','/synthetic','--capacity-detail']),3)
                self.assertEqual(out.getvalue(),'')
                self.assertEqual(json.loads(err.getvalue()),{'status':'health_unconfirmed',
                    'error_class':'ValueError','private_values_disclosed':False})

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

    def test_health_alarms_for_effective_unresolved_admissions_and_unknown_counts(self):
        candidate=healthy_capacity_fence();self.assertEqual(health_codes(candidate),[])
        candidate['effectiveUnresolvedAdmissions']=1
        self.assertIn({'code':'unresolved_admissions','count':1},health_codes(candidate))
        for value in (None,True,False,-1,'1',1.0):
            with self.subTest(value=value):
                candidate=healthy_capacity_fence();candidate['effectiveUnresolvedAdmissions']=value
                self.assertIn({'code':'unresolved_admissions_unconfirmed'},health_codes(candidate))
        candidate=healthy_capacity_fence();del candidate['effectiveUnresolvedAdmissions'];candidate['unresolvedAdmissions']=0
        self.assertIn({'code':'unresolved_admissions_unconfirmed'},health_codes(candidate))

    def test_stopped_admission_proof_does_not_hide_retained_unknown_obligation(self):
        candidate=healthy_capacity_fence();candidate.update(rawUnresolvedAdmissions=1,unresolvedAdmissions=1,
            effectiveUnresolvedAdmissions=0,retainedUnquantifiedUnknownObligations=1)
        codes={alarm['code'] for alarm in health_codes(candidate)}
        self.assertEqual(codes,{'unresolved_external_effects'})

    def test_retained_unknown_counts_validate_independently_without_losing_known_positives(self):
        names=('retainedUnknownObligations','retainedUnquantifiedUnknownObligations')
        candidate=healthy_capacity_fence();self.assertEqual(health_codes(candidate),[])
        for name in names:
            other=next(item for item in names if item!=name)
            for invalid in ('missing',None,True,False,-1,'1',1.0,[],{}):
                for known in (0,1):
                    with self.subTest(field=name,invalid=invalid,known=known):
                        candidate=healthy_capacity_fence();candidate[other]=known
                        if invalid=='missing':del candidate[name]
                        else:candidate[name]=invalid
                        codes={alarm['code'] for alarm in health_codes(candidate)}
                        self.assertIn('retained_unknown_obligations_unconfirmed',codes)
                        self.assertEqual('unresolved_external_effects' in codes,known>0)
        candidate=healthy_capacity_fence();candidate.update({name:2 for name in names})
        self.assertEqual(health_codes(candidate),[{'code':'unresolved_external_effects'}])

    def test_retained_unknown_count_failure_sets_health_cli_attention(self):
        class FakeOperator:
            meta={'profile_sha256':'b'*64,'source_sha256':'a'*64}
            def __init__(self,root):self.root=root
            def status(self):return {'services':[{'service':'db','state':'running','health':'healthy'}]}
            def sql(self,query):
                fence=healthy_capacity_fence();fence['retainedUnknownObligations']=None
                fence['retainedUnquantifiedUnknownObligations']=1
                return ('t\n'+json.dumps(fence)+'\n').encode()
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);(root/'images.lock.json').write_text(json.dumps({'services':{'db':{},'backup':{}}}))
            usage=type('Usage',(),{'free':20*1024**3,'total':40*1024**3})();out=io.StringIO();err=io.StringIO()
            with patch('scripts.self_hosted.health.Operator',return_value=FakeOperator(root)), \
                 patch('scripts.self_hosted.health.shutil.disk_usage',return_value=usage), \
                 patch('scripts.self_hosted.health.ssl._ssl._test_decode_cert',return_value={'notAfter':'future'}), \
                 patch('scripts.self_hosted.health.ssl.cert_time_to_seconds',return_value=4102444800), \
                 redirect_stdout(out),redirect_stderr(err):
                self.assertEqual(health_main(['--release',str(root)]),2)
            result=json.loads(out.getvalue());self.assertEqual(result['status'],'attention_required')
            self.assertEqual({a['code'] for a in result['alarms']},{'retained_unknown_obligations_unconfirmed','unresolved_external_effects'})
            self.assertIsNone(result['retained_unknown_obligations']);self.assertEqual(result['retained_unquantified_unknown_obligations'],1)
            self.assertEqual(err.getvalue(),'')

    def test_unresolved_admission_sets_health_cli_attention_exit(self):
        class FakeOperator:
            meta={'profile_sha256':'b'*64,'source_sha256':'a'*64}
            def __init__(self,root,missing=False):self.root=root;self.missing=missing
            def status(self):return {'services':[{'service':'db','state':'running','health':'healthy'}]}
            def sql(self,query):
                fence=healthy_capacity_fence();fence['unresolvedAdmissions']=0
                if self.missing:del fence['effectiveUnresolvedAdmissions']
                else:fence['effectiveUnresolvedAdmissions']=1
                return ('t\n'+json.dumps(fence)+'\n').encode()
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);(root/'images.lock.json').write_text(json.dumps({'services':{'db':{},'backup':{}}}))
            usage=type('Usage',(),{'free':20*1024**3,'total':40*1024**3})()
            for missing in (False,True):
                with self.subTest(missing=missing):
                    out=io.StringIO();err=io.StringIO()
                    with patch('scripts.self_hosted.health.Operator',return_value=FakeOperator(root,missing)), \
                         patch('scripts.self_hosted.health.shutil.disk_usage',return_value=usage), \
                         patch('scripts.self_hosted.health.ssl._ssl._test_decode_cert',return_value={'notAfter':'future'}), \
                         patch('scripts.self_hosted.health.ssl.cert_time_to_seconds',return_value=4102444800), \
                         redirect_stdout(out),redirect_stderr(err):
                        self.assertEqual(health_main(['--release',str(root)]),2)
                    result=json.loads(out.getvalue());self.assertEqual(result['status'],'attention_required')
                    self.assertIn({'code':'unresolved_admissions_unconfirmed'} if missing else {'code':'unresolved_admissions','count':1},result['alarms'])
                    self.assertIsNone(result['unresolved_admissions']) if missing else self.assertEqual(result['unresolved_admissions'],1)
                    self.assertEqual(err.getvalue(),'')

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
    def test_enabled_opensms_settings_match_signed_hook_contract(self):
        base={**PROVIDER_SETTINGS,'AUTH_SMS_ENABLED':'true','AUTH_PHONE_DELIVERY_MODE':'opensms_hook',
            'COLLECT_SMS_ENABLED':'true','COLLECT_SMS_APPROVAL_SHA256':'a'*64,
            'OPENSMS_BASE_URL':PROFILE['supabase_origin']+'/functions/v1/collect-sms',
            'OPENSMS_APPLICATION_ID':'otp-app','OPENSMS_APPLICATION_TOKEN':'app_'+'a'*64,
            'OPENSMS_SENDER_LABEL':'Collect','OPENSMS_DISPATCH_TTL_SECONDS':'120'}
        for change in ({},{'OPENSMS_APPLICATION_ID':'A'}, {'OPENSMS_APPLICATION_ID':'A'*80},
            {'OPENSMS_APPLICATION_TOKEN':'app_'+'x'*32}, {'OPENSMS_APPLICATION_TOKEN':'app_'+'x'*252},
            {'OPENSMS_SENDER_LABEL':''}, {'OPENSMS_SENDER_LABEL':"O'Brien"},
            {'OPENSMS_SENDER_LABEL':'A'*40}, {'OPENSMS_DISPATCH_TTL_SECONDS':'30'},
            {'OPENSMS_DISPATCH_TTL_SECONDS':'030'}, {'OPENSMS_DISPATCH_TTL_SECONDS':'300'}):
            with self.subTest(valid_fields=tuple(change)):
                self.assertTrue(validated_settings({**base,**change},PROFILE,'a'*64)['configuration_only'])
        for change in ({'OPENSMS_APPLICATION_ID':'_not-an-id'}, {'OPENSMS_APPLICATION_ID':'A'*81},
            {'OPENSMS_APPLICATION_TOKEN':'x'*32}, {'OPENSMS_APPLICATION_TOKEN':'app_'+'x'*31},
            {'OPENSMS_APPLICATION_TOKEN':'app_'+'x'*253}, {'OPENSMS_APPLICATION_TOKEN':'app_'+'x'*32+'='},
            {'OPENSMS_SENDER_LABEL':' leading'}, {'OPENSMS_SENDER_LABEL':'bad\nlabel'},
            {'OPENSMS_SENDER_LABEL':'A'*41}, {'OPENSMS_DISPATCH_TTL_SECONDS':'0030'},
            {'OPENSMS_DISPATCH_TTL_SECONDS':'٣٠'}, {'OPENSMS_DISPATCH_TTL_SECONDS':'29'},
            {'OPENSMS_DISPATCH_TTL_SECONDS':'301'}):
            with self.subTest(invalid_fields=tuple(change)),self.assertRaises(ValueError):
                validated_settings({**base,**change},PROFILE,'a'*64)
        # Incomplete, disabled hook settings remain available for staging.
        disabled={**PROVIDER_SETTINGS,'AUTH_PHONE_DELIVERY_MODE':'opensms_hook',
            'OPENSMS_APPLICATION_ID':'_draft','OPENSMS_APPLICATION_TOKEN':'draft'}
        self.assertTrue(validated_settings(disabled,PROFILE,'a'*64)['configuration_only'])
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
