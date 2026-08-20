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

  test('production Android exposes no USSD bridge or call permission', () {
    final manifest = File(
      'android/app/src/production/AndroidManifest.xml',
    ).readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/app/cool/mobile/MainActivity.kt',
    ).readAsStringSync();

    expect(manifest, isNot(contains('android.permission.CALL_PHONE')));
    expect(activity, isNot(contains('collect/momo_ussd')));
    expect(activity, isNot(contains('Intent.ACTION_CALL')));
  });
}
