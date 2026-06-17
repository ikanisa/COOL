import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
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
      final notificationScreen = File(
        'lib/features/status/production_state_screens.dart',
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
      expect(notificationScreen, contains('_enableNativeNotifications'));
      expect(
        notificationScreen,
        contains('collectNotificationServiceProvider'),
      );
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
      '.dart_tool',
      '.git',
      'build',
      'coverage',
      'ios/Pods',
    };
    final files = Directory.current
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) {
          final path = file.path.replaceFirst('${Directory.current.path}/', '');
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
        });

    for (final file in files) {
      final text = file.readAsStringSync();
      for (final pattern in blockedPatterns) {
        expect(pattern.hasMatch(text), isFalse, reason: file.path);
      }
    }
  });

  test('Collect product boundary scan rejects forbidden app concepts', () {
    final result = Process.runSync(
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
    final trackedEnvFiles = Process.runSync('git', [
      'ls-files',
      '.env',
      '.env.local',
      '.env.json',
    ]);
    expect(trackedEnvFiles.exitCode, 0);
    expect((trackedEnvFiles.stdout as String).trim(), isEmpty);

    final ignoredEnvFiles = Process.runSync('git', [
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
    final repository = File(
      'lib/shared/repositories/collect_repository.dart',
    ).readAsStringSync();
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
    expect(repository, contains('_emptyState(), false'));
    expect(authScreen, contains("throw StateError('WhatsApp sign-in"));
    expect(authScreen, isNot(contains('if (client == null) return;')));

    for (final file in libFiles) {
      final text = file.readAsStringSync();
      final path = file.path;
      if (path.endsWith('collect_repository.dart')) continue;
      if (path.contains('/features/dev/')) continue;
      expect(text, isNot(contains('CollectRepository.fixture')), reason: path);
      expect(text, isNot(contains('col-church')), reason: path);
      expect(text, isNot(contains('St Michel')), reason: path);
      expect(text, isNot(contains('+250788123456')), reason: path);
    }
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
