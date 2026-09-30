import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/repositories/collect_repository.dart';
import '../supabase/supabase_module.dart';

final collectNotificationServiceProvider = Provider<CollectNotificationService>(
  (ref) {
    final service = CollectNotificationService(
      authenticatedUserId: () =>
          ref.read(supabaseClientProvider)?.auth.currentUser?.id,
      authenticatedSessionId: () => _notificationSessionId(
        ref.read(supabaseClientProvider)?.auth.currentSession?.accessToken,
      ),
    );
    ref.listen<String?>(collectAuthenticatedUserIdProvider, (_, owner) {
      unawaited(service.synchronizeOwner(owner));
    }, fireImmediately: true);
    final authSubscription = ref
        .read(supabaseClientProvider)
        ?.auth
        .onAuthStateChange
        .listen((_) {
          unawaited(
            service.synchronizeOwner(
              ref.read(supabaseClientProvider)?.auth.currentUser?.id,
            ),
          );
        });
    ref.onDispose(() {
      unawaited(authSubscription?.cancel());
      unawaited(service.dispose());
    });
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
  const CollectNotificationIntent({
    required this.deepLink,
    this.eventId,
    this.recipientId,
  });

  final String deepLink;
  final String? eventId;
  final String? recipientId;
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

enum CollectNotificationStatus {
  notRequested,
  checking,
  permissionDenied,
  unavailable,
  retryRequired,
  signInRequired,
  ready;

  String get message => switch (this) {
    notRequested => 'Allow notifications to receive your updates.',
    checking => 'Connecting notifications…',
    permissionDenied => 'Notifications are off. Allow them in phone settings.',
    unavailable => 'Notifications are unavailable right now. Try again later.',
    retryRequired =>
      'Notifications could not connect. Check your connection and try again.',
    signInRequired => 'Sign in again to connect notifications on this device.',
    ready => 'Notifications are connected.',
  };
}

class CollectNotificationService {
  CollectNotificationService({
    FlutterLocalNotificationsPlugin? plugin,
    MethodChannel? nativeChannel,
    String? Function()? authenticatedUserId,
    String? Function()? authenticatedSessionId,
  }) : this._(
         plugin ?? FlutterLocalNotificationsPlugin(),
         nativeChannel ?? const MethodChannel(_nativeChannelName),
         authenticatedUserId,
         authenticatedSessionId,
       );

  CollectNotificationService._(
    this._plugin,
    this._nativeChannel,
    this._authenticatedUserId,
    this._authenticatedSessionId,
  );

  static const _nativeChannelName = 'app.cool.mobile/notifications';
  static const _androidChannelId = 'collect_group_updates';
  static const _androidChannelName = 'Collect group updates';
  static const _androidChannelDescription =
      'Contribution confirmations, transfer reminders, group updates, and security notices.';
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
  final String? Function()? _authenticatedUserId;
  final String? Function()? _authenticatedSessionId;
  String? _sessionId;
  final ValueNotifier<CollectNotificationStatus> registrationStatus =
      ValueNotifier(CollectNotificationStatus.notRequested);
  int _registrationGeneration = 0;
  static const _registrationTimeout = Duration(seconds: 20);
  bool _permissionUnavailable = false;
  bool? _permissionGranted;
  bool? get permissionGranted => _permissionGranted;

  Object get registrationContext => (
    owner: _authenticatedUserId == null ? _ownerId : _authenticatedUserId(),
    session: _authenticatedSessionId == null
        ? _sessionId
        : _authenticatedSessionId(),
    generation: _ownerGeneration,
  );
  bool isRegistrationContextCurrent(Object context) =>
      !_disposed && context == registrationContext;

  String? _ownerId;
  bool _hasOwnerSynchronization = false;
  int _ownerGeneration = 0;
  bool _disposed = false;
  Future<void> _notificationWork = Future<void>.value();
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

  /// Invalidates pending display/navigation before native cancellation awaits.
  /// The callback reads Auth directly so delayed stream updates cannot authorize
  /// a previous account's message.
  Future<void> synchronizeOwner(String? rawOwner) {
    final owner = _notificationOwner(rawOwner);
    final session = _authenticatedSessionId?.call();
    if (_disposed ||
        (_hasOwnerSynchronization &&
            owner == _ownerId &&
            session == _sessionId)) {
      return Future<void>.value();
    }
    _hasOwnerSynchronization = true;
    _ownerId = owner;
    _sessionId = session;
    _permissionGranted = null;
    ++_ownerGeneration;
    ++_registrationGeneration;
    registrationStatus.value = CollectNotificationStatus.notRequested;
    _registrationRepository = null;
    return _queueNotificationWork(() async {
      try {
        await _plugin.cancelAll();
      } catch (_) {
        // Recipient checks still deny old taps if native clearing is unavailable.
      }
      if (defaultTargetPlatform == TargetPlatform.iOS && !kIsWeb) {
        try {
          await _nativeChannel.invokeMethod<void>(
            'setNotificationOwner',
            owner,
          );
        } catch (_) {
          // Missing native support does not enable unbound notification display.
        }
      }
    });
  }

  bool _acceptRecipient(Object? rawRecipient, [int? generation]) {
    if (_disposed || (generation != null && generation != _ownerGeneration)) {
      return false;
    }
    final recipient = _notificationOwner(rawRecipient);
    final current = _authenticatedUserId == null
        ? _ownerId
        : _notificationOwner(_authenticatedUserId());
    return recipient != null && recipient == _ownerId && recipient == current;
  }

  Future<void> _queueNotificationWork(Future<void> Function() operation) {
    final work = _notificationWork.then((_) => operation());
    _notificationWork = work.catchError((Object _) {});
    return work;
  }

  Future<void> initialize() {
    if (_disposed) return Future<void>.value();
    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    if (kIsWeb || _disposed) return;
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
      if (_disposed) return;
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
      description: 'Confirmed contributions and ledger updates.',
      importance: Importance.high,
    ),
    AndroidNotificationChannel(
      _androidReminderChannelId,
      'Contribution reminders',
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
      if (_disposed) return;
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
    _permissionUnavailable = kIsWeb;
    await initialize();
    if (kIsWeb) return false;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final result = await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
        _permissionUnavailable = result == null;
        return result ?? false;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final result = await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
        _permissionUnavailable = result == null;
        return result ?? false;
      }
      _permissionUnavailable = true;
      return false;
    } catch (_) {
      _permissionUnavailable = true;
      return false;
    }
  }

  Future<bool> areNotificationsEnabled() async {
    _permissionUnavailable = kIsWeb;
    await initialize();
    if (kIsWeb) return false;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final result = await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.areNotificationsEnabled();
        _permissionUnavailable = result == null;
        return result ?? false;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final permissions = await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.checkPermissions();
        _permissionUnavailable = permissions == null;
        return permissions?.isEnabled ?? false;
      }
      _permissionUnavailable = true;
      return false;
    } catch (_) {
      _permissionUnavailable = true;
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

  /// Permission and server acknowledgement are separate steps. Neither a phone
  /// prompt nor an obtained provider token establishes a registered device.
  Future<bool> enableDevice(CollectRepository repository) async {
    final context = registrationContext;
    if (!_acceptRecipient(_ownerId)) return false;
    final operation = ++_registrationGeneration;
    registrationStatus.value = CollectNotificationStatus.checking;
    final allowed = await requestPermission();
    if (!isRegistrationContextCurrent(context) ||
        operation != _registrationGeneration) {
      return false;
    }
    _permissionGranted = _permissionUnavailable ? null : allowed;
    if (!allowed) {
      registrationStatus.value = _permissionUnavailable
          ? CollectNotificationStatus.unavailable
          : CollectNotificationStatus.permissionDenied;
      return false;
    }
    return registerDevice(repository);
  }

  Future<bool> registerDevice(CollectRepository repository) =>
      _attemptRegistration(repository, registration);

  Future<bool> _attemptRegistration(
    CollectRepository repository,
    Future<CollectNotificationRegistration?> Function() obtain,
  ) async {
    final owner = _ownerId;
    final context = registrationContext;
    if (!_acceptRecipient(owner) ||
        (_authenticatedSessionId != null &&
            _sessionId != _authenticatedSessionId())) {
      return false;
    }
    final operation = ++_registrationGeneration;
    bool current() =>
        isRegistrationContextCurrent(context) &&
        operation == _registrationGeneration &&
        _acceptRecipient(owner);
    _registrationRepository = repository;
    registrationStatus.value = CollectNotificationStatus.checking;
    try {
      final allowed = await areNotificationsEnabled().timeout(
        _registrationTimeout,
      );
      if (!current()) return false;
      _permissionGranted = _permissionUnavailable ? null : allowed;
      if (!allowed) {
        registrationStatus.value = _permissionUnavailable
            ? CollectNotificationStatus.unavailable
            : CollectNotificationStatus.permissionDenied;
        return false;
      }
      final candidate = await obtain().timeout(_registrationTimeout);
      if (!current()) return false;
      if (candidate == null) {
        registrationStatus.value = CollectNotificationStatus.unavailable;
        return false;
      }
      await repository
          .registerNotificationDevice(
            platform: candidate.platform,
            provider: candidate.provider,
            token: candidate.token,
            environment: candidate.environment,
          )
          .timeout(_registrationTimeout);
      if (!current()) return false;
      if (!repository.isNotificationDeviceRegistered(
        provider: candidate.provider,
        token: candidate.token,
      )) {
        registrationStatus.value = CollectNotificationStatus.retryRequired;
        return false;
      }
      registrationStatus.value = CollectNotificationStatus.ready;
      return true;
    } catch (error) {
      if (!current()) return false;
      final needsLogin =
          error is AuthException ||
          (error is PostgrestException &&
              error.message == 'notification_registration_session_stale') ||
          (error is StateError &&
              error.message ==
                  'Sign in again to register notifications on this device.');
      registrationStatus.value = needsLogin
          ? CollectNotificationStatus.signInRequired
          : CollectNotificationStatus.retryRequired;
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
    if (kIsWeb || _disposed) return;
    await _queueNotificationWork(
      () => _displayNotification(
        title: title,
        body: body,
        payload: payload,
        eventType: eventType,
      ),
    );
  }

  Future<void> _displayNotification({
    required String title,
    required String body,
    String? payload,
    String? eventType,
    String? notificationKey,
  }) async {
    try {
      await _plugin.show(
        id: _notificationId(
          notificationKey ?? title,
          notificationKey == null ? body : '',
        ),
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

  Future<void> _handleAndroidForegroundMessage(RemoteMessage message) =>
      handleForegroundPayload(message.data);

  /// Remote display is deliberately generic; event details are read only from
  /// the authenticated in-app inbox. This also protects old provider text.
  Future<void> handleForegroundPayload(Map<Object?, Object?> data) async {
    final generation = _ownerGeneration;
    final recipient = data['recipient_id'];
    if (!_validRemotePayload(data) ||
        !_acceptRecipient(recipient, generation)) {
      return;
    }
    await _queueNotificationWork(() async {
      await initialize();
      if (kIsWeb || !_acceptRecipient(recipient, generation)) return;
      await _displayNotification(
        title: 'Collect',
        body: 'Open Collect to view your updates.',
        payload: jsonEncode({
          'collect_push_version': '2',
          'recipient_id': recipient,
          'collect_event_id': data['collect_event_id'],
          'deep_link': normalizeNotificationDeepLink(data['deep_link']),
        }),
        eventType: data['type'] is String ? data['type'] as String : null,
        notificationKey: '$recipient:${data['collect_event_id']}',
      );
    });
  }

  void _emitRemoteMessageIntent(RemoteMessage message) {
    handleRemoteTap(message.data);
  }

  bool _validRemotePayload(Map<Object?, Object?> data) =>
      data['collect_push_version'] == '2' &&
      _notificationOwner(data['recipient_id']) != null &&
      _notificationOwner(data['collect_event_id']) != null;

  void handleRemoteTap(Map<Object?, Object?> data) {
    if (!_validRemotePayload(data) ||
        !_acceptRecipient(data['recipient_id']) ||
        _tapPayloads.isClosed) {
      return;
    }
    final target = normalizeNotificationDeepLink(data['deep_link']);
    if (target == null) return;
    _tapPayloads.add(
      CollectNotificationIntent(
        deepLink: target,
        eventId: data['collect_event_id'] as String,
        recipientId: data['recipient_id'] as String,
      ),
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
    if (_disposed) return;
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
      case 'notificationForeground':
        final arguments = call.arguments;
        if (arguments is Map) await handleForegroundPayload(arguments);
    }
  }

  Future<void> _registerRemoteToken(
    CollectRepository repository,
    String token, {
    String platform = 'ios',
    String provider = 'apns',
    String? environment,
  }) async {
    if (!identical(repository, _registrationRepository)) return;
    await _attemptRegistration(
      repository,
      () async => CollectNotificationRegistration(
        platform: platform,
        provider: provider,
        token: token,
        environment: environment ?? await _resolveNativeEnvironment(),
      ),
    );
  }

  void _emitTapPayload(String? payload) {
    if (payload == null || payload.length > 2048 || _disposed) return;
    if (payload.startsWith('{')) {
      try {
        final data = jsonDecode(payload);
        if (data is Map) handleRemoteTap(data);
      } catch (_) {
        // Malformed or legacy remote payloads do not select account resources.
      }
      return;
    }
    final target = normalizeNotificationDeepLink(payload);
    // These plain paths are local permission confirmations. Older remote
    // group payloads have no recipient proof and are no longer navigable.
    if (target != null &&
        (target == '/home' || target == '/settings/notifications') &&
        !_tapPayloads.isClosed) {
      _tapPayloads.add(CollectNotificationIntent(deepLink: target));
    }
  }

  void _emitNativeIntent(Object? payload) {
    if (payload is! Map) return;
    handleRemoteTap(payload);
  }

  int _notificationId(String title, String body) {
    final digest = sha1.convert(utf8.encode('$title|$body')).bytes;
    return digest.take(4).fold<int>(0, (value, byte) => (value << 8) + byte) &
        _positiveNotificationIdMask;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    ++_ownerGeneration;
    _ownerId = null;
    _registrationRepository = null;
    await _androidForegroundSubscription?.cancel();
    await _androidTapSubscription?.cancel();
    await _androidTokenSubscription?.cancel();
    _nativeChannel.setMethodCallHandler(null);
    await _queueNotificationWork(() async {
      try {
        await _plugin.cancelAll();
      } catch (_) {
        // Disposal still fences all incoming handlers and navigation.
      }
    });
    await _tapPayloads.close();
    registrationStatus.dispose();
  }
}

String? _notificationOwner(Object? value) =>
    value is String &&
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        ).hasMatch(value)
    ? value
    : null;

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

String? _notificationSessionId(String? token) {
  if (token == null) return null;
  try {
    final value = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))),
    );
    if (value is Map && value['session_id'] is String) {
      return value['session_id'] as String;
    }
  } catch (_) {
    /* Token contents must not appear in diagnostics. */
  }
  return token;
}
