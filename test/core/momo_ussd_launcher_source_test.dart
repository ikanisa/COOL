import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('member payment launcher is MoMo USSD only', () {
    expect(
      File('lib/core/payments/revolut_launcher.dart').existsSync(),
      isFalse,
    );
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      expect(
        file.readAsStringSync(),
        isNot(contains('revolut_launcher.dart')),
        reason: file.path,
      );
    }
    final launcher = File(
      'lib/core/payments/momo_ussd_launcher.dart',
    ).readAsStringSync();
    expect(launcher, contains('class MomoUssdLauncher'));
    expect(launcher, isNot(contains('revolut://')));
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
      final momoChannel = File(
        'android/app/src/main/kotlin/app/cool/mobile/MemberMomoChannel.kt',
      ).readAsStringSync();

      expect(manifest, contains('android.permission.CALL_PHONE'));
      expect(activity, contains('momo.register(messenger)'));
      expect(
        activity,
        contains('momo.onRequestPermissionsResult(requestCode)'),
      );
      expect(momoChannel, contains('collect/momo_ussd'));
      expect(momoChannel, contains('MOMO_USSD_PATTERN'));
      expect(momoChannel, contains('Intent.ACTION_CALL'));
    },
  );
}
