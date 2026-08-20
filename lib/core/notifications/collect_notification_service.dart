import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/repositories/collect_repository.dart';

final collectNotificationServiceProvider = Provider<CollectNotificationService>(
  (ref) {
    final service = CollectNotificationService();
    ref.onDispose(() => unawaited(service.dispose()));
    return service;
  },
);

@pragma('vm:entry-point')
Future<void> collectFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  await Firebase.initializeApp();
}

void configureCollectAndroidPushBackgroundHandler() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    FirebaseMessaging.onBackgroundMessage(
      collectFirebaseMessagingBackgroundHandler,
    );
  }
}

class CollectNotificationIntent {
  const CollectNotificationIntent({required this.deepLink, this.eventId});

  final String deepLink;
  final String? eventId;
}

class CollectNotificationRegistration {
  const CollectNotificationRegistration({
    required this.platform,
    required this.provider,
    required this.token,
    required this.environment,
  });

  final String platform;
  final String provider;
  final String token;
  final String environment;
}

class CollectNotificationService {
  CollectNotificationService({
    FlutterLocalNotificationsPlugin? plugin,
    MethodChannel? nativeChannel,
  }) : this._(
         plugin ?? FlutterLocalNotificationsPlugin(),
         nativeChannel ?? const MethodChannel(_nativeChannelName),
       );

  CollectNotificationService._(this._plugin, this._nativeChannel);

  static const _nativeChannelName = 'app.cool.mobile/notifications';
  static const _androidChannelId = 'collect_group_updates';
  static const _androidChannelName = 'Collect group updates';
  static const _androidChannelDescription =
      'Contribution confirmations, payment reminders, group updates, and security notices.';
  static const _androidContributionChannelId = 'collect_contributions';
  static const _androidReminderChannelId = 'collect_reminders';
  static const _androidSecurityChannelId = 'collect_security';
  static const _positiveNotificationIdMask = 2147483647;
  static const _apnsEnvironment = String.fromEnvironment(
    'APNS_ENVIRONMENT',
    defaultValue: 'sandbox',
  );

  final FlutterLocalNotificationsPlugin _plugin;
  final MethodChannel _nativeChannel;
  final _tapPayloads = StreamController<CollectNotificationIntent>.broadcast();
  Future<void>? _initializing;
  Completer<String?>? _remoteTokenWaiter;
  CollectRepository? _registrationRepository;
  String? _remoteToken;
  FirebaseMessaging? _androidMessaging;
  StreamSubscription<RemoteMessage>? _androidForegroundSubscription;
  StreamSubscription<RemoteMessage>? _androidTapSubscription;
  StreamSubscription<String>? _androidTokenSubscription;

  Stream<CollectNotificationIntent> get notificationTapPayloads =>
      _tapPayloads.stream;

  Future<void> initialize() {
    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    if (kIsWeb) return;
    try {
      const android = AndroidInitializationSettings(
        '@drawable/ic_collect_notification',
      );
      const ios = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const settings = InitializationSettings(android: android, iOS: ios);
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: (response) {
          _emitTapPayload(response.payload);
        },
      );
      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp ?? false) {
        _emitTapPayload(launchDetails?.notificationResponse?.payload);
      }
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      for (final channel in _androidChannels) {
        await androidPlugin?.createNotificationChannel(channel);
      }
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _initializeAndroidRemoteMessaging();
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        _nativeChannel.setMethodCallHandler(_handleNativeMethod);
        try {
          final initial = await _nativeChannel.invokeMethod<Object?>(
            'getInitialNotification',
          );
          _emitNativeIntent(initial);
        } on PlatformException {
          // Remote notifications remain unavailable until native setup exists.
        } on MissingPluginException {
          // Widget tests and non-iOS builds do not expose the native channel.
        }
      }
    } catch (_) {
      // Widget tests and unsupported platforms do not register native plugins.
    }
  }

  static const _androidChannels = <AndroidNotificationChannel>[
    AndroidNotificationChannel(
      _androidContributionChannelId,
      'Contribution confirmations',
      description: 'Reconciled bank contributions and ledger updates.',
      importance: Importance.high,
    ),
    AndroidNotificationChannel(
      _androidReminderChannelId,
      'Payment reminders',
      description: 'Time-sensitive contribution reminders.',
      importance: Importance.defaultImportance,
    ),
    AndroidNotificationChannel(
      _androidChannelId,
      _androidChannelName,
      description: _androidChannelDescription,
      importance: Importance.defaultImportance,
    ),
    AndroidNotificationChannel(
      _androidSecurityChannelId,
      'Security notices',
      description: 'Important account, permission, and privacy notices.',
      importance: Importance.high,
    ),
  ];

  Future<void> _initializeAndroidRemoteMessaging() async {
    try {
      await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      _androidMessaging = messaging;
      _androidForegroundSubscription ??= FirebaseMessaging.onMessage.listen(
        _handleAndroidForegroundMessage,
      );
      _androidTapSubscription ??= FirebaseMessaging.onMessageOpenedApp.listen(
        _emitRemoteMessageIntent,
      );
      _androidTokenSubscription ??= messaging.onTokenRefresh.listen((token) {
        _remoteToken = token;
        final repository = _registrationRepository;
        if (repository != null) {
          unawaited(
            _registerRemoteToken(
              repository,
              token,
              platform: 'android',
              provider: 'fcm',
              environment: 'production',
            ),
          );
        }
      });
      final initial = await messaging.getInitialMessage();
      if (initial != null) _emitRemoteMessageIntent(initial);
    } catch (_) {
      // Non-Firebase flavors retain local notifications and permission UX.
    }
  }

  Future<bool> requestPermission() async {
    await initialize();
    if (kIsWeb) return false;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.requestNotificationsPermission() ??
            false;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> areNotificationsEnabled() async {
    await initialize();
    if (kIsWeb) return false;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.areNotificationsEnabled() ??
            false;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final permissions = await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.checkPermissions();
        return permissions?.isEnabled ?? false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<CollectNotificationRegistration?> registration() async {
    if (kIsWeb) return null;
    await initialize();
    if (defaultTargetPlatform == TargetPlatform.android) {
      final messaging = _androidMessaging;
      if (messaging == null || !await areNotificationsEnabled()) return null;
      try {
        await messaging.setAutoInitEnabled(true);
        final token = (await messaging.getToken())?.trim();
        if (token == null || token.isEmpty) return null;
        _remoteToken = token;
        return CollectNotificationRegistration(
          platform: 'android',
          provider: 'fcm',
          token: token,
          environment: 'production',
        );
      } catch (_) {
        return null;
      }
    }
    if (defaultTargetPlatform != TargetPlatform.iOS) return null;
    final token = await _requestRemoteToken();
    if (token == null || token.isEmpty) return null;
    final environment = await _resolveNativeEnvironment();
    return CollectNotificationRegistration(
      platform: 'ios',
      provider: 'apns',
      token: token,
      environment: environment,
    );
  }

  Future<String> _resolveNativeEnvironment() async {
    var environment = _apnsEnvironment;
    try {
      final nativeEnvironment = await _nativeChannel.invokeMethod<String?>(
        'getRemoteEnvironment',
      );
      if (nativeEnvironment == 'sandbox' || nativeEnvironment == 'production') {
        environment = nativeEnvironment!;
      }
    } on PlatformException {
      // The compile-time environment remains the controlled fallback.
    } on MissingPluginException {
      // Non-iOS and widget-test builds do not expose native entitlements.
    }
    return environment;
  }

  Future<bool> registerDevice(CollectRepository repository) async {
    _registrationRepository = repository;
    try {
      final registration = await this.registration();
      if (registration == null) return false;
      await repository.registerNotificationDevice(
        platform: registration.platform,
        provider: registration.provider,
        token: registration.token,
        environment: registration.environment,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
    String? eventType,
  }) async {
    await initialize();
    if (kIsWeb) return;
    try {
      await _plugin.show(
        id: _notificationId(title, body),
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelIdForEventType(eventType),
            _channelNameForEventType(eventType),
            channelDescription: _channelDescriptionForEventType(eventType),
            icon: '@drawable/ic_collect_notification',
            importance: _importanceForEventType(eventType),
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
            visibility: NotificationVisibility.private,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: payload,
      );
    } catch (_) {
      // Local notification delivery should not break core app flows.
    }
  }

  Future<void> _handleAndroidForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title?.trim() ?? '';
    final body = notification?.body?.trim() ?? '';
    if (title.isEmpty || body.isEmpty) return;
    await showNotification(
      title: title,
      body: body,
      payload: _remoteMessageData(message, 'deep_link'),
      eventType: _remoteMessageData(message, 'type'),
    );
  }

  void _emitRemoteMessageIntent(RemoteMessage message) {
    final target = normalizeNotificationDeepLink(
      _remoteMessageData(message, 'deep_link'),
    );
    if (target == null || _tapPayloads.isClosed) return;
    final rawEventId = _remoteMessageData(message, 'collect_event_id');
    final eventId = rawEventId?.trim().isNotEmpty == true
        ? rawEventId!.trim()
        : null;
    _tapPayloads.add(
      CollectNotificationIntent(deepLink: target, eventId: eventId),
    );
  }

  String _channelIdForEventType(String? eventType) {
    final value = eventType?.toLowerCase() ?? '';
    if (value.contains('contribution')) return _androidContributionChannelId;
    if (value.contains('reminder')) return _androidReminderChannelId;
    if (value.contains('security')) return _androidSecurityChannelId;
    return _androidChannelId;
  }

  String _channelNameForEventType(String? eventType) {
    return _androidChannels
        .firstWhere(
          (channel) => channel.id == _channelIdForEventType(eventType),
        )
        .name;
  }

  String _channelDescriptionForEventType(String? eventType) {
    return _androidChannels
            .firstWhere(
              (channel) => channel.id == _channelIdForEventType(eventType),
            )
            .description ??
        _androidChannelDescription;
  }

  Importance _importanceForEventType(String? eventType) {
    return _androidChannels
        .firstWhere(
          (channel) => channel.id == _channelIdForEventType(eventType),
        )
        .importance;
  }

  Future<String?> _requestRemoteToken() async {
    final cached = _remoteToken;
    if (cached != null && cached.isNotEmpty) return cached;
    try {
      final immediate = await _nativeChannel.invokeMethod<String?>(
        'requestRemoteRegistration',
      );
      if (immediate != null && immediate.isNotEmpty) {
        _remoteToken = immediate;
        return immediate;
      }
      final waiter = _remoteTokenWaiter ??= Completer<String?>();
      return await waiter.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () => null,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> _handleNativeMethod(MethodCall call) async {
    switch (call.method) {
      case 'remoteToken':
        final token = call.arguments is String
            ? (call.arguments as String).trim()
            : '';
        if (token.isEmpty) return;
        _remoteToken = token;
        final waiter = _remoteTokenWaiter;
        if (waiter != null && !waiter.isCompleted) waiter.complete(token);
        final repository = _registrationRepository;
        if (repository != null) {
          unawaited(_registerRemoteToken(repository, token));
        }
      case 'notificationTap':
        _emitNativeIntent(call.arguments);
    }
  }

  Future<void> _registerRemoteToken(
    CollectRepository repository,
    String token, {
    String platform = 'ios',
    String provider = 'apns',
    String? environment,
  }) async {
    try {
      await repository.registerNotificationDevice(
        platform: platform,
        provider: provider,
        token: token,
        environment: environment ?? await _resolveNativeEnvironment(),
      );
    } catch (_) {
      // A later token refresh or app resume retries registration.
    }
  }

  void _emitTapPayload(String? payload) {
    final target = normalizeNotificationDeepLink(payload);
    if (target != null && !_tapPayloads.isClosed) {
      _tapPayloads.add(CollectNotificationIntent(deepLink: target));
    }
  }

  void _emitNativeIntent(Object? payload) {
    if (payload is String) {
      _emitTapPayload(payload);
      return;
    }
    if (payload is! Map) return;
    final target = normalizeNotificationDeepLink(payload['deep_link']);
    if (target == null || _tapPayloads.isClosed) return;
    final rawEventId = payload['collect_event_id'];
    final eventId = rawEventId is String && rawEventId.trim().isNotEmpty
        ? rawEventId.trim()
        : null;
    _tapPayloads.add(
      CollectNotificationIntent(deepLink: target, eventId: eventId),
    );
  }

  int _notificationId(String title, String body) {
    final digest = sha1.convert('$title|$body'.codeUnits).bytes;
    return digest.take(4).fold<int>(0, (value, byte) => (value << 8) + byte) &
        _positiveNotificationIdMask;
  }

  Future<void> dispose() async {
    await _androidForegroundSubscription?.cancel();
    await _androidTapSubscription?.cancel();
    await _androidTokenSubscription?.cancel();
    _nativeChannel.setMethodCallHandler(null);
    await _tapPayloads.close();
  }
}

String? _remoteMessageData(RemoteMessage message, String key) {
  final value = message.data[key];
  if (value == null) return null;
  return value is String ? value : value.toString();
}

String? normalizeNotificationDeepLink(Object? raw) {
  if (raw is! String) return null;
  final value = raw.trim();
  if (value.isEmpty || value.length > 512) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || uri.hasScheme || uri.hasAuthority || uri.hasFragment) {
    return null;
  }
  final path = uri.path;
  const exact = <String>{
    '/home',
    '/activity',
    '/groups',
    '/settings/notifications',
  };
  final groupRoute = RegExp(
    r'^/groups/[A-Za-z0-9_-]+(?:/(?:ledger|members|profile))?$',
  );
  if (!exact.contains(path) && !groupRoute.hasMatch(path)) return null;
  return uri.hasQuery ? '$path?${uri.query}' : path;
}
