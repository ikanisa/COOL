import 'package:cool_app/features/momo/repositories/momo_sms_ingestion_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MomoSmsIngestionRepository sender alignment', () {
    test('approvedInboxSenderIds covers all normalized tokens', () {
      final normalizedFromList = MomoSmsIngestionRepository
          .approvedInboxSenderIds
          .map((s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''))
          .toSet();

      const expectedTokens = <String>{
        'mmoney',
        'mmoneyalerts',
        'mobilemoney',
        'momo',
        'momoalerts',
        'mtnmomo',
        'mtnmomorwanda',
      };

      for (final token in expectedTokens) {
        expect(
          normalizedFromList.contains(token),
          isTrue,
          reason: 'Token "$token" is not covered by approvedInboxSenderIds',
        );
      }
    });

    test('accepts newly added sender variants', () {
      expect(
        MomoSmsIngestionRepository.isApprovedSender('M-Money Alerts'),
        isTrue,
      );
      expect(
        MomoSmsIngestionRepository.isApprovedSender('MoMo Alerts'),
        isTrue,
      );
      expect(
        MomoSmsIngestionRepository.isApprovedSender('MTN MoMo Rwanda'),
        isTrue,
      );
    });

    test('flags sender drift for unapproved transactional bodies', () {
      final metadata = MomoSmsIngestionRepository.senderDriftTelemetry(
        sender: 'MTN Rwanda',
        body:
            'TxId: 123456. Your payment of 1,200 RWF was completed. New balance: 8,900 RWF.',
      );

      expect(metadata, isNotNull);
      expect(metadata!['sender_token'], 'mtnrwanda');
      expect(metadata['sender_kind'], 'alias');
      expect(metadata['has_tx_reference'], isTrue);
      expect(metadata['contains_txid'], isTrue);
      expect(metadata['contains_rwf'], isTrue);
    });

    test('ignores approved senders and non-transactional bodies for drift', () {
      expect(
        MomoSmsIngestionRepository.senderDriftTelemetry(
          sender: 'M-Money',
          body: 'TxId: 123456. Payment of 500 RWF completed.',
        ),
        isNull,
      );
      expect(
        MomoSmsIngestionRepository.senderDriftTelemetry(
          sender: 'Unknown Sender',
          body: 'Welcome to your new plan.',
        ),
        isNull,
      );
      expect(
        MomoSmsIngestionRepository.senderDriftTelemetry(
          sender: 'BANK',
          body:
              'Your account was debited 5,000 RWF. Available balance 95,000 RWF.',
        ),
        isNull,
      );
    });
  });
}
