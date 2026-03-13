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

    test('captures MoMo SMS metadata for ingestion and parsing', () {
      final capture = MomoSmsIngestionRepository.captureFromDeviceMessage(
        sender: 'M-Money',
        body: 'Payment of 10,000 RWF to COOL MARKET confirmed. TxId: ABC12345.',
        timestampMillis: DateTime.utc(2026, 3, 12, 9).millisecondsSinceEpoch,
      );

      expect(capture, isNotNull);
      expect(capture!.detectedTxType, equals('payment'));
      expect(capture.detectedAmount, equals(10000));
      expect(capture.detectedTxId, equals('ABC12345'));
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
    });

    test(
      'rejects raw-number messages that do not look like MoMo transactions',
      () {
        expect(
          MomoSmsIngestionRepository.captureFromDeviceMessage(
            sender: '+250786942353',
            body:
                'Good night umezutex? ni inesi iyo ndikwiga ntago mbanemerewe',
          ),
          isNull,
        );
      },
    );

    test(
      'keeps approved sender messages even when body is not yet recognized',
      () {
        final capture = MomoSmsIngestionRepository.captureFromDeviceMessage(
          sender: 'M-Money Alerts',
          body: 'Welcome to your M-Money campaign today.',
        );

        expect(capture, isNotNull);
        expect(capture!.sender, equals('M-Money Alerts'));
        expect(capture.detectedTxType, isNull);
        expect(capture.detectedAmount, isNull);
      },
    );
  });
}
