import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/process_runner.dart';

String readCollectRepositoryLibrary() {
  return [
    'lib/shared/repositories/collect_repository.dart',
    'lib/shared/repositories/collect_repository_providers.dart',
    'lib/shared/repositories/collect_repository_state.dart',
    'lib/shared/repositories/collect_repository_fixture.dart',
    'lib/shared/repositories/collect_repository_live_reader.dart',
  ].map((path) => File(path).readAsStringSync()).join('\n');
}

void main() {
  test('local and CI Flutter toolchains use the governed stable engine', () {
    const expectedVersion = '3.44.4';
    const expectedRoot = '/Users/jeanbosco/Developer/flutter';
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
    expect(environment, contains('$expectedRoot/bin/flutter'));
    expect(makefile, contains('FLUTTER ?= $expectedRoot/bin/flutter'));
    expect(makefile, contains('DART ?= $expectedRoot/bin/dart'));
    for (final path in governedScripts) {
      final script = File(path).readAsStringSync();
      expect(script, contains('$expectedRoot/bin/flutter'), reason: path);
      expect(
        script,
        isNot(contains('/Volumes/PRO-G40/flutter_3_44/bin/flutter')),
        reason: path,
      );
    }
  });

  test('production Android manifest does not request SMS permissions', () {
    final productionManifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final internalReceiverManifest = File(
      'android/app/src/internal_receiver/AndroidManifest.xml',
    ).readAsStringSync();

    expect(productionManifest, isNot(contains('android.permission.READ_SMS')));
    expect(
      productionManifest,
      isNot(contains('android.permission.RECEIVE_SMS')),
    );
    expect(
      productionManifest,
      contains('android.permission.READ_EXTERNAL_STORAGE'),
    );
    expect(
      productionManifest,
      contains('android.permission.WRITE_EXTERNAL_STORAGE'),
    );
    expect(
      RegExp(
        r'android\.permission\.(READ|WRITE)_EXTERNAL_STORAGE"'
        r'\s+tools:node="remove"',
      ).allMatches(productionManifest),
      hasLength(2),
    );
    expect(internalReceiverManifest, contains('android.permission.READ_SMS'));
    expect(
      internalReceiverManifest,
      contains('android.permission.RECEIVE_SMS'),
    );
  });

  test(
    'native notification runtime is wired without remote-push overclaiming',
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
      final repository = File(
        'lib/shared/repositories/collect_repository.dart',
      ).readAsStringSync();
      final entitlements = File(
        'ios/Runner/Runner.entitlements',
      ).readAsStringSync();

      expect(pubspec, contains('flutter_local_notifications:'));
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
      expect(nativePermissionSheets, contains('registerDevice(repository)'));
      expect(nativePermissionSheets, contains('showNotification('));
      expect(nativePermissionSheets, contains("payload: '/home'"));
      expect(androidGradle, contains('isCoreLibraryDesugaringEnabled = true'));
      expect(androidGradle, contains('desugar_jdk_libs:2.1.4'));
      expect(repository, contains('register_notification_device'));
      expect(entitlements, isNot(contains('aps-environment')));
    },
  );

  test('iOS permission declarations match implemented features only', () {
    final podfile = File('ios/Podfile').readAsStringSync();
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
    final entitlements = File(
      'ios/Runner/Runner.entitlements',
    ).readAsStringSync();

    expect(infoPlist, contains('NSCameraUsageDescription'));
    expect(infoPlist, contains('NSPhotoLibraryUsageDescription'));
    expect(infoPlist, isNot(contains('NSContactsUsageDescription')));
    expect(infoPlist, isNot(contains('NSPhotoLibraryAddUsageDescription')));
    expect(podfile, contains('PERMISSION_CAMERA=1'));
    expect(podfile, contains('PERMISSION_CONTACTS=0'));
    expect(podfile, contains('PERMISSION_NOTIFICATIONS=0'));
    expect(podfile, contains('PERMISSION_PHOTOS_ADD_ONLY=0'));
    expect(entitlements, contains('applinks:collect.ikanisa.com'));
    expect(entitlements, isNot(contains('com.apple.developer.nfc')));
    expect(entitlements, isNot(contains('aps-environment')));
  });

  test('repository text files do not store obvious live secrets', () {
    final blockedPatterns = <RegExp>[
      RegExp(r'sk-proj-[A-Za-z0-9_-]{20,}'),
      RegExp(r'sbp_[A-Za-z0-9]{20,}'),
      RegExp(r'eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+'),
      RegExp(r'postgresql://[^:\s]+:[^@\s]+@'),
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
    final inventory = Process.runSync('git', [
      'ls-files',
      '-z',
      '--cached',
      '--others',
      '--exclude-standard',
    ]);
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
        .map(File.new)
        .where((file) => file.existsSync());

    for (final file in files) {
      final text = file.readAsStringSync();
      for (final pattern in blockedPatterns) {
        expect(pattern.hasMatch(text), isFalse, reason: file.path);
      }
    }
  });

  test(
    'Play Integrity implementation keeps token and key material out of logs',
    () {
      final mainActivity = File(
        'android/app/src/main/kotlin/app/cool/mobile/MainActivity.kt',
      ).readAsStringSync();
      final service = File(
        'lib/core/security/play_integrity_service.dart',
      ).readAsStringSync();
      final edgeFunction = File(
        'supabase/functions/verify-play-integrity/index.ts',
      ).readAsStringSync();
      final playGate = File(
        'scripts/google_play_optimization_gate.sh',
      ).readAsStringSync();

      expect(mainActivity, contains('play_integrity_not_configured'));
      expect(service, contains('MissingPluginException'));
      expect(edgeFunction, contains('PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON'));
      expect(edgeFunction, contains('GOOGLE_PLAY_SERVICE_ACCOUNT_JSON'));
      expect(edgeFunction, isNot(contains('-----BEGIN PRIVATE KEY-----')));
      expect(edgeFunction, isNot(contains('console.log')));
      expect(edgeFunction, isNot(contains('console.error')));
      expect(playGate, contains('play_integrity_implementation'));
      expect(playGate, contains('has_secret_material'));
    },
  );

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

  test(
    'Revolut parity source hygiene gate enforces typography and official assets',
    () {
      final result = runProcessSync(
        './scripts/revolut_parity_source_hygiene_gate.sh',
        ['--json'],
      );
      expect(result.exitCode, 0, reason: result.stderr as String);

      final output = result.stdout as String;
      expect(output, contains('"status": "pass"'));
      expect(output, contains('"exclusive_inter_typefaces"'));
      expect(output, contains('"no_prohibited_product_artwork"'));
      expect(output, contains('"official_logo_identity"'));
      expect(output, contains('"centralized_feature_typography"'));
      expect(output, contains('"fixture_isolation"'));
      expect(output, contains('"secret_scan"'));
      expect(output, contains('"product_boundary"'));

      final makefile = File('Makefile').readAsStringSync();
      final workflow = File('.github/workflows/ci.yml').readAsStringSync();
      expect(makefile, contains('revolut-parity-source-hygiene:'));
      expect(
        makefile,
        contains('./scripts/revolut_parity_source_hygiene_gate.sh'),
      );
      expect(workflow, contains('make revolut-parity-source-hygiene'));
    },
  );

  test('local env files stay ignored and Codex env stays placeholder-only', () {
    final trackedEnvFiles = runProcessSync('git', [
      'ls-files',
      '.env',
      '.env.local',
      '.env.json',
    ]);
    expect(trackedEnvFiles.exitCode, 0);
    expect((trackedEnvFiles.stdout as String).trim(), isEmpty);

    final ignoredEnvFiles = runProcessSync('git', [
      'check-ignore',
      '.env',
      '.env.local',
      '.env.json',
    ]);
    expect(ignoredEnvFiles.exitCode, 0);

    final codexEnv = File(
      '.codex/environments/environment.toml',
    ).readAsStringSync();
    final sensitiveAssignments = RegExp(
      r'^(SUPABASE_ACCESS_TOKEN|SUPABASE_DB_PASSWORD|DATABASE_URL|'
      r'SUPABASE_SERVICE_ROLE_KEY|OPENAI_API_KEY|WHATSAPP_CLOUD_API_TOKEN|'
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
        .where((file) => file.path.endsWith('.dart'));

    expect(
      repository,
      contains('final repository = CollectRepository(supabase: supabase);'),
    );
    expect(repository, contains("throw StateError('Live WhatsApp sign-in"));
    expect(repository, matches(RegExp(r'_emptyCollectState\(\),\s*false')));
    expect(authScreen, contains("throw StateError('WhatsApp sign-in"));
    expect(authScreen, isNot(contains('if (client == null) return;')));

    for (final file in libFiles) {
      final text = file.readAsStringSync();
      final path = file.path;
      if (path.contains('/shared/repositories/collect_repository')) continue;
      if (path.endsWith('lib/main.dart')) {
        expect(text, contains("'COLLECT_MOBILE_EVIDENCE_MODE'"), reason: path);
        expect(text, contains('if (mobileEvidenceMode)'), reason: path);
      } else {
        expect(
          text,
          isNot(contains('CollectRepository.fixture')),
          reason: path,
        );
      }
      expect(text, isNot(contains('col-church')), reason: path);
      expect(text, isNot(contains('St Michel')), reason: path);
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

  test('Supabase operator scripts use local CLI fallbacks', () {
    final scripts = [
      'scripts/supabase_production_readiness.sh',
      'scripts/supabase_advisors_gate.sh',
      'scripts/supabase_advisors_warning_inventory.sh',
      'scripts/collect_linked_uat.sh',
      'scripts/collect_admin_security_uat.sh',
      'scripts/collect_live_parser_uat.sh',
      'scripts/supabase_deploy.sh',
      'scripts/supabase_apply_auth_hardening.sh',
      'scripts/supabase_apply_network_restrictions.sh',
      'scripts/supabase_operational_report.sh',
    ];

    for (final script in scripts) {
      final text = File(script).readAsStringSync();
      expect(text, contains('scripts/supabase_cli_helpers.sh'), reason: script);
      expect(
        text,
        isNot(
          matches(
            RegExp(
              r'(^|\s)supabase\s+'
              r'(db|functions|secrets|network-restrictions|projects|backups|ssl-enforcement)\b',
              multiLine: true,
            ),
          ),
        ),
        reason: script,
      );
      expect(
        text,
        isNot(
          matches(RegExp(r'(^|\s)psql\s+"\$DATABASE_URL"', multiLine: true)),
        ),
        reason: script,
      );
    }
  });
}
