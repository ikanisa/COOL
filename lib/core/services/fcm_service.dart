import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../theme/cool_icons.dart';

import '../config/app_market.dart';
import '../config/deep_link_config.dart';
import '../router/app_routes.dart';
import '../router/navigation_keys.dart';
import 'fcm_foreground_notification_presenter.dart';
import 'firebase_bootstrap_service.dart';
import 'hive_runtime.dart';

part 'fcm_service_runtime.dart';
part 'fcm_service_support.dart';

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
}
