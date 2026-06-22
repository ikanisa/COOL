import 'package:collect_app/app/env/app_env.dart';
import 'package:collect_app/features/collections/group_link_screen.dart';
import 'package:collect_app/features/collections/group_share_service.dart';
import 'package:collect_app/features/home/app_share_service.dart';
import 'package:collect_app/core/security/sms_access_channel.dart';
import 'package:collect_app/core/security/hash_utils.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/providers/collect_app_state.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('group creation stores receiver MoMo from profile flow', () async {
    final repo = CollectRepository.fixture(seeded: false);
    await repo.signInWithOtp(phone: '+250788123456', otp: '123456');
    final collection = await repo.createCollection(
      title: 'Family group',
      description: 'Family support',
      receiverMomoNumber: '+250788123456',
      collectionType: CollectionType.wedding,
    );

    expect(collection.receiverMomoNumber, '+250788123456');
    expect(collection.collectionType, CollectionType.wedding);
  });

  test('collection type model maps approved market categories', () {
    final collection = CollectCollection.fromJson(const {
      'id': 'col-sport',
      'slug': 'rayon-away-day',
      'creator_user_id': 'owner',
      'title': 'Rayon away day support',
      'description': 'Fan club travel support',
      'collection_type': 'sport',
      'category_subtype': 'fan_club',
      'purpose_label': 'Away travel',
      'diaspora_enabled': true,
      'diaspora_regions': ['eu', 'us'],
      'moderation_status': 'approved',
      'created_at': '2026-06-22T08:00:00Z',
    });

    expect(collection.collectionType, CollectionType.sport);
    expect(collection.categorySubtype, 'fan_club');
    expect(collection.purposeLabel, 'Away travel');
    expect(collection.diasporaEnabled, isTrue);
    expect(collection.diasporaRegions, ['eu', 'us']);
    expect(collection.moderationStatus, 'approved');
  });

  test('group creation accepts MoMo Pay code receiver mode', () async {
    final repo = CollectRepository.fixture(seeded: false);
    await repo.signInWithOtp(phone: '+250788123456', otp: '123456');
    final collection = await repo.createCollection(
      title: 'Merchant group',
      description: 'MoMo Pay collections',
      receiverMomoNumber: '12345',
      receiverLabel: 'MoMo Pay code',
      receiverIsMomoPayCode: true,
    );

    expect(collection.receiverMomoNumber, '12345');
    expect(collection.receiverDisplayLabel, 'MoMo Pay code');
  });

  test(
    'WhatsApp OTP sign-in accepts non-Rwanda international numbers',
    () async {
      final repo = CollectRepository.fixture(seeded: false);
      final profile = await repo.signInWithOtp(
        phone: '+1 (415) 555-0100',
        otp: '123456',
      );

      expect(profile.whatsappPhone, '+14155550100');
      expect(profile.publicId, matches(RegExp(r'^[0-9]{6}$')));
    },
  );

  test('payment intent stays pending for automated SMS allocation', () async {
    final repo = CollectRepository.fixture();
    final collection = repo.state.collections.first;
    final intent = await repo.createPaymentIntent(
      PaymentIntentDraft(collectionId: collection.id, amountRwf: 5000),
    );

    expect(intent.status, 'pending');
    expect(intent.expectedAmountRwf, 5000);
    expect(repo.contributionsFor(collection.id), hasLength(2));
  });

  test('fixture state includes payment intent for render evidence routes', () {
    final repo = CollectRepository.fixture();
    final intent = repo.intentById('intent-render');

    expect(intent.collectionId, 'col-church');
    expect(intent.expectedAmountRwf, 15000);
    expect(intent.receiverLabel, 'St Michel treasury');
    expect(intent.receiverMomoNumber, '+250788123456');
    expect(intent.senderPhoneHash, HashUtils.phoneHash('0788123456'));
    expect(intent.status, 'pending');
    expect(intent.expiresAt.isAfter(DateTime.now()), isTrue);
  });

  test(
    'payment intent exposes receiver context without manual instructions',
    () async {
      final repo = CollectRepository.fixture();
      final intent = await repo.createPaymentIntent(
        const PaymentIntentDraft(collectionId: 'col-church', amountRwf: 7500),
      );

      expect(intent.expectedAmountRwf, 7500);
      expect(intent.receiverMomoNumber, '+250788123456');
      expect(intent.receiverLabel, 'St Michel treasury');
      expect(intent.senderPhoneHash, HashUtils.phoneHash('0788123456'));
    },
  );

  test('payment intent model preserves Supabase sender phone hash', () {
    final intent = PaymentIntentModel.fromJson(const {
      'id': 'intent-1',
      'collection_id': 'col-1',
      'expected_amount_rwf': 5000,
      'receiver_momo_number': '+250788123456',
      'receiver_label': 'Treasury',
      'network': 'mtn_momo',
      'sender_phone_hash': 'sender-hash',
      'status': 'pending',
      'created_at': '2026-06-01T12:00:00Z',
      'expires_at': '2026-06-02T12:00:00Z',
    });

    expect(intent.senderPhoneHash, 'sender-hash');
  });

  test('MTN WhatsApp sign-in autofills local profile MoMo', () async {
    final repo = CollectRepository.fixture(seeded: false);
    await repo.signInWithOtp(phone: '+250788123456', otp: '123456');
    final collection = await repo.createCollection(
      title: 'Family group',
      description: 'Family support',
      receiverMomoNumber: '+250788123456',
    );
    final container = ProviderContainer(
      overrides: [collectRepositoryProvider.overrideWith((ref) => repo)],
    );
    addTearDown(container.dispose);

    expect(container.read(profileReadinessProvider).readyForContribution, true);
    expect(repo.state.currentProfile?.momoNumber, '0788123456');

    await repo.updateProfile(momoNumber: '+250788123456');
    expect(repo.state.currentProfile?.momoNumber, '0788123456');

    await repo.updateProfile(momoPayCode: '123456');
    expect(repo.state.currentProfile?.momoNumber, '0788123456');
    expect(repo.state.currentProfile?.momoPayCode, '123456');

    expect(container.read(profileReadinessProvider).readyForContribution, true);
    expect(
      await repo.createPaymentIntent(
        PaymentIntentDraft(collectionId: collection.id, amountRwf: 5000),
      ),
      isA<PaymentIntentModel>(),
    );
  });

  test('shared group link opens by slug', () async {
    final repo = CollectRepository.fixture();
    final collection = await repo.joinGroupBySlug('st-michel-building-fund');

    expect(collection.id, 'col-church');
    expect(collection.title, 'St Michel building fund');
  });

  test('group share links use Collect Ikanisa domain', () {
    final repo = CollectRepository.fixture();
    final collection = repo.collectionById('col-church');
    const env = AppEnv(
      supabaseUrl: '',
      supabaseAnonKey: '',
      publicUrl: '',
      adminAppUrl: '',
      enableSmsReader: false,
      enableAndroidSmsAccess: false,
      enableAdminPanel: false,
      enableAdminDevTools: false,
      authCaptchaEnabled: false,
      authCaptchaProvider: '',
      authCaptchaSiteKey: '',
    );

    expect(
      groupDeepLinkFor(env, collection),
      'https://collect.ikanisa.com/c/st-michel-building-fund',
    );
    expect(
      groupShareMessageFor(env, collection),
      'Join St Michel building fund for offering and donations on Collect: https://collect.ikanisa.com/c/st-michel-building-fund',
    );
    expect(
      collectGroupSlugFromInput(
        'https://collect.ikanisa.com/c/st-michel-building-fund',
      ),
      'st-michel-building-fund',
    );
  });

  test('app share links use Collect invite route without group data', () {
    final repo = CollectRepository.fixture();
    const env = AppEnv(
      supabaseUrl: '',
      supabaseAnonKey: '',
      publicUrl: '',
      adminAppUrl: '',
      enableSmsReader: false,
      enableAndroidSmsAccess: false,
      enableAdminPanel: false,
      enableAdminDevTools: false,
      authCaptchaEnabled: false,
      authCaptchaProvider: '',
      authCaptchaSiteKey: '',
    );
    const customEnv = AppEnv(
      supabaseUrl: '',
      supabaseAnonKey: '',
      publicUrl: 'https://collect.example.com/',
      adminAppUrl: '',
      enableSmsReader: false,
      enableAndroidSmsAccess: false,
      enableAdminPanel: false,
      enableAdminDevTools: false,
      authCaptchaEnabled: false,
      authCaptchaProvider: '',
      authCaptchaSiteKey: '',
    );

    expect(
      collectAppInviteLinkFor(env, repo.state.currentProfile),
      'https://collect.ikanisa.com/invite/038491',
    );
    expect(
      collectAppInviteLinkFor(env, null),
      'https://collect.ikanisa.com/app',
    );
    expect(
      collectAppInviteLinkFor(customEnv, repo.state.currentProfile),
      'https://collect.example.com/invite/038491',
    );
    expect(
      collectAppShareMessageFor(env, repo.state.currentProfile),
      'Join me on Collect for group contributions in Rwanda: '
      'https://collect.ikanisa.com/invite/038491',
    );
    expect(
      collectAppShareMessageFor(env, repo.state.currentProfile),
      isNot(contains('St Michel building fund')),
    );
  });

  test(
    'pending Android SMS sync drains only when SMS access is enabled',
    () async {
      final channel = _FakeSmsAccessChannel(
        pending: const [
          SmsAccessEnvelope(
            rawSender: 'MTN MOMO',
            rawBody: 'You have received 5,000 RWF. TxId ABCD1234.',
            receivedAtDevice: '1',
          ),
        ],
      );
      final repo = CollectRepository.fixture(smsAccessChannel: channel);

      expect(await repo.syncPendingSmsAccess(), 0);
      expect(channel.drainCalls, 0);

      await repo.setSmsAccess(true);

      expect(await repo.syncPendingSmsAccess(), 1);
      expect(channel.drainCalls, 1);
      expect(repo.contributionsFor('col-church'), hasLength(2));
    },
  );

  test('SMS access denial keeps group receiver ingestion disabled', () async {
    final repo = CollectRepository.fixture(
      smsAccessChannel: _FakeSmsAccessChannel(pending: const [], grant: false),
    );

    expect(await repo.setSmsAccess(true), isFalse);
    expect(repo.state.smsAccessEnabled, isFalse);
    expect(repo.state.smsAccessDenied, isTrue);
  });

  test('local production interfaces expose members and owner health', () async {
    final repo = CollectRepository.fixture();

    final members = await repo.membersForCollection('col-church');
    final health = await repo.ownerHealthFor('col-church');

    expect(members.single.safeLabel, 'Collect ID 038491');
    expect(health.receiverConfigured, isTrue);
    expect(health.pendingPaymentIntents, 1);
  });

  test('local receiver update and sign out mutate safe client state', () async {
    final repo = CollectRepository.fixture();

    final collection = await repo.updateCollectionReceiver(
      collectionId: 'col-team',
      receiverMomoNumber: '+250788000111',
      receiverLabel: 'Team treasurer',
    );
    expect(collection.receiverMomoNumber, '+250788000111');
    expect(collection.receiverDisplayLabel, 'Team treasurer');

    await repo.signOut();
    expect(repo.state.currentProfile, isNull);
    expect(repo.state.collections, isEmpty);
  });
}

class _FakeSmsAccessChannel extends SmsAccessChannel {
  _FakeSmsAccessChannel({required this.pending, this.grant = true});

  final List<SmsAccessEnvelope> pending;
  final bool grant;
  var enabled = false;
  var drainCalls = 0;

  @override
  Future<bool> setEnabled(bool enabled) async {
    this.enabled = enabled && grant;
    return this.enabled;
  }

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<List<SmsAccessEnvelope>> drainPendingSms() async {
    drainCalls += 1;
    return pending;
  }
}
