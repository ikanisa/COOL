import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/config/country_catalog.dart';
import 'package:cool_app/features/momo/services/nfc_service.dart';

void main() {
  group('NfcPaymentPayload', () {
    test('encodes and parses a momo code payload', () {
      const payload = NfcPaymentPayload(
        recipientType: MomoRecipientType.code,
        recipientValue: '123456',
        amount: '5000',
        countryCode: 'RW',
      );

      final encoded = payload.encode();
      final parsed = NfcPaymentPayload.tryParse(encoded);

      expect(parsed, isNotNull);
      expect(parsed!.recipientType, MomoRecipientType.code);
      expect(parsed.recipientValue, '123456');
      expect(parsed.amount, '5000');
      expect(parsed.countryCode, 'RW');
    });

    test('parses the legacy phone payload format', () {
      final parsed = NfcPaymentPayload.tryParse('COOL:0788123456:3500');

      expect(parsed, isNotNull);
      expect(parsed!.recipientType, MomoRecipientType.phoneNumber);
      expect(parsed.recipientValue, '0788123456');
      expect(parsed.amount, '3500');
      expect(parsed.countryCode, isNull);
    });

    test('round-trips the deep link uri payload', () {
      const payload = NfcPaymentPayload(
        recipientType: MomoRecipientType.code,
        recipientValue: '123456',
        amount: '6500',
        countryCode: 'RW',
      );

      final uri = payload.toDeepLinkUri();
      final parsed = NfcPaymentPayload.tryParseUri(uri);

      expect(parsed, isNotNull);
      expect(parsed!.recipientType, MomoRecipientType.code);
      expect(parsed.recipientValue, '123456');
      expect(parsed.amount, '6500');
      expect(parsed.countryCode, 'RW');
      expect(uri.toString(), contains('action=nfc_pay'));
    });
  });
}
