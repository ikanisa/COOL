import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/features/momo/services/nfc_hce_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('app.cool.mobile/nfc_hce');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('reads active payment request state', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'isSupported':
          return true;
        case 'isPaymentRequestActive':
          return true;
        case 'getPaymentRequestUri':
          return 'https://cool.app/momo?action=nfc_pay&recipient=0788'
              '&amount=5000';
      }
      return null;
    });

    final service = NfcHceService(channel: channel);

    expect(await service.isSupported(), isTrue);
    expect(await service.isPaymentRequestActive(), isTrue);
    expect(
      (await service.getPaymentRequestUri())?.toString(),
      'https://cool.app/momo?action=nfc_pay&recipient=0788&amount=5000',
    );
  });

  test('passes payload uri to native start and stop calls', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });

    final service = NfcHceService(channel: channel);
    final uri = Uri.parse(
      'https://cool.app/momo?action=nfc_pay&recipient=0788&amount=5000',
    );

    await service.startPaymentRequest(uri: uri);
    await service.stopPaymentRequest();

    expect(calls.map((call) => call.method), [
      'startPaymentRequest',
      'stopPaymentRequest',
    ]);
    expect(calls.first.arguments, <String, dynamic>{'uri': uri.toString()});
  });
}
