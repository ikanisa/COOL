import 'package:cool_app/core/services/momo_sms_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // These tests cover the local heuristic parser only.
  // The AI-backed parser lives in `supabase/functions/parse-momo-sms`.
  group('MomoSmsParser', () {
    test('parses approved M-Money payment confirmations', () {
      final transaction = MomoSmsParser.parse(
        sender: 'M-Money',
        smsBody:
            'Payment of 10,000 RWF to COOL MARKET confirmed. TxId: ABC12345.',
      );

      expect(transaction, isNotNull);
      expect(transaction!.type, MomoTxType.payment);
      expect(transaction.amountRwf, 10000);
      expect(transaction.transactionId, 'ABC12345');
      expect(transaction.sender, 'M-Money');
    });

    test('accepts MobileMoney as an approved legacy sender alias', () {
      final transaction = MomoSmsParser.parse(
        sender: 'MobileMoney',
        smsBody:
            'You have received 5,000 RWF from 0788123456. Your new balance is 12,000 RWF. TxId: RX1234.',
      );

      expect(transaction, isNotNull);
      expect(transaction!.type, MomoTxType.received);
      expect(transaction.amountRwf, 5000);
      expect(transaction.transactionId, 'RX1234');
    });

    test('rejects broad carrier senders that are not explicitly approved', () {
      final transaction = MomoSmsParser.parse(
        sender: 'MTN',
        smsBody:
            'Payment of 10,000 RWF to COOL MARKET confirmed. TxId: ABC12345.',
      );

      expect(transaction, isNull);
      expect(MomoSmsParser.isApprovedSender('MTN'), isFalse);
    });

    test('normalizes punctuation when checking approved sender IDs', () {
      expect(MomoSmsParser.isApprovedSender('m money'), isTrue);
      expect(MomoSmsParser.isApprovedSender('MoMo'), isFalse);
    });
  });
}
