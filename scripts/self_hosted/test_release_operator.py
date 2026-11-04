import copy
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from scripts.self_hosted.release_operator import Operator
from scripts.self_hosted.prepare import CONFIGURATION_FILES,PROVIDER_SETTINGS,dotenv,seal_configuration
from scripts.self_hosted.configure import validated_settings
from scripts.supabase.deployment_profile import profile_sha256


class OperatorDiagnostics(unittest.TestCase):
    def setUp(self):
        self.area=tempfile.TemporaryDirectory()
        self.addCleanup(self.area.cleanup)
        # macOS exposes its temporary directory through /var -> /private/var;
        # production Operator requires a physical, non-symlinked release path.
        self.root=Path(self.area.name).resolve()
        (self.root/'private').mkdir()
        self.operator=object.__new__(Operator)
        self.operator.root=self.root

    def logs(self):
        return list((self.root/'private').glob('operation-*.log'))

    def test_timeout_retains_only_private_stderr_and_scrubs_exception(self):
        timeout=subprocess.TimeoutExpired(['docker','secret-argument'],5,
            output=b'secret-output',stderr=b'secret-diagnostic\xff')
        with patch('scripts.self_hosted.release_operator.subprocess.run',side_effect=timeout) as run:
            with self.assertRaises(subprocess.TimeoutExpired) as caught:
                self.operator.run(['docker','secret-argument'],input_bytes=b'secret-input',timeout=5)
        run.assert_called_once_with(['docker','secret-argument'],input=b'secret-input',capture_output=True,timeout=5)
        error=caught.exception
        self.assertIs(error,timeout)
        self.assertEqual(error.cmd,'operation')
        self.assertEqual(error.args,('operation',5))
        self.assertIsNone(error.output)
        self.assertIsNone(error.stdout)
        self.assertIsNone(error.stderr)
        self.assertTrue(error.private_diagnostic_retained)
        self.assertNotIn('secret',repr(error))
        self.assertNotIn('secret',str(error))
        logs=self.logs();self.assertEqual(len(logs),1)
        self.assertEqual(logs[0].read_bytes(),b'secret-diagnostic\xff')
        self.assertEqual(stat.S_IMODE(logs[0].stat().st_mode),0o600)

    def test_missing_stderr_and_bounded_truncation(self):
        for stderr,expected in ((None,b''),(b'x'*(1024*1024+1),b'x'*(1024*1024)+b'\n[stderr truncated]\n')):
            with self.subTest(stderr_size=None if stderr is None else len(stderr)):
                error=subprocess.TimeoutExpired('private command',9,output=b'private output',stderr=stderr)
                with patch('scripts.self_hosted.release_operator.subprocess.run',side_effect=error):
                    with self.assertRaises(subprocess.TimeoutExpired):self.operator.run(['private command'])
                log=max(self.logs(),key=lambda p:p.stat().st_size)
                self.assertEqual(log.read_bytes(),expected)
                self.assertTrue(error.private_diagnostic_retained)
                log.unlink()

    def test_log_creation_failure_preserves_and_scrubs_timeout(self):
        error=subprocess.TimeoutExpired(['secret-command'],3,output=b'secret-output',stderr=b'secret-error')
        with patch('scripts.self_hosted.release_operator.subprocess.run',side_effect=error), \
             patch('scripts.self_hosted.release_operator.os.open',side_effect=PermissionError('secret-path')):
            with self.assertRaises(subprocess.TimeoutExpired) as caught:self.operator.run(['secret-command'])
        self.assertIs(caught.exception,error)
        self.assertFalse(error.private_diagnostic_retained)
        self.assertEqual(error.cmd,'operation')
        self.assertEqual(error.args,('operation',3))
        self.assertIsNone(error.stdout)
        self.assertIsNone(error.stderr)
        self.assertNotIn('secret',repr(error))
        self.assertNotIn('secret',str(error))
        self.assertEqual(self.logs(),[])

    def test_start_private_stops_after_compose_timeout(self):
        self.operator.docker='synthetic-docker';self.operator.project='collect-test'
        failure=subprocess.TimeoutExpired(['private-compose'],60,stderr=b'private timeout')
        with patch.object(self.operator,'docker_preflight',return_value={'services':{'db':{},'proxy':{},'web':{},'functions':{}}}), \
             patch.object(self.operator,'prepare_database_tls',return_value={'postgres_uid':1}), \
             patch('scripts.self_hosted.release_operator.subprocess.run',side_effect=failure) as run:
            with self.assertRaises(subprocess.TimeoutExpired):self.operator.start_private()
        self.assertEqual(run.call_count,1)
        self.assertEqual(failure.cmd,'operation')
        self.assertEqual(len(self.logs()),1)
        self.assertEqual(self.logs()[0].read_bytes(),b'private timeout')

    def test_publish_refuses_colliding_frontend_origins_before_docker(self):
        self.operator.profile={'admin_origin':'https://same.example','public_origin':'https://same.example'}
        with patch.object(self.operator,'docker_preflight') as preflight, \
             patch.object(self.operator,'validate_runtime_database') as database:
            with self.assertRaisesRegex(ValueError,'Admin and public origins must differ'):
                self.operator.publish()
        preflight.assert_not_called();database.assert_not_called()

    def test_production_publish_rejects_missing_captcha_after_private_configuration(self):
        self.operator.profile={'environment':'production','admin_origin':'https://admin.example',
            'public_origin':'https://public.example'}
        self.operator.meta={'source_sha256':'a'*64}
        settings={**PROVIDER_SETTINGS,'SMTP_HOST':'smtp.example','SMTP_PORT':'587',
            'SMTP_USER':'synthetic-user','SMTP_PASS':'synthetic-password',
            'SMTP_ADMIN_EMAIL':'sender@example.com','TURNSTILE_SITE_KEY':'',
            'TURNSTILE_SECRET_KEY':''}
        # Private preparation accepts incomplete configuration, but publication
        # must fail before assets or the public listener are started.
        self.assertTrue(validated_settings(settings,self.operator.profile,'a'*64)['smtp_configured'])
        (self.root/'private'/'provider-settings.json').write_text(json.dumps(settings))
        with patch.object(self.operator,'docker_preflight') as preflight, \
             patch.object(self.operator,'validate_runtime_database') as database, \
             patch('scripts.self_hosted.assets.verify_assets') as assets, \
             patch.object(self.operator,'compose') as compose:
            with self.assertRaisesRegex(ValueError,'Production Auth SMTP and abuse controls must be configured'):
                self.operator.publish()
        preflight.assert_not_called();database.assert_not_called();assets.assert_not_called();compose.assert_not_called()

    def test_publish_scrubs_malformed_nested_service_account_json_from_exception_chain(self):
        self.operator.profile={'environment':'qualification','admin_origin':'https://admin.example',
            'public_origin':'https://public.example'}
        self.operator.meta={'source_sha256':'a'*64}
        secret='synthetic-private-key-never-disclose'
        settings={**PROVIDER_SETTINGS,'FCM_SERVICE_ACCOUNT_JSON':'{"private_key":"'+secret+'"'}
        (self.root/'private'/'provider-settings.json').write_text(json.dumps(settings))
        with patch.object(self.operator,'docker_preflight') as preflight, \
             patch.object(self.operator,'validate_runtime_database') as database, \
             patch('scripts.self_hosted.assets.verify_assets') as assets, \
             patch.object(self.operator,'compose') as compose:
            with self.assertRaisesRegex(ValueError,'Provider settings could not be parsed') as caught:
                self.operator.publish()
        error=caught.exception
        self.assertNotIsInstance(error,json.JSONDecodeError)
        self.assertIsNone(error.__cause__);self.assertIsNone(error.__context__)
        self.assertNotIn(secret,str(error));self.assertNotIn(secret,repr(error));self.assertNotIn(secret,repr(vars(error)))
        preflight.assert_not_called();database.assert_not_called();assets.assert_not_called();compose.assert_not_called()

    def test_publish_uses_bounded_provider_reader_before_publication(self):
        self.operator.profile={'environment':'qualification','admin_origin':'https://admin.example',
            'public_origin':'https://public.example'}
        self.operator.meta={'source_sha256':'a'*64}
        secret=b'synthetic-private-field'
        cases=(('malformed',b'{"field":"'+secret+b'"'),
               ('invalid_utf8',b'{"field":"'+secret+b'\xff"}'),
               ('nested',b'{"field":'+b'['*12000+b'"'+secret+b'"'+b']'*12000+b'}'),
               ('oversized',b'{"field":"'+secret+b'x'*32768+b'"}'))
        for name,data in cases:
            with self.subTest(case=name):
                (self.root/'private'/'provider-settings.json').write_bytes(data)
                with patch('scripts.self_hosted.configure.MAX_PROVIDER_SETTINGS_BYTES',32768), \
                     patch.object(self.operator,'docker_preflight') as preflight, \
                     patch.object(self.operator,'validate_runtime_database') as database, \
                     patch('scripts.self_hosted.assets.verify_assets') as assets, \
                     patch.object(self.operator,'compose') as compose:
                    with self.assertRaisesRegex(ValueError,'Provider settings could not be parsed') as caught:
                        self.operator.publish()
                error=caught.exception
                self.assertIsNone(error.__cause__);self.assertIsNone(error.__context__)
                self.assertNotIn(secret.decode(),repr(error));self.assertNotIn(secret.decode(),repr(vars(error)))
                preflight.assert_not_called();database.assert_not_called();assets.assert_not_called();compose.assert_not_called()

    def test_publish_validates_provider_settings_before_service_probes(self):
        self.operator.profile={'environment':'qualification','admin_origin':'https://admin.example',
            'public_origin':'https://public.example'}
        self.operator.meta={'profile_sha256':'a'*64,'source_sha256':'b'*64}
        settings={**PROVIDER_SETTINGS};events=[];config={'synthetic':'model'}
        def read(_):events.append('read');return settings
        def validate(*_):events.append('validate');return {'smtp_configured':True}
        def preflight():events.append('preflight');return config
        def database():events.append('database')
        def assets(_):events.append('assets')
        def auth(model,observed):
            self.assertIs(model,config);self.assertIs(observed,settings);events.append('auth')
        def compose(*_,**__):events.append('compose')
        with patch('scripts.self_hosted.release_operator.read_provider_settings',side_effect=read), \
             patch('scripts.self_hosted.release_operator.validated_settings',side_effect=validate), \
             patch.object(self.operator,'docker_preflight',side_effect=preflight), \
             patch.object(self.operator,'validate_runtime_database',side_effect=database), \
             patch('scripts.self_hosted.assets.verify_assets',side_effect=assets), \
             patch.object(self.operator,'validate_running_auth',side_effect=auth), \
             patch.object(self.operator,'compose',side_effect=compose):
            result=self.operator.publish()
        self.assertTrue(result['public_listener_started'])
        self.assertEqual(events,['read','validate','preflight','database','assets','auth','compose'])

    def test_publish_cli_explains_origin_collision_without_disclosing_values(self):
        profile={'format':'collect.deployment.v1','id':'synthetic','mode':'self_hosted',
            'environment':'qualification','supabase_origin':'https://identity.example',
            'admin_origin':'https://same.example','public_origin':'https://same.example',
            'member_api_origin':'https://api.example','google_callback_origin':'https://same.example'}
        commit='a'*40;content=b'synthetic upstream source\n';name='volumes/db/jwt.sql'
        upstream=self.root/'upstream'/name;upstream.parent.mkdir(parents=True);upstream.write_bytes(content)
        source=self.root/'source';source.mkdir()
        source_upstream=source/'deploy/self-hosted/upstream'/name;source_upstream.parent.mkdir(parents=True);source_upstream.write_bytes(content)
        lock=source/'deploy/self-hosted/upstream.lock.json'
        lock.write_text(json.dumps({'format':'collect.selfhost.upstream.v1','commit':commit,
            'files':[{'path':name,'sha256':hashlib.sha256(content).hexdigest()}]}))
        files=[]
        for path in sorted(source.rglob('*')):
            if path.is_file():
                data=path.read_bytes();files.append({'path':path.relative_to(source).as_posix(),'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
        digest=hashlib.sha256(json.dumps(files,sort_keys=True,separators=(',',':')).encode()).hexdigest()
        meta={'format':'collect.selfhost.release.v1','profile':profile,
            'profile_sha256':profile_sha256(profile),'source_sha256':digest,'upstream_commit':commit}
        (self.root/'source-manifest.json').write_text(json.dumps({'format':'collect.selfhost.source.v1','sha256':digest,'files':files}))
        for name in CONFIGURATION_FILES:
            path=self.root/name;path.parent.mkdir(parents=True,exist_ok=True)
            path.write_text(json.dumps(meta) if name=='release.json' else '{}')
            if name.startswith('private/'):path.chmod(0o600)
        seal_configuration(self.root)
        result=subprocess.run([sys.executable,'-B','-m','scripts.self_hosted.release_operator',
            '--release',str(self.root),'publish','--apply'],capture_output=True,text=True,timeout=15)
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(result.stdout,'')
        payload=json.loads(result.stderr)
        self.assertEqual(payload['error_class'],'FrontendOriginsMustDiffer')
        self.assertFalse(payload['private_values_disclosed'])
        self.assertNotIn(profile['admin_origin'],result.stderr)

    def test_publish_stops_after_compose_timeout(self):
        self.operator.docker='synthetic-docker';self.operator.project='collect-test'
        self.operator.profile={'environment':'qualification','admin_origin':'https://admin.example','public_origin':'https://public.example'}
        self.operator.meta={'profile_sha256':'a'*64,'source_sha256':'b'*64}
        (self.root/'private'/'provider-settings.json').write_text('{}')
        failure=subprocess.TimeoutExpired(['private-compose'],60,stderr=b'private timeout')
        with patch.object(self.operator,'docker_preflight'), \
             patch.object(self.operator,'validate_runtime_database'), \
             patch('scripts.self_hosted.release_operator.validated_settings',return_value={}), \
             patch('scripts.self_hosted.assets.verify_assets') as verify, \
             patch.object(self.operator,'validate_running_auth') as auth, \
             patch('scripts.self_hosted.release_operator.subprocess.run',side_effect=failure) as run:
            with self.assertRaises(subprocess.TimeoutExpired):self.operator.publish()
        verify.assert_called_once_with(self.operator)
        auth.assert_called_once()
        self.assertEqual(run.call_count,1)
        self.assertEqual(failure.cmd,'operation')
        self.assertEqual(len(self.logs()),1)
        self.assertEqual(self.logs()[0].read_bytes(),b'private timeout')

    def test_success_and_nonzero_keep_existing_behavior(self):
        for code in (0,2):
            with self.subTest(code=code):
                result=subprocess.CompletedProcess(['command'],code,b'result-output',b'private-stderr')
                with patch('scripts.self_hosted.release_operator.subprocess.run',return_value=result):
                    if code==0:self.assertEqual(self.operator.run(['command']),b'result-output')
                    else:
                        with self.assertRaisesRegex(RuntimeError,'private diagnostic'):self.operator.run(['command'])
                log=self.logs()[0]
                self.assertEqual(log.read_bytes(),b'private-stderr')
                self.assertEqual(stat.S_IMODE(log.stat().st_mode),0o600)
                log.unlink()

    def test_empty_success_does_not_create_a_diagnostic_but_failure_does(self):
        evidence=self.root/'private'/'operation-preserved.log'
        evidence.write_bytes(b'existing evidence')
        evidence.chmod(0o600)
        success=subprocess.CompletedProcess(['command'],0,b'result',b'')
        failure=subprocess.CompletedProcess(['command'],2,b'',b'')
        with patch('scripts.self_hosted.release_operator.subprocess.run',return_value=success):
            for _ in range(2):self.assertEqual(self.operator.run(['command']),b'result')
        self.assertEqual(self.logs(),[evidence])
        self.assertEqual(evidence.read_bytes(),b'existing evidence')
        with patch('scripts.self_hosted.release_operator.subprocess.run',return_value=failure):
            with self.assertRaisesRegex(RuntimeError,'private diagnostic'):self.operator.run(['command'])
        logs=set(self.logs())-{evidence};self.assertEqual(len(logs),1)
        diagnostic=logs.pop()
        self.assertEqual(diagnostic.read_bytes(),b'')
        self.assertEqual(stat.S_IMODE(diagnostic.stat().st_mode),0o600)
        self.assertEqual(evidence.read_bytes(),b'existing evidence')

class AuthPublicationGate(unittest.TestCase):
    def setUp(self):
        self.area=tempfile.TemporaryDirectory()
        self.addCleanup(self.area.cleanup)
        self.root=Path(self.area.name).resolve()
        (self.root/'private').mkdir()
        (self.root/'private'/'configuration.json').write_text('synthetic seal')
        self.operator=object.__new__(Operator)
        self.operator.root=self.root;self.operator.docker='synthetic-docker';self.operator.project='collect-test'
        self.operator.profile={'environment':'qualification','admin_origin':'https://admin.example',
            'public_origin':'https://public.example','supabase_origin':'https://supabase.example',
            'google_callback_origin':'https://admin.example'}
        self.operator.meta={'profile_sha256':'a'*64,'source_sha256':'b'*64}
        self.image='example.invalid/auth@sha256:'+'c'*64
        self.id='d'*64;self.image_id='sha256:'+'e'*64
        self.jwt_keys='[{"kty":"oct","k":"synthetic-signing-key"}]'
        self.jwt_secret='synthetic$signing-secret'
        self.postgres_password='f'*64
        self.settings={**PROVIDER_SETTINGS,'AUTH_SMS_ENABLED':'true',
            'TURNSTILE_SITE_KEY':'synthetic-site-key','TURNSTILE_SECRET_KEY':'synthetic-captcha-secret',
            'SMTP_HOST':'smtp.example','SMTP_USER':'synthetic-user','SMTP_PASS':'synthetic$password',
            'SMTP_ADMIN_EMAIL':'sender@example.com'}
        self.stack={'AUTH_ANONYMOUS_ENABLED':'false','GOTRUE_EXTERNAL_GOOGLE_ENABLED':'false',
                    'GOOGLE_CLIENT_ID':'','GOOGLE_SECRET':'',
                    'JWT_KEYS':self.jwt_keys,'JWT_SECRET':self.jwt_secret,'JWT_EXPIRY':'3600',
                    'POSTGRES_PASSWORD':self.postgres_password,'POSTGRES_HOST':'db',
                    'POSTGRES_PORT':'5432','POSTGRES_DB':'postgres',
                    'ENABLE_PHONE_SIGNUP':'true','HOOK_ENABLED':'true','CAPTCHA_ENABLED':'true',
                    'CAPTCHA_SECRET':'synthetic-captcha-secret','SMTP_HOST':'smtp.example',
                    'SMTP_USER':'synthetic-user','SMTP_PASS':'synthetic$password',
                    'SMTP_PORT':'587','SMTP_ADMIN_EMAIL':'sender@example.com','SMTP_SENDER_NAME':'Collect',
                    'HOOK_SECRET':'synthetic-hook-secret'}
        self.template={'GOTRUE_DB_DRIVER':'postgres',
            'GOTRUE_DB_DATABASE_URL':'postgres://supabase_auth_admin:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}',
            'API_EXTERNAL_URL':'https://supabase.example/auth/v1','GOTRUE_SITE_URL':'https://public.example',
            'GOTRUE_URI_ALLOW_LIST':'https://admin.example/functions/v1/collect-api/v1/auth/google/callback',
            'GOTRUE_DISABLE_SIGNUP':'false','GOTRUE_EXTERNAL_EMAIL_ENABLED':'true',
            'GOTRUE_MAILER_SECURE_EMAIL_CHANGE_ENABLED':'true',
            **{'GOTRUE_MAILER_URLPATHS_'+suffix:'/auth/v1/verify' for suffix in ('INVITE','CONFIRMATION','RECOVERY','EMAIL_CHANGE')},
            'GOTRUE_RATE_LIMIT_EMAIL_SENT':'30','GOTRUE_RATE_LIMIT_SMS_SENT':'30',
            'GOTRUE_RATE_LIMIT_ANONYMOUS_USERS':'10',
            'GOTRUE_JWT_AUD':'authenticated','GOTRUE_JWT_DEFAULT_GROUP_NAME':'authenticated',
            'GOTRUE_JWT_ADMIN_ROLES':'service_role','GOTRUE_JWT_EXP':'${JWT_EXPIRY}',
            'GOTRUE_JWT_KEYS':'${JWT_KEYS}','GOTRUE_JWT_SECRET':'${JWT_SECRET}',
            'GOTRUE_JWT_ISSUER':'https://supabase.example/auth/v1',
            'GOTRUE_EXTERNAL_ANONYMOUS_USERS_ENABLED':'${AUTH_ANONYMOUS_ENABLED}',
            'GOTRUE_EXTERNAL_GOOGLE_ENABLED':'${GOTRUE_EXTERNAL_GOOGLE_ENABLED}',
            'GOTRUE_EXTERNAL_GOOGLE_CLIENT_ID':'${GOOGLE_CLIENT_ID}',
            'GOTRUE_EXTERNAL_GOOGLE_SECRET':'${GOOGLE_SECRET}',
            'GOTRUE_EXTERNAL_GOOGLE_REDIRECT_URI':'https://supabase.example/auth/v1/callback',
            'GOTRUE_EXTERNAL_PHONE_ENABLED':'${ENABLE_PHONE_SIGNUP}',
            'GOTRUE_HOOK_SEND_SMS_ENABLED':'${HOOK_ENABLED}',
            'GOTRUE_HOOK_SEND_SMS_URI':'http://functions:9000/send-sms-hook',
            'GOTRUE_HOOK_SEND_SMS_SECRETS':'v1,whsec_${HOOK_SECRET}',
            'GOTRUE_SMS_PROVIDER':'twilio','GOTRUE_SMS_OTP_LENGTH':'6','GOTRUE_SMS_OTP_EXP':'300',
            'GOTRUE_SMS_AUTOCONFIRM':'false','GOTRUE_MAILER_AUTOCONFIRM':'false',
            'GOTRUE_SECURITY_CAPTCHA_ENABLED':'${CAPTCHA_ENABLED}',
            'GOTRUE_SECURITY_CAPTCHA_PROVIDER':'turnstile',
            'GOTRUE_SECURITY_CAPTCHA_SECRET':'${CAPTCHA_SECRET}',
            'GOTRUE_SMTP_HOST':'${SMTP_HOST}','GOTRUE_SMTP_USER':'${SMTP_USER}',
            'GOTRUE_SMTP_PASS':'${SMTP_PASS}','GOTRUE_SMTP_PORT':'${SMTP_PORT}',
            'GOTRUE_SMTP_ADMIN_EMAIL':'${SMTP_ADMIN_EMAIL}',
            'GOTRUE_SMTP_SENDER_NAME':'${SMTP_SENDER_NAME}','GOTRUE_API_PORT':9999}
        self.expected={'GOTRUE_DB_DRIVER':'postgres',
            'GOTRUE_DB_DATABASE_URL':'postgres://supabase_auth_admin:'+self.postgres_password+'@db:5432/postgres',
            'API_EXTERNAL_URL':'https://supabase.example/auth/v1','GOTRUE_SITE_URL':'https://public.example',
            'GOTRUE_URI_ALLOW_LIST':'https://admin.example/functions/v1/collect-api/v1/auth/google/callback',
            'GOTRUE_DISABLE_SIGNUP':'false','GOTRUE_EXTERNAL_EMAIL_ENABLED':'true',
            'GOTRUE_MAILER_SECURE_EMAIL_CHANGE_ENABLED':'true',
            **{'GOTRUE_MAILER_URLPATHS_'+suffix:'/auth/v1/verify' for suffix in ('INVITE','CONFIRMATION','RECOVERY','EMAIL_CHANGE')},
            'GOTRUE_RATE_LIMIT_EMAIL_SENT':'30','GOTRUE_RATE_LIMIT_SMS_SENT':'30',
            'GOTRUE_RATE_LIMIT_ANONYMOUS_USERS':'10',
            'GOTRUE_JWT_AUD':'authenticated','GOTRUE_JWT_DEFAULT_GROUP_NAME':'authenticated',
            'GOTRUE_JWT_ADMIN_ROLES':'service_role','GOTRUE_JWT_EXP':'3600',
            'GOTRUE_JWT_KEYS':self.jwt_keys,'GOTRUE_JWT_SECRET':self.jwt_secret,
            'GOTRUE_JWT_ISSUER':'https://supabase.example/auth/v1',
            'GOTRUE_EXTERNAL_ANONYMOUS_USERS_ENABLED':'false',
            'GOTRUE_EXTERNAL_GOOGLE_ENABLED':'false',
            'GOTRUE_EXTERNAL_GOOGLE_CLIENT_ID':'','GOTRUE_EXTERNAL_GOOGLE_SECRET':'',
            'GOTRUE_EXTERNAL_GOOGLE_REDIRECT_URI':'https://supabase.example/auth/v1/callback',
            'GOTRUE_EXTERNAL_PHONE_ENABLED':'true','GOTRUE_HOOK_SEND_SMS_ENABLED':'true',
            'GOTRUE_HOOK_SEND_SMS_URI':'http://functions:9000/send-sms-hook',
            'GOTRUE_HOOK_SEND_SMS_SECRETS':'v1,whsec_synthetic-hook-secret',
            'GOTRUE_SMS_PROVIDER':'twilio','GOTRUE_SMS_OTP_LENGTH':'6','GOTRUE_SMS_OTP_EXP':'300',
            'GOTRUE_SMS_AUTOCONFIRM':'false','GOTRUE_MAILER_AUTOCONFIRM':'false',
            'GOTRUE_SECURITY_CAPTCHA_ENABLED':'true','GOTRUE_SECURITY_CAPTCHA_SECRET':'synthetic-captcha-secret',
            'GOTRUE_SECURITY_CAPTCHA_PROVIDER':'turnstile',
            'GOTRUE_SMTP_HOST':'smtp.example','GOTRUE_SMTP_USER':'synthetic-user',
            'GOTRUE_SMTP_PASS':'synthetic$password','GOTRUE_SMTP_PORT':'587',
            'GOTRUE_SMTP_ADMIN_EMAIL':'sender@example.com','GOTRUE_SMTP_SENDER_NAME':'Collect',
            'GOTRUE_API_PORT':'9999'}
        self.resolved={'services':{'auth':{'image':self.image,
            'environment':{k:v.replace('$','$$') for k,v in self.expected.items()}}}}
        self.image_row={'Id':self.image_id,'Config':{'Env':['PATH=/usr/bin','GOTRUE_API_PORT=old-default']}}
        labels={'com.docker.compose.project':self.operator.project,'com.docker.compose.service':'auth',
                'com.docker.compose.oneoff':'False','com.docker.compose.container-number':'1',
                'com.collect.profile-sha256':self.operator.meta['profile_sha256'],
                'com.collect.source-sha256':self.operator.meta['source_sha256'],
                'com.collect.release-root':str(self.root)}
        self.container={'Id':self.id,'Image':self.image_id,'Config':{'Image':self.image,'Labels':labels,
            'Env':['PATH=/usr/bin',*[key+'='+value for key,value in self.expected.items()]]},
            'State':{'Status':'running','Running':True,'Paused':False,'Restarting':False,'Dead':False,
                     'Health':{'Status':'healthy'}}}
        self.ids=[self.id];self.events=[]
        (self.root/'private'/'provider-settings.json').write_text(json.dumps(self.settings))
        (self.root/'private'/'keys.json').write_text(json.dumps({'COLLECT_SMS_HOOK_SECRET':'synthetic-hook-secret',
            'JWT_KEYS':self.jwt_keys,'JWT_SECRET':self.jwt_secret,'POSTGRES_PASSWORD':self.postgres_password}))
        self.write_configuration()

    def write_configuration(self,extra=None):
        auth={'image':self.image,'environment':self.template}
        if extra:auth.update(extra)
        (self.root/'compose.json').write_text(json.dumps({'services':{'auth':auth}}))
        (self.root/'private'/'stack.env').write_text(dotenv(self.stack))

    def run_read(self,args,**kwargs):
        self.events.append(tuple(args[1:3]))
        if args[1:3]==['ps','-aq']:return ('\n'.join(self.ids)+'\n').encode()
        if args[1:3]==['container','inspect']:return json.dumps([self.container]).encode()
        if args[1:3]==['image','inspect']:return json.dumps([self.image_row]).encode()
        self.fail('Unexpected command in Auth check')

    def check(self):
        with patch('scripts.self_hosted.release_operator.verify_configuration') as seal, \
             patch.object(self.operator,'auth_inspection',side_effect=self.run_read):
            self.operator.validate_running_auth(self.resolved,self.settings)
        self.assertEqual(seal.call_count,2)

    def test_matching_running_auth_accepts_image_defaults_and_literal_dollars(self):
        self.check()
        self.assertEqual(self.events,[('ps','-aq'),('container','inspect'),('image','inspect')])

    def test_missing_duplicate_or_unrecognized_containers_are_refused(self):
        for ids in ([],[self.id,'f'*64],['not-a-container']):
            with self.subTest(count=len(ids)):
                self.ids=ids;self.events=[]
                with self.assertRaises(ValueError):self.check()
                self.assertEqual(self.events,[('ps','-aq')])

    def test_stale_unhealthy_or_wrong_identity_is_refused_without_printing_values(self):
        changes=[('stopped',lambda c:c['State'].update(Status='exited',Running=False)),
                 ('unhealthy',lambda c:c['State']['Health'].update(Status='unhealthy')),
                 ('paused',lambda c:c['State'].update(Paused=True)),
                 ('restarting',lambda c:c['State'].update(Restarting=True)),
                 ('oneoff',lambda c:c['Config']['Labels'].update({'com.docker.compose.oneoff':'True'})),
                 ('number',lambda c:c['Config']['Labels'].update({'com.docker.compose.container-number':'2'})),
                 ('release',lambda c:c['Config']['Labels'].update({'com.collect.source-sha256':'f'*64})),
                 ('container_id',lambda c:c.update(Id='f'*64)),
                 ('image',lambda c:c.update(Image='sha256:'+'f'*64)),
                 ('stale_secret',lambda c:c['Config'].__setitem__('Env',[('GOTRUE_SMTP_PASS=synthetic-old-secret' if e.startswith('GOTRUE_SMTP_PASS=') else e) for e in c['Config']['Env']])),
                 ('missing_setting',lambda c:c['Config']['Env'].pop()),
                 ('extra_setting',lambda c:c['Config']['Env'].append('GOTRUE_SMS_PROVIDER=other')),
                 ('duplicate',lambda c:c['Config']['Env'].append('GOTRUE_SMTP_PASS=duplicate'))]
        original=copy.deepcopy(self.container)
        for name,change in changes:
            with self.subTest(case=name):
                self.container=copy.deepcopy(original);change(self.container)
                with self.assertRaises(ValueError) as caught:self.check()
                self.assertNotIn('synthetic-',str(caught.exception))

    def test_resolved_configuration_must_match_sealed_settings(self):
        original=copy.deepcopy(self.resolved)
        for case in ('shell_override','unescaped_dollar','escaped_unicode'):
            with self.subTest(case=case):
                self.resolved=copy.deepcopy(original)
                env=self.resolved['services']['auth']['environment']
                if case=='shell_override':env['GOTRUE_EXTERNAL_PHONE_ENABLED']='false'
                if case=='unescaped_dollar':env['GOTRUE_SMTP_PASS']='synthetic$password'
                if case=='escaped_unicode':env['GOTRUE_SMTP_PASS']='synthetic-\\u00e9'
                self.events=[]
                with self.assertRaises(ValueError):self.check()
                self.assertEqual(self.events,[])

    def test_unsupported_or_incomplete_auth_templates_are_refused(self):
        original=copy.deepcopy(self.template)
        for case in ('missing_required','unsupported_interpolation','missing_variable','env_file'):
            with self.subTest(case=case):
                self.template=copy.deepcopy(original)
                if case=='missing_required':self.template.pop('GOTRUE_HOOK_SEND_SMS_ENABLED')
                if case=='unsupported_interpolation':self.template['GOTRUE_SMTP_PASS']='${SMTP_PASS:-fallback}'
                if case=='missing_variable':self.template['GOTRUE_SMTP_PASS']='${UNLISTED}'
                self.write_configuration({'env_file':['other.env']} if case=='env_file' else None)
                self.events=[]
                with self.assertRaises(ValueError):self.check()
                self.assertEqual(self.events,[])

    def test_consistent_container_still_requires_validated_auth_security_semantics(self):
        baseline_template=copy.deepcopy(self.template);baseline_expected=copy.deepcopy(self.expected)
        changes=[('db_driver','GOTRUE_DB_DRIVER','mysql'),
                 ('db_url_missing','GOTRUE_DB_DATABASE_URL',None),
                 ('db_url','GOTRUE_DB_DATABASE_URL','postgres://other:synthetic@other.example:5432/postgres'),
                 ('api_url','API_EXTERNAL_URL','https://other.example/auth/v1'),
                 ('site_url','GOTRUE_SITE_URL','https://other.example'),
                 ('redirect_allowlist','GOTRUE_URI_ALLOW_LIST','https://other.example/callback'),
                 ('signup_disabled','GOTRUE_DISABLE_SIGNUP','true'),
                 ('email_disabled','GOTRUE_EXTERNAL_EMAIL_ENABLED','false'),
                 ('secure_email_disabled','GOTRUE_MAILER_SECURE_EMAIL_CHANGE_ENABLED','false'),
                 ('invite_path','GOTRUE_MAILER_URLPATHS_INVITE','/other'),
                 ('confirmation_path','GOTRUE_MAILER_URLPATHS_CONFIRMATION','/other'),
                 ('recovery_path','GOTRUE_MAILER_URLPATHS_RECOVERY','/other'),
                 ('email_change_path','GOTRUE_MAILER_URLPATHS_EMAIL_CHANGE','/other'),
                 ('email_rate','GOTRUE_RATE_LIMIT_EMAIL_SENT','100'),
                 ('sms_rate','GOTRUE_RATE_LIMIT_SMS_SENT','100'),
                 ('anonymous_rate','GOTRUE_RATE_LIMIT_ANONYMOUS_USERS','100'),
                 ('jwt_audience','GOTRUE_JWT_AUD','other'),
                 ('jwt_group','GOTRUE_JWT_DEFAULT_GROUP_NAME','other'),
                 ('jwt_admin_roles','GOTRUE_JWT_ADMIN_ROLES','other'),
                 ('jwt_expiry','GOTRUE_JWT_EXP','7200'),
                 ('jwt_issuer_missing','GOTRUE_JWT_ISSUER',None),
                 ('jwt_issuer','GOTRUE_JWT_ISSUER','https://other.example/auth/v1'),
                 ('jwt_keys_missing','GOTRUE_JWT_KEYS',None),
                 ('jwt_keys','GOTRUE_JWT_KEYS','other-synthetic-keys'),
                 ('jwt_secret_missing','GOTRUE_JWT_SECRET',None),
                 ('jwt_secret','GOTRUE_JWT_SECRET','other-synthetic-secret'),
                 ('anonymous_missing','GOTRUE_EXTERNAL_ANONYMOUS_USERS_ENABLED',None),
                 ('anonymous_enabled','GOTRUE_EXTERNAL_ANONYMOUS_USERS_ENABLED','true'),
                 ('google_enabled_missing','GOTRUE_EXTERNAL_GOOGLE_ENABLED',None),
                 ('google_enabled','GOTRUE_EXTERNAL_GOOGLE_ENABLED','true'),
                 ('google_client_missing','GOTRUE_EXTERNAL_GOOGLE_CLIENT_ID',None),
                 ('google_client','GOTRUE_EXTERNAL_GOOGLE_CLIENT_ID','other-synthetic-client'),
                 ('google_secret_missing','GOTRUE_EXTERNAL_GOOGLE_SECRET',None),
                 ('google_secret','GOTRUE_EXTERNAL_GOOGLE_SECRET','other-synthetic-secret'),
                 ('google_redirect_missing','GOTRUE_EXTERNAL_GOOGLE_REDIRECT_URI',None),
                 ('google_redirect','GOTRUE_EXTERNAL_GOOGLE_REDIRECT_URI','https://other.example/auth/v1/callback'),
                 ('captcha_missing','GOTRUE_SECURITY_CAPTCHA_ENABLED',None),
                 ('captcha_disabled','GOTRUE_SECURITY_CAPTCHA_ENABLED','false'),
                 ('captcha_secret','GOTRUE_SECURITY_CAPTCHA_SECRET','other-synthetic-value'),
                 ('phone_disabled','GOTRUE_EXTERNAL_PHONE_ENABLED','false'),
                 ('hook_disabled','GOTRUE_HOOK_SEND_SMS_ENABLED','false'),
                 ('hook_target','GOTRUE_HOOK_SEND_SMS_URI','http://other.example'),
                 ('hook_secret','GOTRUE_HOOK_SEND_SMS_SECRETS','v1,whsec_other'),
                 ('sms_autoconfirm','GOTRUE_SMS_AUTOCONFIRM','true'),
                 ('email_autoconfirm','GOTRUE_MAILER_AUTOCONFIRM','true'),
                 ('otp_length','GOTRUE_SMS_OTP_LENGTH','4'),
                 ('otp_expiry','GOTRUE_SMS_OTP_EXP','600'),
                 ('provider','GOTRUE_SMS_PROVIDER','twilio_verify'),
                 ('smtp_password','GOTRUE_SMTP_PASS','other-synthetic-value')]
        for name,key,value in changes:
            with self.subTest(case=name):
                self.template=copy.deepcopy(baseline_template);self.expected=copy.deepcopy(baseline_expected)
                if value is None:self.template.pop(key);self.expected.pop(key)
                else:self.template[key]=value;self.expected[key]=value
                self.resolved['services']['auth']['environment']={k:v.replace('$','$$') for k,v in self.expected.items()}
                self.container['Config']['Env']=['PATH=/usr/bin',*[k+'='+v for k,v in self.expected.items()]]
                self.write_configuration();self.events=[]
                with self.assertRaisesRegex(ValueError,'differs from the sealed release'):
                    self.check()
                self.assertEqual(self.events,[])

    def test_missing_or_invalid_jwt_source_keys_are_refused_before_inspection(self):
        original={'COLLECT_SMS_HOOK_SECRET':'synthetic-hook-secret',
                  'JWT_KEYS':self.jwt_keys,'JWT_SECRET':self.jwt_secret,'POSTGRES_PASSWORD':self.postgres_password}
        for key in ('JWT_KEYS','JWT_SECRET','POSTGRES_PASSWORD'):
            values=(None,'',123,'g'*64,'f'*63) if key=='POSTGRES_PASSWORD' else (None,'',123)
            for value in values:
                with self.subTest(key=key,value=value):
                    keys=original.copy()
                    if value is None:keys.pop(key)
                    else:keys[key]=value
                    (self.root/'private'/'keys.json').write_text(json.dumps(keys))
                    self.events=[]
                    with self.assertRaisesRegex(ValueError,'Sealed Auth settings cannot be verified'):
                        self.check()
                    self.assertEqual(self.events,[])

    def test_enabled_google_and_anonymous_use_the_validated_settings(self):
        self.settings.update(AUTH_SMS_ENABLED='false',AUTH_ANONYMOUS_ENABLED='true',
            GOOGLE_AUTH_ENABLED='true',GOTRUE_EXTERNAL_GOOGLE_ENABLED='true',
            GOOGLE_CLIENT_ID='synthetic-google-client',GOOGLE_SECRET='synthetic$google-secret')
        validated_settings(self.settings,self.operator.profile,'b'*64)
        self.stack.update(AUTH_ANONYMOUS_ENABLED='true',GOTRUE_EXTERNAL_GOOGLE_ENABLED='true',
            GOOGLE_CLIENT_ID=self.settings['GOOGLE_CLIENT_ID'],GOOGLE_SECRET=self.settings['GOOGLE_SECRET'],
            ENABLE_PHONE_SIGNUP='false',HOOK_ENABLED='false')
        self.expected.update(GOTRUE_EXTERNAL_ANONYMOUS_USERS_ENABLED='true',
            GOTRUE_EXTERNAL_GOOGLE_ENABLED='true',GOTRUE_EXTERNAL_GOOGLE_CLIENT_ID=self.settings['GOOGLE_CLIENT_ID'],
            GOTRUE_EXTERNAL_GOOGLE_SECRET=self.settings['GOOGLE_SECRET'],
            GOTRUE_EXTERNAL_PHONE_ENABLED='false',GOTRUE_HOOK_SEND_SMS_ENABLED='false')
        (self.root/'private'/'provider-settings.json').write_text(json.dumps(self.settings))
        self.write_configuration()
        self.resolved['services']['auth']['environment']={k:v.replace('$','$$') for k,v in self.expected.items()}
        self.container['Config']['Env']=['PATH=/usr/bin',*[k+'='+v for k,v in self.expected.items()]]
        self.check()
        baseline_template=copy.deepcopy(self.template);baseline_expected=copy.deepcopy(self.expected)
        for name,key,value in (
            ('anonymous_disabled','GOTRUE_EXTERNAL_ANONYMOUS_USERS_ENABLED','false'),
            ('google_disabled','GOTRUE_EXTERNAL_GOOGLE_ENABLED','false'),
            ('google_client','GOTRUE_EXTERNAL_GOOGLE_CLIENT_ID','other-synthetic-client'),
            ('google_secret','GOTRUE_EXTERNAL_GOOGLE_SECRET','other-synthetic-secret'),
            ('google_redirect','GOTRUE_EXTERNAL_GOOGLE_REDIRECT_URI','https://other.example/auth/v1/callback'),
        ):
            with self.subTest(case=name):
                self.template=copy.deepcopy(baseline_template);self.expected=copy.deepcopy(baseline_expected)
                self.template[key]=value;self.expected[key]=value
                self.write_configuration()
                self.resolved['services']['auth']['environment']={k:v.replace('$','$$') for k,v in self.expected.items()}
                self.container['Config']['Env']=['PATH=/usr/bin',*[k+'='+v for k,v in self.expected.items()]]
                self.events=[]
                with self.assertRaisesRegex(ValueError,'differs from the sealed release'):
                    self.check()
                self.assertEqual(self.events,[])

    def test_provider_settings_must_still_match_sealed_readback(self):
        (self.root/'private'/'provider-settings.json').write_text(json.dumps({**self.settings,'AUTH_SMS_ENABLED':'false'}))
        with self.assertRaisesRegex(ValueError,'settings changed before verification'):
            self.check()
        self.assertEqual(self.events,[])

    def test_auth_gate_uses_bounded_provider_reader_before_inspection(self):
        secret=b'synthetic-private-field'
        cases=(('nested',b'{"field":'+b'['*12000+b'"'+secret+b'"'+b']'*12000+b'}'),
               ('oversized',b'{"field":"'+secret+b'x'*32768+b'"}'))
        for name,data in cases:
            with self.subTest(case=name):
                (self.root/'private'/'provider-settings.json').write_bytes(data)
                self.events=[]
                with patch('scripts.self_hosted.configure.MAX_PROVIDER_SETTINGS_BYTES',32768), \
                     patch('scripts.self_hosted.release_operator.verify_configuration'), \
                     patch.object(self.operator,'auth_inspection',side_effect=self.run_read):
                    with self.assertRaisesRegex(ValueError,'Provider settings could not be parsed') as caught:
                        self.operator.validate_running_auth(self.resolved,self.settings)
                self.assert_exception_chain_safe(caught.exception,secret.decode())
                self.assertEqual(self.events,[])

    def test_disabled_phone_and_native_provider_remain_supported_when_consistent(self):
        for mode in ('disabled','native'):
            with self.subTest(mode=mode):
                if mode=='disabled':
                    self.settings['AUTH_SMS_ENABLED']='false';self.stack['ENABLE_PHONE_SIGNUP']='false'
                    self.expected['GOTRUE_EXTERNAL_PHONE_ENABLED']='false'
                else:
                    self.settings.update(AUTH_SMS_ENABLED='true',AUTH_PHONE_DELIVERY_MODE='twilio',
                        GOTRUE_SMS_TWILIO_ACCOUNT_SID='AC'+'a'*32,GOTRUE_SMS_TWILIO_AUTH_TOKEN='b'*32,
                        GOTRUE_SMS_TWILIO_MESSAGE_SERVICE_SID='MG'+'c'*32)
                    self.stack['ENABLE_PHONE_SIGNUP']='true';self.expected['GOTRUE_EXTERNAL_PHONE_ENABLED']='true'
                    for key,value in self.settings.items():
                        if key.startswith('GOTRUE_SMS_TWILIO_'):
                            self.stack[key]=value;self.template[key]='${'+key+'}';self.expected[key]=value
                self.stack['HOOK_ENABLED']='false';self.expected['GOTRUE_HOOK_SEND_SMS_ENABLED']='false'
                validated_settings(self.settings,self.operator.profile,'b'*64)
                (self.root/'private'/'provider-settings.json').write_text(json.dumps(self.settings))
                self.write_configuration()
                self.resolved['services']['auth']['environment']={k:v.replace('$','$$') for k,v in self.expected.items()}
                self.container['Config']['Env']=['PATH=/usr/bin',*[k+'='+v for k,v in self.expected.items()]]
                self.events=[];self.check()
        self.expected['GOTRUE_SMS_TWILIO_AUTH_TOKEN']='other-synthetic-token'
        self.template['GOTRUE_SMS_TWILIO_AUTH_TOKEN']='other-synthetic-token'
        self.write_configuration()
        self.resolved['services']['auth']['environment']={k:v.replace('$','$$') for k,v in self.expected.items()}
        self.container['Config']['Env']=['PATH=/usr/bin',*[k+'='+v for k,v in self.expected.items()]]
        self.events=[]
        with self.assertRaises(ValueError):self.check()
        self.assertEqual(self.events,[])

    def test_changed_seal_is_refused(self):
        receipt=self.root/'private'/'configuration.json'
        def verify(_):
            if self.events:receipt.write_text('new synthetic seal')
        with patch('scripts.self_hosted.release_operator.verify_configuration',side_effect=verify), \
             patch.object(self.operator,'auth_inspection',side_effect=self.run_read):
            with self.assertRaisesRegex(ValueError,'changed during Auth verification'):
                self.operator.validate_running_auth(self.resolved,self.settings)

    def test_publish_checks_auth_before_starting_public_services(self):
        calls=[]
        def read(args,**kwargs):calls.append('inspect');return self.run_read(args,**kwargs)
        def compose(*args,**kwargs):calls.append('publish');return b''
        with patch.object(self.operator,'docker_preflight',side_effect=lambda:(calls.append('preflight') or self.resolved)), \
             patch.object(self.operator,'validate_runtime_database',side_effect=lambda:calls.append('database')), \
             patch('scripts.self_hosted.release_operator.validated_settings',return_value={}), \
             patch('scripts.self_hosted.assets.verify_assets',side_effect=lambda op:calls.append('assets')), \
             patch('scripts.self_hosted.release_operator.verify_configuration',side_effect=lambda root:calls.append('seal')), \
             patch.object(self.operator,'auth_inspection',side_effect=read),patch.object(self.operator,'compose',side_effect=compose):
            self.operator.publish()
        self.assertEqual(calls,['preflight','database','assets','seal','inspect','inspect','inspect','seal','publish'])

    def test_stale_or_unknown_auth_never_starts_public_services(self):
        for mode in ('stale','inspect_failed'):
            with self.subTest(mode=mode):
                self.container['Config']['Env']=[item.replace('GOTRUE_EXTERNAL_PHONE_ENABLED=true','GOTRUE_EXTERNAL_PHONE_ENABLED=false')
                                                  for item in self.container['Config']['Env']]
                failure=RuntimeError('synthetic inspect failure') if mode=='inspect_failed' else None
                with patch.object(self.operator,'docker_preflight',return_value=self.resolved), \
                     patch.object(self.operator,'validate_runtime_database'), \
                     patch('scripts.self_hosted.release_operator.validated_settings',return_value={}), \
                     patch('scripts.self_hosted.assets.verify_assets'), \
                     patch('scripts.self_hosted.release_operator.verify_configuration'), \
                     patch.object(self.operator,'auth_inspection',side_effect=failure or self.run_read), \
                     patch.object(self.operator,'compose') as compose:
                    with self.assertRaises((ValueError,RuntimeError)):self.operator.publish()
                compose.assert_not_called()

    def test_failed_inspection_keeps_both_output_streams_out_of_diagnostics(self):
        failure=subprocess.CompletedProcess(['docker'],1,b'synthetic-secret',b'synthetic-secret')
        timeout=subprocess.TimeoutExpired(['docker','synthetic-secret'],15,output=b'synthetic-secret',stderr=b'synthetic-secret')
        for result in (failure,timeout):
            with self.subTest(kind=type(result).__name__):
                with patch('scripts.self_hosted.release_operator.subprocess.run',
                           side_effect=result if isinstance(result,Exception) else None,
                           return_value=None if isinstance(result,Exception) else result):
                    with self.assertRaises(ValueError) as caught:self.operator.auth_inspection(['docker','inspect','synthetic'])
                self.assert_exception_chain_safe(caught.exception,'synthetic-secret')
                self.assertEqual(list((self.root/'private').glob('operation-*.log')),[])

    def assert_exception_chain_safe(self,error,secret):
        seen=set();pending=[error]
        while pending:
            current=pending.pop()
            if id(current) in seen:continue
            seen.add(id(current))
            for value in (repr(current),str(current),repr(current.args),repr(vars(current)),
                          repr(getattr(current,'doc',None)),repr(getattr(current,'object',None)),
                          repr(getattr(current,'cmd',None)),repr(getattr(current,'output',None)),
                          repr(getattr(current,'stderr',None))):
                self.assertNotIn(secret,value)
            for linked in (current.__cause__,current.__context__):
                if linked is not None:pending.append(linked)
        self.assertIsNone(error.__cause__)
        self.assertIsNone(error.__context__)

    def test_malformed_inspection_json_does_not_escape_through_exception_chain(self):
        malformed=b'{"provider_secret":"synthetic-secret",'
        for stage in ('container','image'):
            with self.subTest(stage=stage):
                def inspect(args,**kwargs):
                    if args[1:3]==[stage,'inspect']:return malformed
                    return self.run_read(args,**kwargs)
                with patch('scripts.self_hosted.release_operator.verify_configuration'), \
                     patch.object(self.operator,'auth_inspection',side_effect=inspect):
                    with self.assertRaises(ValueError) as caught:
                        self.operator.validate_running_auth(self.resolved,self.settings)
                self.assert_exception_chain_safe(caught.exception,'synthetic-secret')

    def test_invalid_inspection_id_bytes_do_not_escape_through_exception_chain(self):
        with patch('scripts.self_hosted.release_operator.verify_configuration'), \
             patch.object(self.operator,'auth_inspection',return_value=b'synthetic-secret\xff'):
            with self.assertRaises(ValueError) as caught:
                self.operator.validate_running_auth(self.resolved,self.settings)
        self.assert_exception_chain_safe(caught.exception,'synthetic-secret')

    def test_malformed_private_inputs_do_not_escape_through_exception_chain(self):
        for name,data in (('provider-settings.json','{"synthetic-secret":'),
                          ('keys.json','{"synthetic-secret":'),
                          ('stack.env','SYNTHETIC="synthetic-secret')):
            with self.subTest(file=name):
                path=self.root/'private'/name;original=path.read_bytes()
                path.write_text(data)
                try:
                    with patch('scripts.self_hosted.release_operator.verify_configuration'):
                        with self.assertRaises(ValueError) as caught:
                            self.operator.validate_running_auth(self.resolved,self.settings)
                    self.assert_exception_chain_safe(caught.exception,'synthetic-secret')
                finally:path.write_bytes(original)

    def test_malformed_compose_model_does_not_escape_through_exception_chain(self):
        def docker(args,**kwargs):
            if args[1:3]==['context','inspect']:return b'"unix:///synthetic-docker.sock"'
            if args[1]=='info':return b'{"ServerVersion":"29.0.0","OSType":"linux"}'
            self.fail('Unexpected command before Compose model')
        with patch.dict(os.environ,{'DOCKER_HOST':'unix:///synthetic-docker.sock'}), \
             patch.object(self.operator,'run',side_effect=docker), \
             patch.object(self.operator,'compose',return_value=b'{"synthetic-secret":'):
            with self.assertRaises(ValueError) as caught:self.operator.docker_preflight()
        self.assert_exception_chain_safe(caught.exception,'synthetic-secret')

if __name__=='__main__':
    unittest.main()
