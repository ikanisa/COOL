import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('current product documents define Rwanda MoMo USSD scope', () {
    for (final path in [
      'docs/PRODUCT.md',
      'docs/COLLECT_REVISED_PRODUCT_DEFINITION_FOR_REVIEW.md',
      'README.md',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('Rwanda'), reason: path);
      expect(source, contains('MoMo'), reason: path);
      expect(source, contains('USSD'), reason: path);
      expect(source.toLowerCase(), isNot(contains('diaspora')), reason: path);
      expect(
        source.toLowerCase(),
        isNot(contains('bank transfer')),
        reason: path,
      );
    }
  });

  test('environment keeps production credentials server-side', () {
    final environment = File('docs/ENVIRONMENT.md').readAsStringSync();
    final example = File('.env.example').readAsStringSync();

    for (final secret in <String>[
      'FCM_SERVICE_ACCOUNT_JSON',
      'APNS_PRIVATE_KEY_BASE64',
      'PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON',
      'AUTH_JWT_SECRET',
      'AUTH_TOKEN_HASH_SECRET',
      'DATA_ENCRYPTION_KEY',
    ]) {
      expect(environment, contains(secret));
      expect(example, isNot(contains('$secret=')));
    }
    expect(
      environment,
      contains('Android production builds set both SMS switches to `true`'),
    );
    expect(environment, contains('PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER'));
    expect(example, contains('PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER='));
    expect(environment, contains('no `READ_SMS`, `SEND_SMS`'));
    expect(environment, isNot(contains('STRIPE_SECRET_KEY')));
    expect(
      environment,
      contains('COLLECT_API_URL=https://api.collect.ikanisa.com'),
    );
  });

  test('Android production build requires the linked Play project number', () {
    final build = File(
      'scripts/android_play_store_build.sh',
    ).readAsStringSync();

    expect(build, contains('PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER_VALUE'));
    expect(
      build,
      contains('must be the positive project number linked to Collect'),
    );
    expect(build, contains('export PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER='));
  });

  test('Google Play packet records the pending Rwanda SMS approval gate', () {
    final packet =
        jsonDecode(
              File(
                'docs/release/GOOGLE_PLAY_CONSOLE_AUDIT_PACKET.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final appContent = Map<String, dynamic>.from(packet['app_content'] as Map);
    final permissions = Map<String, dynamic>.from(
      appContent['permissions'] as Map,
    );
    final values = List<String>.from(
      permissions['production_permissions'] as List,
    );

    expect(permissions['restricted_sms_permissions_in_production'], isTrue);
    expect(
      permissions['sms_permissions_declaration_status'],
      'required_pending_play_approval',
    );
    expect(values, contains('android.permission.RECEIVE_SMS'));
    expect(values, isNot(contains('android.permission.READ_SMS')));
    expect(values, contains('android.permission.CALL_PHONE'));
  });

  test('release gates distinguish public production and internal receiver', () {
    final play = File(
      'scripts/google_play_optimization_gate.sh',
    ).readAsStringSync();
    final mobile = File(
      'scripts/flutter_mobile_release_gate.sh',
    ).readAsStringSync();
    final upload = File(
      'scripts/google_play_production_upload.sh',
    ).readAsStringSync();

    expect(
      play,
      contains('expected_apk_restricted = ["android.permission.RECEIVE_SMS"]'),
    );
    expect(play, contains('restricted_sms_declaration'));
    expect(play, contains('android_group_creation_attestation'));
    expect(mobile, contains('production_receive_only'));
    expect(upload, contains('google_play_sms_declaration_invalid_for_phase'));
  });
}
