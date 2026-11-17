"""Synthetic ZIP/tool outcomes only. Never signs an actual APK or reads real keys."""
import argparse
import copy
import datetime as dt
import hashlib
import importlib.util
import io
import json
import os
import re
from pathlib import Path
import stat
import subprocess
import secrets
import sys
import tempfile
import unittest
from unittest.mock import patch
import warnings
import zipfile
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
SCRIPTS = Path(__file__).resolve().parents[1] / 'scripts'
sys.path.insert(0, str(SCRIPTS))
spec = importlib.util.spec_from_file_location('candidate_signer_under_test', SCRIPTS / 'sign_candidate.py')
signer = importlib.util.module_from_spec(spec); spec.loader.exec_module(signer)
A = signer.A
REAL_RUN_TOOL = signer.run_tool


def xml(flavor, **changes):
    package = changes.get('package', signer.PACKAGES[flavor])
    flags = 'android:debuggable="'+changes.get('debuggable', 'false')+'" android:testOnly="'+changes.get('testOnly', 'false')+'"'
    receiver = ''
    if flavor == 'internal_receiver':
        receiver = '<uses-permission android:name="android.permission.READ_SMS"/><uses-permission android:name="android.permission.RECEIVE_SMS"/>'
        receiver += ''.join('<uses-permission android:name="android.permission.'+p+'"/>' for p in (
            'FOREGROUND_SERVICE','FOREGROUND_SERVICE_SPECIAL_USE','POST_NOTIFICATIONS','WAKE_LOCK','REQUEST_IGNORE_BATTERY_OPTIMIZATIONS'))
    components = ''
    if flavor == 'internal_receiver':
        for name, tag, permission, exported in [
            ('CollectSmsReceiver', 'receiver', 'android.permission.BROADCAST_SMS', 'true'),
            ('MomoGatewayRecoveryReceiver', 'receiver', None, 'false'),
            ('MomoGatewayJobService', 'service', 'android.permission.BIND_JOB_SERVICE', 'true'),
            ('MomoGatewayLocalRecoveryService', 'service', 'android.permission.BIND_JOB_SERVICE', 'true'),
            ('ObservationSmsReceiver', 'receiver', 'android.permission.BROADCAST_SMS', 'true'),
            ('ObservationBootReceiver', 'receiver', None, 'false'),
            ('ObservationJobService', 'service', 'android.permission.BIND_JOB_SERVICE', 'true')]:
            components += '<'+tag+' android:name="app.cool.mobile.receiver_sms.'+name+'" android:exported="'+exported+'"'+(
                ' android:permission="'+permission+'"' if permission else '')+'/>'
        components += '<service android:name="app.cool.mobile.receiver_sms.BuriContinuousSyncService" android:exported="false" android:stopWithTask="false" android:foregroundServiceType="specialUse"><property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE" android:value="Internal receiving-phone SMS monitoring with local inbox observation and bounded authenticated synchronization, controlled by the current authorized administrator and a visible ongoing notification."/></service>'
    return ('<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="'+package+'" android:versionCode="'+
            changes.get('versionCode', str(signer.VERSION_CODE))+'" android:versionName="synthetic-candidate">'+receiver+
            '<uses-sdk android:minSdkVersion="26" android:targetSdkVersion="36"/>'+
            '<application android:usesCleartextTraffic="false" android:allowBackup="false" '+flags+'>'+components+
            '</application></manifest>').encode()


def apk(manifest, *, dex=b'synthetic dex bytes', signed=False):
    output = io.BytesIO()
    with zipfile.ZipFile(output, 'w') as archive:
        archive.writestr('AndroidManifest.xml', manifest)
        archive.writestr('classes.dex', dex)
        if signed: archive.comment = b'synthetic signature tool changed bytes'
    return output.getvalue()


class SyntheticTools:
    def __init__(self, certificate):
        self.certificate = certificate; self.calls = []; self.wrong_verify = False
        self.tamper_signed = False; self.tamper_aligned = False; self.fail_sign = False
        self.multiple_signers = False; self.after_align = None

    def __call__(self, argv, env):
        argv = [str(v) for v in argv]; self.calls.append((argv, dict(env)))
        tool = Path(argv[0]).name
        if tool == 'keytool': return self.certificate
        if tool == 'apkanalyzer':
            with zipfile.ZipFile(argv[-1]) as archive: return archive.read('AndroidManifest.xml')
        if tool == 'zipalign':
            if '-c' in argv: return b''
            raw = Path(argv[-2]).read_bytes()
            if self.tamper_aligned:
                with zipfile.ZipFile(io.BytesIO(raw)) as archive: raw = apk(archive.read('AndroidManifest.xml'), dex=b'changed aligned bytes')
            signer.write_private(Path(argv[-1]), raw)
            if self.after_align: self.after_align()
            return b''
        if tool == 'apksigner' and argv[1] == 'sign':
            if self.fail_sign: raise signer.SigningRejected('signing_tool_failed')
            target = Path(argv[argv.index('--out') + 1])
            with zipfile.ZipFile(argv[-1]) as archive:
                raw = apk(archive.read('AndroidManifest.xml'), dex=b'changed signed bytes' if self.tamper_signed else archive.read('classes.dex'), signed=True)
            signer.write_private(target, raw); return b''
        if tool == 'apksigner' and argv[1] == 'verify':
            pin = 'f'*64 if self.wrong_verify else signer.digest(self.certificate)
            second = 'Signer #2 certificate SHA-256 digest: '+'e'*64+'\n' if self.multiple_signers else ''
            return ('Verified using v2 scheme (APK Signature Scheme v2): true\nSigner #1 certificate SHA-256 digest: '+pin+'\n'+second).encode()
        raise AssertionError('Unexpected synthetic tool invocation')


class CandidateSigning(unittest.TestCase):
    def test_signing_version_matches_android_default_config(self):
        gradle = (SCRIPTS.parent / 'app/build.gradle.kts').read_text(encoding='utf8')
        versions = re.findall(r'^\s*versionCode\s*=\s*(\d+)\s*$', gradle, re.MULTILINE)
        self.assertEqual(len(versions), 1)
        self.assertEqual(int(versions[0]), signer.VERSION_CODE)

    def test_cloud_package_identity_is_distinct_from_legacy_and_matches_signer(self):
        gradle = (SCRIPTS.parent / 'app/build.gradle.kts').read_text(encoding='utf8')
        self.assertIn('applicationIdSuffix = ".staff.cloud"', gradle)
        self.assertIn('applicationIdSuffix = ".gateway.cloud"', gradle)
        self.assertEqual(signer.PACKAGES, {
            'staff': 'rw.ikanisa.burimunsi.staff.cloud',
            'internal_receiver': 'rw.ikanisa.burimunsi.gateway.cloud',
        })
        for flavor, legacy in (('staff', 'rw.ikanisa.burimunsi.staff'),
                               ('internal_receiver', 'rw.ikanisa.burimunsi.gateway')):
            with self.assertRaises(ValueError):
                signer.manifest(xml(flavor, package=legacy), flavor)

    def test_observation_components_have_exact_release_boundaries(self):
        good = xml('internal_receiver')
        signer.manifest(good, 'internal_receiver')
        for name in ('ObservationSmsReceiver', 'ObservationBootReceiver', 'ObservationJobService','BuriContinuousSyncService'):
            for mutation in ('missing', 'duplicate', 'type', 'exported', 'permission'):
                with self.subTest(component=name, mutation=mutation):
                    root = ET.fromstring(good)
                    app = root.find('application')
                    node = next(e for e in app if e.get(A+'name') == 'app.cool.mobile.receiver_sms.'+name)
                    if mutation == 'missing': app.remove(node)
                    elif mutation == 'duplicate': app.append(copy.deepcopy(node))
                    elif mutation == 'type': node.tag = 'service' if node.tag == 'receiver' else 'receiver'
                    elif mutation == 'exported': node.set(A+'exported', 'false' if node.get(A+'exported') == 'true' else 'true')
                    else: node.set(A+'permission', 'unexpected.permission')
                    with self.assertRaises(ValueError): signer.manifest(ET.tostring(root), 'internal_receiver')

    def test_continuous_receiver_type_power_and_staff_boundaries(self):
        good=xml('internal_receiver')
        for mutation in ('stop_with_task','data_sync_type','missing_property','wrong_property','missing_permission'):
            with self.subTest(mutation=mutation):
                root=ET.fromstring(good);service=next(e for e in root.find('application').findall('service') if e.get(A+'name').endswith('BuriContinuousSyncService'))
                if mutation=='stop_with_task':service.set(A+'stopWithTask','true')
                elif mutation=='data_sync_type':service.set(A+'foregroundServiceType','dataSync')
                elif mutation=='missing_property':service.remove(service.find('property'))
                elif mutation=='wrong_property':service.find('property').set(A+'value','unqualified')
                else:root.remove(next(e for e in root.findall('uses-permission') if e.get(A+'name')=='android.permission.FOREGROUND_SERVICE_SPECIAL_USE'))
                with self.assertRaises(ValueError):signer.manifest(ET.tostring(root),'internal_receiver')
        root=ET.fromstring(xml('staff'));ET.SubElement(root,'uses-permission',{A+'name':'android.permission.FOREGROUND_SERVICE'})
        with self.assertRaises(ValueError):signer.manifest(ET.tostring(root),'staff')

    def test_compiled_special_use_enum_is_exactly_the_declared_type(self):
        for value in ('specialUse','0x40000000','1073741824'):
            root=ET.fromstring(xml('internal_receiver'));service=next(e for e in root.find('application').findall('service') if e.get(A+'name').endswith('BuriContinuousSyncService'))
            service.set(A+'foregroundServiceType',value);signer.manifest(ET.tostring(root),'internal_receiver')
        for value in ('0x40000001','1073741825','dataSync','specialUse|dataSync'):
            root=ET.fromstring(xml('internal_receiver'));service=next(e for e in root.find('application').findall('service') if e.get(A+'name').endswith('BuriContinuousSyncService'))
            service.set(A+'foregroundServiceType',value)
            with self.assertRaises(ValueError):signer.manifest(ET.tostring(root),'internal_receiver')

    def setUp(self):
        temp = tempfile.TemporaryDirectory(); self.addCleanup(temp.cleanup)
        self.base = Path(temp.name).resolve(); self.evidence = self.base / 'evidence'; self.evidence.mkdir(mode=0o700)
        private = self.base / 'private'; private.mkdir(mode=0o700)
        self.store = private / 'fixture.p12'; signer.write_private(self.store, b'synthetic keystore, not a real key')
        self.password = private / 'password'; self.password_value = b'synthetic-password-never-log\n'
        signer.write_private(self.password, self.password_value)
        self.cert = b'synthetic certificate DER outcome'; self.pin = signer.digest(self.cert)
        self.source = 'a'*64; self.fake = SyntheticTools(self.cert)
        self.sdk = self.base / 'sdk'; self.java = self.base / 'jdk'
        for path in [self.sdk/'build-tools/36.0.0/zipalign', self.sdk/'build-tools/36.0.0/apksigner',
                     self.sdk/'cmdline-tools/latest/bin/apkanalyzer', self.java/'bin/keytool']:
            path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(b'synthetic non-executed tool'); path.chmod(0o755)
        (self.sdk/'build-tools/36.0.0/lib').mkdir(); (self.sdk/'build-tools/36.0.0/lib/apksigner.jar').write_bytes(b'synthetic jar')
        (self.sdk/'build-tools/36.0.0/source.properties').write_text('Pkg.Revision=36.0.0\n')
        (self.java/'release').write_text('JAVA_VERSION="17.0.16"\n')
        cloud = 'https://rrlduytparvsjfmegalh.supabase.co'
        self.profile = {'format': 'collect.deployment.v1', 'id': 'signer-fixture', 'mode': 'managed', 'environment': 'qualification',
            'supabase_origin': cloud, 'member_api_origin': cloud,
            'admin_origin': cloud, 'public_origin': 'https://public.example.test', 'google_callback_origin': cloud}
        self.properties = {'collectSupabaseOrigin': self.profile['supabase_origin'], 'collectAdminOrigin': self.profile['admin_origin'],
            'burimunsiApiOrigin': self.profile['supabase_origin'], 'burimunsiApiPathPrefix': '/functions/v1/collect-api',
            'collectGatewayOrigin': self.profile['supabase_origin']+'/functions/v1/collect-api',
            'collectPublishableKey': 'sb_publishable_synthetic_signer_fixture'}
        self.candidate = {'properties': self.properties, 'source_sha256': self.source}
        self.signing = {'format': 'collect.burimunsi.testing-signing-profile.v1', 'purpose': 'testing-candidate-signing',
            'alias': 'synthetic-buri-alias', 'certificate_sha256': self.pin, 'packages': signer.PACKAGES,
            'version_code': signer.VERSION_CODE, 'production_authorized': False}
        timestamp = dt.datetime.now(dt.timezone.utc).isoformat()
        rows = []
        for flavor, package in signer.PACKAGES.items():
            ref = self.put(flavor+'.apk', apk(xml(flavor)))
            rows.append({'flavor': flavor, 'package': package, 'version_code': signer.VERSION_CODE, **ref})
        self.build = {'format': 'collect.burimunsi.configured-release-build.v1', 'source_sha256': self.source,
            'candidate_sha256': self.put('candidate.json', self.candidate)['sha256'], 'properties': self.properties,
            'tasks': signer.TASKS, 'command_sha256': 'b'*64, 'returncode': 0, 'finished_at': timestamp,
            'unsigned_apk_sha256': {row['flavor']: row['sha256'] for row in rows}}
        self.doc = {'format': 'collect.burimunsi.unsigned-testing-candidate.v1', 'created_at': timestamp,
            'source_sha256': self.source, 'candidate': self.put('candidate.json', self.candidate),
            'profile': self.put('profile.json', self.profile), 'signing_profile': self.put('signing.json', self.signing),
            'build': self.put('build.json', self.build), 'artifacts': rows}
        self.path = self.evidence / 'unsigned-candidate.json'
        self.args = argparse.Namespace(evidence=self.path, evidence_sha256='', alias=self.signing['alias'], certificate_sha256=self.pin,
            output=self.base/'signed', sdk=self.sdk, java_home=self.java, keystore=self.store,
            store_password_file=self.password, key_password_file=None, execute=False)
        self.refresh()
        def gate(candidate, profile, properties):
            current = json.loads(Path(candidate).read_bytes())
            selected = json.loads(Path(profile).read_bytes())
            try: profile_sha = signer.readiness._configuration(selected, properties)
            except ValueError: return {'ready': False}
            return {'ready': properties == current['properties'], 'source_sha256': self.source, 'profile_sha256': profile_sha,
                'production_authorized': False, 'signing_authorized': False, 'distribution_authorized': False}
        for target, value in [('source_fingerprint', lambda: {'sha256': self.source})]:
            p = patch.object(signer.pipeline, target, value); p.start(); self.addCleanup(p.stop)
        p = patch.object(signer.readiness, 'evaluate_candidate', side_effect=gate); p.start(); self.addCleanup(p.stop)
        p = patch.object(signer, 'run_tool', side_effect=self.fake); p.start(); self.addCleanup(p.stop)

    def put(self, name, value):
        raw = value if isinstance(value, bytes) else signer.canonical(value)
        path = self.evidence/name; path.write_bytes(raw)
        return {'path': name, 'sha256': signer.digest(raw)}

    def refresh(self):
        self.path.write_bytes(signer.canonical(self.doc)); self.args.evidence_sha256 = signer.digest(self.path.read_bytes())

    def rewrite_apk(self, flavor, raw):
        row = next(row for row in self.doc['artifacts'] if row['flavor'] == flavor)
        row.update(self.put(row['path'], raw)); self.build['unsigned_apk_sha256'][flavor] = row['sha256']
        self.doc['build'] = self.put('build.json', self.build); self.refresh()

    def test_default_plan_has_no_signing_or_output_and_does_not_promote(self):
        result = signer.sign(self.args)
        self.assertEqual(result['status'], 'PLAN'); self.assertFalse(result['signing_executed'])
        self.assertFalse(result['production_authorized']); self.assertFalse(result['distribution_authorized'])
        self.assertFalse(self.args.output.exists())
        self.assertFalse(any(Path(argv[0]).name == 'apksigner' for argv, _ in self.fake.calls))

    def test_synthetic_roundtrip_preserves_payload_and_uses_only_password_files(self):
        self.args.execute = True; result = signer.sign(self.args)
        self.assertEqual(result['status'], 'PASS'); self.assertEqual(len(result['artifacts']), 2)
        self.assertFalse(result['production_authorized']); self.assertFalse(result['distribution_authorized'])
        self.assertEqual(result['signing_tool_completed_flavors'], list(signer.PACKAGES))
        self.assertTrue(all(stat.S_IMODE((self.args.output/row['path']).stat().st_mode) == 0o600 for row in result['artifacts']))
        self.assertEqual(stat.S_IMODE((self.args.output/'result.json').stat().st_mode), 0o600)
        secret = self.password_value.decode().strip()
        self.assertNotIn(secret, (self.args.output/'result.json').read_text())
        for argv, env in self.fake.calls:
            self.assertNotIn(secret, repr(argv)); self.assertNotIn(secret, repr(env))
            self.assertNotIn('JAVA_TOOL_OPTIONS', env); self.assertNotIn('JDK_JAVA_OPTIONS', env)
            if Path(argv[0]).name == 'apksigner' and argv[1] == 'sign':
                self.assertTrue(argv[argv.index('--ks-pass')+1].startswith('file:'))
                self.assertNotIn('--key-pass', argv)
        self.assertEqual(self.store.read_bytes(), b'synthetic keystore, not a real key')
        self.assertEqual(self.password.read_bytes(), self.password_value)

    def test_explicit_same_password_path_uses_pkcs12_store_default(self):
        self.args.execute = True; self.args.key_password_file = self.password
        result = signer.sign(self.args)
        self.assertEqual(result['key_password_mode'], 'store-password-default')
        for argv, _ in self.fake.calls:
            if Path(argv[0]).name == 'apksigner' and argv[1] == 'sign': self.assertNotIn('--key-pass', argv)

    def test_explicit_separate_password_file_is_used_and_protected(self):
        separate = self.password.parent/'separate-password'; signer.write_private(separate, self.password_value)
        self.args.execute = True; self.args.key_password_file = separate
        result = signer.sign(self.args)
        self.assertEqual(result['key_password_mode'], 'separate-protected-file')
        for argv, _ in self.fake.calls:
            if Path(argv[0]).name == 'apksigner' and argv[1] == 'sign':
                self.assertEqual(argv[argv.index('--key-pass')+1], 'file:'+str(separate))

    def test_changed_source_is_rejected_before_any_tool(self):
        self.source = 'c'*64
        with self.assertRaises(ValueError): signer.sign(self.args)
        self.assertFalse(self.fake.calls)

    def test_tampered_unsigned_bytes_fail_without_regenerating_evidence(self):
        (self.evidence/'staff.apk').write_bytes(apk(xml('staff'), dex=b'tampered'))
        with self.assertRaises(ValueError): signer.sign(self.args)
        self.assertFalse(self.fake.calls)

    def test_changed_manifest_requires_explicit_new_evidence_pin(self):
        self.path.write_bytes(self.path.read_bytes()+b' ')
        with self.assertRaises(ValueError): signer.sign(self.args)
        self.assertFalse(self.fake.calls)

    def test_different_compiler_properties_cannot_be_masked_by_ambient_environment(self):
        self.build['properties'] = {**self.properties, 'collectAdminOrigin': 'https://wrong.example.test'}
        self.doc['build'] = self.put('build.json', self.build); self.refresh()
        with patch.dict(os.environ, {'BURI_BUILD_PUBLIC_PROPERTIES': json.dumps(self.properties)}):
            with self.assertRaises(ValueError): signer.sign(self.args)
        self.assertFalse(self.fake.calls)

    def test_external_signing_profile_and_cli_pin_must_both_match(self):
        self.args.certificate_sha256 = 'd'*64
        with self.assertRaises(ValueError): signer.sign(self.args)
        self.assertFalse(self.fake.calls)

    def test_previous_release_signing_profile_is_refused_before_signing(self):
        self.signing['version_code'] = 47
        self.doc['signing_profile'] = self.put('signing.json', self.signing); self.refresh()
        with self.assertRaisesRegex(ValueError, 'signing_profile_wrong'): signer.sign(self.args)
        self.assertFalse(self.fake.calls)

    def test_previous_release_artifact_evidence_is_refused_before_signing(self):
        self.doc['artifacts'][0]['version_code'] = 47
        self.refresh()
        with self.assertRaisesRegex(ValueError, 'unsigned_artifact_identity_wrong'): signer.sign(self.args)
        self.assertFalse(self.fake.calls)

    def test_actual_keystore_certificate_is_checked_before_alignment_or_signing(self):
        self.fake.certificate = b'other synthetic certificate'
        with self.assertRaisesRegex(ValueError, 'keystore_certificate_mismatch'): signer.sign(self.args)
        self.assertEqual(len(self.fake.calls), 1)

    def test_wrong_apk_signer_certificate_prevents_verified_output(self):
        self.args.execute = True; self.fake.wrong_verify = True
        with self.assertRaises(ValueError): signer.sign(self.args)
        self.assertFalse((self.args.output/'staff-testing-candidate.apk').exists())
        result = json.loads((self.args.output/'result.json').read_bytes())
        self.assertEqual(result['status'], 'FAIL'); self.assertTrue(result['signing_executed'])

    def test_multiple_signers_are_refused(self):
        self.args.execute = True; self.fake.multiple_signers = True
        with self.assertRaises(ValueError): signer.sign(self.args)
        self.assertFalse((self.args.output/'staff-testing-candidate.apk').exists())

    def test_signing_profile_cannot_grant_production(self):
        self.signing['production_authorized'] = True
        self.doc['signing_profile'] = self.put('signing.json', self.signing); self.refresh()
        with self.assertRaises(ValueError): signer.sign(self.args)
        self.assertFalse(self.fake.calls)

    def test_cool_qualification_native_test_or_different_package_is_refused(self):
        for package in ('app.cool.mobile', 'rw.ikanisa.burimunsi.staff', 'rw.ikanisa.burimunsi.gateway',
                        'rw.ikanisa.burimunsi.staff.cloud.qualification',
                        'rw.ikanisa.burimunsi.staff.cloud.nativeTest', 'rw.ikanisa.burimunsi.other'):
            self.rewrite_apk('staff', apk(xml('staff', package=package)))
            with self.assertRaises(ValueError): signer.sign(self.args)
        self.assertFalse(any(Path(argv[0]).name == 'apksigner' for argv, _ in self.fake.calls))

    def test_debug_testonly_or_wrong_version_is_refused(self):
        for field, value in [('debuggable', 'true'), ('testOnly', 'true'), ('versionCode', '47'), ('versionCode', '24'), ('versionCode', '23')]:
            self.rewrite_apk('staff', apk(xml('staff', **{field: value})))
            with self.assertRaises(ValueError): signer.sign(self.args)

    def test_signing_or_alignment_payload_substitution_is_refused(self):
        self.args.execute = True; self.fake.tamper_aligned = True
        with self.assertRaises(ValueError): signer.sign(self.args)
        self.assertFalse(any(argv[1:2] == ['sign'] for argv, _ in self.fake.calls))
        self.args.output = self.base/'other-signed'; self.fake.tamper_aligned = False; self.fake.tamper_signed = True
        with self.assertRaises(ValueError): signer.sign(self.args)
        self.assertFalse((self.args.output/'staff-testing-candidate.apk').exists())

    def test_unsigned_apk_with_prior_signature_or_duplicate_entry_is_refused(self):
        for duplicate in (False, True):
            output = io.BytesIO()
            with warnings.catch_warnings():
                warnings.simplefilter('ignore', UserWarning)
                with zipfile.ZipFile(output, 'w') as archive:
                    archive.writestr('AndroidManifest.xml', xml('staff')); archive.writestr('classes.dex', b'synthetic')
                    archive.writestr('classes.dex' if duplicate else 'META-INF/PRIOR.SF', b'synthetic')
            self.rewrite_apk('staff', output.getvalue())
            with self.assertRaises(ValueError): signer.sign(self.args)
        self.assertFalse(any(argv[1:2] == ['sign'] for argv, _ in self.fake.calls))

    def test_credential_change_during_alignment_prevents_signing(self):
        self.args.execute = True
        self.fake.after_align = lambda: self.password.write_bytes(b'different synthetic password\n')
        with self.assertRaises(ValueError): signer.sign(self.args)
        self.assertFalse(any(argv[1:2] == ['sign'] for argv, _ in self.fake.calls))

    def test_incomplete_signing_is_not_retried_or_reported_as_no_attempt(self):
        self.args.execute = True; self.fake.fail_sign = True
        with self.assertRaises(ValueError): signer.sign(self.args)
        result = json.loads((self.args.output/'result.json').read_bytes())
        self.assertEqual(result['signing_attempted_flavors'], ['staff'])
        self.assertTrue(result['signing_outcome_unconfirmed'])
        self.assertEqual(sum(argv[1:2] == ['sign'] for argv, _ in self.fake.calls), 1)
        with self.assertRaises(ValueError): signer.sign(self.args)

    def test_existing_outputs_cannot_be_overwritten(self):
        self.args.output.mkdir(); sentinel = self.args.output/'sentinel'; sentinel.write_bytes(b'preserved')
        self.args.execute = True
        with self.assertRaises(ValueError): signer.sign(self.args)
        self.assertEqual(sentinel.read_bytes(), b'preserved'); self.assertFalse(self.fake.calls)

    def test_credential_mode_parent_links_and_multiline_password_fail_closed(self):
        self.password.chmod(0o644)
        with self.assertRaises(ValueError): signer.sign(self.args)
        self.password.chmod(0o600); self.password.parent.chmod(0o755)
        with self.assertRaises(ValueError): signer.sign(self.args)
        self.password.parent.chmod(0o700); self.password.write_bytes(b'first\nsecond\n')
        with self.assertRaises(ValueError): signer.sign(self.args)
        self.password.write_bytes(self.password_value)
        link = self.password.parent/'linked'; link.symlink_to(self.password); self.args.store_password_file = link
        with self.assertRaises(ValueError): signer.sign(self.args)
        self.assertFalse(self.fake.calls)

    def test_unpinned_sdk_or_jdk_version_is_refused(self):
        (self.sdk/'build-tools/36.0.0/source.properties').write_text('Pkg.Revision=35.0.0\n')
        with self.assertRaises(ValueError): signer.sign(self.args)
        (self.sdk/'build-tools/36.0.0/source.properties').write_text('Pkg.Revision=36.0.0\n')
        (self.java/'release').write_text('JAVA_VERSION="21.0.1"\n')
        with self.assertRaises(ValueError): signer.sign(self.args)
        self.assertFalse(self.fake.calls)

    def test_tool_error_output_never_becomes_exception_or_receipt_text(self):
        # Exercise the actual wrapper, outside the suite's fake command adapter.
        with patch.object(signer.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, b'', b'synthetic-secret-sentinel')):
            with self.assertRaises(ValueError) as caught: REAL_RUN_TOOL(['synthetic-tool'], {})
        self.assertNotIn('synthetic-secret-sentinel', str(caught.exception))
        self.assertEqual(str(caught.exception), 'signing_tool_failed')


class ActualSdkPKCS12PasswordRegression(unittest.TestCase):
    """SDK36/JDK17 with a new disposable TEST key, never the Buri signing key."""
    @classmethod
    def setUpClass(cls):
        sdk = Path(os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT') or Path.home()/'Library/Android/sdk')
        ready = signer.pipeline.OVERLAY/'.cache/burimunsi-drive-20261109/toolchain/jdk17-ready.json'
        java = json.loads(ready.read_bytes())['JAVA_HOME'] if ready.is_file() else os.environ.get('JAVA_HOME')
        if not java or not (sdk/'build-tools/36.0.0/apksigner').is_file():
            raise unittest.SkipTest('Installed SDK36/JDK17 required for isolated password-file regression')
        cls.selected, _, cls.env = signer.tools(sdk, java)

    def test_real_sdk_default_and_separate_file_succeed_while_repeated_file_reproduces_eof(self):
        with tempfile.TemporaryDirectory(prefix='burimunsi-TEST-password-regression-') as temporary:
            root = Path(temporary).resolve(); root.chmod(0o700)
            password_path = root/'password'; separate_path = root/'separate-password'
            password_bytes = (secrets.token_hex(24)+'\n').encode()
            signer.write_private(password_path, password_bytes); signer.write_private(separate_path, password_bytes)
            store_path = root/'TEST-only.p12'; alias = 'isolated-test-only'
            REAL_RUN_TOOL([self.selected['keytool'], '-genkeypair', '-keystore', store_path, '-storetype', 'PKCS12',
                '-alias', alias, '-keyalg', 'RSA', '-keysize', '2048', '-validity', '1',
                '-dname', 'CN=Isolated TEST password regression', '-storepass:file', password_path], self.env)
            store_path.chmod(0o600)
            store = signer.private_input(store_path, 16*1024*1024)
            password = signer.private_input(password_path, 4096, password=True)
            separate = signer.private_input(separate_path, 4096, password=True)
            source = root/'synthetic.apk'; signer.write_private(source, apk(xml('staff')))
            aligned = root/'aligned.apk'
            REAL_RUN_TOOL([self.selected['zipalign'], '-P', '16', '4', source, aligned], self.env)
            # Reproduce the actual SDK PasswordRetriever failure without ever
            # logging the password, raw child output or any real credential.
            bad = signer.signing_command(self.selected['apksigner'], store, password, None, alias, root/'refused.apk', aligned)
            index = bad.index('--min-sdk-version'); bad[index:index] = ['--key-pass', 'file:'+str(password_path)]
            failed = subprocess.run([str(v) for v in bad], stdin=subprocess.DEVNULL, capture_output=True, env=self.env, timeout=120)
            self.assertNotEqual(failed.returncode, 0)
            self.assertTrue(b'end of file' in (failed.stdout+failed.stderr).lower())
            certificate = REAL_RUN_TOOL([self.selected['keytool'], '-exportcert', '-keystore', store_path,
                '-storetype', 'PKCS12', '-alias', alias, '-storepass:file', password_path], self.env)
            for name, key_password in [('default', None), ('separate', separate)]:
                target = root/(name+'.apk')
                command = signer.signing_command(self.selected['apksigner'], store, password, key_password, alias, target, aligned)
                self.assertEqual('--key-pass' in command, key_password is not None)
                self.assertTrue(password_bytes.decode().strip() not in repr(command))
                self.assertTrue(password_bytes.decode().strip() not in repr(self.env))
                REAL_RUN_TOOL(command, self.env)
                proof = REAL_RUN_TOOL([self.selected['apksigner'], 'verify', '--min-sdk-version', '26',
                    '--verbose', '--print-certs', '-Werr', target], self.env)
                self.assertTrue(signer.digest(certificate).encode() in proof)
                self.assertTrue(b'Verified using v2 scheme' in proof)
                REAL_RUN_TOOL([self.selected['zipalign'], '-c', '-P', '16', '4', target], self.env)
                self.assertEqual(signer.payload(target.read_bytes(), 'staff', unsigned=False),
                                 signer.payload(source.read_bytes(), 'staff', unsigned=True))
            self.assertEqual(password_path.read_bytes(), password_bytes)
            self.assertEqual(separate_path.read_bytes(), password_bytes)


if __name__ == '__main__': unittest.main()
