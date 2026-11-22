"""Host-only fixture regressions for native execution infrastructure; never APK evidence."""
import argparse
import base64
import copy
import dataclasses
import importlib.util
import json
import pathlib
import re
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
import release_readiness as readiness
import datetime as dt
import hashlib


# Fixed rosters independently check discovery and the names reported by the runner.
EXPECTED_STAFF_CASES = {
    'rw.ikanisa.burimunsi.NativeSandboxContractTest#brokerLocalSetupDoesNotCreateSessionOrReplaceInstallation',
    'rw.ikanisa.burimunsi.NativeSandboxContractTest#compiledConfigurationContainsNoLiveEndpointOrBinding',
    'rw.ikanisa.burimunsi.NativeSandboxContractTest#concurrentSecureStoreInstancesShareOneAtomicFileSafely',
    'rw.ikanisa.burimunsi.NativeSandboxContractTest#gatewayCannotBindOrResumeInSandbox',
    'rw.ikanisa.burimunsi.NativeSandboxContractTest#installationUsesOnlyDedicatedSandboxIdentity',
    'rw.ikanisa.burimunsi.NativeSandboxContractTest#installedSandboxHasNoInternetBackupOrCleartext',
    'rw.ikanisa.burimunsi.NativeSandboxContractTest#launcherActivityBelongsToSandbox',
    'rw.ikanisa.burimunsi.NativeSandboxContractTest#localSetupIsEncryptedOutsideBackupAndClearPreservesOtherCustody',
    'rw.ikanisa.burimunsi.NativeSandboxContractTest#localSetupRejectsAnotherInstallationAndAllowsOnlyExplicitFileRecovery',
    'rw.ikanisa.burimunsi.NativeSandboxContractTest#memberPhotoCaptureUsesOnlyPrivateProviderAndSystemGrants',
    'rw.ikanisa.burimunsi.NativeSandboxContractTest#memberPhotoPreparationResizesRotatesAndWipesInput',
    'rw.ikanisa.burimunsi.NativeSandboxContractTest#savedSessionCanBeReopenedAndExplicitlyCleared',
    'rw.ikanisa.burimunsi.NativeSandboxContractTest#setupUsesTheExistingPersistedInstallationIdentity',
    'rw.ikanisa.burimunsi.NativeUiContractTest#allOriginalFifteenPanelTitlesRemainReachable',
    'rw.ikanisa.burimunsi.NativeUiContractTest#allSmsDoesNotClaimEmptyWhileTheLocalQueueIsUnknown',
    'rw.ikanisa.burimunsi.NativeUiContractTest#allSmsIncludesOwnQueuedRowsWithoutMergingUncertainSources',
    'rw.ikanisa.burimunsi.NativeUiContractTest#allocationActionStaysAboveNavigationAndHonorsAccessAndOfflineState',
    'rw.ikanisa.burimunsi.NativeUiContractTest#paymentReferenceAndProviderIdDisplayIndependently',
    'rw.ikanisa.burimunsi.NativeUiContractTest#auditedSmsPreviewsSearchBothTypedStreamsAndMarkPartial',
    'rw.ikanisa.burimunsi.NativeUiContractTest#automaticOutgoingTransactionShowsActualFieldsWithoutAllocating',
    'rw.ikanisa.burimunsi.NativeUiContractTest#backgroundPrivacyNeverExposesRawReceipt',
    'rw.ikanisa.burimunsi.NativeUiContractTest#bottomNavigationCoversEverySignedInRouteAndMapsDetailSelection',
    'rw.ikanisa.burimunsi.NativeUiContractTest#configurationBlockDoesNotPretendSignInIsRunning',
    'rw.ikanisa.burimunsi.NativeUiContractTest#discardPromptRemainsInTheCurrentSheetAndPreservesDraftUntilConfirmed',
    'rw.ikanisa.burimunsi.NativeUiContractTest#exportFormatsDispatchOnlyAfterAnExplicitContextualChoice',
    'rw.ikanisa.burimunsi.NativeUiContractTest#freshEntryIsOriginalPhoneAndFourDigitPasscode',
    'rw.ikanisa.burimunsi.NativeUiContractTest#gatewayObservationsCanSyncAndResumeButCannotPauseWithoutPairing',
    'rw.ikanisa.burimunsi.NativeUiContractTest#gatewayShowsOnlyThePairedReceivingCodeSnapshot',
    'rw.ikanisa.burimunsi.NativeUiContractTest#gatewayUsesSmsPermissionWithoutPairingCode',
    'rw.ikanisa.burimunsi.NativeUiContractTest#homeOmitsGatewayControlForAllRolesAndSettingsKeepsRecovery',
    'rw.ikanisa.burimunsi.NativeUiContractTest#initialLoadingSkeletonDoesNotClaimAnEmptyResult',
    'rw.ikanisa.burimunsi.NativeUiContractTest#invalidPhoneNeverEnablesSignIn',
    'rw.ikanisa.burimunsi.NativeUiContractTest#navigationUsesControllerReadPolicyAndAlwaysHonorsClosedAccessGate',
    'rw.ikanisa.burimunsi.NativeUiContractTest#observationStatusAndRetryReflectAdminProcessingAuthority',
    'rw.ikanisa.burimunsi.NativeUiContractTest#originalFiltersIncludeProcessingAndApplyOnlyTheSelectedStatus',
    'rw.ikanisa.burimunsi.NativeUiContractTest#originalFormPlaceholdersDescribeExpectedInputs',
    'rw.ikanisa.burimunsi.NativeUiContractTest#originalHeadersExposeFiltersProfileHistoryAndExport',
    'rw.ikanisa.burimunsi.NativeUiContractTest#overviewKeepsAuthoritativeUnallocatedAmountAndAllPaymentsAction',
    'rw.ikanisa.burimunsi.NativeUiContractTest#paginationFailureRequiresExplicitRetryInsteadOfAnAutomaticLoop',
    'rw.ikanisa.burimunsi.NativeUiContractTest#pairedReceiverCanRequestMissingSmsPermissionWithoutPausing',
    'rw.ikanisa.burimunsi.NativeUiContractTest#parsedSmsUsesExistingScreensWithoutManualVerification',
    'rw.ikanisa.burimunsi.NativeUiContractTest#passcodeConfirmationImeDoesNotChangeCredentialUntilSave',
    'rw.ikanisa.burimunsi.NativeUiContractTest#phoneNextAndPasscodeDoneSubmitOnce',
    'rw.ikanisa.burimunsi.NativeUiContractTest#privacyGateDisposesCredentialsAndRecordsWithinOriginalRoute',
    'rw.ikanisa.burimunsi.NativeUiContractTest#profileToPasscodeReplacesSheetAndCloseReturnsToRoute',
    'rw.ikanisa.burimunsi.NativeUiContractTest#queuedSmsMetadataShowsQueuedAndIsPermissionGated',
    'rw.ikanisa.burimunsi.NativeUiContractTest#rawReceiptOpensDirectlyAndLinksToItsContribution',
    'rw.ikanisa.burimunsi.NativeUiContractTest#reducedMotionKeepsLoadingMeaningWithStaticRendering',
    'rw.ikanisa.burimunsi.NativeUiContractTest#refreshAndExportFeedbackNeverReplaceValidRecordsWithFakeSuccess',
    'rw.ikanisa.burimunsi.NativeUiContractTest#searchIsLiveAndHasNoAddedSubmitControl',
    'rw.ikanisa.burimunsi.NativeUiContractTest#settingsSmsPermissionUsesTheAvailableAndroidAction',
    'rw.ikanisa.burimunsi.NativeUiContractTest#signInShowsAccessibleProgressAndRetainsThePhoneOnFailure',
    'rw.ikanisa.burimunsi.NativeUiContractTest#smartOnboardingHasKinyarwandaCopy',
    'rw.ikanisa.burimunsi.NativeUiContractTest#smartOnboardingUsesTheExistingAddMemberSheet',
    'rw.ikanisa.burimunsi.NativeUiContractTest#smsDownloadsStayMetadataOnlyAndRequireClearingBodySearch',
    'rw.ikanisa.burimunsi.NativeUiContractTest#staffViewsHaveNoInventedPreferencesOrAdminGatewayControls',
    'rw.ikanisa.burimunsi.NativeUiContractTest#startupShowsBlackBrandedSplashBeforeOriginalLogin',
    'rw.ikanisa.burimunsi.NativeUiContractTest#supportActionsUseOnlyAnAvailableRuntimeContact',
    'rw.ikanisa.burimunsi.NativeUiContractTest#syncPolicySettingsStayInTheReceiverAdminRole',
    'rw.ikanisa.burimunsi.NativeUiContractTest#twoHundredPercentTypePreservesCompleteMoneyAndAccessibleIdentity',
    'rw.ikanisa.burimunsi.NativeUiContractTest#typedFilterOverlayReturnsToItsPanelAndShowsActualSort',
    'rw.ikanisa.burimunsi.NativeUiContractTest#typedFiltersValidateAmountsAndPreserveInclusiveKigaliDates',
    'rw.ikanisa.burimunsi.NativeUiContractTest#unknownFinancialOutcomeNeverShowsAllocationAction',
    'rw.ikanisa.burimunsi.StaffPackageIsolationTest#installedPackageEnforcesRoleBoundary',
    'rw.ikanisa.burimunsi.export.ExportRenderingTest#nativePdfCancellationAndOutputFailureNeverCloseTheCallerOrReturnSuccess',
    'rw.ikanisa.burimunsi.export.ExportRenderingTest#nativePdfOpensAndRendersEveryPageWithoutLosingTheSuppliedRowCount',
    'rw.ikanisa.burimunsi.export.ExportRenderingTest#nativePdfPageBudgetFailsBeforeAnyFileBytesInsteadOfDroppingRows',
    'rw.ikanisa.burimunsi.export.ExportRenderingTest#nativeWorkbookContainsReadableXmlAndLiteralFormulaLookingText',
    'rw.ikanisa.burimunsi.export.ExportRenderingTest#zeroRecordPdfStillOpensAsOneCompletePage',
}
EXPECTED_RECEIVER_ONLY_CASES = {
    'app.cool.mobile.receiver_sms.GatewayDurabilityTest#' + method
    for method in (
        'retainedCiphertextReopensInAnotherStoreInstance',
        'duplicateIdentityCannotHideDifferentEvidence',
        'durableAcknowledgementAndTombstoneSurviveReopen',
        'capacityPreservesExistingEvidenceAndLiveReserve',
        'pauseAndOwnerChangeNeverDiscardPendingEvidence',
        'legacyControlTransitionReopensEncryptedAndHoldsObservation',
        'legacyMigrationCopiesBeforeDeletingOriginal',
        'corruptCiphertextBlocksOwnerResetAndPreservesBytes',
        'unresolvedObservationsStayEncryptedAndScopedAcrossReopen',
        'preReconciliationQueueKeepsOriginalIdentityUntilExactAcknowledgement',
        'code48HeldJournalPreservesUncertainCiphertextAndRedactsOnlyTerminalRecords',
        'corruptObservationCiphertextDoesNotResetTheQueue',
        'observationProfileAndConsentAreEncryptedAndAccountScoped',
        'observationPauseIsEncryptedAndSurvivesAnotherAccount',
        'pduCorrelationEvidenceIsEncryptedAndNeverPosts',
        'offlineSandboxCannotCaptureObservations',
        'offlineSandboxCannotScanSmsInbox',
        'continuousSupervisorRemainsOfflineInQualificationSandbox',
        'continuousExecutionLeaseSurvivesAnInterruptedCallerUntilItsActualExit',
        'continuousCycleBudgetAndFailureRetryRemainBounded',
    )
}
EXPECTED_CASE_COUNTS = {
    'staff': len(EXPECTED_STAFF_CASES),
    'internal_receiver': len(EXPECTED_STAFF_CASES | EXPECTED_RECEIVER_ONLY_CASES),
}


def manifest(spec, extra='', app_extra='', app_body='', root_extra=''):
    if spec.test:
        return f'<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="{spec.package}"><instrumentation android:name="{n.RUNNER}" android:targetPackage="{n.Artifact(spec.flavor, "nativeTest").package}"/></manifest>'
    debug = 'false' if spec.kind == 'qualification' else 'true'
    test_only = 'true' if spec.kind in ('nativeTest', 'qualification') else 'false'
    name = n.VERSION_NAME + {'debug': '', 'qualification': '-qualification', 'nativeTest': '-native-test'}[spec.kind]
    return f'''<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="{spec.package}" android:versionCode="{n.VERSION_CODE}" android:versionName="{name}" {root_extra}>
      <uses-sdk android:minSdkVersion="26" android:targetSdkVersion="36"/>{extra}
      <application android:usesCleartextTraffic="false" android:allowBackup="false" android:debuggable="{debug}" android:testOnly="{test_only}" {app_extra}>{app_body}</application></manifest>'''


def receiver_manifest(spec):
    permissions = ''.join(f'<uses-permission android:name="android.permission.{p}"/>' for p in (
        'READ_SMS','RECEIVE_SMS','FOREGROUND_SERVICE','FOREGROUND_SERVICE_SPECIAL_USE','POST_NOTIFICATIONS','WAKE_LOCK','REQUEST_IGNORE_BATTERY_OPTIMIZATIONS'))
    parts = [('CollectSmsReceiver', 'receiver', 'android.permission.BROADCAST_SMS', 'true'),
             ('MomoGatewayRecoveryReceiver', 'receiver', None, 'false'),
             ('MomoGatewayJobService', 'service', 'android.permission.BIND_JOB_SERVICE', 'true'),
             ('MomoGatewayLocalRecoveryService', 'service', 'android.permission.BIND_JOB_SERVICE', 'true'),
             ('ObservationSmsReceiver', 'receiver', 'android.permission.BROADCAST_SMS', 'true'),
             ('ObservationBootReceiver', 'receiver', None, 'false'),
             ('ObservationJobService', 'service', 'android.permission.BIND_JOB_SERVICE', 'true')]
    body = ''
    for name, tag, permission, exported in parts:
        guard = f'android:permission="{permission}"' if permission else ''
        body += f'<{tag} android:name="app.cool.mobile.receiver_sms.{name}" android:exported="{exported}" {guard}/>'
    body += '<service android:name="app.cool.mobile.receiver_sms.BuriContinuousSyncService" android:exported="false" android:stopWithTask="false" android:foregroundServiceType="specialUse"><property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE" android:value="Internal receiving-phone SMS monitoring with local inbox observation and bounded authenticated synchronization, controlled by the current authorized administrator and a visible ongoing notification."/></service>'
    return manifest(spec, permissions, app_body=body)


def stream(expected):
    text = ''
    for i, name in enumerate(sorted(expected), 1):
        cls, method = name.split('#')
        block = f'INSTRUMENTATION_STATUS: class={cls}\nINSTRUMENTATION_STATUS: test={method}\nINSTRUMENTATION_STATUS: current={i}\n'
        text += block + 'INSTRUMENTATION_STATUS_CODE: 1\n' + block + 'INSTRUMENTATION_STATUS_CODE: 0\n'
    return text + f'INSTRUMENTATION_RESULT: stream=\nTime: 0.1\nOK ({len(expected)} tests)\nINSTRUMENTATION_CODE: -1\n'


class ListingHeaderContract(unittest.TestCase):
    def test_restoration_counts_the_header_rows_before_the_first_rendered_record(self):
        screens = n.ROOT / 'app/src/main/kotlin/rw/ikanisa/burimunsi/ui'
        restoration = (n.ROOT / 'core/src/main/kotlin/rw/ikanisa/burimunsi/core/PagedRestoration.kt').read_text()
        for screen, route in [('PaymentsScreen', 'PAYMENTS'), ('MembersScreen', 'MEMBERS'),
                              ('MemberScreen', 'MEMBER'), ('SmsScreen', 'SMS')]:
            with self.subTest(route=route):
                owner = 'BuriSmsScreen.kt' if route == 'SMS' else 'BuriRecordsScreens.kt'
                source = (screens / owner).read_text()
                before_rows = source.split('fun ' + screen + '(', 1)[1].split('itemsIndexed(', 1)[0]
                fixed = len(re.findall(r'^\s*item\s*(?:\([^)]*\)\s*)?\{', before_rows, re.MULTILINE))
                self.assertRegex(restoration, rf'Route\.{route} -> {fixed}\b')
                if route == 'SMS':
                    self.assertRegex(before_rows, r'if\s*\(s\.showSmsSearchNotice\)\s*item\s*\{')
                    self.assertRegex(restoration, r'if\s*\(smsSearchNotice\)\s*1\s*else\s*0')
                if route == 'MEMBERS':
                    self.assertRegex(before_rows, r'state\s*=\s*routeList\s*\(')
                    components = (screens / 'BuriComponents.kt').read_text()
                    scroll = components.split('fun routeList(', 1)[1].split('@Composable', 1)[0]
                    self.assertRegex(scroll, r'remember\s*\(revision\)')
                    self.assertRegex(scroll, r'm\.memberListPosition\s*\(')

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
        self.assertEqual(n.expected_tests(), EXPECTED_STAFF_CASES)
        self.assertFalse(n.plan()['native_build_executed'])
    def test_plan_never_calls_subprocess(self):
        with patch.object(n.subprocess, 'run', side_effect=AssertionError('Plan executed a tool')):
            self.assertEqual(n.plan()['mode'], 'plan')
    def test_custom_build_type_has_manifest_dependency(self):
        s=(n.ROOT/'app/build.gradle.kts').read_text()
        self.assertIn('testBuildType = "nativeTest"', s)
        self.assertIn('add("nativeTestImplementation", "androidx.compose.ui:ui-test-manifest")', s)
        self.assertIn('androidTestImplementation("androidx.test:runner:1.7.0")', s)
    def test_qualification_and_native_test_share_the_offline_manifest(self):
        gradle = (n.ROOT/'app/build.gradle.kts').read_text()
        self.assertIn('offlineBuildTypes = listOf("qualification", "nativeTest")', gradle)
        self.assertIn('for (name in offlineBuildTypes) sourceSets.named(name)', gradle)
        self.assertIn('manifest.srcFile("src/offline/AndroidManifest.xml")', gradle)
        s=(n.ROOT/'app/src/offline/AndroidManifest.xml').read_text()
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
        a=n.Artifact('staff','nativeTest',True);self.assertTrue(n.inspect_xml(manifest(a).replace('android:targetPackage="rw.ikanisa.burimunsi.staff.cloud.nativeTest"','android:targetPackage="rw.ikanisa.burimunsi.staff"'),a))
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
    package = 'rw.ikanisa.burimunsi.staff.cloud.nativeTest'

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
        xml = f'<hierarchy><node package="com.android.systemui" text="9:21"/><node package="{self.package}" text="Phone number"/></hierarchy>'
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
        self.assertEqual(staff, EXPECTED_STAFF_CASES)
        self.assertTrue(staff < receiver)
        self.assertEqual(receiver - staff, EXPECTED_RECEIVER_ONLY_CASES)
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
                    return f'<hierarchy><node package="{package}" text="Phone number"/></hierarchy>'
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
                    self.assertIn(action[2], {'rw.ikanisa.burimunsi.staff.cloud.nativeTest', 'rw.ikanisa.burimunsi.gateway.cloud.nativeTest'})
                    self.assertEqual(action[3:], ['cat', 'cache/prototype-sign-in.png'])
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
                         EXPECTED_CASE_COUNTS)
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
        self.assertIn('Invalid native prototype sign-in screenshot', report['error'])
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
        self.assertEqual(report['flavors'][0]['completed'], EXPECTED_CASE_COUNTS['staff'])
        self.assertEqual(report['flavors'][1]['completed'], EXPECTED_CASE_COUNTS['internal_receiver'] - 1)
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
        for p in ('rw.ikanisa.burimunsi.staff','rw.ikanisa.burimunsi.gateway',
                  'rw.ikanisa.burimunsi.staff.cloud','rw.ikanisa.burimunsi.gateway.cloud','com.other.app'):
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
        runtime = argparse.Namespace(returncode=0, stderr='openjdk version "17.0.1"', stdout='')
        compiler = argparse.Namespace(returncode=0, stderr='', stdout='javac 17.0.1')
        with patch.object(pre.subprocess, 'run', side_effect=[runtime, compiler]):
            report = pre.inspect('/nonexistent-android-sdk')
        self.assertTrue(next(c for c in report['checks'] if c['name']=='java')['ok'])
        self.assertFalse(report['ready_for_build'])
        self.assertIsNone(report['sdk_licences_accepted'])
    def test_java17_runtime_without_compiler_is_not_a_jdk(self):
        runtime = argparse.Namespace(returncode=0, stderr='openjdk version "17.0.1"', stdout='')
        with patch.object(pre.shutil, 'which', side_effect=['/tools/java', None]), \
             patch.object(pre.os, 'environ', {}), \
             patch.object(pre.subprocess, 'run', return_value=runtime):
            report = pre.inspect('/nonexistent-android-sdk')
        self.assertFalse(next(c for c in report['checks'] if c['name'] == 'java')['ok'])

    def test_build_stops_before_compilation_when_prerequisites_missing(self):
        with tempfile.TemporaryDirectory() as td:
            args=argparse.Namespace(output=pathlib.Path(td).resolve()/'run',sdk='/nonexistent',download_gradle=False)
            with patch.object(n,'preflight',return_value={'ready_for_build':False,'checks':[{'name':'java','ok':False}]}),patch.object(n,'command',side_effect=AssertionError('Build proceeded')),patch('builtins.print'):
                self.assertEqual(n.build(args),2)
            report=json.loads((args.output/'build-result.json').read_text())
            self.assertFalse(report['native_build_executed']);self.assertEqual(report['status'],'BLOCKED')


class TestingCandidateReadiness(unittest.TestCase):
    """Synthetic host receipts only; not native build or signing evidence."""
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.base=pathlib.Path(self.tmp.name).resolve();self.overlay=self.base/'source'
        native=self.overlay/'native/burimunsi';native.mkdir(parents=True)
        (native/'source.txt').write_text('qualification source')
        upstream=self.overlay/'upstream/collect';upstream.mkdir(parents=True);(upstream/'receiver.kt').write_text('qualified receiver')
        self.root=native;self.evidence=self.base/'evidence';self.evidence.mkdir()
        for name,value in [('ROOT',native),('OVERLAY',self.overlay)]:
            p=patch.object(n,name,value);p.start();self.addCleanup(p.stop)
        self.contracts={'staff':['Fixture#staff'],'internal_receiver':['Fixture#receiver']}
        p=patch.object(n,'test_contracts',return_value=self.contracts);p.start();self.addCleanup(p.stop)
        self.now=dt.datetime(2026,11,10,tzinfo=dt.timezone.utc);timestamp=self.now.isoformat()
        cloud='https://rrlduytparvsjfmegalh.supabase.co'
        self.profile={'format':'collect.deployment.v1','id':'candidate-fixture','mode':'managed','environment':'qualification',
          'supabase_origin':cloud,'admin_origin':cloud,
          'member_api_origin':cloud,'public_origin':'https://collect.example','google_callback_origin':cloud}
        self.properties={'collectSupabaseOrigin':self.profile['supabase_origin'],'collectAdminOrigin':self.profile['admin_origin'],
          'burimunsiApiOrigin':self.profile['supabase_origin'],'burimunsiApiPathPrefix':'/functions/v1/collect-api',
          'collectGatewayOrigin':self.profile['supabase_origin']+'/functions/v1/collect-api',
          'collectPublishableKey':'sb_publishable_fixture_opaque_public_value'}
        current=n.source_fingerprint();rows=[];inspections=[];cleanup=[]
        for spec in n.artifacts():
            ref=self.put('build/apks/'+spec.filename,b'SYNTHETIC HOST APK BYTES '+spec.filename.encode())
            row={'spec':dataclasses.asdict(spec),'package':spec.package,'bytes':(self.evidence/ref['path']).stat().st_size,
              'sha256':ref['sha256'],'path':'apks/'+spec.filename,'ok':True,'failures':[],
              'certificate_sha256':None if spec.kind=='qualification' else 'a'*64,'signature_verified':spec.kind!='qualification',
              'optimized_unsigned_qualification':spec.kind=='qualification'}
            rows.append(row)
            if spec.kind=='nativeTest':
                inspections.append(self.put('device/inspection-'+spec.filename+'.json',row));cleanup.append({'package':spec.package,'removed':True})
        flavors=[];logs={}
        for flavor,expected in self.contracts.items():
            raw=stream(set(expected));logs[flavor]=self.put('device/'+flavor+'.txt',raw.encode())
            flavors.append({'flavor':flavor,**n.parse_instrumentation(raw,set(expected))})
        self.manifest={'format':'collect.burimunsi.testing-candidate.v1','purpose':'testing-candidate-build','created_at':timestamp,
          'source_sha256':current['sha256'],'profile_sha256':readiness._configuration(self.profile,self.properties),
          'properties':copy.deepcopy(self.properties),'qualification':{
            'build_result':self.put('build/build-result.json',{'status':'PASS','native_build_executed':True,'apk_inspection_passed':True,
                'artifact_count':8,'production_deployment':False,'finished_at':timestamp}),
            'source_fingerprint':self.put('build/source-fingerprint.json',current),
            'artifacts':self.put('build/artifacts.json',{'source_sha256':current['sha256'],'artifacts':rows,'expected_tests_per_flavor':self.contracts}),
            'instrumentation_result':self.put('device/result.json',{'status':'PASS','installation_executed':True,'instrumentation_executed':True,
                'device_api':36,'production_deployment':False,'finished_at':timestamp,'flavors':flavors,'cleanup':cleanup}),
            'device_inspections':inspections,'instrumentation_logs':logs}}
        self.profile_path=self.evidence/'profile.json';self.profile_path.write_text(json.dumps(self.profile))
        self.manifest_path=self.evidence/'candidate.json'
    def put(self,name,value):
        path=self.evidence/name;path.parent.mkdir(parents=True,exist_ok=True)
        raw=value if isinstance(value,bytes) else json.dumps(value).encode();path.write_bytes(raw)
        return {'path':name,'sha256':hashlib.sha256(raw).hexdigest()}
    def run_gate(self):
        self.manifest_path.write_text(json.dumps(self.manifest))
        return readiness.evaluate_candidate(self.manifest_path,self.profile_path,self.properties,pipeline=n,now=self.now)
    def test_current_candidate_requires_neither_signed_release_nor_carrier_pilot_and_never_promotes(self):
        result=self.run_gate();self.assertTrue(result['ready'],result)
        for key in ['production_authorized','signing_authorized','distribution_authorized']:self.assertFalse(result[key])
        self.assertFalse(readiness.evaluate(self.manifest,{},self.evidence,'promotion')['ready'])
    def test_current_source_change_invalidates_previous_qualification(self):
        (self.root/'source.txt').write_text('changed source')
        self.assertIn('CANDIDATE_SOURCE_CHANGED',self.run_gate()['errors'])
    def test_stale_manifest_cannot_admit_a_new_build(self):
        self.manifest['created_at']=(self.now-dt.timedelta(days=2)).isoformat()
        self.assertIn('CANDIDATE_EVIDENCE_STALE',self.run_gate()['errors'])
    def test_fresh_manifest_does_not_refresh_stale_native_build_evidence(self):
        ref=self.manifest['qualification']['build_result'];doc=json.loads((self.evidence/ref['path']).read_text())
        doc['finished_at']=(self.now-dt.timedelta(days=2)).isoformat()
        self.manifest['qualification']['build_result']=self.put(ref['path'],doc)
        self.assertIn('CANDIDATE_EVIDENCE_STALE',self.run_gate()['errors'])
    def test_tampered_apk_bytes_fail_even_with_pass_receipts(self):
        (self.evidence/'build/apks/staff-nativeTest.apk').write_bytes(b'changed')
        self.assertIn('CANDIDATE_ARTIFACT_CHANGED',self.run_gate()['errors'])
    def test_missing_evidence_fails_closed(self):
        (self.evidence/'build/build-result.json').unlink();self.assertFalse(self.run_gate()['ready'])
    def test_wrong_gradle_selected_origin_is_not_retarged_by_manifest(self):
        self.properties['collectAdminOrigin']='https://different.collect.example'
        self.assertIn('CANDIDATE_PUBLIC_PROPERTIES_MISMATCH',self.run_gate()['errors'])
    def test_profile_mismatch_cannot_point_to_a_second_backend(self):
        self.profile['supabase_origin']='https://different.collect.example';self.profile_path.write_text(json.dumps(self.profile))
        self.assertIn('CANDIDATE_PROFILE_MISMATCH',self.run_gate()['errors'])
    def test_non_cloud_profile_cannot_qualify_a_configured_candidate(self):
        self.profile['mode']='self_hosted';self.profile_path.write_text(json.dumps(self.profile))
        self.assertIn('CANDIDATE_PROFILE_WRONG',self.run_gate()['errors'])
    def test_every_public_origin_is_canonical_https_without_private_url_fields(self):
        for origin in ['http://collect.example','https://user:password@collect.example','https://a..example','https://collect.example/path','https://127.0.0.1']:
            with self.subTest(kind=origin.split(':')[0]):
                self.profile['public_origin']=origin;self.profile_path.write_text(json.dumps(self.profile))
                result=self.run_gate();self.assertIn('CANDIDATE_ORIGIN_WRONG',result['errors']);self.assertNotIn(origin,json.dumps(result))
    def test_secret_jwt_and_jwk_cannot_be_public_compiler_inputs(self):
        token_parts = [
            json.dumps({'alg': 'none', 'typ': 'JWT'}).encode(),
            json.dumps({'sub': 'synthetic-test-only'}).encode(),
        ]
        unsigned_fixture = '.'.join(
            base64.urlsafe_b64encode(part).decode().rstrip('=') for part in token_parts
        ) + '.fixture'
        for value in ['sb_secret_private_fixture',unsigned_fixture,'{"kty":"RSA","d":"private"}']:
            with self.subTest(kind=value.split('_')[0]):
                self.properties['collectPublishableKey']=value;self.manifest['properties']=copy.deepcopy(self.properties)
                result=self.run_gate();self.assertIn('CANDIDATE_PUBLIC_KEY_WRONG',result['errors']);self.assertNotIn(value,json.dumps(result))
    def test_business_group_is_not_a_public_build_property(self):
        self.properties['collectionId']='business-group';self.manifest['properties']=copy.deepcopy(self.properties)
        self.assertIn('CANDIDATE_FIELDS_WRONG',self.run_gate()['errors'])
    def test_candidate_cannot_claim_promotion_purpose(self):
        self.manifest['purpose']='production-promotion';self.assertIn('CANDIDATE_PURPOSE_WRONG',self.run_gate()['errors'])
    def test_device_inspection_must_match_actual_retained_apk_identity(self):
        ref=self.manifest['qualification']['device_inspections'][0];doc=json.loads((self.evidence/ref['path']).read_text());doc['sha256']='b'*64
        self.manifest['qualification']['device_inspections'][0]=self.put(ref['path'],doc)
        self.assertIn('CANDIDATE_DEVICE_INSPECTIONS_WRONG',self.run_gate()['errors'])
    def test_raw_instrumentation_is_reparsed_instead_of_trusting_pass_flag(self):
        self.manifest['qualification']['instrumentation_logs']['staff']=self.put('device/staff.txt',b'INSTRUMENTATION_CODE: 0\n')
        self.assertFalse(self.run_gate()['ready'])
    def test_changed_current_test_inventory_invalidates_prior_test_counts(self):
        self.contracts['staff'].append('Fixture#new');self.assertFalse(self.run_gate()['ready'])
    def test_linked_receipts_are_refused(self):
        original=self.evidence/'build/build-result.json';copy_path=self.evidence/'saved.json';original.rename(copy_path);original.symlink_to(copy_path)
        self.assertIn('CANDIDATE_LINK_REFUSED',self.run_gate()['errors'])
    def test_duplicate_body_fields_are_refused_without_echoing_values(self):
        self.manifest_path.write_text('{"purpose":"first","purpose":"second"}')
        result=readiness.evaluate_candidate(self.manifest_path,self.profile_path,self.properties,pipeline=n,now=self.now)
        self.assertIn('CANDIDATE_DUPLICATE_FIELD',result['errors'])
    def test_legacy_build_still_requires_historical_tasks_and_evidence(self):
        result=readiness.evaluate({'tasks':[]},{},self.evidence,'build')
        self.assertFalse(result['ready']);self.assertTrue(any('65-task' in e for e in result['errors']))

if __name__ == '__main__':unittest.main()
