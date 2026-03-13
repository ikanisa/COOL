import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/config/country_catalog.dart';
import 'package:cool_app/core/models/momo_qr_payload.dart';

void main() {
  final rwanda = CoolCountryCatalog.resolve(country: 'RW');
  final momoNumber = rwanda.buildE164Phone('0781234567');

  group('MomoQrPayload', () {
    test('profile QR uses COOL app link and roundtrips', () {
      final payload = MomoQrPayload.profile(
        recipientValue: momoNumber,
        recipientType: MomoRecipientType.phoneNumber,
        countryCode: rwanda.isoCode,
      );

      final qrData = payload.toQrData(rwanda);
      final parsed = MomoQrPayload.tryParse(qrData);

      expect(qrData, startsWith('https://'));
      expect(parsed, isNotNull);
      expect(parsed!.action, MomoQrAction.profile);
      expect(parsed.recipientValue, momoNumber);
      expect(parsed.countryCode, 'RW');
      expect(parsed.canLaunchImmediately, isFalse);
    });

    test('payment request QR generates a direct dialer payload', () {
      final payload = MomoQrPayload.paymentRequest(
        recipientValue: momoNumber,
        recipientType: MomoRecipientType.phoneNumber,
        amount: 5000,
        countryCode: rwanda.isoCode,
      );

      final qrData = payload.toQrData(rwanda);
      final decodedDialer = Uri.decodeComponent(
        qrData.substring('tel:'.length),
      );

      expect(qrData, startsWith('tel:'));
      expect(decodedDialer, startsWith('*182'));
      expect(decodedDialer, contains('5000'));
      expect(decodedDialer, endsWith('#'));
    });

    test('pay app links roundtrip through URI parsing', () {
      final payload = MomoQrPayload.paymentRequest(
        recipientValue: momoNumber,
        recipientType: MomoRecipientType.phoneNumber,
        amount: 2500,
        countryCode: rwanda.isoCode,
        reference: 'REQ-2500',
      );

      final parsed = MomoQrPayload.tryParseUri(payload.toAppLinkUri());

      expect(parsed, isNotNull);
      expect(parsed!.action, MomoQrAction.pay);
      expect(parsed.amount, 2500);
      expect(parsed.reference, 'REQ-2500');
      expect(parsed.countryCode, 'RW');
    });

    test('legacy momo payloads and plain phone payloads still parse', () {
      final legacy = MomoQrPayload.tryParse('momo://$momoNumber');
      final plain = MomoQrPayload.tryParse('0781234567');

      expect(legacy, isNotNull);
      expect(legacy!.recipientValue, momoNumber);
      expect(legacy.action, MomoQrAction.profile);

      expect(plain, isNotNull);
      expect(plain!.recipientValue, '0781234567');
      expect(plain.action, MomoQrAction.profile);
    });
  });
}
