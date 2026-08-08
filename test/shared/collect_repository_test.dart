import 'package:collect_app/app/env/app_env.dart';
import 'package:collect_app/features/collections/group_link_screen.dart';
import 'package:collect_app/features/collections/group_share_service.dart';
import 'package:collect_app/features/home/app_share_service.dart';
import 'package:collect_app/core/security/sms_access_channel.dart';
import 'package:collect_app/core/security/hash_utils.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/providers/collect_app_state.dart';
import 'package:collect_app/shared/repositories/collect_offline_cache.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/utils/support_contact.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('App Review access is isolated to seeded fixture data', () async {
    final repo = CollectRepository.appReviewDemo();

    final profile = await repo.signInForAppReview(phone: '+250700000001');

    expect(profile.whatsappPhone, '+250700000001');
    expect(profile.momoNumber, '0788123456');
    expect(repo.isLive, isFalse);
    expect(repo.state.collections, isNotEmpty);
    expect(repo.state.contributions, isNotEmpty);
  });

  test('normal repositories reject the isolated App Review path', () {
    final repo = CollectRepository.fixture(seeded: false);

    expect(repo.signInForAppReview(phone: '+250700000001'), throwsStateError);
  });

  test('group creation stores receiver MoMo from profile flow', () async {
    final repo = CollectRepository.fixture(seeded: false);
    await repo.signInWithOtp(phone: '+250788123456', otp: '123456');
    final collection = await repo.createCollection(
      title: 'Family group',
      description: 'Family support',
      receiverMomoNumber: '0788123456',
      collectionType: CollectionType.wedding,
    );

    expect(collection.receiverMomoNumber, '0788123456');
    expect(collection.collectionType, CollectionType.wedding);
  });

  test('group creation accepts receiver MoMo without profile setup', () async {
    final repo = CollectRepository();

    final collection = await repo.createCollection(
      title: 'Parish support',
      description: 'Community support',
      receiverMomoNumber: '0789123456',
      collectionType: CollectionType.church,
    );

    expect(repo.state.currentProfile, isNull);
    expect(collection.creatorUserId, 'local-group-owner');
    expect(collection.receiverMomoNumber, '0789123456');
    expect(collection.collectionType, CollectionType.church);
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

  test('runtime config maps public backend settings with defaults', () {
    final config = CollectRuntimeConfig.fromJson(const {
      'brand': {
        'display_name': 'Collect Rwanda',
        'legal_name': 'IKANISA Rwanda Ltd.',
        'public_url': 'https://collect.example',
        'admin_url': '',
      },
      'support_channels': [
        {
          'key': 'support.whatsapp',
          'value': '250700000001',
          'display_value': '+250 700 000 001',
        },
        {'key': 'support.email', 'value': 'support@example.com'},
      ],
      'payment_entrypoints': [
        {
          'key': 'rw.mtn_momo.ussd.collect_2000',
          'code': '*182*8*1*00000*2000#',
          'display_code': '*182*8*1*00000*2000#',
        },
      ],
    });

    expect(config.brandDisplayName, 'Collect Rwanda');
    expect(config.legalName, 'IKANISA Rwanda Ltd.');
    expect(config.publicUrl, 'https://collect.example');
    expect(config.adminUrl, collectDefaultAdminUrl);
    expect(config.whatsAppSupportPhone, '250700000001');
    expect(config.whatsAppSupportDisplay, '+250 700 000 001');
    expect(config.supportEmail, 'support@example.com');
    expect(config.ussdDisplayCode, '*182*8*1*00000*2000#');
    expect(
      collectWhatsAppSupportUri(phone: config.whatsAppSupportPhone).toString(),
      'https://wa.me/250700000001',
    );
  });

  test(
    'collection model accepts public visibility and string region aliases',
    () {
      final collection = CollectCollection.fromJson(const {
        'id': 'col-diaspora',
        'slug': 'diaspora-building-fund',
        'creator_user_id': 'owner',
        'title': 'Diaspora building fund',
        'description': 'Public donor support',
        'collection_type': 'church',
        'diaspora_regions': 'eu',
        'visibility': 'public_approved',
        'created_at': '2026-06-22T08:00:00Z',
      });

      expect(collection.isPublic, isTrue);
      expect(collection.diasporaRegions, ['eu']);
      expect(collection.collectionType, CollectionType.church);
    },
  );

  test('group creation accepts MoMo Pay code receiver mode', () async {
    final repo = CollectRepository.fixture(seeded: false);
    await repo.signInWithOtp(phone: '+250788123456', otp: '123456');
    final collection = await repo.createCollection(
      title: 'Merchant group',
      description: 'MoMo Pay collections',
      receiverMomoNumber: '12345',
      receiverLabel: 'MoMo code',
      receiverIsMomoPayCode: true,
    );

    expect(collection.receiverMomoNumber, '12345');
    expect(collection.receiverDisplayLabel, 'MoMo code');
  });

  test('group creation rejects invalid MoMo Pay receiver codes', () async {
    final repo = CollectRepository.fixture(seeded: false);
    await repo.signInWithOtp(phone: '+250788123456', otp: '123456');

    expect(
      repo.createCollection(
        title: 'Merchant group',
        description: 'MoMo Pay collections',
        receiverMomoNumber: '12',
        receiverIsMomoPayCode: true,
      ),
      throwsA(isA<FormatException>()),
    );
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
      expect(profile.momoNumber, isNull);
      expect(profile.publicId, matches(RegExp(r'^[0-9]{6}$')));
    },
  );

  test('non-MTN Rwanda WhatsApp sign-in does not auto-fill MoMo', () async {
    final repo = CollectRepository.fixture(seeded: false);
    final profile = await repo.signInWithOtp(
      phone: '+250720000001',
      otp: '123456',
    );

    expect(profile.whatsappPhone, '+250720000001');
    expect(profile.momoNumber, isNull);
  });

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

  test('payment intent creation reuses an active matching request', () async {
    final repo = CollectRepository.fixture();
    final before = repo.state.paymentIntents.length;

    final intent = await repo.createPaymentIntent(
      const PaymentIntentDraft(collectionId: 'col-church', amountRwf: 15000),
    );

    expect(intent.id, 'intent-render');
    expect(repo.state.paymentIntents, hasLength(before));
  });

  test('fixture state includes payment intent for render evidence routes', () {
    final repo = CollectRepository.fixture();
    final intent = repo.intentById('intent-render');

    expect(intent.collectionId, 'col-church');
    expect(intent.expectedAmountRwf, 15000);
    expect(intent.receiverLabel, 'St Michel treasury');
    expect(intent.receiverMomoNumber, '0788123456');
    expect(intent.senderPhoneHash, HashUtils.phoneHash('0788123456'));
    expect(intent.status, 'pending');
    expect(intent.expiresAt.isAfter(DateTime.now()), isTrue);
  });

  test('fixture evidence clock produces deterministic rendered timestamps', () {
    final fixtureNow = DateTime.utc(2026, 7, 24, 21);
    final repo = CollectRepository.fixture(fixtureNow: fixtureNow);

    expect(
      repo.state.collections.first.createdAt,
      fixtureNow.subtract(const Duration(days: 3)),
    );
    expect(
      repo.state.paymentIntents.single.createdAt,
      fixtureNow.subtract(const Duration(minutes: 8)),
    );
    expect(
      repo.state.paymentIntents.single.expiresAt,
      fixtureNow.add(const Duration(hours: 23)),
    );
    expect(repo.state.contributions.map((item) => item.createdAt), [
      fixtureNow.subtract(const Duration(hours: 5)),
      fixtureNow.subtract(const Duration(hours: 2)),
    ]);
  });

  test('fixture can opt into dense deterministic performance data', () {
    final fixtureNow = DateTime.utc(2026, 7, 25, 4);
    final repo = CollectRepository.fixture(
      fixtureNow: fixtureNow,
      fixtureCollectionCount: 24,
      fixtureContributionCount: 80,
    );

    expect(repo.state.collections, hasLength(24));
    expect(repo.state.contributions, hasLength(80));
    expect(repo.state.collections.last.id, 'col-fixture-24');
    expect(repo.state.contributions.last.id, 'pay-fixture-80');
    expect(
      repo.state.contributions.last.createdAt,
      fixtureNow.subtract(const Duration(minutes: 78 * 7)),
    );
  });

  test(
    'offline snapshot persists profile groups ledger and payment state',
    () async {
      SharedPreferences.setMockInitialValues({});
      const cache = CollectOfflineCache(
        preferencesKey: 'collect.offline_snapshot.repository_test',
      );
      final repo = CollectRepository.fixture();
      final savedAt = DateTime.utc(2026, 6, 30, 8, 15);

      await cache.save(
        CollectOfflineSnapshot(
          savedAt: savedAt,
          currentProfile: repo.state.currentProfile,
          collections: repo.state.collections,
          paymentIntents: repo.state.paymentIntents,
          contributions: repo.state.contributions,
        ),
      );

      final restored = await cache.read();

      expect(restored, isNotNull);
      expect(restored!.savedAt, savedAt);
      expect(restored.currentProfile?.publicId, '038491');
      expect(
        restored.collections.map((item) => item.id),
        contains('col-church'),
      );
      expect(restored.paymentIntents.single.id, 'intent-render');
      expect(restored.contributions, hasLength(2));
      expect(
        restored.contributions.any((item) => item.transactionId != null),
        isFalse,
        reason:
            'Offline cache keeps ledger totals readable without transaction IDs.',
      );
    },
  );

  test(
    'repository restores stale offline snapshot with explicit status',
    () async {
      SharedPreferences.setMockInitialValues({});
      const cache = CollectOfflineCache(
        preferencesKey: 'collect.offline_snapshot.restore_test',
      );
      final seeded = CollectRepository.fixture();
      final savedAt = DateTime.utc(2026, 6, 30, 9, 30);
      await cache.save(
        CollectOfflineSnapshot(
          savedAt: savedAt,
          currentProfile: seeded.state.currentProfile,
          collections: seeded.state.collections,
          paymentIntents: seeded.state.paymentIntents,
          contributions: seeded.state.contributions,
        ),
      );
      final repo = CollectRepository.fixture(
        seeded: false,
        offlineCache: cache,
      );

      final restored = await repo.restoreOfflineSnapshot(
        reason: 'SocketException: network is offline',
      );

      expect(restored, isTrue);
      expect(repo.state.usingStaleCache, isTrue);
      expect(repo.state.lastSuccessfulSyncAt, savedAt);
      expect(repo.state.currentProfile?.publicId, '038491');
      expect(repo.state.collections, hasLength(2));
      expect(repo.state.paymentIntents.single.id, 'intent-render');
      expect(repo.state.contributions, hasLength(2));
      expect(repo.state.lastError, contains('SocketException'));

      final container = ProviderContainer(
        overrides: [collectRepositoryProvider.overrideWith((ref) => repo)],
      );
      addTearDown(container.dispose);

      expect(
        container.read(connectivityStatusProvider),
        ConnectivityStatus.offlineStale,
      );
      expect(
        container.read(offlineSnapshotStatusProvider).label,
        contains('Offline saved data'),
      );
    },
  );

  test(
    'controlled backend loss preserves auth group contribution and recovery state',
    () async {
      SharedPreferences.setMockInitialValues({});
      const cache = CollectOfflineCache(
        preferencesKey: 'collect.offline_snapshot.backend_network_loss_uat',
      );
      final online = _ControlledNetworkRepository(offlineCache: cache);
      await online.signInWithOtp(phone: '+250788123456', otp: '123456');
      await online.updateProfile(momoNumber: '+250788123456');
      final created = await online.createCollection(
        title: 'Network UAT group',
        description: 'Controlled backend loss and recovery coverage',
        receiverMomoNumber: '0788123456',
      );
      final intent = await online.createPaymentIntent(
        const PaymentIntentDraft(collectionId: 'col-church', amountRwf: 21000),
      );
      final savedAt = DateTime.utc(2026, 7, 30, 10, 15);
      await cache.save(_snapshotFrom(online.state, savedAt: savedAt));

      final offline = CollectRepository(offlineCache: cache);
      final restored = await offline.restoreOfflineSnapshot(
        reason: 'SocketException: controlled backend unavailable',
      );

      expect(restored, isTrue);
      expect(offline.state.usingStaleCache, isTrue);
      expect(offline.state.lastSuccessfulSyncAt, savedAt);
      expect(offline.state.lastError, contains('SocketException'));
      expect(offline.state.currentProfile?.publicId, '038491');
      expect(
        offline.state.collections.map((item) => item.id),
        containsAll(<String>['col-church', created.id]),
      );
      expect(
        offline.state.paymentIntents.map((item) => item.id),
        contains(intent.id),
      );
      expect(offline.contributionsFor('col-church'), hasLength(2));
      expect(
        offline.state.contributions.any((item) => item.transactionId != null),
        isFalse,
        reason:
            'Stale-cache recovery keeps ledger status readable without retaining raw transaction IDs.',
      );

      final container = ProviderContainer(
        overrides: [collectRepositoryProvider.overrideWith((ref) => offline)],
      );
      addTearDown(container.dispose);

      expect(
        container.read(profileReadinessProvider).readyForContribution,
        isTrue,
      );
      expect(
        container.read(connectivityStatusProvider),
        ConnectivityStatus.offlineStale,
      );
      expect(
        container.read(realtimeSyncStatusProvider),
        RealtimeSyncStatus.needsAttention,
      );
      expect(
        container.read(
          paymentUiStatusProvider(
            PaymentStatusKey(collectionId: 'col-church', intentId: intent.id),
          ),
        ),
        PaymentUiStatus.pending,
      );
      expect(
        container.read(offlineSnapshotStatusProvider).label,
        contains('Offline saved data'),
      );

      await expectLater(
        offline.createPaymentIntent(
          const PaymentIntentDraft(collectionId: 'col-church', amountRwf: 5000),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Sign in before starting a contribution'),
          ),
        ),
      );
    },
  );

  test(
    'controlled backend restoration clears stale state and keeps newest sync',
    () async {
      SharedPreferences.setMockInitialValues({});
      const cache = CollectOfflineCache(
        preferencesKey: 'collect.offline_snapshot.backend_network_restore_uat',
      );
      final backend = _ControlledNetworkRepository(offlineCache: cache);
      final initialSyncAt = DateTime.utc(2026, 7, 30, 11);
      await cache.save(_snapshotFrom(backend.state, savedAt: initialSyncAt));

      final interrupted = CollectRepository(offlineCache: cache);
      expect(
        await interrupted.restoreOfflineSnapshot(
          reason: 'Network connection lost during group sync',
        ),
        isTrue,
      );
      expect(interrupted.state.usingStaleCache, isTrue);

      await backend.updateCollectionReceiver(
        collectionId: 'col-church',
        receiverMomoNumber: '0788000111',
        receiverLabel: 'Restored treasury',
      );
      final syncedIntent = await backend.createPaymentIntent(
        const PaymentIntentDraft(collectionId: 'col-church', amountRwf: 31000),
      );
      final restoredSyncAt = DateTime.utc(2026, 7, 30, 11, 5);
      final authoritativeSnapshot = _snapshotFrom(
        backend.state,
        savedAt: restoredSyncAt,
      );
      final recovered = _ControlledNetworkRepository(seeded: false);
      recovered.applyAuthoritativeSync(authoritativeSnapshot);

      final container = ProviderContainer(
        overrides: [collectRepositoryProvider.overrideWith((ref) => recovered)],
      );
      addTearDown(container.dispose);

      expect(recovered.state.usingStaleCache, isFalse);
      expect(recovered.state.lastError, isNull);
      expect(recovered.state.lastSuccessfulSyncAt, restoredSyncAt);
      expect(
        recovered.collectionById('col-church').receiverMomoNumber,
        '0788000111',
      );
      expect(
        recovered.collectionById('col-church').receiverDisplayLabel,
        'Restored treasury',
      );
      expect(recovered.intentById(syncedIntent.id).expectedAmountRwf, 31000);
      expect(recovered.contributionsFor('col-church'), hasLength(2));
      expect(
        container.read(connectivityStatusProvider),
        ConnectivityStatus.online,
      );
      expect(
        container.read(realtimeSyncStatusProvider),
        RealtimeSyncStatus.current,
      );
      expect(container.read(offlineSnapshotStatusProvider).label, 'Live data');
    },
  );

  test('fixture state includes backend notification events', () {
    final repo = CollectRepository.fixture();
    final events = repo.state.notificationEvents;

    expect(events, hasLength(3));
    expect(events.first.type, 'contribution_confirmed');
    expect(events.first.title, 'Contribution confirmed');
    expect(events.where((event) => event.unread), hasLength(2));
  });

  test(
    'notification event parser and mark-read state are implemented',
    () async {
      final event = NotificationEvent.fromJson(const {
        'id': 'notif-1',
        'user_id': 'user-1',
        'collection_id': 'col-1',
        'type': 'app_update',
        'title': 'Collect updated',
        'body': 'Group records refresh after confirmed MoMo SMS matching.',
        'deep_link': '/home',
        'status': 'queued',
        'created_at': '2026-06-26T12:00:00Z',
      });

      expect(event.unread, isTrue);
      expect(event.deepLink, '/home');

      final repo = CollectRepository.fixture();
      await repo.markNotificationRead('notif-app-update');
      final marked = repo.state.notificationEvents.singleWhere(
        (item) => item.id == 'notif-app-update',
      );

      expect(marked.status, 'read');
      expect(marked.unread, isFalse);
      expect(marked.readAt, isNotNull);
    },
  );

  test(
    'payment intent exposes receiver context without manual instructions',
    () async {
      final repo = CollectRepository.fixture();
      final intent = await repo.createPaymentIntent(
        const PaymentIntentDraft(collectionId: 'col-church', amountRwf: 7500),
      );

      expect(intent.expectedAmountRwf, 7500);
      expect(intent.receiverMomoNumber, '0788123456');
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

    expect(intent.receiverMomoNumber, '0788123456');
    expect(intent.senderPhoneHash, 'sender-hash');
  });

  test('collection model localizes Supabase receiver MoMo rows', () {
    final collection = CollectCollection.fromJson(const {
      'id': 'col-1',
      'slug': 'parish-support',
      'creator_user_id': 'owner',
      'title': 'Parish support',
      'description': 'Support',
      'collection_receivers': [
        {'momo_number': '+250789123456', 'label': 'Treasury'},
      ],
      'created_at': '2026-06-01T12:00:00Z',
    });

    expect(collection.receiverMomoNumber, '0789123456');
  });

  test('profile model localizes Supabase MoMo number rows', () {
    final profile = CollectProfile.fromJson(const {
      'id': 'user-1',
      'public_id': '123456',
      'whatsapp_phone': '+250789123456',
      'momo_number': '+250789123456',
    });

    expect(profile.momoNumber, '0789123456');
    expect(profile.whatsappPhone, '+250789123456');
  });

  test('MTN WhatsApp sign-in autofills local profile MoMo', () async {
    final repo = CollectRepository.fixture(seeded: false);
    await repo.signInWithOtp(phone: '+250788123456', otp: '123456');
    final collection = await repo.createCollection(
      title: 'Family group',
      description: 'Family support',
      receiverMomoNumber: '0788123456',
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
            id: 'sms-1',
            rawSender: 'MTN MOMO',
            rawBody: 'You have received 5,000 RWF. TxId ABCD1234.',
            receivedAtDevice: '1',
          ),
        ],
      );
      final repo = CollectRepository.fixture(smsAccessChannel: channel);

      expect(await repo.syncPendingSmsAccess(), 0);
      expect(channel.readCalls, 0);

      await repo.setSmsAccess(true);

      expect(await repo.syncPendingSmsAccess(), 1);
      expect(channel.readCalls, 1);
      expect(channel.acknowledgedIds, ['sms-1']);
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
      receiverMomoNumber: '0788000111',
      receiverLabel: 'Team treasurer',
    );
    expect(collection.receiverMomoNumber, '0788000111');
    expect(collection.receiverDisplayLabel, 'Team treasurer');

    await repo.signOut();
    expect(repo.state.currentProfile, isNull);
    expect(repo.state.collections, isEmpty);
  });

  test('local group profile update accepts MoMo code receivers', () async {
    final repo = CollectRepository.fixture();

    final collection = await repo.updateCollectionProfile(
      collectionId: 'col-team',
      title: 'Team savings',
      description: 'Team monthly support',
      receiverMomoNumber: '123456',
      receiverLabel: 'MoMo code',
      recurringCadence: 'weekly',
      collectionType: CollectionType.ikimina,
      categorySubtype: 'group_savings',
      purposeLabel: 'Save together',
      isPublic: true,
      receiverIsMomoPayCode: true,
    );

    expect(collection.receiverMomoNumber, '123456');
    expect(collection.receiverDisplayLabel, 'MoMo code');
    expect(collection.recurringCadence, 'weekly');
    expect(collection.isPublic, isTrue);
  });

  test(
    'archiving removes a group from active providers and blocks new actions',
    () async {
      final repo = CollectRepository.fixture();
      final container = ProviderContainer(
        overrides: [collectRepositoryProvider.overrideWith((ref) => repo)],
      );
      addTearDown(container.dispose);

      expect(
        container.read(activeCollectionsProvider).map((item) => item.id),
        contains('col-church'),
      );

      await repo.archiveCollection('col-church');

      expect(repo.collectionById('col-church').isArchived, isTrue);
      expect(
        container.read(activeCollectionsProvider).map((item) => item.id),
        isNot(contains('col-church')),
      );
      expect(
        container.read(homeCollectionsProvider).map((item) => item.id),
        isNot(contains('col-church')),
      );
      await expectLater(
        repo.createPaymentIntent(
          const PaymentIntentDraft(collectionId: 'col-church', amountRwf: 5000),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('archived'),
          ),
        ),
      );
      await expectLater(
        repo.inviteCollectionAdmin(
          collectionId: 'col-church',
          publicId: '123456',
        ),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        repo.transferCollectionOwnership(
          collectionId: 'col-church',
          publicId: '123456',
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'owner actions reject self-targets and enforce the new owner boundary',
    () async {
      final repo = CollectRepository.fixture();

      await expectLater(
        repo.inviteCollectionAdmin(
          collectionId: 'col-church',
          publicId: '038491',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('already own'),
          ),
        ),
      );
      await expectLater(
        repo.transferCollectionOwnership(
          collectionId: 'col-church',
          publicId: '038491',
        ),
        throwsA(isA<FormatException>()),
      );

      await repo.transferCollectionOwnership(
        collectionId: 'col-church',
        publicId: '123456',
      );

      expect(
        repo.collectionById('col-church').creatorUserId,
        'collect-id-123456',
      );
      await expectLater(
        repo.archiveCollection('col-church'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Only the group owner'),
          ),
        ),
      );
    },
  );

  test(
    'account deletion requires a reason before creating a request',
    () async {
      final repo = CollectRepository.fixture();

      await expectLater(
        repo.requestAccountDeletion(reason: '  '),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('deletion reason'),
          ),
        ),
      );
      await repo.requestAccountDeletion(reason: 'No longer needed');
      expect(repo.state.currentProfile, isNotNull);
    },
  );
}

class _FakeSmsAccessChannel extends SmsAccessChannel {
  _FakeSmsAccessChannel({required this.pending, this.grant = true});

  final List<SmsAccessEnvelope> pending;
  final bool grant;
  var enabled = false;
  var readCalls = 0;
  final List<String> acknowledgedIds = [];

  @override
  Future<bool> setEnabled(bool enabled) async {
    this.enabled = enabled && grant;
    return this.enabled;
  }

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<SmsAccessStatus> status() async => SmsAccessStatus(
    supported: true,
    declared: true,
    enabled: enabled,
    granted: enabled,
    requestedBefore: enabled,
    shouldShowRationale: false,
    permanentlyDenied: false,
  );

  @override
  Future<List<SmsAccessEnvelope>> readPendingSms() async {
    readCalls += 1;
    return pending;
  }

  @override
  Future<bool> acknowledgePendingSms(Iterable<String> ids) async {
    acknowledgedIds.addAll(ids);
    return true;
  }
}

class _ControlledNetworkRepository extends CollectRepository {
  _ControlledNetworkRepository({super.seeded = true, super.offlineCache})
    : super.fixture();

  void applyAuthoritativeSync(CollectOfflineSnapshot snapshot) {
    state = state.copyWith(
      currentProfile: snapshot.currentProfile,
      collections: snapshot.collections,
      paymentIntents: snapshot.paymentIntents,
      contributions: snapshot.contributions,
      isLoading: false,
      usingStaleCache: false,
      lastSuccessfulSyncAt: snapshot.savedAt,
    );
  }
}

CollectOfflineSnapshot _snapshotFrom(
  CollectState state, {
  required DateTime savedAt,
}) {
  return CollectOfflineSnapshot(
    savedAt: savedAt,
    currentProfile: state.currentProfile,
    collections: state.collections,
    paymentIntents: state.paymentIntents,
    contributions: state.contributions,
  );
}
