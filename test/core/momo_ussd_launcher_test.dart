import 'dart:io';

import 'package:collect_app/core/payments/momo_ussd_launcher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('collect/momo_ussd_test');

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'Android launcher passes the complete encoded tel URI natively',
    () async {
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            received = call;
            return true;
          });

      final launched = await MomoUssdLauncher(
        androidChannel: channel,
      ).launch(Uri.parse('tel:*182**8*1*2209724*100%23'));

      expect(launched, isTrue);
      expect(received?.method, 'launch');
      expect(received?.arguments, <String, String>{
        'uri': 'tel:*182**8*1*2209724*100%23',
      });
    },
  );

  test('launcher rejects non-tel schemes before native handoff', () {
    expect(
      () => MomoUssdLauncher(
        androidChannel: channel,
      ).launch(Uri.parse('https://example.com')),
      throwsArgumentError,
    );
  });

  test('Android bridge starts only the allowlisted MoMo USSD shape', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/app/cool/mobile/MainActivity.kt',
    ).readAsStringSync();

    expect(manifest, contains('android.permission.CALL_PHONE'));
    expect(activity, contains('"collect/momo_ussd"'));
    expect(activity, contains('Intent(Intent.ACTION_CALL, uri)'));
    expect(activity, contains(r'^\*182\*\*8\*1\*[0-9]{4,9}\*[1-9][0-9]*#$'));
    expect(activity, isNot(contains('PIN')));
  });
}
