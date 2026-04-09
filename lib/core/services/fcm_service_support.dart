part of 'fcm_service.dart';

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
