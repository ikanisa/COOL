import '../fixtures/collect_repository_fixture.dart';

import 'package:collect_app/core/security/sms_access_channel.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _AccountSwitchingSmsAccess extends SmsAccessChannel {
  void Function()? onDisable;
  bool suspendedAfterSwitch = false;

  @override
  Future<bool> setEnabled(bool enabled, {String? ownerUserId}) async {
    if (!enabled) onDisable?.call();
    return true;
  }

  @override
  Future<bool> suspendUnlessOwner(String? currentUserId) async {
    suspendedAfterSwitch = true;
    return true;
  }
}

class _SwitchableFixtureRepository extends FixtureCollectRepository {
  _SwitchableFixtureRepository({required super.smsAccessChannel});

  void switchTo(CollectProfile profile) {
    state = state.copyWith(currentProfile: profile);
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

  test(
    'profile save cannot overwrite an account switched during SMS disable',
    () async {
      final smsAccess = _AccountSwitchingSmsAccess();
      final repository = _SwitchableFixtureRepository(
        smsAccessChannel: smsAccess,
      );
      final previous = repository.state.currentProfile!;
      smsAccess.onDisable = () {
        repository.switchTo(
          const CollectProfile(
            id: 'different-account',
            publicId: '123456',
            whatsappPhone: '+250788111222',
            countryCode: 'RW',
            currencyCode: 'RWF',
            momoProvider: 'mtn_momo',
            momoNumber: '0788111222',
          ),
        );
      };

      await expectLater(
        repository.updateCurrentProfile(
          countryCode: 'RW',
          momoProvider: 'airtel_money',
          momoNumber: '0720000001',
        ),
        throwsStateError,
      );
      expect(repository.state.currentProfile?.id, 'different-account');
      expect(repository.state.currentProfile?.momoNumber, '0788111222');
      expect(repository.state.currentProfile?.id, isNot(previous.id));
      expect(smsAccess.suspendedAfterSwitch, isTrue);
    },
  );

  test('member group creation stays private and uses MoMo receiver', () async {
    final repository = FixtureCollectRepository();
    final group = await repository.createCollection(
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
