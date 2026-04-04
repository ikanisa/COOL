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
import 'fcm_foreground_notification_presenter.dart';
import 'hive_runtime.dart';
import 'firebase_bootstrap_service.dart';

/// Top-level background message handler (must be a top-level function).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await FirebaseBootstrapService.ensureInitialized();
  debugPrint('[FCM] Background message: ${message.messageId}');
}

enum FcmTopicCategory { matchAlerts, promotions, groupUpdates }

const _defaultTopicPreferences = <FcmTopicCategory, bool>{
  FcmTopicCategory.matchAlerts: true,
  FcmTopicCategory.promotions: true,
  FcmTopicCategory.groupUpdates: true,
};

String _topicStorageKey(FcmTopicCategory category) {
  return switch (category) {
    FcmTopicCategory.matchAlerts => 'topic_match_alerts_enabled',
    FcmTopicCategory.promotions => 'topic_promotions_enabled',
    FcmTopicCategory.groupUpdates => 'topic_group_updates_enabled',
  };
}

String _topicNameFor(FcmTopicCategory category) {
  return switch (category) {
    FcmTopicCategory.matchAlerts => 'match_alerts_${AppMarket.countryCode}',
    FcmTopicCategory.promotions => 'promotions_${AppMarket.countryCode}',
    FcmTopicCategory.groupUpdates => 'group_updates_${AppMarket.countryCode}',
  };
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
    this.activeTopics = const <String>{},
    this.topicPreferences = _defaultTopicPreferences,
    this.lastError,
  });

  static const _sentinel = Object();

  final bool preferenceEnabled;
  final FcmAuthorizationStatus authorizationStatus;
  final bool isInitialized;
  final String? activeMarketTopic;
  final Set<String> activeTopics;
  final Map<FcmTopicCategory, bool> topicPreferences;
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
    Set<String>? activeTopics,
    Map<FcmTopicCategory, bool>? topicPreferences,
    Object? lastError = _sentinel,
  }) {
    return FcmStatus(
      preferenceEnabled: preferenceEnabled ?? this.preferenceEnabled,
      authorizationStatus: authorizationStatus ?? this.authorizationStatus,
      isInitialized: isInitialized ?? this.isInitialized,
      activeMarketTopic: activeMarketTopic == _sentinel
          ? this.activeMarketTopic
          : activeMarketTopic as String?,
      activeTopics: activeTopics ?? this.activeTopics,
      topicPreferences: topicPreferences ?? this.topicPreferences,
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

abstract class FcmTopicPreferenceStore {
  Future<Map<FcmTopicCategory, bool>> readPreferences();
  Future<void> writePreference(FcmTopicCategory category, bool enabled);
}

class HiveFcmTopicPreferenceStore implements FcmTopicPreferenceStore {
  HiveFcmTopicPreferenceStore({
    required OpenHiveBox<dynamic> openBox,
    this.boxName = FcmService.preferenceBoxName,
  }) : _openBox = openBox;

  final OpenHiveBox<dynamic> _openBox;
  final String boxName;

  @override
  Future<Map<FcmTopicCategory, bool>> readPreferences() async {
    final box = await _openBox(boxName);
    return <FcmTopicCategory, bool>{
      for (final category in FcmTopicCategory.values)
        category:
            box.get(
                  _topicStorageKey(category),
                  defaultValue: _defaultTopicPreferences[category],
                )
                as bool? ??
            _defaultTopicPreferences[category]!,
    };
  }

  @override
  Future<void> writePreference(FcmTopicCategory category, bool enabled) async {
    final box = await _openBox(boxName);
    await box.put(_topicStorageKey(category), enabled);
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
    required FcmTopicPreferenceStore topicPreferenceStore,
    required FcmTokenRepository tokenRepository,
    FcmForegroundNotificationPresenter? foregroundPresenter,
    bool Function()? isFirebaseAvailable,
  }) : _messagingClient = messagingClient,
       _preferenceStore = preferenceStore,
       _topicPreferenceStore = topicPreferenceStore,
       _tokenRepository = tokenRepository,
       _foregroundPresenter =
           foregroundPresenter ?? LocalFcmForegroundNotificationPresenter(),
       _isFirebaseAvailable =
           isFirebaseAvailable ?? (() => Firebase.apps.isNotEmpty);

  static const preferenceBoxName = 'cool_fcm_prefs';
  static const preferenceKey = 'notifications_enabled';

  final FcmPreferenceStore _preferenceStore;
  final FcmTopicPreferenceStore _topicPreferenceStore;
  final FcmTokenRepository _tokenRepository;
  final FcmForegroundNotificationPresenter _foregroundPresenter;
  final bool Function() _isFirebaseAvailable;

  FcmMessagingClient? _messagingClient;
  bool _handlersRegistered = false;
  bool _foregroundPresenterInitialized = false;
  bool _isInitialized = false;
  String? _activeUserId;
  String? _currentToken;
  String? _activeMarketTopic;
  final Set<String> _activeTopicSubscriptions = <String>{};
  Map<FcmTopicCategory, bool> _topicPreferences =
      Map<FcmTopicCategory, bool>.of(_defaultTopicPreferences);
  FcmStatus _status = const FcmStatus();

  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;

  FcmStatus get currentStatus => _status;
  bool get isAvailable => _isInitialized;
  bool get isNotificationsEnabled => _status.preferenceEnabled;

  Future<FcmStatus> status({bool refreshPermission = true}) async {
    await _loadTopicPreferences();
    var preferenceEnabled = await _safeReadPreference();
    final authorizationStatus = refreshPermission
        ? await _safeReadAuthorizationStatus()
        : _status.authorizationStatus;

    if (preferenceEnabled &&
        authorizationStatus == FcmAuthorizationStatus.denied) {
      preferenceEnabled = false;
      await _safeWritePreference(false);
      await _captureCurrentToken();
      await _clearTopicSubscriptions();
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
        activeTopics: _activeTopicSubscriptions.toSet(),
        topicPreferences: Map<FcmTopicCategory, bool>.unmodifiable(
          _topicPreferences,
        ),
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
      await _clearTopicSubscriptions();
      await _deleteStoredToken(userId: userId);
      await _safeDeleteDeviceToken();
      return _setStatus(
        current.copyWith(
          preferenceEnabled: false,
          authorizationStatus: authorizationStatus,
          isInitialized: false,
          activeTopics: const <String>{},
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
    await _clearTopicSubscriptions();
    await _deleteStoredToken(userId: userId ?? _activeUserId);
    await _safeDeleteDeviceToken();
    _isInitialized = false;
    return _setStatus(
      (await status()).copyWith(
        preferenceEnabled: false,
        isInitialized: false,
        activeMarketTopic: null,
        activeTopics: const <String>{},
        lastError: null,
      ),
    );
  }

  Future<FcmStatus> setTopicEnabled(
    FcmTopicCategory category,
    bool enabled,
  ) async {
    await _safeWriteTopicPreference(category, enabled);
    _topicPreferences = <FcmTopicCategory, bool>{
      ..._topicPreferences,
      category: enabled,
    };

    if (_isInitialized && _status.preferenceEnabled && _status.isAuthorized) {
      return syncTopics();
    }

    return _setStatus(
      (await status()).copyWith(
        topicPreferences: Map<FcmTopicCategory, bool>.unmodifiable(
          _topicPreferences,
        ),
      ),
    );
  }

  Future<FcmStatus> syncTopics() async {
    final current = await status();
    if (!_isInitialized ||
        !current.preferenceEnabled ||
        !current.isAuthorized) {
      await _clearTopicSubscriptions();
      return _setStatus(
        current.copyWith(
          isInitialized: _isInitialized,
          activeMarketTopic: null,
          activeTopics: const <String>{},
        ),
      );
    }

    const desiredMarketTopic = 'market_${AppMarket.countryCode}';
    final desiredTopics = <String>{
      desiredMarketTopic,
      for (final entry in _topicPreferences.entries)
        if (entry.value) _topicNameFor(entry.key),
    };

    final staleTopics = _activeTopicSubscriptions.difference(desiredTopics);
    for (final topic in staleTopics) {
      try {
        await _client.unsubscribeFromTopic(topic);
      } catch (error) {
        debugPrint('[FCM] Topic unsubscribe failed: $error');
      }
    }

    final newTopics = desiredTopics.difference(_activeTopicSubscriptions);
    for (final topic in newTopics) {
      try {
        await _client.subscribeToTopic(topic);
      } catch (error) {
        debugPrint('[FCM] Topic subscribe failed: $error');
      }
    }

    _activeTopicSubscriptions
      ..clear()
      ..addAll(desiredTopics);
    _activeMarketTopic = desiredMarketTopic;
    return _setStatus(
      current.copyWith(
        isInitialized: _isInitialized,
        activeMarketTopic: _activeMarketTopic,
        activeTopics: _activeTopicSubscriptions.toSet(),
        topicPreferences: Map<FcmTopicCategory, bool>.unmodifiable(
          _topicPreferences,
        ),
        lastError: null,
      ),
    );
  }

  Future<FcmStatus> clearSession({required String userId}) async {
    await _captureCurrentToken();
    await _clearTopicSubscriptions();
    await _deleteStoredToken(userId: userId);
    await _safeDeleteDeviceToken();
    _activeUserId = null;
    _currentToken = null;
    _isInitialized = false;
    return _setStatus(
      (await status(refreshPermission: false)).copyWith(
        isInitialized: false,
        activeMarketTopic: null,
        activeTopics: const <String>{},
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

  Future<void> _loadTopicPreferences() async {
    try {
      final stored = await _topicPreferenceStore.readPreferences();
      _topicPreferences = <FcmTopicCategory, bool>{
        ..._defaultTopicPreferences,
        ...stored,
      };
    } catch (error) {
      debugPrint('[FCM] Failed to read topic preferences: $error');
      _topicPreferences = Map<FcmTopicCategory, bool>.of(
        _defaultTopicPreferences,
      );
    }
  }

  Future<void> _safeWriteTopicPreference(
    FcmTopicCategory category,
    bool enabled,
  ) async {
    try {
      await _topicPreferenceStore.writePreference(category, enabled);
    } catch (error) {
      debugPrint('[FCM] Failed to persist topic preference: $error');
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
    if (!_foregroundPresenterInitialized) {
      _foregroundPresenterInitialized = true;
      unawaited(
        _foregroundPresenter.initialize(
          onSelectNotification: _handleNotificationPayload,
        ),
      );
    }
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

  Future<void> _clearTopicSubscriptions() async {
    if (_activeTopicSubscriptions.isEmpty) {
      return;
    }

    for (final activeTopic in _activeTopicSubscriptions.toList(
      growable: false,
    )) {
      try {
        await _client.unsubscribeFromTopic(activeTopic);
      } catch (error) {
        debugPrint('[FCM] Topic unsubscribe failed: $error');
      }
    }
    _activeTopicSubscriptions.clear();
    _activeMarketTopic = null;
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

    final title = notification.title?.trim().isNotEmpty == true
        ? notification.title!.trim()
        : 'Cool';
    final body = notification.body?.trim().isNotEmpty == true
        ? notification.body!.trim()
        : 'Open Cool to view the latest update.';
    final payload = _notificationPayload(message);

    debugPrint('[FCM] Foreground: $title');
    unawaited(
      _showForegroundNotification(title: title, body: body, payload: payload),
    );
  }

  void _handleNotificationTap(RemoteMessage message) {
    _handleNotificationPayload(_notificationPayload(message));
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
        route == AppRoutes.profile ||
        route == AppRoutes.momo;
  }

  String? _resolveRoute(RemoteMessage message) {
    final routeData = message.data['route']?.toString();
    return _resolveRouteFromPayload(routeData);
  }

  String? _notificationPayload(RemoteMessage message) {
    return _resolveRoute(message);
  }

  Future<void> _handleNotificationPayload(String? payload) async {
    final route = _resolveRouteFromPayload(payload);
    if (route == null) {
      return;
    }

    debugPrint('[FCM] Notification tap → navigating to: $route');

    final context = rootNavigatorKey.currentContext;
    if (context != null) {
      _openRoute(context, route);
    }
  }

  String? _resolveRouteFromPayload(String? routeData) {
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

  Future<void> _showForegroundNotification({
    required String title,
    required String body,
    required String? payload,
  }) async {
    try {
      await _foregroundPresenter.show(
        title: title,
        body: body,
        payload: payload,
      );
    } catch (error) {
      debugPrint('[FCM] Foreground notification failed: $error');
      _showForegroundBanner(title: title, body: body, payload: payload);
    }
  }

  void _showForegroundBanner({
    required String title,
    required String body,
    required String? payload,
  }) {
    final context = rootNavigatorKey.currentContext;
    if (context == null) {
      return;
    }

    final route = _resolveRouteFromPayload(payload);
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: const Icon(Icons.notifications_rounded, color: Colors.white),
        backgroundColor: const Color(0xFF1A1A2E),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              body,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
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

    Future.delayed(const Duration(seconds: 5), () {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
      }
    });
  }
}
