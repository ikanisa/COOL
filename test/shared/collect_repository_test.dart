import '../fixtures/collect_repository_fixture.dart';

import 'package:collect_app/core/security/sms_access_channel.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingSmsAccess extends SmsAccessChannel {
  final List<bool> changes = [];

  @override
  Future<bool> setEnabled(bool enabled, {String? ownerUserId}) async {
    changes.add(enabled);
    return true;
  }
}

class _SwitchableFixtureRepository extends FixtureCollectRepository {
  _SwitchableFixtureRepository({required super.smsAccessChannel});

  void setSmsChoice(bool enabled) {
    state = state.copyWith(smsAccessEnabled: enabled);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('fixture public groups use Rwanda MoMo', () {
    final repository = FixtureCollectRepository();
    final publicGroups = repository.state.collections.where((g) => g.isPublic);
    expect(publicGroups, isNotEmpty);
    expect(publicGroups.every((g) => g.receiverNetwork == 'mtn_momo'), isTrue);
    expect(publicGroups.every((g) => g.settlementCurrency == 'RWF'), isTrue);
    expect(
      publicGroups.every(
        (g) => {
          'rwanda_momo',
          'unavailable',
        }.contains(g.contributionRailFor(null)),
      ),
      isTrue,
    );
  });

  test('Rwanda contribution request creates a pending MoMo intent', () async {
    final repository = FixtureCollectRepository();
    final group = repository.state.collections.firstWhere((g) => g.isPublic);
    final intent = await repository.createPaymentIntent(
      PaymentIntentDraft(collectionId: group.id, amountRwf: 5000),
    );
    expect(intent.currency, 'RWF');
    expect(intent.rail, 'rwanda_momo');
    expect(intent.receiverMomoNumber, isNotEmpty);
    expect(intent.status, 'pending');
  });

  test(
    'active Rwanda MoMo request with same group and amount is reused',
    () async {
      final repository = FixtureCollectRepository(
        fixtureNow: DateTime.now().toUtc(),
      );
      const draft = PaymentIntentDraft(
        collectionId: 'qa-private-group',
        amountRwf: 9876,
      );
      final first = await repository.createPaymentIntent(draft);
      final second = await repository.createPaymentIntent(draft);
      expect(second.id, first.id);
      expect(
        repository.state.paymentIntents.where((i) => i.id == first.id),
        hasLength(1),
      );
    },
  );

  test('foreign profile cannot initiate a contribution', () async {
    final repository = FixtureCollectRepository(
      profileOverride: const CollectProfile(
        id: 'foreign-profile',
        publicId: '123456',
        whatsappPhone: '+250788123456',
        countryCode: 'GB',
        currencyCode: 'GBP',
        momoProvider: 'mtn_momo',
        momoNumber: '0788123456',
      ),
    );
    await expectLater(
      repository.createPaymentIntent(
        const PaymentIntentDraft(
          collectionId: 'qa-private-group',
          amountRwf: 5000,
        ),
      ),
      throwsFormatException,
    );
  });

  for (final enabled in [true, false]) {
    test('profile change preserves SMS choice $enabled', () async {
      final smsAccess = _RecordingSmsAccess();
      final repository = _SwitchableFixtureRepository(
        smsAccessChannel: smsAccess,
      );
      repository.setSmsChoice(enabled);
      final updated = await repository.updateCurrentProfile(
        countryCode: 'RW',
        momoProvider: 'airtel_money',
        momoNumber: '0720000001',
      );
      expect(updated.momoNumber, '0720000001');
      expect(repository.state.smsAccessEnabled, enabled);
      expect(smsAccess.changes, isEmpty);
      repository.dispose();
    });
  }

  test('member group creation stays private and uses MoMo receiver', () async {
    final repository = FixtureCollectRepository();
    final group = await repository.createCollectionWithVerifiedReceiver(
      title: 'RWF savings circle',
      description: 'Private Rwanda MoMo group',
      receiverMomoNumber: '0788123456',
      receiverProvider: 'mtn_momo',
      isPublic: true,
    );
    expect(group.receiverMomoNumber, '0788123456');
    expect(group.isPublic, isFalse);
    expect(group.visibilityStatus, 'private');
  });

  test('non-Rwanda payment intent is rejected on parsing', () {
    expect(
      () => PaymentIntentModel.fromJson(const {
        'id': 'foreign-intent',
        'collection_id': 'qa-private-group',
        'amount_minor': 7500,
        'currency': 'EUR',
        'rail': 'diaspora_bank',
        'status': 'awaiting_transfer',
        'created_at': '2026-08-20T10:00:00Z',
      }),
      throwsFormatException,
    );
  });
}
