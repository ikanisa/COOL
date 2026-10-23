import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_offline_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _base = {
  'id': 'synthetic-intent',
  'collection_id': 'synthetic-group',
  'amount_minor': 5000,
  'status': 'pending',
  'created_at': '2026-10-18T08:00:00Z',
  'expires_at': '2026-10-19T08:00:00Z',
};
const _committed = {
  ..._base,
  'confirmation_status': 'credited',
  'payment_id': 'synthetic-payment',
  'contribution_entry_id': 'synthetic-entry',
  'credited_amount_rwf': 5000,
  'posted_at': '2026-10-18T08:30:00Z',
  'provider_transaction_at': '2026-10-18T10:15:00+02:00',
  'provider_transaction_reference': 'MOMO-SYNTHETIC-001',
  'balance_after_contribution_rwf': 12500,
  'group_balance_after_contribution_rwf': 30000,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('legacy status alone never establishes a credited contribution', () {
    final payload = {..._base}..['status'] = 'matched';
    final intent = PaymentIntentModel.fromJson(payload);
    expect(intent.confirmationStatus, 'awaiting_confirmation');
    expect(intent.hasCommittedContribution, isFalse);
  });

  test('credited receipt requires complete committed association', () {
    expect(
      PaymentIntentModel.fromJson(_committed).hasCommittedContribution,
      isTrue,
    );
    for (final key in [
      'payment_id',
      'contribution_entry_id',
      'credited_amount_rwf',
      'posted_at',
    ]) {
      expect(
        () => PaymentIntentModel.fromJson({..._committed, key: null}),
        throwsFormatException,
        reason: key,
      );
    }
    expect(
      () => PaymentIntentModel.fromJson(const {
        ..._base,
        'confirmation_status': 'payment_received',
      }),
      throwsFormatException,
    );
  });

  test('provider transaction time is distinct from the credited time', () {
    final intent = PaymentIntentModel.fromJson(_committed);
    expect(intent.providerTransactionAt, DateTime.utc(2026, 10, 18, 8, 15));
    expect(intent.postedAt, DateTime.utc(2026, 10, 18, 8, 30));
    expect(intent.providerTransactionAt!.isBefore(intent.postedAt!), isTrue);
  });

  test('legacy and null provider times stay absent without falling back', () {
    final legacy = {..._committed}..remove('provider_transaction_at');
    for (final payload in [
      legacy,
      {...legacy, 'provider_transaction_at': null},
    ]) {
      final intent = PaymentIntentModel.fromJson(payload);
      expect(intent.hasCommittedContribution, isTrue);
      expect(intent.providerTransactionAt, isNull);
      expect(intent.postedAt, DateTime.utc(2026, 10, 18, 8, 30));
    }
    expect(PaymentIntentModel.fromJson(_base).providerTransactionAt, isNull);
  });

  test(
    'provider transaction time rejects malformed and unzoned timestamps',
    () {
      for (final value in [
        '',
        'not-a-time',
        '2026-10-18',
        '2026-10-18T08:15:00',
        '2026-02-30T08:15:00Z',
        '2026-10-18T25:15:00Z',
        '2026-10-18T08:15:00+02:80',
        1792300000000,
        false,
      ]) {
        expect(
          () => PaymentIntentModel.fromJson({
            ..._committed,
            'provider_transaction_at': value,
          }),
          throwsFormatException,
          reason: '$value',
        );
      }
    },
  );

  test(
    'offline recovery retains committed receipt identity and time',
    () async {
      const cache = CollectOfflineCache(
        preferencesKey: 'synthetic.momo.receipt',
      );
      await cache.save(
        CollectOfflineSnapshot(
          savedAt: DateTime.utc(2026, 10, 18),
          currentProfile: null,
          collections: const [],
          paymentIntents: [PaymentIntentModel.fromJson(_committed)],
          contributions: const [],
        ),
      );
      final restored = (await cache.read())!.paymentIntents.single;
      expect(restored.hasCommittedContribution, isTrue);
      expect(restored.contributionEntryId, 'synthetic-entry');
      expect(restored.postedAt, DateTime.utc(2026, 10, 18, 8, 30));
      expect(restored.providerTransactionAt, DateTime.utc(2026, 10, 18, 8, 15));
      expect(restored.providerTransactionReference, 'MOMO-SYNTHETIC-001');
      expect(restored.balanceAfterContributionRwf, 12500);
      expect(restored.groupBalanceAfterContributionRwf, 30000);
    },
  );
}
