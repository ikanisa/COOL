part of 'fcm_service.dart';

extension _FcmServiceRuntime on FcmService {
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
        route == AppRoutes.profile;
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

    final uri = Uri.tryParse(routeData);
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'cool')) {
      return DeepLinkConfig.routeForUri(uri);
    }

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
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              body,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
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
                fontWeight: FontWeight.w600,
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
