import 'package:collect_app/core/data/exact_json_values.dart';
import 'package:collect_app/core/payments/momo_ussd_launcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  const channel = MethodChannel('collect/momo_ussd');
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  for (final amount in [0, -1, maxExactJsonInteger + 1]) {
    test(
      'unsafe amount $amount never reaches the native USSD bridge',
      () async {
        await expectLater(
          const MomoUssdLauncher().launch(
            receiver: '0788123456',
            amountRwf: amount,
            provider: 'mtn_momo',
          ),
          throwsFormatException,
        );
        expect(calls, isEmpty);
      },
    );
  }
  test(
    'exact maximum is preserved as decimal text at the native boundary',
    () async {
      expect(
        await const MomoUssdLauncher().launch(
          receiver: '0788123456',
          amountRwf: maxExactJsonInteger,
          provider: 'mtn_momo',
        ),
        isTrue,
      );
      expect(calls.single.arguments, {
        'ussd_code': '*182**8*1*0788123456*9007199254740991#',
      });
    },
  );
}
