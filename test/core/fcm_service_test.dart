import 'dart:async';

import 'package:cool_app/core/services/fcm_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

class InMemoryPreferenceStore implements FcmPreferenceStore {
  InMemoryPreferenceStore({required this.enabled});

  bool enabled;

  @override
  Future<bool> readEnabled() async => enabled;

  @override
  Future<void> writeEnabled(bool enabled) async {
    this.enabled = enabled;
  }
}

class TokenMutation {
  const TokenMutation({
    required this.userId,
    required this.token,
    this.platform,
  });

  final String userId;
  final String token;
  final String? platform;
}

class FakeFcmTokenRepository implements FcmTokenRepository {
  final upserts = <TokenMutation>[];
  final deletes = <TokenMutation>[];

  @override
  Future<void> upsertToken({
    required String userId,
    required String token,
    required String platform,
  }) async {
    upserts.add(
      TokenMutation(userId: userId, token: token, platform: platform),
    );
  }

  @override
  Future<void> deleteToken({
    required String userId,
    required String token,
  }) async {
    deletes.add(TokenMutation(userId: userId, token: token));
  }
}

class FakeFcmMessagingClient implements FcmMessagingClient {
  FakeFcmMessagingClient({
    required this.authorizationStatus,
    this.requestResult,
    this.token,
  });

  FcmAuthorizationStatus authorizationStatus;
  final FcmAuthorizationStatus? requestResult;
  String? token;
  bool deleteTokenCalled = false;
  bool backgroundHandlerRegistered = false;
  final subscribedTopics = <String>[];
  final unsubscribedTopics = <String>[];

  final StreamController<String> _tokenRefreshController =
      StreamController<String>.broadcast();
  final StreamController<RemoteMessage> _messageController =
      StreamController<RemoteMessage>.broadcast();
  final StreamController<RemoteMessage> _messageOpenedController =
      StreamController<RemoteMessage>.broadcast();

  @override
  Future<FcmAuthorizationStatus> getAuthorizationStatus() async {
    return authorizationStatus;
  }

  @override
  Future<FcmAuthorizationStatus> requestPermission() async {
    authorizationStatus = requestResult ?? authorizationStatus;
    return authorizationStatus;
  }

  @override
  Future<String?> getToken() async => token;

  @override
  Stream<String> get onTokenRefresh => _tokenRefreshController.stream;

  @override
  Stream<RemoteMessage> get onMessage => _messageController.stream;

  @override
  Stream<RemoteMessage> get onMessageOpenedApp =>
      _messageOpenedController.stream;

  @override
  Future<RemoteMessage?> getInitialMessage() async => null;

  @override
  Future<void> deleteToken() async {
    deleteTokenCalled = true;
    token = null;
  }

  @override
  Future<void> subscribeToTopic(String topic) async {
    subscribedTopics.add(topic);
  }

  @override
  Future<void> unsubscribeFromTopic(String topic) async {
    unsubscribedTopics.add(topic);
  }

  @override
  void registerBackgroundHandler() {
    backgroundHandlerRegistered = true;
  }

  Future<void> dispose() async {
    await _tokenRefreshController.close();
    await _messageController.close();
    await _messageOpenedController.close();
  }
}

void main() {
  late InMemoryPreferenceStore preferenceStore;
  late FakeFcmMessagingClient messagingClient;
  late FakeFcmTokenRepository tokenRepository;
  late FcmService service;

  setUp(() {
    preferenceStore = InMemoryPreferenceStore(enabled: true);
    messagingClient = FakeFcmMessagingClient(
      authorizationStatus: FcmAuthorizationStatus.authorized,
      token: 'token-1',
    );
    tokenRepository = FakeFcmTokenRepository();
    service = FcmService(
      messagingClient: messagingClient,
      preferenceStore: preferenceStore,
      tokenRepository: tokenRepository,
      isFirebaseAvailable: () => true,
    );
  });

  tearDown(() async {
    service.dispose();
    await messagingClient.dispose();
  });

  test('initialize respects a persisted disabled preference', () async {
    preferenceStore.enabled = false;

    final status = await service.initialize(userId: 'user-1');

    expect(status.preferenceEnabled, isFalse);
    expect(status.isInitialized, isFalse);
    expect(tokenRepository.upserts, isEmpty);
    expect(messagingClient.backgroundHandlerRegistered, isFalse);
  });

  test(
    'enable persists the preference, stores a token, and subscribes topics',
    () async {
      preferenceStore.enabled = false;
      messagingClient = FakeFcmMessagingClient(
        authorizationStatus: FcmAuthorizationStatus.notDetermined,
        requestResult: FcmAuthorizationStatus.authorized,
        token: 'token-1',
      );
      service = FcmService(
        messagingClient: messagingClient,
        preferenceStore: preferenceStore,
        tokenRepository: tokenRepository,
        isFirebaseAvailable: () => true,
      );

      final status = await service.enable(userId: 'user-1');

      expect(preferenceStore.enabled, isTrue);
      expect(status.isEffectivelyEnabled, isTrue);
      expect(status.activeMarketTopic, 'market_RW');
      expect(tokenRepository.upserts, hasLength(1));
      expect(tokenRepository.upserts.single.userId, 'user-1');
      expect(tokenRepository.upserts.single.token, 'token-1');
      expect(messagingClient.subscribedTopics, ['market_RW']);
    },
  );

  test('disable removes the active topic and token and persists off', () async {
    await service.enable(userId: 'user-1');

    final status = await service.disable(userId: 'user-1');

    expect(preferenceStore.enabled, isFalse);
    expect(status.preferenceEnabled, isFalse);
    expect(status.isInitialized, isFalse);
    expect(status.activeMarketTopic, isNull);
    expect(tokenRepository.deletes, hasLength(1));
    expect(tokenRepository.deletes.single.userId, 'user-1');
    expect(tokenRepository.deletes.single.token, 'token-1');
    expect(messagingClient.unsubscribedTopics, contains('market_RW'));
    expect(messagingClient.deleteTokenCalled, isTrue);
  });

  test(
    'clearSession removes token state but preserves the saved preference',
    () async {
      await service.enable(userId: 'user-1');

      final status = await service.clearSession(userId: 'user-1');

      expect(preferenceStore.enabled, isTrue);
      expect(status.preferenceEnabled, isTrue);
      expect(status.isInitialized, isFalse);
      expect(status.activeMarketTopic, isNull);
      expect(tokenRepository.deletes, hasLength(1));
      expect(messagingClient.unsubscribedTopics, contains('market_RW'));
      expect(messagingClient.deleteTokenCalled, isTrue);
    },
  );

  test('syncTopics keeps the fixed Rwanda market topic', () async {
    await service.enable(userId: 'user-1');

    final status = await service.syncTopics();

    expect(status.activeMarketTopic, 'market_RW');
    expect(messagingClient.unsubscribedTopics, isEmpty);
    expect(messagingClient.subscribedTopics, ['market_RW']);
  });

  test('enable keeps the preference off when permission is denied', () async {
    preferenceStore.enabled = false;
    messagingClient = FakeFcmMessagingClient(
      authorizationStatus: FcmAuthorizationStatus.notDetermined,
      requestResult: FcmAuthorizationStatus.denied,
      token: 'token-1',
    );
    service = FcmService(
      messagingClient: messagingClient,
      preferenceStore: preferenceStore,
      tokenRepository: tokenRepository,
      isFirebaseAvailable: () => true,
    );

    final status = await service.enable(userId: 'user-1');

    expect(preferenceStore.enabled, isFalse);
    expect(status.preferenceEnabled, isFalse);
    expect(status.isInitialized, isFalse);
    expect(status.lastError, contains('blocked'));
    expect(tokenRepository.upserts, isEmpty);
    expect(messagingClient.subscribedTopics, isEmpty);
  });
}
