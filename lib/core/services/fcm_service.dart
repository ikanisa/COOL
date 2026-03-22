import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../config/app_market.dart';
import '../config/deep_link_config.dart';
import '../router/app_routes.dart';
import '../router/navigation_keys.dart';
import 'hive_runtime.dart';
import 'firebase_bootstrap_service.dart';

/// Top-level background message handler (must be a top-level function).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await FirebaseBootstrapService.ensureInitialized();
  debugPrint('[FCM] Background message: ${message.messageId}');
}

enum FcmAuthorizationStatus {
  unknown,
  notDetermined,
  denied,
  authorized,
  provisional,
}

class FcmStatus {
  const FcmStatus({
    this.preferenceEnabled = false,
    this.authorizationStatus = FcmAuthorizationStatus.unknown,
    this.isInitialized = false,
    this.activeMarketTopic,
    this.lastError,
  });

  static const _sentinel = Object();

  final bool preferenceEnabled;
  final FcmAuthorizationStatus authorizationStatus;
  final bool isInitialized;
  final String? activeMarketTopic;
  final String? lastError;

  bool get isAuthorized =>
      authorizationStatus == FcmAuthorizationStatus.authorized ||
      authorizationStatus == FcmAuthorizationStatus.provisional;

  bool get isEffectivelyEnabled =>
      preferenceEnabled && isAuthorized && isInitialized;

  FcmStatus copyWith({
    bool? preferenceEnabled,
    FcmAuthorizationStatus? authorizationStatus,
    bool? isInitialized,
    Object? activeMarketTopic = _sentinel,
    Object? lastError = _sentinel,
  }) {
    return FcmStatus(
      preferenceEnabled: preferenceEnabled ?? this.preferenceEnabled,
      authorizationStatus: authorizationStatus ?? this.authorizationStatus,
      isInitialized: isInitialized ?? this.isInitialized,
      activeMarketTopic: activeMarketTopic == _sentinel
          ? this.activeMarketTopic
          : activeMarketTopic as String?,
      lastError: lastError == _sentinel ? this.lastError : lastError as String?,
    );
  }
}

abstract class FcmPreferenceStore {
  Future<bool> readEnabled();
  Future<void> writeEnabled(bool enabled);
}

class HiveFcmPreferenceStore implements FcmPreferenceStore {
  HiveFcmPreferenceStore({
    required OpenHiveBox<dynamic> openBox,
    this.boxName = FcmService.preferenceBoxName,
    this.enabledKey = FcmService.preferenceKey,
  }) : _openBox = openBox;

  final OpenHiveBox<dynamic> _openBox;
  final String boxName;
  final String enabledKey;

  @override
  Future<bool> readEnabled() async {
    final box = await _openBox(boxName);
    return box.get(enabledKey, defaultValue: true) as bool;
  }

  @override
  Future<void> writeEnabled(bool enabled) async {
    final box = await _openBox(boxName);
    await box.put(enabledKey, enabled);
  }
}

abstract class FcmTokenRepository {
  Future<void> upsertToken({
    required String userId,
    required String token,
    required String platform,
  });

  Future<void> deleteToken({required String userId, required String token});
}

class SupabaseFcmTokenRepository implements FcmTokenRepository {
  SupabaseFcmTokenRepository({required SupabaseClient Function() clientFactory})
    : _clientFactory = clientFactory;

  final SupabaseClient Function() _clientFactory;

  @override
  Future<void> upsertToken({
    required String userId,
    required String token,
    required String platform,
  }) async {
    await _clientFactory().from('user_fcm_tokens').upsert({
      'user_id': userId,
      'token': token,
      'platform': platform,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,token');
  }

  @override
  Future<void> deleteToken({
    required String userId,
    required String token,
  }) async {
    await _clientFactory()
        .from('user_fcm_tokens')
        .delete()
        .eq('user_id', userId)
        .eq('token', token);
  }
}

abstract class FcmMessagingClient {
  Future<FcmAuthorizationStatus> getAuthorizationStatus();
  Future<FcmAuthorizationStatus> requestPermission();
  Future<String?> getToken();
  Stream<String> get onTokenRefresh;
  Stream<RemoteMessage> get onMessage;
  Stream<RemoteMessage> get onMessageOpenedApp;
  Future<RemoteMessage?> getInitialMessage();
  Future<void> deleteToken();
  Future<void> subscribeToTopic(String topic);
  Future<void> unsubscribeFromTopic(String topic);
  void registerBackgroundHandler();
}

class FirebaseMessagingClient implements FcmMessagingClient {
  FirebaseMessagingClient(this._messaging);

  final FirebaseMessaging _messaging;

  @override
  Future<FcmAuthorizationStatus> getAuthorizationStatus() async {
    final settings = await _messaging.getNotificationSettings();
    return _mapAuthorizationStatus(settings.authorizationStatus);
  }

  @override
  Future<FcmAuthorizationStatus> requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    return _mapAuthorizationStatus(settings.authorizationStatus);
  }

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Stream<RemoteMessage> get onMessage => FirebaseMessaging.onMessage;

  @override
  Stream<RemoteMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp;

  @override
  Future<RemoteMessage?> getInitialMessage() => _messaging.getInitialMessage();

  @override
  Future<void> deleteToken() => _messaging.deleteToken();

  @override
  Future<void> subscribeToTopic(String topic) =>
      _messaging.subscribeToTopic(topic);

  @override
  Future<void> unsubscribeFromTopic(String topic) =>
      _messaging.unsubscribeFromTopic(topic);

  @override
  void registerBackgroundHandler() {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }
}

FcmAuthorizationStatus _mapAuthorizationStatus(AuthorizationStatus status) {
  switch (status) {
    case AuthorizationStatus.notDetermined:
      return FcmAuthorizationStatus.notDetermined;
    case AuthorizationStatus.denied:
      return FcmAuthorizationStatus.denied;
    case AuthorizationStatus.authorized:
      return FcmAuthorizationStatus.authorized;
    case AuthorizationStatus.provisional:
      return FcmAuthorizationStatus.provisional;
  }
}

/// Manages Firebase Cloud Messaging: token lifecycle, permission,
/// topic subscriptions, and foreground/background message handling.
class FcmService {
  FcmService({
    FcmMessagingClient? messagingClient,
    required FcmPreferenceStore preferenceStore,
    required FcmTokenRepository tokenRepository,
    bool Function()? isFirebaseAvailable,
  }) : _messagingClient = messagingClient,
       _preferenceStore = preferenceStore,
       _tokenRepository = tokenRepository,
       _isFirebaseAvailable =
           isFirebaseAvailable ?? (() => Firebase.apps.isNotEmpty);

  static const preferenceBoxName = 'cool_fcm_prefs';
  static const preferenceKey = 'notifications_enabled';

  final FcmPreferenceStore _preferenceStore;
  final FcmTokenRepository _tokenRepository;
  final bool Function() _isFirebaseAvailable;

  FcmMessagingClient? _messagingClient;
  bool _handlersRegistered = false;
  bool _isInitialized = false;
  String? _activeUserId;
  String? _currentToken;
  String? _activeMarketTopic;
  FcmStatus _status = const FcmStatus();

  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;

  FcmStatus get currentStatus => _status;
  bool get isAvailable => _isInitialized;
  bool get isNotificationsEnabled => _status.preferenceEnabled;

  Future<FcmStatus> status({bool refreshPermission = true}) async {
    var preferenceEnabled = await _safeReadPreference();
    final authorizationStatus = refreshPermission
        ? await _safeReadAuthorizationStatus()
        : _status.authorizationStatus;

    if (preferenceEnabled &&
        authorizationStatus == FcmAuthorizationStatus.denied) {
      preferenceEnabled = false;
      await _safeWritePreference(false);
      await _captureCurrentToken();
      await _clearTopicSubscription();
      await _deleteStoredToken();
      await _safeDeleteDeviceToken();
      _isInitialized = false;
    }

    return _setStatus(
      _status.copyWith(
        preferenceEnabled: preferenceEnabled,
        authorizationStatus: authorizationStatus,
        isInitialized: _isInitialized,
        activeMarketTopic: _activeMarketTopic,
        lastError: null,
      ),
    );
  }

  Future<FcmStatus> initialize({required String userId}) async {
    _activeUserId = userId;
    final current = await status();
    if (!_isFirebaseAvailable()) {
      _isInitialized = false;
      return _setStatus(current.copyWith(isInitialized: false));
    }

    if (!current.preferenceEnabled) {
      _isInitialized = false;
      return _setStatus(current.copyWith(isInitialized: false));
    }

    final authorizationStatus = await _ensurePermission();
    if (authorizationStatus == FcmAuthorizationStatus.denied) {
      _isInitialized = false;
      await _safeWritePreference(false);
      await _captureCurrentToken();
      await _clearTopicSubscription();
      await _deleteStoredToken(userId: userId);
      await _safeDeleteDeviceToken();
      return _setStatus(
        current.copyWith(
          preferenceEnabled: false,
          authorizationStatus: authorizationStatus,
          isInitialized: false,
          lastError: 'Notifications are blocked in system settings.',
        ),
      );
    }

    try {
      _bindMessagingHandlersIfNeeded();
      await _captureCurrentToken();
      await _upsertCurrentToken();
      _isInitialized = true;
      return _setStatus(
        current.copyWith(
          preferenceEnabled: true,
          authorizationStatus: authorizationStatus,
          isInitialized: true,
          activeMarketTopic: _activeMarketTopic,
          lastError: null,
        ),
      );
    } catch (error) {
      debugPrint('[FCM] Init failed: $error');
      _isInitialized = false;
      return _setStatus(
        current.copyWith(isInitialized: false, lastError: error.toString()),
      );
    }
  }

  Future<FcmStatus> enable({required String userId}) async {
    await _safeWritePreference(true);
    final initialized = await initialize(userId: userId);
    if (!initialized.isAuthorized) {
      return initialized;
    }
    return syncTopics();
  }

  Future<FcmStatus> disable({String? userId}) async {
    await _safeWritePreference(false);
    await _captureCurrentToken();
    await _clearTopicSubscription();
    await _deleteStoredToken(userId: userId ?? _activeUserId);
    await _safeDeleteDeviceToken();
    _isInitialized = false;
    return _setStatus(
      (await status()).copyWith(
        preferenceEnabled: false,
        isInitialized: false,
        activeMarketTopic: null,
        lastError: null,
      ),
    );
  }

  Future<FcmStatus> syncTopics() async {
    final current = await status();
    if (!_isInitialized ||
        !current.preferenceEnabled ||
        !current.isAuthorized) {
      await _clearTopicSubscription();
      return _setStatus(
        current.copyWith(
          isInitialized: _isInitialized,
          activeMarketTopic: null,
        ),
      );
    }

    const desiredTopic = 'market_${AppMarket.countryCode}';

    if (_activeMarketTopic != null && _activeMarketTopic != desiredTopic) {
      try {
        await _client.unsubscribeFromTopic(_activeMarketTopic!);
      } catch (error) {
        debugPrint('[FCM] Topic unsubscribe failed: $error');
      }
    }

    if (desiredTopic != _activeMarketTopic) {
      try {
        await _client.subscribeToTopic(desiredTopic);
      } catch (error) {
        debugPrint('[FCM] Topic subscribe failed: $error');
      }
    }

    _activeMarketTopic = desiredTopic;
    return _setStatus(
      current.copyWith(
        isInitialized: _isInitialized,
        activeMarketTopic: _activeMarketTopic,
        lastError: null,
      ),
    );
  }

  Future<FcmStatus> clearSession({required String userId}) async {
    await _captureCurrentToken();
    await _clearTopicSubscription();
    await _deleteStoredToken(userId: userId);
    await _safeDeleteDeviceToken();
    _activeUserId = null;
    _currentToken = null;
    _isInitialized = false;
    return _setStatus(
      (await status(refreshPermission: false)).copyWith(
        isInitialized: false,
        activeMarketTopic: null,
        lastError: null,
      ),
    );
  }

  void dispose() {
    _tokenRefreshSubscription?.cancel();
    _messageSubscription?.cancel();
    _messageOpenedSubscription?.cancel();
  }

  FcmMessagingClient get _client {
    final existing = _messagingClient;
    if (existing != null) {
      return existing;
    }

    final created = FirebaseMessagingClient(FirebaseMessaging.instance);
    _messagingClient = created;
    return created;
  }

  Future<bool> _safeReadPreference() async {
    try {
      return await _preferenceStore.readEnabled();
    } catch (error) {
      debugPrint('[FCM] Failed to read notification preference: $error');
      return false;
    }
  }

  Future<void> _safeWritePreference(bool enabled) async {
    try {
      await _preferenceStore.writeEnabled(enabled);
    } catch (error) {
      debugPrint('[FCM] Failed to persist notification pref: $error');
    }
  }

  Future<FcmAuthorizationStatus> _safeReadAuthorizationStatus() async {
    if (!_isFirebaseAvailable()) {
      return FcmAuthorizationStatus.unknown;
    }

    try {
      return await _client.getAuthorizationStatus();
    } catch (error) {
      debugPrint('[FCM] Failed to read notification settings: $error');
      return FcmAuthorizationStatus.unknown;
    }
  }

  Future<FcmAuthorizationStatus> _ensurePermission() async {
    final current = await _safeReadAuthorizationStatus();
    if (current == FcmAuthorizationStatus.notDetermined ||
        current == FcmAuthorizationStatus.unknown) {
      try {
        return await _client.requestPermission();
      } catch (error) {
        debugPrint('[FCM] Permission request failed: $error');
        return FcmAuthorizationStatus.unknown;
      }
    }

    return current;
  }

  void _bindMessagingHandlersIfNeeded() {
    if (_handlersRegistered) {
      return;
    }

    _handlersRegistered = true;
    _client.registerBackgroundHandler();
    _tokenRefreshSubscription = _client.onTokenRefresh.listen((token) {
      _currentToken = token;
      unawaited(_upsertCurrentToken());
    });
    _messageSubscription = _client.onMessage.listen(_handleForegroundMessage);
    _messageOpenedSubscription = _client.onMessageOpenedApp.listen(
      _handleNotificationTap,
    );
    unawaited(_consumeInitialMessage());
  }

  Future<void> _consumeInitialMessage() async {
    try {
      final initialMessage = await _client.getInitialMessage();
      if (initialMessage != null) {
        _handleNotificationTap(initialMessage);
      }
    } catch (error) {
      debugPrint('[FCM] Failed to read initial message: $error');
    }
  }

  Future<void> _captureCurrentToken() async {
    if (!_isFirebaseAvailable()) {
      return;
    }

    if (_currentToken != null) {
      return;
    }

    try {
      _currentToken = await _client.getToken();
    } catch (error) {
      debugPrint('[FCM] Failed to read token: $error');
    }
  }

  Future<void> _upsertCurrentToken() async {
    final userId = _activeUserId;
    final token = _currentToken;
    if (userId == null || token == null || token.isEmpty) {
      return;
    }

    try {
      await _tokenRepository.upsertToken(
        userId: userId,
        token: token,
        platform: defaultTargetPlatform.name.toLowerCase(),
      );
    } catch (error) {
      debugPrint('[FCM] Token upsert failed: $error');
    }
  }

  Future<void> _deleteStoredToken({String? userId}) async {
    final effectiveUserId = userId ?? _activeUserId;
    final token = _currentToken;
    if (effectiveUserId == null || token == null || token.isEmpty) {
      return;
    }

    try {
      await _tokenRepository.deleteToken(userId: effectiveUserId, token: token);
    } catch (error) {
      debugPrint('[FCM] Token delete failed: $error');
    }
  }

  Future<void> _safeDeleteDeviceToken() async {
    if (!_isFirebaseAvailable()) {
      return;
    }

    try {
      await _client.deleteToken();
    } catch (error) {
      debugPrint('[FCM] Token delete failed: $error');
    } finally {
      _currentToken = null;
    }
  }

  Future<void> _clearTopicSubscription() async {
    final activeTopic = _activeMarketTopic;
    if (activeTopic == null || activeTopic.isEmpty) {
      return;
    }

    try {
      await _client.unsubscribeFromTopic(activeTopic);
    } catch (error) {
      debugPrint('[FCM] Topic unsubscribe failed: $error');
    } finally {
      _activeMarketTopic = null;
    }
  }

  FcmStatus _setStatus(FcmStatus status) {
    _status = status;
    return _status;
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) {
      return;
    }

    debugPrint('[FCM] Foreground: ${notification.title}');

    // Show a MaterialBanner at the top of the app.
    final context = rootNavigatorKey.currentContext;
    if (context == null) {
      return;
    }

    final route = _resolveRoute(message);
    final imageUrl = message.data['image_url']?.toString();

    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: const Icon(Icons.notifications_rounded, color: Colors.white),
        backgroundColor: const Color(0xFF1A1A2E),
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (notification.title != null)
                    Text(
                      notification.title!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  if (notification.body != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      notification.body!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (imageUrl != null && imageUrl.isNotEmpty) ...[
              const SizedBox(width: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  imageUrl,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              if (route != null) {
                _openRoute(context, route);
              }
            },
            child: Text(
              route != null ? 'VIEW' : 'DISMISS',
              style: const TextStyle(
                color: Color(0xFF6C63FF),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    // Auto-dismiss after 5 seconds.
    Future.delayed(const Duration(seconds: 5), () {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
      }
    });
  }

  void _handleNotificationTap(RemoteMessage message) {
    final route = _resolveRoute(message);
    if (route == null) {
      return;
    }

    debugPrint('[FCM] Notification tap → navigating to: $route');

    final context = rootNavigatorKey.currentContext;
    if (context != null) {
      _openRoute(context, route);
    }
  }

  void _openRoute(BuildContext context, String route) {
    final router = GoRouter.of(context);
    if (_replacesCurrentRoute(route)) {
      router.go(route);
      return;
    }
    router.push(route);
  }

  bool _replacesCurrentRoute(String route) {
    return route == AppRoutes.home ||
        route == AppRoutes.groups ||
        route == AppRoutes.mobility ||
        route == AppRoutes.profile ||
        route == AppRoutes.partners ||
        route == AppRoutes.momo ||
        route == AppRoutes.credit ||
        route == AppRoutes.missions;
  }

  String? _resolveRoute(RemoteMessage message) {
    final routeData = message.data['route']?.toString();
    if (routeData == null || routeData.isEmpty) {
      return null;
    }

    // Try as URI first (for deep links), then as plain route path.
    final uri = Uri.tryParse(routeData);
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'cool')) {
      return DeepLinkConfig.routeForUri(uri);
    }

    // Plain route path (e.g. '/groups/123').
    return routeData.startsWith('/') ? routeData : '/$routeData';
  }
}
