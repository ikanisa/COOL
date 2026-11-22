import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/providers/collect_app_state.dart';
import 'package:collect_app/shared/repositories/collect_offline_cache.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures/collect_repository_fixture.dart';

class _StatusRepository extends FixtureCollectRepository {
  void publishIntents(
    List<PaymentIntentModel> intents, {
    bool stale = false,
    bool scopeUncertain = false,
  }) {
    state = state.copyWith(
      paymentIntents: intents,
      usingStaleCache: stale,
      memberScopeUncertain: scopeUncertain,
    );
  }
}

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

  test(
    'payment status follows the requested group and current intent list',
    () {
      final repository = _StatusRepository();
      final container = ProviderContainer(
        overrides: [
          collectRepositoryProvider.overrideWith((ref) => repository),
        ],
      );
      addTearDown(container.dispose);
      final now = DateTime.now().toUtc();
      final pending = PaymentIntentModel.fromJson({
        ..._base,
        'created_at': now.toIso8601String(),
        'expires_at': now.add(const Duration(days: 1)).toIso8601String(),
      });
      final failed = PaymentIntentModel.fromJson(
        Map.of(_base)..['status'] = 'failed',
      );
      final status = paymentUiStatusProvider(
        PaymentStatusKey(
          collectionId: pending.collectionId,
          intentId: pending.id,
        ),
      );
      final otherGroup = paymentUiStatusProvider(
        PaymentStatusKey(collectionId: 'other-group', intentId: pending.id),
      );
      repository.publishIntents([pending], stale: true);
      expect(container.read(status), PaymentUiStatus.pending);
      expect(container.read(otherGroup), PaymentUiStatus.needsReview);
      repository.publishIntents([failed]);
      expect(container.read(status), PaymentUiStatus.needsReview);
      repository.publishIntents([pending], scopeUncertain: true);
      expect(container.read(status), PaymentUiStatus.needsReview);
      repository.publishIntents([pending, pending]);
      expect(container.read(status), PaymentUiStatus.needsReview);
    },
  );

  test(
    'payment status requires committed evidence for credit and reversal',
    () {
      final repository = _StatusRepository();
      final container = ProviderContainer(
        overrides: [
          collectRepositoryProvider.overrideWith((ref) => repository),
        ],
      );
      addTearDown(container.dispose);
      final status = paymentUiStatusProvider(
        const PaymentStatusKey(
          collectionId: 'synthetic-group',
          intentId: 'synthetic-intent',
        ),
      );
      void check(Map<String, dynamic> payload, PaymentUiStatus expected) {
        repository.publishIntents([PaymentIntentModel.fromJson(payload)]);
        expect(
          container.read(status),
          expected,
          reason: '${payload['status']} / ${payload['confirmation_status']}',
        );
      }

      check(_committed, PaymentUiStatus.confirmed);
      check(
        Map.of(_committed)..['confirmation_status'] = 'reversed',
        PaymentUiStatus.reversed,
      );
      check({
        ..._base,
        'confirmation_status': 'payment_received',
        'payment_id': 'synthetic-payment',
      }, PaymentUiStatus.paymentLinked);
      for (final raw in [
        'matched',
        'confirmed',
        'paid',
        'failed',
        'refused',
        'cancelled',
        'unknown',
      ]) {
        check(Map.of(_base)..['status'] = raw, PaymentUiStatus.needsReview);
      }
      check(Map.of(_base)..['status'] = 'expired', PaymentUiStatus.expired);
    },
  );

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
