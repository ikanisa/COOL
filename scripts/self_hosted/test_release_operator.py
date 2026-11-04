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
from scripts.self_hosted.prepare import CONFIGURATION_FILES,PROVIDER_SETTINGS,seal_configuration
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
        with patch.object(self.operator,'docker_preflight'), \
             patch.object(self.operator,'validate_runtime_database'), \
             patch('scripts.self_hosted.assets.verify_assets') as assets, \
             patch.object(self.operator,'compose') as compose:
            with self.assertRaisesRegex(ValueError,'Production Auth SMTP and abuse controls must be configured'):
                self.operator.publish()
        assets.assert_not_called();compose.assert_not_called()

    def test_publish_cli_explains_origin_collision_without_disclosing_values(self):
        profile={'format':'collect.deployment.v1','id':'synthetic','mode':'self_hosted',
            'environment':'qualification','supabase_origin':'https://identity.example',
            'admin_origin':'https://same.example','public_origin':'https://same.example',
            'member_api_origin':'https://api.example','google_callback_origin':'https://same.example'}
        digest=hashlib.sha256(b'[]').hexdigest()
        meta={'format':'collect.selfhost.release.v1','profile':profile,
            'profile_sha256':profile_sha256(profile),'source_sha256':digest}
        (self.root/'source').mkdir()
        (self.root/'source-manifest.json').write_text(json.dumps({'format':'collect.selfhost.source.v1','sha256':digest,'files':[]}))
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
             patch('scripts.self_hosted.release_operator.subprocess.run',side_effect=failure) as run:
            with self.assertRaises(subprocess.TimeoutExpired):self.operator.publish()
        verify.assert_called_once_with(self.operator)
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

if __name__=='__main__':
    unittest.main()
