import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Revolut launcher uses app deep link with official web fallback', () {
    final launcher = File(
      'lib/core/payments/revolut_launcher.dart',
    ).readAsStringSync();

    expect(launcher, contains("Uri.parse('revolut://')"));
    expect(launcher, contains('https://www.revolut.com/app/'));
    expect(launcher, contains('LaunchMode.externalApplication'));
    expect(launcher, isNot(contains('tel:')));
    expect(launcher, isNot(contains('ACTION_CALL')));
  });

  test(
    'production Android exposes validated MoMo USSD and call permission',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final activity = File(
        'android/app/src/main/kotlin/app/cool/mobile/MainActivity.kt',
      ).readAsStringSync();

      expect(manifest, contains('android.permission.CALL_PHONE'));
      expect(activity, contains('collect/momo_ussd'));
      expect(activity, contains('MOMO_USSD_PATTERN'));
      expect(activity, contains('Intent.ACTION_CALL'));
    },
  );
}
