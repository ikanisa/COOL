import 'package:cool_app/features/momo/repositories/momo_sms_ingestion_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MomoSmsIngestionRepository', () {
    test('accepts approved sender variants', () {
      expect(MomoSmsIngestionRepository.isApprovedSender('M-Money'), isTrue);
      expect(MomoSmsIngestionRepository.isApprovedSender('M Money'), isTrue);
      expect(
        MomoSmsIngestionRepository.isApprovedSender('MobileMoney'),
        isTrue,
      );
      expect(
        MomoSmsIngestionRepository.isApprovedSender('Mobile Money'),
        isTrue,
      );
      expect(MomoSmsIngestionRepository.isApprovedSender('MoMo'), isTrue);
      expect(
        MomoSmsIngestionRepository.isApprovedSender('MTN MoMo Rwanda'),
        isTrue,
      );
      expect(MomoSmsIngestionRepository.isApprovedSender('BANK'), isFalse);
    });

    test('builds a stable device message key from normalized content', () {
      final receivedAt = DateTime.utc(2026, 3, 12, 10, 30);
      final first = MomoSmsIngestionRepository.buildDeviceMessageKey(
        sender: 'Mobile Money',
        body: 'Payment of 10,000 RWF confirmed. TxId: ABC12345.',
        receivedAt: receivedAt,
      );
      final second = MomoSmsIngestionRepository.buildDeviceMessageKey(
        sender: 'MobileMoney',
        body: 'Payment  of 10,000   RWF confirmed. TxId: ABC12345.',
        receivedAt: receivedAt,
      );

      expect(first, equals(second));
    });

    test('captures approved M-Money SMS without device-side parsing', () {
      final capture = MomoSmsIngestionRepository.captureFromDeviceMessage(
        sender: 'M-Money',
        body: 'Payment of 10,000 RWF to COOL MARKET confirmed. TxId: ABC12345.',
        timestampMillis: DateTime.utc(2026, 3, 12, 9).millisecondsSinceEpoch,
      );

      expect(capture, isNotNull);
      expect(capture!.sender, equals('M-Money'));
      expect(
        capture.body,
        equals(
          'Payment of 10,000 RWF to COOL MARKET confirmed. TxId: ABC12345.',
        ),
      );
      expect(capture.deviceMessageKey, isNotEmpty);
    });

    test('rejects unsupported senders and empty bodies', () {
      expect(
        MomoSmsIngestionRepository.captureFromDeviceMessage(
          sender: 'BANK',
          body: 'Payment of 10,000 RWF confirmed.',
        ),
        isNull,
      );
      expect(
        MomoSmsIngestionRepository.captureFromDeviceMessage(
          sender: 'M-Money',
          body: '   ',
        ),
        isNull,
      );
    });

    test(
      'keeps approved sender messages even when body is not yet recognized',
      () {
        final capture = MomoSmsIngestionRepository.captureFromDeviceMessage(
          sender: 'M-Money Alerts',
          body: 'Welcome to your M-Money campaign today.',
        );

        expect(capture, isNotNull);
        expect(capture!.sender, equals('M-Money Alerts'));
        expect(capture.body, equals('Welcome to your M-Money campaign today.'));
      },
    );

    test('rejects non-M-Money messages without body heuristics', () {
      expect(
        MomoSmsIngestionRepository.captureFromDeviceMessage(
          sender: '+250788767816',
          body:
              'You have received 50000 RWF from Yvette NYIRAMAHIRWE '
              '(*********235) at 2025-11-19 23:12:44 . Balance:633978 RWF. '
              'FT Id: 24224946460',
        ),
        isNull,
      );
      expect(
        MomoSmsIngestionRepository.captureFromDeviceMessage(
          sender: 'BANK',
          body: 'Payment of 10,000 RWF confirmed.',
        ),
        isNull,
      );
    });

    test('flags strong MoMo drift signals from msisdn senders', () {
      final metadata = MomoSmsIngestionRepository.senderDriftTelemetry(
        sender: '+250788767816',
        body:
            'You have received 50000 RWF from Yvette NYIRAMAHIRWE '
            '(*********235) at 2025-11-19 23:12:44 . Balance:633978 RWF. '
            'FT Id: 24224946460',
      );

      expect(metadata, isNotNull);
      expect(metadata!['sender_kind'], 'msisdn');
      expect(metadata['has_tx_reference'], isTrue);
      expect(metadata['contains_balance'], isTrue);
      expect(metadata['contains_outcome_signal'], isTrue);
      expect(metadata['signal_count'], greaterThanOrEqualTo(3));
    });

    test('ignores generic bank-like alerts from unapproved senders', () {
      final metadata = MomoSmsIngestionRepository.senderDriftTelemetry(
        sender: 'BANK',
        body:
            'Your account was debited 5,000 RWF at 2026-03-22 10:00. '
            'Available balance 95,000 RWF.',
      );

      expect(metadata, isNull);
    });
  });
}
