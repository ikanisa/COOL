import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/process_runner.dart';
import 'helpers/android_manifest_permissions.dart';
import 'helpers/repository_source_files.dart';

String repositoryCustodyRoot() {
  final root = Directory(
    Platform.environment['COLLECT_REPOSITORY_CUSTODY_ROOT'] ??
        Directory.current.path,
  ).resolveSymbolicLinksSync();
  final observed = Process.runSync('git', [
    'rev-parse',
    '--show-toplevel',
  ], workingDirectory: root);
  expect(
    observed.exitCode,
    0,
    reason: 'Repository custody must be a Git checkout.',
  );
  expect(
    Directory((observed.stdout as String).trim()).resolveSymbolicLinksSync(),
    root,
    reason: 'Repository custody must identify the checkout root.',
  );
  return root;
}

String readCollectRepositoryLibrary() {
  return [
    'lib/shared/repositories/collect_repository.dart',
    'lib/shared/repositories/collect_repository_contribution_actions.dart',
    'lib/shared/repositories/collect_repository_notification_actions.dart',
    'lib/shared/repositories/collect_repository_group_actions.dart',
    'lib/shared/repositories/collect_repository_providers.dart',
    'lib/shared/repositories/collect_repository_state.dart',
    'lib/shared/repositories/collect_repository_live_reader.dart',
  ].map((path) => File(path).readAsStringSync()).join('\n');
}

void main() {
  test('strict dotenv loader treats configuration as guarded data', () {
    final tempDir = Directory.systemTemp.createTempSync('collect_dotenv_');
    try {
      final valid = File('${tempDir.path}/valid.env')
        ..writeAsStringSync("SAFE_VALUE='literal value with spaces'\n");
      Process.runSync('chmod', ['600', valid.path]);
      final validResult = runProcessSync('/bin/bash', [
        '-c',
        '. scripts/load_dotenv_strict.sh; collect_load_dotenv_strict "\$1"; printf "%s" "\$SAFE_VALUE"',
        'dotenv-test',
        valid.path,
      ]);
      expect(validResult.exitCode, 0, reason: validResult.stderr.toString());
      expect(validResult.stdout, 'literal value with spaces');

      final marker = File('${tempDir.path}/must-not-exist');
      final malicious = File('${tempDir.path}/malicious.env')
        ..writeAsStringSync('BAD=\$(touch ${marker.path})\n');
      Process.runSync('chmod', ['600', malicious.path]);
      final maliciousResult = runProcessSync('/bin/bash', [
        '-c',
        '. scripts/load_dotenv_strict.sh; collect_load_dotenv_strict "\$1"',
        'dotenv-test',
        malicious.path,
      ]);
      expect(maliciousResult.exitCode, isNonZero);
      expect(
        maliciousResult.stderr,
        contains('shell expansion syntax rejected'),
      );
      expect(marker.existsSync(), isFalse);

      final permissive = File('${tempDir.path}/permissive.env')
        ..writeAsStringSync('SAFE_VALUE=visible\n');
      Process.runSync('chmod', ['644', permissive.path]);
      final permissiveResult = runProcessSync('/bin/bash', [
        '-c',
        '. scripts/load_dotenv_strict.sh; collect_load_dotenv_strict "\$1"',
        'dotenv-test',
        permissive.path,
      ]);
      expect(permissiveResult.exitCode, isNonZero);
      expect(permissiveResult.stderr, contains('mode'));
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('local and CI Flutter toolchains use the governed stable engine', () {
    const expectedVersion = '3.44.4';
    final fvmConfig =
        jsonDecode(File('.fvmrc').readAsStringSync()) as Map<String, dynamic>;
    final environment = File('docs/ENVIRONMENT.md').readAsStringSync();
    final makefile = File('Makefile').readAsStringSync();
    final governedScripts = <String>[
      'scripts/admin_pwa_authenticated_render_smoke.sh',
      'scripts/admin_pwa_release_build.sh',
      'scripts/android_device_uat.sh',
      'scripts/mobile_native_performance_profile.sh',
      'scripts/mobile_route_render_smoke.sh',
      'scripts/repo_wide_qa_uat.sh',
    ];

    expect(fvmConfig['flutter'], expectedVersion);
    expect(environment, contains('Flutter `$expectedVersion`'));
    expect(environment, contains('Dart `3.12.2`'));
    final ci = File('.github/workflows/ci.yml').readAsStringSync();
    expect(ci, contains('with open(".fvmrc", "r", encoding="utf-8")'));
    expect(
      ci,
      contains(
        r'flutter-version: ${{ steps.flutter-version.outputs.version }}',
      ),
    );
    final platformPackage =
        jsonDecode(File('deploy/platform-api/package.json').readAsStringSync())
            as Map<String, dynamic>;
    expect((platformPackage['engines'] as Map)['node'], '>=22');
    final ciNodeVersions = RegExp(
      r"node-version:\s*'(\d+)\.[^']+'",
    ).allMatches(ci).toList();
    expect(ciNodeVersions, isNotEmpty);
    expect(
      ciNodeVersions.every((match) => int.parse(match[1]!) >= 22),
      isTrue,
      reason: 'CI Node versions must satisfy the canonical API engine floor.',
    );
    expect(environment, contains('qualified installation'));
    expect(makefile, contains('FLUTTER ?= flutter'));
    expect(makefile, contains('DART ?= dart'));
    final sdkGuard = File(
      'scripts/qa/run_integrated_candidate_checks.sh',
    ).readAsStringSync();
    expect(sdkGuard, contains('Flutter does not match the checked-in SDK pin'));
    expect(
      sdkGuard,
      contains('Dart executable does not match Flutter bundled Dart'),
    );
    for (final path in governedScripts) {
      final script = File(path).readAsStringSync();
      if (path == 'scripts/repo_wide_qa_uat.sh') {
        expect(
          script,
          contains('scripts/qa/release_evidence.py'),
          reason: path,
        );
        final releaseRunner = File(
          'scripts/qa/release_evidence.py',
        ).readAsStringSync();
        expect(
          releaseRunner,
          contains("('flutter_verify', ['make', 'verify'])"),
        );
        expect(makefile, contains('verify: format-check analyze test'));
      } else {
        expect(script, contains(r'FLUTTER="${FLUTTER:-'), reason: path);
        expect(script, contains(r'"$FLUTTER"'), reason: path);
      }
      expect(
        script,
        isNot(contains('/Volumes/PRO-G40/flutter_3_44/bin/flutter')),
        reason: path,
      );
    }
  });

  test('production Android scopes MoMo SMS and USSD permissions', () {
    final mainManifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final productionManifest = File(
      'android/app/src/production/AndroidManifest.xml',
    ).readAsStringSync();
    final internalReceiverManifest = File(
      'android/app/src/internal_receiver/AndroidManifest.xml',
    ).readAsStringSync();
    final receiver = File(
      'android/app/src/main/kotlin/app/cool/mobile/receiver_sms/CollectSmsReceiver.kt',
    ).readAsStringSync();
    final playGate = File(
      'scripts/google_play_optimization_gate.sh',
    ).readAsStringSync();
    final playUpload = File(
      'scripts/google_play_production_upload.sh',
    ).readAsStringSync();
    final playPacket =
        jsonDecode(
              File(
                'docs/release/GOOGLE_PLAY_CONSOLE_AUDIT_PACKET.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;

    final mainPermissions = requestedAndroidPermissions(mainManifest);
    final productionPermissions = requestedAndroidPermissions(
      productionManifest,
    );
    final receiverPermissions = requestedAndroidPermissions(
      internalReceiverManifest,
    );
    const forbiddenProduction = {
      'android.permission.READ_SMS',
      'android.permission.SEND_SMS',
      'android.permission.BROADCAST_SMS',
      'android.permission.READ_CALL_LOG',
      'android.permission.WRITE_CALL_LOG',
      'android.permission.READ_EXTERNAL_STORAGE',
      'android.permission.WRITE_EXTERNAL_STORAGE',
    };
    expect(mainPermissions.intersection(forbiddenProduction), isEmpty);
    expect(productionPermissions.intersection(forbiddenProduction), isEmpty);
    expect(mainPermissions, contains('android.permission.RECEIVE_SMS'));
    expect(mainPermissions, contains('android.permission.CALL_PHONE'));
    expect(
      removedAndroidPermissions(mainManifest),
      containsAll({
        'android.permission.READ_EXTERNAL_STORAGE',
        'android.permission.WRITE_EXTERNAL_STORAGE',
      }),
    );
    expect(
      removedAndroidPermissions(productionManifest),
      contains('android.permission.READ_SMS'),
    );
    // Only the optional dedicated receiver can recover its retained inbox.
    // Main and ordinary production permissions remain constrained above.
    expect(receiverPermissions, {
      'android.permission.RECEIVE_SMS',
      'android.permission.READ_SMS',
      'android.permission.RECEIVE_BOOT_COMPLETED',
      'android.permission.ACCESS_NETWORK_STATE',
    });
    expect(
      removedAndroidPermissions(internalReceiverManifest),
      containsAll({
        'android.permission.CALL_PHONE',
        'android.permission.CAMERA',
        'android.permission.POST_NOTIFICATIONS',
      }),
    );
    expect(
      internalReceiverManifest,
      contains('android:name="android.hardware.telephony"'),
    );
    expect(internalReceiverManifest, contains('android:required="false"'));
    expect(internalReceiverManifest, contains('android:exported="true"'));
    expect(
      internalReceiverManifest,
      contains('android:permission="android.permission.BROADCAST_SMS"'),
    );
    expect(receiver, contains('Secure SMS queue unavailable'));
    expect(receiver, contains('isLikelyMomoReceipt'));
    expect(receiver, contains('CURRENCY_HINT'));
    expect(playGate, contains('production_permissions'));
    expect(
      playGate,
      contains('expected_apk_restricted = ["android.permission.RECEIVE_SMS"]'),
    );
    expect(playUpload, contains('google_play_sms_permission_scope_mismatch'));
    expect(playUpload, contains('google_play_sms_declaration_invalid_for_phase'));
    expect(
      ((playPacket['app_content'] as Map<String, dynamic>)['permissions']
          as Map<String, dynamic>)['sms_permissions_declaration_status'],
      'required_pending_play_approval',
    );
  });

  test(
    'native notification runtime is wired for local, APNs, and FCM delivery',
    () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final service = File(
        'lib/core/notifications/collect_notification_service.dart',
      ).readAsStringSync();
      final nativePermissionSheets = File(
        'lib/features/status/native_permission_sheets.dart',
      ).readAsStringSync();
      final androidGradle = File(
        'android/app/build.gradle.kts',
      ).readAsStringSync();
      final repository = readCollectRepositoryLibrary();
      final entitlements = File(
        'ios/Runner/Runner.entitlements',
      ).readAsStringSync();
      final appDelegate = File(
        'ios/Runner/AppDelegate.swift',
      ).readAsStringSync();

      expect(pubspec, contains('flutter_local_notifications:'));
      expect(pubspec, contains('firebase_messaging:'));
      expect(service, contains('FlutterLocalNotificationsPlugin'));
      expect(service, contains('requestNotificationsPermission'));
      expect(service, contains('IOSFlutterLocalNotificationsPlugin'));
      expect(service, contains('registerDevice'));
      expect(service, contains('showNotification'));
      expect(nativePermissionSheets, contains('showNotificationSettingsSheet'));
      expect(nativePermissionSheets, contains('requestNativeNotifications'));
      expect(
        nativePermissionSheets,
        contains('collectNotificationServiceProvider'),
      );
      expect(
        nativePermissionSheets,
        contains('service.enableDevice(repository)'),
      );
      expect(
        nativePermissionSheets,
        isNot(contains('Collect notifications enabled')),
      );
      expect(service, contains('isNotificationDeviceRegistered'));
      expect(service, contains('CollectNotificationStatus.ready'));
      expect(androidGradle, contains('isCoreLibraryDesugaringEnabled = true'));
      expect(androidGradle, contains('desugar_jdk_libs:2.1.4'));
      expect(repository, contains('register_notification_device'));
      expect(service, contains('requestRemoteRegistration'));
      expect(service, contains("provider: 'fcm'"));
      expect(service, contains('FirebaseMessaging.onMessage'));
      expect(service, contains('getInitialMessage'));
      expect(service, contains('collect_security'));
      expect(service, contains('notificationTapPayloads'));
      expect(service, contains('normalizeNotificationDeepLink'));
      expect(repository, contains('unregister_notification_device'));
      expect(entitlements, contains('aps-environment'));
      expect(appDelegate, contains('registerForRemoteNotifications'));
      expect(
        appDelegate,
        contains('didRegisterForRemoteNotificationsWithDeviceToken'),
      );
      expect(appDelegate, contains('notificationTap'));
    },
  );

  test('iOS permission declarations match implemented features only', () {
    final podfile = File('ios/Podfile').readAsStringSync();
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
    final privacyManifest = File(
      'ios/Runner/PrivacyInfo.xcprivacy',
    ).readAsStringSync();
    final xcodeProject = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final entitlements = File(
      'ios/Runner/Runner.entitlements',
    ).readAsStringSync();

    expect(infoPlist, contains('NSCameraUsageDescription'));
    expect(infoPlist, contains('NSPhotoLibraryUsageDescription'));
    expect(infoPlist, isNot(contains('NSContactsUsageDescription')));
    expect(infoPlist, isNot(contains('NSPhotoLibraryAddUsageDescription')));
    expect(infoPlist, contains('CFBundleAllowMixedLocalizations'));
    expect(infoPlist, contains('FlutterSceneDelegate'));
    expect(podfile, contains('PERMISSION_CAMERA=1'));
    expect(podfile, contains('PERMISSION_CONTACTS=0'));
    expect(podfile, contains('PERMISSION_NOTIFICATIONS=0'));
    expect(podfile, contains('PERMISSION_PHOTOS_ADD_ONLY=0'));
    expect(entitlements, contains('applinks:collect.ikanisa.com'));
    expect(entitlements, isNot(contains('com.apple.developer.nfc')));
    expect(entitlements, contains('aps-environment'));
    expect(infoPlist, contains('remote-notification'));
    expect(xcodeProject, contains('com.apple.Push'));
    expect(privacyManifest, contains('<key>NSPrivacyTracking</key>'));
    expect(privacyManifest, contains('<false/>'));
    for (final dataType in <String>[
      'NSPrivacyCollectedDataTypePhoneNumber',
      'NSPrivacyCollectedDataTypeUserID',
      'NSPrivacyCollectedDataTypeDeviceID',
      'NSPrivacyCollectedDataTypePaymentInfo',
      'NSPrivacyCollectedDataTypeOtherFinancialInfo',
      'NSPrivacyCollectedDataTypePhotosorVideos',
      'NSPrivacyCollectedDataTypeCustomerSupport',
      'NSPrivacyCollectedDataTypeOtherUserContent',
    ]) {
      expect(privacyManifest, contains(dataType), reason: dataType);
    }
    expect(xcodeProject, contains('PrivacyInfo.xcprivacy in Resources'));
  });

  test(
    'iOS App Store build preserves production data and review isolation',
    () {
      final fastfile = File('fastlane/Fastfile').readAsStringSync();
      final workflow = File(
        '.github/workflows/ios-app-store.yml',
      ).readAsStringSync();
      final main = File('lib/main.dart').readAsStringSync();
      final repository = readCollectRepositoryLibrary();

      expect(fastfile, contains('scripts/qa/native_build_config.py'));
      expect(fastfile, contains('collect_native_public_defines'));
      expect(
        fastfile,
        contains(
          './scripts/google_play_production_upload.sh --submit --phase ',
        ),
      );
      expect(
        File('scripts/qa/native_build_config.py').readAsStringSync(),
        contains('"APP_ENVIRONMENT": "production"'),
      );
      expect(workflow, contains('iOS 26 SDK or later is required'));
      expect(
        workflow,
        contains('SUPABASE_URL: https://rrlduytparvsjfmegalh.supabase.co'),
      );
      expect(fastfile, isNot(contains('APP_REVIEW_AUTH_PHONE')));
      expect(fastfile, isNot(contains('APP_REVIEW_AUTH_OTP')));
      expect(main, isNot(contains('CollectRepository.appReviewDemo')));
      expect(repository, isNot(contains('signInForAppReview')));
    },
  );

  test('Android Play build uses ephemeral public configuration only', () {
    final script = File(
      'scripts/android_play_store_build.sh',
    ).readAsStringSync();

    expect(script, contains('mktemp'));
    expect(script, contains('umask 077'));
    expect(script, contains('build apk'));
    expect(script, contains('build appbundle'));
    expect(script, contains('--flavor production'));
    expect(script, contains('--dart-define-from-file'));
    expect(script, contains('scripts/qa/native_build_config.py'));
    expect(script, contains('PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER'));
    expect(script, contains('scripts/qa/native_build_config.py'));
    final config = File('scripts/qa/native_build_config.py').readAsStringSync();
    expect(config, contains('"COLLECT_MOBILE_EVIDENCE_MODE": "false"'));
    expect(config, contains('"COLLECT_BACKEND": "supabase"'));
    expect(script, contains('--no-build-cache'));
    expect(script, contains('org.gradle.caching=false'));
    expect(script, contains('COOL_SIGN_PRODUCTION_DEBUG_WITH_PLAY_KEY=false'));
    expect(script, contains(':app:clean'));
    expect(script, isNot(contains(r'"$ROOT_DIR/android" clean')));
    expect(script, contains('verify_public_runtime_config'));
    expect(script, contains('lib/arm64-v8a/libapp.so'));
    expect(script, contains('base/lib/arm64-v8a/libapp.so'));
    expect(script, contains('accepts no extra Flutter arguments'));
    expect(script, isNot(contains(r'"$@"')));
    expect(script, isNot(contains('APP_REVIEW_OTP')));
    expect(script, isNot(contains('APP_REVIEW_PHONE')));
    expect(script, isNot(contains('AUTH_LOCAL_BYPASS')));
  });

  test('iOS App Store build cannot enable fixture evidence mode', () {
    final script = File('scripts/ios_app_store_build.sh').readAsStringSync();

    final config = File('scripts/qa/native_build_config.py').readAsStringSync();
    expect(config, contains('"COLLECT_MOBILE_EVIDENCE_MODE": "false"'));
    expect(config, contains('"COLLECT_BACKEND": "supabase"'));
    expect(
      script,
      contains('Payload/Collect.app/Frameworks/App.framework/App'),
    );
    expect(script, contains('SUPABASE_API_URL'));
    expect(script, contains('scripts/qa/native_build_config.py'));
    expect(script, contains('accepts no extra Flutter arguments'));
    expect(script, isNot(contains(r'"$@"')));
  });

  test('external GitHub Actions are pinned to immutable commits', () {
    final workflows = Directory('.github/workflows')
        .listSync()
        .whereType<File>()
        .where(
          (file) =>
              (file.path.endsWith('.yml') || file.path.endsWith('.yaml')) &&
              !isVerifiedAppleDoubleMetadata(file),
        );
    final externalUse = RegExp(r'uses:\s+([^\s@]+)@([^\s#]+)');
    final fullCommit = RegExp(r'^[0-9a-f]{40}$');

    for (final workflow in workflows) {
      final source = workflow.readAsStringSync();
      for (final match in externalUse.allMatches(source)) {
        final action = match.group(1)!;
        if (action.startsWith('./')) continue;
        expect(
          match.group(2),
          matches(fullCommit),
          reason: '$action in ${workflow.path} must use a full commit SHA.',
        );
      }
    }
  });

  test('repository text files do not store obvious live secrets', () {
    final blockedPatterns = <RegExp>[
      RegExp(r'sk-proj-[A-Za-z0-9_-]{20,}'),
      RegExp(r'sbp_[A-Za-z0-9]{20,}'),
      RegExp(r'eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+'),
      RegExp(r'postgresql://[A-Za-z0-9_.%+-]+:[A-Za-z0-9_:%+\-.~!$&()*+,;=]+@'),
      RegExp(r'EAAG[A-Za-z0-9]{20,}'),
    ];
    final skippedRoots = {
      '.cache',
      '.dart_tool',
      '.git',
      'build',
      'coverage',
      'output',
      'ios/Pods',
      'vendor/bundle',
      'release-evidence',
      'evidence-packs',
    };
    final root = repositoryCustodyRoot();
    final inventory = Process.runSync('git', [
      'ls-files',
      '-z',
      '--cached',
      '--others',
      '--exclude-standard',
    ], workingDirectory: root);
    expect(inventory.exitCode, 0, reason: inventory.stderr as String);
    final files = (inventory.stdout as String)
        .split('\u0000')
        .where((path) => path.isNotEmpty)
        .where((path) {
          if (skippedRoots.any(
            (root) => path == root || path.startsWith('$root/'),
          )) {
            return false;
          }
          if (path == 'test/security_hygiene_test.dart') {
            return false;
          }
          return path.endsWith('.dart') ||
              path.endsWith('.md') ||
              path.endsWith('.toml') ||
              path.endsWith('.yaml') ||
              path.endsWith('.yml') ||
              path.endsWith('.json') ||
              path.endsWith('.example') ||
              path.endsWith('.properties');
        })
        .map((path) => File('$root/$path'))
        .where(
          (file) => file.existsSync() && !isVerifiedAppleDoubleMetadata(file),
        );

    for (final file in files) {
      final text = file.readAsStringSync();
      for (final pattern in blockedPatterns) {
        // Public upstream JWT test bytes remain inert fixture evidence even
        // when captured in a dated source packet. Only these exact public
        // files bypass the JWT rule; every other secret rule still applies.
        if (pattern.pattern.startsWith('eyJ') &&
            const {
              '4bdb86ee4499ba6332ba690ddfd9eb7990fdb0c2869c97af7f4563533319f6ee',
              '4172db82411fb90360f50af4a6e19abe0302d61530cf777043f0626ef58da6cb',
            }.contains(sha256.convert(file.readAsBytesSync()).toString())) {
          continue;
        }
        expect(pattern.hasMatch(text), isFalse, reason: file.path);
      }
    }
  });

  test('Play Integrity group attestation is present without credentials', () {
    final mainActivity = File(
      'android/app/src/main/kotlin/app/cool/mobile/MainActivity.kt',
    ).readAsStringSync();
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    expect(mainActivity, contains('collect/play_integrity'));
    expect(gradle, contains('com.google.android.play:integrity'));
    expect(
      File('lib/core/security/play_integrity_service.dart').existsSync(),
      isTrue,
    );
    expect(
      File('deploy/platform-api/src/native_integrity.js').existsSync(),
      isTrue,
    );
  });

  test('Collect product boundary scan rejects forbidden app concepts', () {
    final result = runProcessSync(
      './scripts/collect_product_boundary_scan.sh',
      ['--json'],
    );
    expect(result.exitCode, 0);

    final output = result.stdout as String;
    expect(output, contains('"status": "pass"'));
    expect(output, contains('"hit_count": 0'));

    final makefile = File('Makefile').readAsStringSync();
    expect(makefile, contains('collect-product-boundary-scan:'));
    expect(makefile, contains('./scripts/collect_product_boundary_scan.sh'));
  });

  test('local env files stay ignored and Codex env stays placeholder-only', () {
    final root = repositoryCustodyRoot();
    final trackedEnvFiles = runProcessSync('git', [
      'ls-files',
      '.env',
      '.env.local',
      '.env.json',
    ], workingDirectory: root);
    expect(trackedEnvFiles.exitCode, 0);
    expect((trackedEnvFiles.stdout as String).trim(), isEmpty);

    final ignoredEnvFiles = runProcessSync('git', [
      'check-ignore',
      '.env',
      '.env.local',
      '.env.json',
    ], workingDirectory: root);
    expect(ignoredEnvFiles.exitCode, 0);

    final codexEnv = File(
      '$root/.codex/environments/environment.toml',
    ).readAsStringSync();
    final sensitiveAssignments = RegExp(
      r'^(DATABASE_URL|OPENAI_API_KEY|WHATSAPP_CLOUD_API_TOKEN|'
      r'SEND_SMS_HOOK_SECRET|INTERNAL_FUNCTION_SECRET|SMS_INGEST_HMAC_SECRET)='
      r'(.+)$',
      multiLine: true,
    ).allMatches(codexEnv);

    for (final assignment in sensitiveAssignments) {
      expect(assignment.group(2), isEmpty, reason: assignment.group(1));
    }

    final makefile = File('Makefile').readAsStringSync();
    final workflow = File('.github/workflows/ci.yml').readAsStringSync();
    final releaseSecretScan = File(
      'scripts/release_secret_scan.sh',
    ).readAsStringSync();

    expect(makefile, contains('release-secret-scan:'));
    expect(makefile, contains('./scripts/release_secret_scan.sh'));
    expect(workflow, contains('make release-secret-scan'));
    expect(releaseSecretScan, contains('gitleaks detect'));
    expect(releaseSecretScan, contains('--redact'));
    expect(
      releaseSecretScan,
      contains('git ls-files -z --cached --others --exclude-standard'),
    );
    expect(releaseSecretScan, contains('Potential secret pattern:'));
    expect(releaseSecretScan, contains('Values were not printed.'));
    expect(releaseSecretScan, isNot(contains(r'cat "$path"')));
    expect(releaseSecretScan, isNot(contains(r'echo "$text"')));
  });

  test('mobile runtime does not wire fixture data or no-op auth fallbacks', () {
    final repository = readCollectRepositoryLibrary();
    final authScreen = File(
      'lib/features/auth/auth_screen.dart',
    ).readAsStringSync();
    final libFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (file) =>
              file.path.endsWith('.dart') &&
              !isVerifiedAppleDoubleMetadata(file),
        );

    expect(
      repository,
      matches(
        RegExp(r'final repository = CollectRepository\(\s*backend: backend,'),
      ),
    );
    expect(repository, contains("throw StateError('Live WhatsApp sign-in"));
    expect(repository, matches(RegExp(r'_emptyCollectState\(\),\s*false')));
    expect(authScreen, contains("throw StateError('WhatsApp sign-in"));
    expect(authScreen, isNot(contains('if (client == null) return;')));

    for (final file in libFiles) {
      final text = file.readAsStringSync();
      final path = file.path;
      expect(text, isNot(contains('test/fixtures/')), reason: path);
      expect(text, isNot(contains('FixtureCollectRepository')), reason: path);
      expect(text, isNot(contains('_fixtureCollectState')), reason: path);
      if (path.endsWith('/collect_repository.dart')) continue;
      if (path.endsWith('lib/main.dart')) {
        expect(text, contains("'COLLECT_MOBILE_EVIDENCE_MODE'"), reason: path);
        expect(text, contains('if (mobileEvidenceMode)'), reason: path);
        expect(
          text,
          isNot(contains('CollectRepository.fixture')),
          reason: path,
        );
      } else {
        expect(
          text,
          isNot(contains('CollectRepository.fixture')),
          reason: path,
        );
      }
      expect(text, isNot(contains('qa-private-group')), reason: path);
      expect(text, isNot(contains('+250788123456')), reason: path);
    }
  });

  test('user mobile app cannot import route or mount admin surfaces', () {
    final mobileEntrypoints = {
      'lib/main.dart': File('lib/main.dart').readAsStringSync(),
      'lib/app/app.dart': File('lib/app/app.dart').readAsStringSync(),
      'lib/app/router.dart': File('lib/app/router.dart').readAsStringSync(),
      'integration_test/app_uat_smoke_test.dart': File(
        'integration_test/app_uat_smoke_test.dart',
      ).readAsStringSync(),
    };
    const forbiddenMobileAdminReferences = [
      'package:collect_app/admin/',
      "import '../admin/",
      'CollectAdminApp',
      'adminAuthGuardProvider',
      'adminRepositoryProvider',
      "path: '/admin",
      "'/admin",
      '"/admin',
    ];

    for (final entry in mobileEntrypoints.entries) {
      for (final forbidden in forbiddenMobileAdminReferences) {
        expect(entry.value, isNot(contains(forbidden)), reason: entry.key);
      }
    }

    final router = mobileEntrypoints['lib/app/router.dart']!;
    expect(router, contains('const collectRoutePaths = <String>['));
    expect(router, isNot(contains('/admin')));
  });
}
