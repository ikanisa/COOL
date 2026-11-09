"""Host-only fixture regressions for native execution infrastructure; never APK evidence."""
import argparse
import copy
import dataclasses
import importlib.util
import json
import pathlib
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[3]
SCRIPTS = ROOT / 'native/burimunsi/scripts'
sys.path.insert(0, str(SCRIPTS))
import native_pipeline as n
import build_preflight as pre


def manifest(spec, extra='', app_extra='', app_body='', root_extra=''):
    if spec.test:
        return f'<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="{spec.package}"><instrumentation android:name="{n.RUNNER}" android:targetPackage="{n.Artifact(spec.flavor, "nativeTest").package}"/></manifest>'
    debug = 'false' if spec.kind == 'qualification' else 'true'
    test_only = 'true' if spec.kind in ('nativeTest', 'qualification') else 'false'
    return f'''<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="{spec.package}" {root_extra}>
      <uses-sdk android:minSdkVersion="26" android:targetSdkVersion="36"/>{extra}
      <application android:usesCleartextTraffic="false" android:allowBackup="false" android:debuggable="{debug}" android:testOnly="{test_only}" {app_extra}>{app_body}</application></manifest>'''


def receiver_manifest(spec):
    permissions = ''.join(f'<uses-permission android:name="android.permission.{p}"/>' for p in ('READ_SMS', 'RECEIVE_SMS'))
    parts = [('CollectSmsReceiver', 'receiver', 'android.permission.BROADCAST_SMS', 'true'),
             ('MomoGatewayRecoveryReceiver', 'receiver', None, 'false'),
             ('MomoGatewayJobService', 'service', 'android.permission.BIND_JOB_SERVICE', 'true'),
             ('MomoGatewayLocalRecoveryService', 'service', 'android.permission.BIND_JOB_SERVICE', 'true')]
    body = ''
    for name, tag, permission, exported in parts:
        guard = f'android:permission="{permission}"' if permission else ''
        body += f'<{tag} android:name="app.cool.mobile.receiver_sms.{name}" android:exported="{exported}" {guard}/>'
    return manifest(spec, permissions, app_body=body)


def stream(expected):
    text = ''
    for i, name in enumerate(sorted(expected), 1):
        cls, method = name.split('#')
        block = f'INSTRUMENTATION_STATUS: class={cls}\nINSTRUMENTATION_STATUS: test={method}\nINSTRUMENTATION_STATUS: current={i}\n'
        text += block + 'INSTRUMENTATION_STATUS_CODE: 1\n' + block + 'INSTRUMENTATION_STATUS_CODE: 0\n'
    return text + f'INSTRUMENTATION_RESULT: stream=\nTime: 0.1\nOK ({len(expected)} tests)\nINSTRUMENTATION_CODE: -1\n'


class NativePlan(unittest.TestCase):
    def test_eight_distinct_artifacts(self):
        self.assertEqual(len(n.artifacts()), 8)
        self.assertEqual(len({a.filename for a in n.artifacts()}), 8)
        self.assertEqual(len({a.package for a in n.artifacts()}), 8)
    def test_no_production_assemble_task(self):
        self.assertEqual(n.build_tasks()[0], 'clean')
        self.assertFalse(any('Release' in task for task in n.build_tasks()))
    def test_both_flavors_linted(self):
        for task in (':app:lintStaffDebug', ':app:lintInternal_receiverDebug', ':app:lintStaffNativeTest', ':app:lintInternal_receiverNativeTest'):
            self.assertIn(task, n.build_tasks())
    def test_all_app_and_test_apks_built(self):
        self.assertEqual(sum(':app:assemble' in v for v in n.build_tasks()), 8)
    def test_union_of_native_and_ui_authored_tests_not_execution(self):
        self.assertEqual(n.expected_tests(), {'rw.ikanisa.burimunsi.NativeUiContractTest#collectLoginUsesNativeCredentialsAndClearsSubmittedPassword', 'rw.ikanisa.burimunsi.NativeUiContractTest#collectLoginDisposalClearsRememberedCredentials', 'rw.ikanisa.burimunsi.NativeUiContractTest#collectLoginDenialProvidesRecoveryWithoutPrivateRecords', 'rw.ikanisa.burimunsi.StaffPackageIsolationTest#installedPackageEnforcesRoleBoundary', 'rw.ikanisa.burimunsi.NativeUiContractTest#pausedGuardRemovesRecordSemantics', 'rw.ikanisa.burimunsi.NativeUiContractTest#twoHundredPercentTypeKeepsTheFullAmountAccessible', 'rw.ikanisa.burimunsi.NativeUiContractTest#phoneNextFocusesPasscodeAndDoneSubmitsOnlyOnce', 'rw.ikanisa.burimunsi.NativeSandboxContractTest#installedSandboxHasNoInternetBackupOrCleartext', 'rw.ikanisa.burimunsi.NativeUiContractTest#memberLedgerUsesFullPhoneAndSourceReference', 'rw.ikanisa.burimunsi.NativeSandboxContractTest#gatewayCannotBindOrResumeInSandbox', 'rw.ikanisa.burimunsi.NativeSandboxContractTest#installationUsesOnlyDedicatedSandboxIdentity', 'rw.ikanisa.burimunsi.NativeUiContractTest#homeHasNoRemovedLabelsAndPreservesAccessibleName', 'rw.ikanisa.burimunsi.NativeUiContractTest#paymentHistoryShowsRecordedEventsWithoutInventingSuccess', 'rw.ikanisa.burimunsi.NativeUiContractTest#expiredGuardHasRecoveryAndNoFinancialRows', 'rw.ikanisa.burimunsi.NativeUiContractTest#bottomNavigationExposesSelectedTab', 'rw.ikanisa.burimunsi.NativeUiContractTest#pausingDisposesRememberedCredentialInput', 'rw.ikanisa.burimunsi.NativeUiContractTest#invalidPhoneNeverEnablesSignIn', 'rw.ikanisa.burimunsi.NativeSandboxContractTest#launcherActivityBelongsToSandbox', 'rw.ikanisa.burimunsi.NativeUiContractTest#kinyarwandaLabelsDoNotTranslateProviderEvidence', 'rw.ikanisa.burimunsi.NativeUiContractTest#originalSmsRemainsUnalteredInKinyarwanda', 'rw.ikanisa.burimunsi.NativeUiContractTest#confirmingPasscodeImeDoesNotCommitCredentialChange', 'rw.ikanisa.burimunsi.NativeUiContractTest#paymentDetailHasOriginalReferenceAndNoCreditedLabel', 'rw.ikanisa.burimunsi.NativeUiContractTest#searchImeSubmitsTheVisibleQuery', 'rw.ikanisa.burimunsi.NativeUiContractTest#staffHasNoMessagesShortcut', 'rw.ikanisa.burimunsi.NativeSandboxContractTest#compiledConfigurationContainsNoLiveEndpointOrBinding', 'rw.ikanisa.burimunsi.NativeUiContractTest#phoneAndFourDigitFieldsHaveStableAccessibleNames'})
        self.assertFalse(n.plan()['native_build_executed'])
    def test_plan_never_calls_subprocess(self):
        with patch.object(n.subprocess, 'run', side_effect=AssertionError('Plan executed a tool')):
            self.assertEqual(n.plan()['mode'], 'plan')
    def test_custom_build_type_has_manifest_dependency(self):
        s=(n.ROOT/'app/build.gradle.kts').read_text()
        self.assertIn('testBuildType = "nativeTest"', s)
        self.assertIn('add("nativeTestImplementation", "androidx.compose.ui:ui-test-manifest")', s)
        self.assertIn('androidTestImplementation("androidx.test:runner:1.7.0")', s)
    def test_native_test_manifest_offline(self):
        s=(n.ROOT/'app/src/nativeTest/AndroidManifest.xml').read_text()
        self.assertIn('android.permission.INTERNET" tools:node="remove"',s)
        self.assertIn('android:testOnly="true"',s)
    def test_existing_staff_test_no_longer_skipped_for_gateway(self):
        s=(n.ROOT/'app/src/androidTest/kotlin/rw/ikanisa/burimunsi/StaffPackageIsolationTest.kt').read_text()
        self.assertNotIn('assumeFalse',s)
        self.assertIn('if (BuildConfig.IS_GATEWAY)',s)


class ArtifactSelection(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=pathlib.Path(self.tmp.name).resolve()
        (self.root/'test.apk').write_bytes(b'fixture, not an APK')
        self.data={'variantName':'staffNativeTest','elements':[{'outputFile':'test.apk','filters':[]}]}
        self.save()
    def tearDown(self):self.tmp.cleanup()
    def save(self):(self.root/'output-metadata.json').write_text(json.dumps(self.data))
    def choose(self):return n.select_apk(self.root,'staffNativeTest')
    def test_selects_exact_metadata(self):self.assertEqual(self.choose(),self.root/'test.apk')
    def test_missing_metadata(self):
        (self.root/'output-metadata.json').unlink()
        with self.assertRaises(n.PipelineError):self.choose()
    def test_wrong_variant(self):
        self.data['variantName']='staffRelease';self.save()
        with self.assertRaises(n.PipelineError):self.choose()
    def test_ambiguous_outputs(self):
        self.data['elements']*=2;self.save()
        with self.assertRaises(n.PipelineError):self.choose()
    def test_split_outputs(self):
        self.data['elements'][0]['filters']=[{'filterType':'ABI','value':'arm64-v8a'}];self.save()
        with self.assertRaises(n.PipelineError):self.choose()
    def test_traversal(self):
        self.data['elements'][0]['outputFile']='../outside.apk';self.save()
        with self.assertRaises(n.PipelineError):self.choose()
    def test_absolute_path(self):
        self.data['elements'][0]['outputFile']=str(self.root/'test.apk');self.save()
        with self.assertRaises(n.PipelineError):self.choose()
    def test_symlink_output(self):
        (self.root/'test.apk').unlink();(self.root/'test.apk').symlink_to(self.root/'output-metadata.json')
        with self.assertRaises(n.PipelineError):self.choose()
    def test_missing_apk(self):
        (self.root/'test.apk').unlink()
        with self.assertRaises(n.PipelineError):self.choose()
    def test_wrong_extension(self):
        self.data['elements'][0]['outputFile']='test.aab';self.save()
        with self.assertRaises(n.PipelineError):self.choose()
    def test_existing_evidence_refused(self):
        with self.assertRaises(n.PipelineError):n.fresh_dir(self.root)
    def test_new_evidence_allowed(self):self.assertTrue(n.fresh_dir(self.root/'new').is_dir())


class ApkManifestContract(unittest.TestCase):
    def setUp(self):self.spec=n.Artifact('staff','nativeTest')
    def test_valid_staff_native_test(self):self.assertEqual(n.inspect_xml(manifest(self.spec),self.spec),[])
    def test_valid_staff_qualification(self):
        a=n.Artifact('staff','qualification');self.assertEqual(n.inspect_xml(manifest(a),a),[])
    def test_valid_staff_debug(self):
        a=n.Artifact('staff','debug');self.assertEqual(n.inspect_xml(manifest(a),a),[])
    def test_internet_refused(self):self.assertTrue(n.inspect_xml(manifest(self.spec,'<uses-permission android:name="android.permission.INTERNET"/>'),self.spec))
    def test_sdk23_permission_bypass_refused(self):self.assertTrue(n.inspect_xml(manifest(self.spec,'<uses-permission-sdk-23 android:name="android.permission.READ_SMS"/>'),self.spec))
    def test_non_testonly_refused(self):self.assertTrue(n.inspect_xml(manifest(self.spec).replace('testOnly="true"','testOnly="false"'),self.spec))
    def test_nondebuggable_native_test_refused(self):self.assertTrue(n.inspect_xml(manifest(self.spec).replace('debuggable="true"','debuggable="false"'),self.spec))
    def test_live_identity_refused(self):self.assertTrue(n.inspect_xml(manifest(self.spec).replace('.nativeTest',''),self.spec))
    def test_shared_uid_refused(self):self.assertTrue(n.inspect_xml(manifest(self.spec,root_extra='android:sharedUserId="example.shared"'),self.spec))
    def test_sdk_drift_refused(self):self.assertTrue(n.inspect_xml(manifest(self.spec).replace('targetSdkVersion="36"','targetSdkVersion="35"'),self.spec))
    def test_valid_receiver(self):
        a=n.Artifact('internal_receiver','nativeTest');self.assertEqual(n.inspect_xml(receiver_manifest(a),a),[])
    def test_receiver_permissions_without_components_refused(self):
        a=n.Artifact('internal_receiver','nativeTest');self.assertTrue(n.inspect_xml(manifest(a,'<uses-permission android:name="android.permission.READ_SMS"/><uses-permission android:name="android.permission.RECEIVE_SMS"/>'),a))
    def test_missing_receiver_service_refused(self):
        a=n.Artifact('internal_receiver','nativeTest');self.assertTrue(n.inspect_xml(receiver_manifest(a).replace('MomoGatewayJobService','OtherJob'),a))
    def test_bad_broadcast_guard_refused(self):
        a=n.Artifact('internal_receiver','nativeTest');self.assertTrue(n.inspect_xml(receiver_manifest(a).replace('BROADCAST_SMS','READ_SMS'),a))
    def test_exposed_recovery_refused(self):
        a=n.Artifact('internal_receiver','nativeTest');self.assertTrue(n.inspect_xml(receiver_manifest(a).replace('exported="false"','exported="true"'),a))
    def test_test_apk_target_matches(self):
        a=n.Artifact('staff','nativeTest',True);self.assertEqual(n.inspect_xml(manifest(a),a),[])
    def test_wrong_test_target(self):
        a=n.Artifact('staff','nativeTest',True);self.assertTrue(n.inspect_xml(manifest(a).replace('android:targetPackage="rw.ikanisa.burimunsi.staff.nativeTest"','android:targetPackage="rw.ikanisa.burimunsi.staff"'),a))
    def test_wrong_runner(self):
        a=n.Artifact('staff','nativeTest',True);self.assertTrue(n.inspect_xml(manifest(a).replace(n.RUNNER,'other.Runner'),a))


class InstrumentationParsing(unittest.TestCase):
    def setUp(self):self.expected={'example.Test#one','example.Test#two'};self.text=stream(self.expected)
    def reject(self,text):self.assertFalse(n.parse_instrumentation(text,self.expected)['passed'])
    def test_exact_pass(self):self.assertTrue(n.parse_instrumentation(self.text,self.expected)['passed'])
    def test_zero_tests(self):self.reject('OK (0 tests)\nINSTRUMENTATION_CODE: -1\n')
    def test_adb_zero_exit_not_evidence(self):self.reject('')
    def test_missing_final(self):self.reject(self.text.replace('INSTRUMENTATION_CODE: -1',''))
    def test_wrong_final(self):self.reject(self.text.replace('INSTRUMENTATION_CODE: -1','INSTRUMENTATION_CODE: 0'))
    def test_duplicate_final(self):self.reject(self.text+'INSTRUMENTATION_CODE: -1\n')
    def test_failed_test(self):self.reject(self.text.replace('INSTRUMENTATION_STATUS_CODE: 0','INSTRUMENTATION_STATUS_CODE: -2',1))
    def test_assumption_skip(self):self.reject(self.text.replace('INSTRUMENTATION_STATUS_CODE: 0','INSTRUMENTATION_STATUS_CODE: -4',1))
    def test_ignored_test(self):self.reject(self.text.replace('INSTRUMENTATION_STATUS_CODE: 0','INSTRUMENTATION_STATUS_CODE: -3',1))
    def test_unexpected_test(self):self.reject(self.text.replace('test=one','test=other'))
    def test_wrong_total(self):self.reject(self.text.replace('OK (2 tests)','OK (1 tests)'))
    def test_crash(self):self.reject(self.text+'Process crashed\n')
    def test_aborted(self):self.reject(self.text+'INSTRUMENTATION_ABORTED: failure\n')
    def test_failure_footer(self):self.reject(self.text+'FAILURES!!!\n')
    def test_no_start(self):self.reject(self.text.replace('INSTRUMENTATION_STATUS_CODE: 1','INSTRUMENTATION_STATUS_CODE: 0',1))
    def test_duplicate_completion(self):self.reject(self.text+self.text)
    def test_no_expected_contract(self):self.assertFalse(n.parse_instrumentation('OK (0 tests)\nINSTRUMENTATION_CODE: -1',set())['passed'])
    def test_malformed_status(self):self.reject(self.text.replace('INSTRUMENTATION_STATUS_CODE: 1','INSTRUMENTATION_STATUS_CODE: invalid',1))


class CommandLogging(unittest.TestCase):
    def test_live_stdout_and_stderr_are_synced_before_child_exit(self):
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td).resolve()
            log, release = root / 'command.log', root / 'release'
            durable = threading.Event()
            results, errors = [], []
            fsync = n.os.fsync
            def sync(fd):
                fsync(fd)
                if b'LIVE_STDOUT\nLIVE_STDERR\n' in log.read_bytes():
                    durable.set()
            script = (
                "import pathlib,sys,time\n"
                "print('LIVE_STDOUT',flush=True)\n"
                "print('LIVE_STDERR',file=sys.stderr,flush=True)\n"
                "while not pathlib.Path(sys.argv[1]).exists(): time.sleep(0.01)\n"
            )
            def execute():
                try:
                    results.append(n.command([sys.executable, '-c', script, str(release)], log, timeout=5))
                except BaseException as error:
                    errors.append(error)
            with patch.object(n.os, 'fsync', side_effect=sync):
                child = threading.Thread(target=execute)
                child.start()
                try:
                    self.assertTrue(durable.wait(3), 'Output was not durable while the child was running')
                    self.assertTrue(child.is_alive(), 'The child exited before live-log verification')
                    self.assertEqual(log.read_text(), 'LIVE_STDOUT\nLIVE_STDERR\n')
                finally:
                    release.touch()
                    child.join(3)
                self.assertFalse(child.is_alive(), 'Synthetic child did not finish')
            self.assertEqual(errors, [])
            self.assertEqual(results, ['LIVE_STDOUT\nLIVE_STDERR\n'])

    def test_timeout_retains_real_child_progress_and_timeout_marker(self):
        with tempfile.TemporaryDirectory() as td:
            log = pathlib.Path(td).resolve() / 'timeout.log'
            script = (
                "import sys,time\n"
                "print('TIMEOUT_STDOUT',flush=True)\n"
                "print('TIMEOUT_STDERR',file=sys.stderr,flush=True)\n"
                "time.sleep(10)\n"
            )
            with self.assertRaisesRegex(n.PipelineError, 'Command timed out:'):
                n.command([sys.executable, '-c', script], log, timeout=1)
            self.assertEqual(log.read_text(), 'TIMEOUT_STDOUT\nTIMEOUT_STDERR\n\nTIMED OUT\n')

    def test_nonzero_exit_retains_real_child_stdout_and_stderr(self):
        with tempfile.TemporaryDirectory() as td:
            log = pathlib.Path(td).resolve() / 'failed.log'
            script = (
                "import sys\n"
                "print('FAILED_STDOUT',flush=True)\n"
                "print('FAILED_STDERR',file=sys.stderr,flush=True)\n"
                "sys.exit(7)\n"
            )
            with self.assertRaisesRegex(n.PipelineError, r'Command failed \(7\)'):
                n.command([sys.executable, '-c', script], log)
            self.assertEqual(log.read_text(), 'FAILED_STDOUT\nFAILED_STDERR\n')

    def test_missing_executable_keeps_diagnostic_and_failure_contract(self):
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td).resolve()
            log = root / 'missing.log'
            with self.assertRaisesRegex(n.PipelineError, 'Tool could not be executed:'):
                n.command([str(root / 'missing-executable')], log)
            self.assertIn('missing-executable', log.read_text())


class StartupUiReadiness(unittest.TestCase):
    package = 'rw.ikanisa.burimunsi.staff.nativeTest'

    def wait_with(self, xml, *, dump='UI hierchary dumped', dump_error=None):
        calls = []
        def call(parts, name, timeout):
            calls.append((parts, name, timeout))
            if parts[:3] == ['shell', 'uiautomator', 'dump']:
                if dump_error:
                    raise dump_error
                return dump
            if parts[:2] == ['shell', 'cat']:
                return xml
            if parts[:3] == ['shell', 'rm', '-f']:
                return ''
            raise AssertionError('Unexpected UI readiness action: ' + repr(parts))
        return call, calls

    def test_app_content_is_required_and_only_the_unique_dump_is_removed(self):
        xml = f'<hierarchy><node package="com.android.systemui" text="9:21"/><node package="{self.package}" text="Managed setup required"/></hierarchy>'
        call, calls = self.wait_with(xml)
        n.wait_for_startup_ui(call, self.package, 'staff')
        remote = calls[0][0][-1]
        self.assertRegex(remote, r'^/data/local/tmp/burimunsi-startup-[a-f0-9]{32}\.xml$')
        self.assertEqual([parts for parts, _, _ in calls], [
            ['shell', 'uiautomator', 'dump', remote],
            ['shell', 'cat', remote],
            ['shell', 'rm', '-f', remote],
        ])
        self.assertEqual(calls[1][1], 'staff-startup.xml')
        self.assertTrue(all(timeout == 30 for _, _, timeout in calls))

    def test_exit_zero_idle_failure_is_refused_and_its_dump_cleaned(self):
        call, calls = self.wait_with('<hierarchy/>', dump='ERROR: could not get idle state.')
        with self.assertRaisesRegex(n.PipelineError, 'did not reach accessibility idle'):
            n.wait_for_startup_ui(call, self.package, 'staff')
        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[-1][0], ['shell', 'rm', '-f', calls[0][0][-1]])

    def test_foreign_or_blank_splash_content_cannot_qualify(self):
        for xml in (
            f'<hierarchy><node package="{self.package}.test" text="Foreign test window"/></hierarchy>',
            f'<hierarchy><node package="com.android.systemui" text="9:21"/><node package="{self.package}" text=""/></hierarchy>',
        ):
            with self.subTest(xml=xml):
                call, calls = self.wait_with(xml)
                with self.assertRaisesRegex(n.PipelineError, 'no content owned by the sandbox'):
                    n.wait_for_startup_ui(call, self.package, 'staff')
                self.assertEqual(calls[-1][0][:3], ['shell', 'rm', '-f'])

    def test_malformed_hierarchy_is_refused_and_dump_cleaned(self):
        call, calls = self.wait_with('<hierarchy><node')
        with self.assertRaisesRegex(n.PipelineError, 'Invalid startup UI hierarchy'):
            n.wait_for_startup_ui(call, self.package, 'staff')
        self.assertEqual(calls[-1][0][:3], ['shell', 'rm', '-f'])

    def test_dump_timeout_keeps_failure_and_cleans_only_owned_path(self):
        call, calls = self.wait_with('', dump_error=n.PipelineError('Command timed out: staff-ui-idle.txt'))
        with self.assertRaisesRegex(n.PipelineError, 'Command timed out:'):
            n.wait_for_startup_ui(call, self.package, 'staff')
        self.assertEqual(calls[-1][0], ['shell', 'rm', '-f', calls[0][0][-1]])


class FlavorInstrumentation(unittest.TestCase):
    def test_receiver_requires_its_durability_methods_and_staff_does_not(self):
        contracts = n.test_contracts()
        staff = set(contracts['staff'])
        receiver = set(contracts['internal_receiver'])
        self.assertEqual(len(staff), 26)
        self.assertTrue(staff < receiver)
        self.assertEqual(receiver - staff, {
            'app.cool.mobile.receiver_sms.GatewayDurabilityTest#' + method
            for method in (
                'retainedCiphertextReopensInAnotherStoreInstance',
                'duplicateIdentityCannotHideDifferentEvidence',
                'durableAcknowledgementAndTombstoneSurviveReopen',
                'capacityPreservesExistingEvidenceAndLiveReserve',
                'pauseAndOwnerChangeNeverDiscardPendingEvidence',
                'legacyMigrationCopiesBeforeDeletingOriginal',
                'corruptCiphertextBlocksOwnerResetAndPreservesBytes',
            )
        })
        self.assertNotIn('app.cool.mobile.receiver_sms.GatewayDurabilityTest', n.instrumentation_classes('staff'))
        self.assertIn('app.cool.mobile.receiver_sms.GatewayDurabilityTest', n.instrumentation_classes('internal_receiver'))
        # Private carrier replay targets a .debug package and an explicitly
        # supplied corpus, so it cannot be an assumed/skipped sandbox pass.
        self.assertFalse(any('CarrierFixtureReplayTest' in value for values in contracts.values() for value in values))
        self.assertEqual(n.plan()['expected_instrumentation_tests_per_flavor'], contracts)

    def test_unknown_flavor_is_rejected(self):
        with self.assertRaises(n.PipelineError):
            n.expected_tests(flavor='production')

    def run_synthetic_instrumentation(self, *, omit_inventory_receiver=False,
                                      legacy_inventory=False, omit_receiver_method=False,
                                      foreign_startup=False, startup_idle_error=False,
                                      lose_foreground_after_idle=False, invalid_login_capture=False):
        """Exercise orchestration with fake APK/device boundaries; never calls adb."""
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td).resolve()
            evidence = root / 'build'
            (evidence / 'apks').mkdir(parents=True)
            contracts = n.test_contracts()
            recorded = copy.deepcopy(contracts)
            if omit_inventory_receiver:
                recorded['internal_receiver'] = recorded['staff']
            rows = []
            for spec in n.artifacts():
                if spec.kind != 'nativeTest':
                    continue
                path = evidence / 'apks' / spec.filename
                path.write_bytes(b'Synthetic test fixture, not an Android APK')
                rows.append({'spec': dataclasses.asdict(spec), 'path': path.relative_to(evidence).as_posix(),
                             'sha256': n.sha(path), 'certificate_sha256': 'fixture-signer'})
            inventory = {'source_sha256': 'fixture-source', 'artifacts': rows,
                         'expected_tests_per_flavor': recorded}
            if legacy_inventory:
                inventory.pop('expected_tests_per_flavor')
                inventory['expected_tests'] = recorded['staff']
            n.write_json(evidence / 'artifacts.json', inventory)
            n.write_json(evidence / 'build-result.json', {'status': 'PASS', 'apk_inspection_passed': True})
            args = argparse.Namespace(execute=True, serial='emulator-5554', sdk=None,
                                      allow_physical_device=False, output=root / 'device', build_evidence=evidence)
            calls = []
            foreground = ''
            remote_dump = None
            def command(argv, *unused, **kwargs):
                nonlocal foreground, remote_dump
                calls.append(argv)
                if argv[1:] == ['devices', '-l']:
                    return 'List of devices attached\nemulator-5554 device product:synthetic\n'
                action = argv[3:]
                if action[:2] == ['shell', 'getprop']:
                    return {'ro.kernel.qemu': '1', 'ro.build.version.sdk': '36',
                            'sys.boot_completed': '1', 'ro.build.fingerprint': 'synthetic'}[action[2]]
                if action == ['shell', 'am', 'get-current-user']:
                    return '0'
                if action[:4] == ['shell', 'pm', 'list', 'packages']:
                    return ''
                if action[0] in ('install', 'uninstall'):
                    return 'Success\n'
                if action[:3] == ['shell', 'dumpsys', 'package']:
                    return 'Synthetic installed-package observation'
                if action[:3] == ['shell', 'am', 'instrument']:
                    classes = set(action[action.index('class') + 1].split(','))
                    flavor = 'internal_receiver' if '.gateway.' in action[-1] else 'staff'
                    selected = {value for value in contracts[flavor] if value.split('#')[0] in classes}
                    if flavor == 'internal_receiver' and omit_receiver_method:
                        selected.remove('app.cool.mobile.receiver_sms.GatewayDurabilityTest#corruptCiphertextBlocksOwnerResetAndPreservesBytes')
                    return stream(selected)
                if action[:3] == ['shell', 'am', 'start']:
                    foreground = action[-1].split('/')[0]
                    return 'Status: ok\n'
                if action[:3] == ['shell', 'uiautomator', 'dump']:
                    remote_dump = action[-1]
                    return 'ERROR: could not get idle state.' if startup_idle_error else 'UI hierchary dumped to: ' + remote_dump
                if action[:2] == ['shell', 'cat']:
                    self.assertEqual(action[-1], remote_dump)
                    package = 'com.android.launcher' if foreign_startup else foreground
                    return f'<hierarchy><node package="{package}" text="Managed setup required"/></hierarchy>'
                if action[:3] == ['shell', 'rm', '-f']:
                    self.assertEqual(action[-1], remote_dump)
                    return ''
                if action == ['shell', 'dumpsys', 'activity', 'activities']:
                    return 'mResumedActivity ' + ('com.android.launcher' if lose_foreground_after_idle else foreground)
                if action[:3] == ['shell', 'am', 'force-stop']:
                    return ''
                raise AssertionError('Unexpected synthetic device command: ' + repr(argv))
            def capture(argv, **kwargs):
                calls.append(argv)
                action = argv[3:]
                if action != ['exec-out', 'screencap', '-p']:
                    self.assertEqual(action[:2], ['exec-out', 'run-as'])
                    self.assertIn(action[2], {'rw.ikanisa.burimunsi.staff.nativeTest', 'rw.ikanisa.burimunsi.gateway.nativeTest'})
                    self.assertEqual(action[3:], ['cat', 'cache/collect-sign-in.png'])
                    if invalid_login_capture:
                        return argparse.Namespace(stdout=b'not an image')
                return argparse.Namespace(stdout=b'\x89PNG\r\n\x1a\nsynthetic')
            with patch.object(n, 'sdk_path', return_value=root / 'sdk'), \
                 patch.object(n, 'sdk_tool', return_value=root / 'sdk/adb'), \
                 patch.object(n, 'source_fingerprint', return_value={'sha256': 'fixture-source'}), \
                 patch.object(n, 'inspect_apk', return_value={'certificate_sha256': 'fixture-signer'}), \
                 patch.object(n, 'command', side_effect=command), \
                 patch.object(n.subprocess, 'run', side_effect=capture), \
                 patch('builtins.print'):
                code = n.instrument(args)
            report = json.loads((args.output / 'instrumentation-result.json').read_text())
            return code, report, calls

    def test_actual_selector_executes_distinct_role_contracts(self):
        code, report, calls = self.run_synthetic_instrumentation()
        self.assertEqual(code, 0, report)
        self.assertEqual({value['flavor']: value['completed'] for value in report['flavors']},
                         {'staff': 26, 'internal_receiver': 33})
        selectors = [call[call.index('class') + 1] for call in calls if 'class' in call]
        self.assertEqual(len(selectors), 2)
        self.assertNotIn('GatewayDurabilityTest', selectors[0])
        self.assertIn('app.cool.mobile.receiver_sms.GatewayDurabilityTest', selectors[1])
        self.assertEqual(len(report['cleanup']), 4)
        self.assertTrue(all(value['removed'] for value in report['cleanup']))
        self.assertEqual({item['flavor'] for item in report['ui_artifacts']}, {'staff', 'internal_receiver'})
        dumps = [i for i, call in enumerate(calls) if call[3:6] == ['shell', 'uiautomator', 'dump']]
        shots = [i for i, call in enumerate(calls) if call[3:] == ['exec-out', 'screencap', '-p']]
        self.assertEqual(len(dumps), 2)
        self.assertEqual(len(shots), 2)
        self.assertNotEqual(calls[dumps[0]][-1], calls[dumps[1]][-1])
        for dumped, shot in zip(dumps, shots):
            remote = calls[dumped][-1]
            self.assertEqual(calls[dumped + 1][3:], ['shell', 'cat', remote])
            self.assertEqual(calls[dumped + 2][3:], ['shell', 'rm', '-f', remote])
            self.assertEqual(calls[shot - 1][3:], ['shell', 'dumpsys', 'activity', 'activities'])
            self.assertLess(dumped, shot)

    def test_invalid_login_capture_refuses_visual_proof_and_cleans_sandboxes(self):
        code, report, calls = self.run_synthetic_instrumentation(invalid_login_capture=True)
        self.assertEqual(code, 2)
        self.assertIn('Invalid native Collect sign-in screenshot', report['error'])
        self.assertTrue(all(value['removed'] for value in report['cleanup']))
        self.assertNotIn('ui_artifacts', report)

    def test_foreign_startup_window_refuses_capture_and_cleans_sandboxes(self):
        code, report, calls = self.run_synthetic_instrumentation(foreign_startup=True)
        self.assertEqual(code, 2)
        self.assertIn('no content owned by the sandbox', report['error'])
        self.assertFalse(any(call[3:] == ['exec-out', 'screencap', '-p'] for call in calls))
        self.assertTrue(all(value['removed'] for value in report['cleanup']))

    def test_idle_failure_refuses_capture_and_cleans_sandboxes(self):
        code, report, calls = self.run_synthetic_instrumentation(startup_idle_error=True)
        self.assertEqual(code, 2)
        self.assertIn('did not reach accessibility idle', report['error'])
        self.assertFalse(any(call[3:] == ['exec-out', 'screencap', '-p'] for call in calls))
        self.assertTrue(all(value['removed'] for value in report['cleanup']))

    def test_foreground_is_checked_after_idle_and_before_capture(self):
        code, report, calls = self.run_synthetic_instrumentation(lose_foreground_after_idle=True)
        self.assertEqual(code, 2)
        self.assertIn('not foreground; screenshot refused', report['error'])
        self.assertTrue(any(call[3:6] == ['shell', 'uiautomator', 'dump'] for call in calls))
        self.assertFalse(any(call[3:] == ['exec-out', 'screencap', '-p'] for call in calls))
        self.assertTrue(all(value['removed'] for value in report['cleanup']))

    def test_missing_receiver_inventory_is_refused_before_install(self):
        code, report, calls = self.run_synthetic_instrumentation(omit_inventory_receiver=True)
        self.assertEqual(code, 2)
        self.assertFalse(report['installation_executed'])
        self.assertFalse(any('install' in call for call in calls))

    def test_legacy_shared_inventory_cannot_omit_receiver_tests(self):
        code, report, calls = self.run_synthetic_instrumentation(legacy_inventory=True)
        self.assertEqual(code, 2)
        self.assertFalse(report['installation_executed'])
        self.assertFalse(any('install' in call for call in calls))

    def test_missing_receiver_execution_fails_even_when_junit_reports_success(self):
        code, report, calls = self.run_synthetic_instrumentation(omit_receiver_method=True)
        self.assertEqual(code, 2)
        self.assertEqual(report['status'], 'FAIL')
        self.assertEqual(report['flavors'][0]['completed'], 26)
        self.assertEqual(report['flavors'][1]['completed'], 32)
        self.assertFalse(report['flavors'][1]['passed'])
        self.assertTrue(all(value['removed'] for value in report['cleanup']))


class DeviceSafety(unittest.TestCase):
    def test_named_device(self):n.selected_device('List of devices attached\nemulator-5554 device product:sdk\n','emulator-5554')
    def test_offline(self):
        with self.assertRaises(n.PipelineError):n.selected_device('emulator-5554 offline','emulator-5554')
    def test_unauthorized(self):
        with self.assertRaises(n.PipelineError):n.selected_device('ABC unauthorized','ABC')
    def test_absent(self):
        with self.assertRaises(n.PipelineError):n.selected_device('emulator-5554 device','emulator-5556')
    def test_serial_injection(self):
        with self.assertRaises(n.PipelineError):n.selected_device('bad device','bad;reboot')
    def test_only_sandbox_packages(self):
        for a in n.artifacts():
            if a.kind=='nativeTest':self.assertEqual(n.validated_sandbox_package(a.package),a.package)
            else:
                with self.assertRaises(n.PipelineError):n.validated_sandbox_package(a.package)
    def test_live_package_refused(self):
        for p in ('rw.ikanisa.burimunsi.staff','rw.ikanisa.burimunsi.gateway','com.other.app'):
            with self.assertRaises(n.PipelineError):n.validated_sandbox_package(p)
    def test_plan_does_not_install(self):
        args=argparse.Namespace(execute=False,serial='emulator-5554')
        with patch.object(n.subprocess,'run',side_effect=AssertionError('Unexpected device action')),patch('builtins.print'):
            self.assertEqual(n.instrument(args),0)
    def test_no_overwrite_or_grant_all_permissions(self):
        source=(SCRIPTS/'native_pipeline.py').read_text()
        self.assertIn("call(['install', '-t', str(path)]",source)
        self.assertIn("['shell', 'pm', 'list', 'packages', '-u', package]",source)
        self.assertNotIn("['shell', 'pm', 'clear'",source)
        self.assertNotIn("['install', '-r'",source)
    def test_jdk21_alone_is_not_a_build_ready_java(self):
        completed=argparse.Namespace(returncode=0,stderr='openjdk version "21.0.1"',stdout='')
        with patch.object(pre.subprocess,'run',return_value=completed):
            report=pre.inspect('/nonexistent-android-sdk')
        self.assertFalse(next(c for c in report['checks'] if c['name']=='java')['ok'])
    def test_jdk17_is_correct_java(self):
        completed=argparse.Namespace(returncode=0,stderr='openjdk version "17.0.1"',stdout='')
        with patch.object(pre.subprocess,'run',return_value=completed):
            report=pre.inspect('/nonexistent-android-sdk')
        self.assertTrue(next(c for c in report['checks'] if c['name']=='java')['ok'])
        self.assertFalse(report['ready_for_build'])
        self.assertIsNone(report['sdk_licences_accepted'])
    def test_build_stops_before_compilation_when_prerequisites_missing(self):
        with tempfile.TemporaryDirectory() as td:
            args=argparse.Namespace(output=pathlib.Path(td).resolve()/'run',sdk='/nonexistent',download_gradle=False)
            with patch.object(n,'preflight',return_value={'ready_for_build':False,'checks':[{'name':'java','ok':False}]}),patch.object(n,'command',side_effect=AssertionError('Build proceeded')),patch('builtins.print'):
                self.assertEqual(n.build(args),2)
            report=json.loads((args.output/'build-result.json').read_text())
            self.assertFalse(report['native_build_executed']);self.assertEqual(report['status'],'BLOCKED')


if __name__ == '__main__':unittest.main()
