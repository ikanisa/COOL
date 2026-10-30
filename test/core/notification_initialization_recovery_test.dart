import 'dart:async';

import 'package:collect_app/core/notifications/collect_notification_service.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

const _ownerA = '99910000-0000-4000-8000-000000000001';
const _ownerB = '99910000-0000-4000-8000-000000000002';
const _event = '99910000-0000-4000-8000-000000000099';
const _token = 'synthetic-fcm-token';
const _nativeChannel = MethodChannel('test.collect/initialization');

RemoteMessage _message(String owner) => RemoteMessage(
  data: {
    'collect_push_version': '2',
    'recipient_id': owner,
    'collect_event_id': _event,
    'deep_link': '/groups/group-1/ledger',
    'type': 'contribution',
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_nativeChannel, null);
  });

  test(
    'Firebase setup failure can recover and register in the same process',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.service.synchronizeOwner(h.owner);
      h.initializeMessaging = () async => throw StateError('temporary failure');

      expect(await h.service.registerDevice(h.repository), isFalse);
      expect(
        h.service.registrationStatus.value,
        CollectNotificationStatus.unavailable,
      );
      expect(h.repository.tokens, isEmpty);
      final failedAttempts = h.messagingInitializations;
      expect(failedAttempts, greaterThan(0));

      h.initializeMessaging = () async => h.messaging;
      expect(await h.service.registerDevice(h.repository), isTrue);
      expect(
        h.service.registrationStatus.value,
        CollectNotificationStatus.ready,
      );
      expect(h.repository.tokens, [_token]);
      expect(h.messagingInitializations, failedAttempts + 1);
      expect(h.plugin.initializations, 1);
      expect(h.plugin.launchLookups, 1);
      expect(h.plugin.android.channels, hasLength(4));
    },
  );

  test(
    'concurrent callers share the attempt and a failed attempt is released',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final started = Completer<void>();
      final gate = Completer<FirebaseMessaging>();
      h.initializeMessaging = () {
        started.complete();
        return gate.future;
      };

      final first = h.service.initialize();
      final second = h.service.initialize();
      expect(identical(first, second), isTrue);
      await started.future;
      expect(h.messagingInitializations, 1);
      gate.completeError(StateError('temporary failure'));
      await Future.wait([first, second]);

      h.initializeMessaging = () async => h.messaging;
      await h.service.initialize();
      await Future.wait([h.service.initialize(), h.service.initialize()]);
      expect(h.messagingInitializations, 2);
      expect(h.messaging.initialLookups, 1);
      expect(h.plugin.initializations, 1);
    },
  );

  for (final outcome in ['throws', 'returns false', 'returns null']) {
    test('Android local initialization retries when it $outcome', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.plugin.initializeAction = () async => switch (outcome) {
        'throws' => throw PlatformException(code: 'temporary'),
        'returns false' => false,
        _ => null,
      };

      await h.service.initialize();
      expect(h.messagingInitializations, 0);
      h.plugin.initializeAction = () async => true;
      await h.service.initialize();
      await h.service.initialize();
      expect(h.plugin.initializations, 2);
      expect(h.messagingInitializations, 1);
    });
  }

  test(
    'partial remote setup keeps one handler per stream and one launch tap',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.service.synchronizeOwner(h.owner);
      h.plugin.launchAction = () async => const NotificationAppLaunchDetails(
        true,
        notificationResponse: NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: '/settings/notifications',
        ),
      );
      h.messaging.initialAction = () async =>
          throw PlatformException(code: 'temporary_initial_message_failure');
      final taps = <CollectNotificationIntent>[];
      final subscription = h.service.notificationTapPayloads.listen(taps.add);
      addTearDown(subscription.cancel);

      await h.service.initialize();
      h.messaging.initialAction = () async => _message(_ownerA);
      await h.service.initialize();
      await h.service.initialize();
      h.taps.add(_message(_ownerA));
      h.foreground.add(_message(_ownerA));
      await Future<void>.delayed(Duration.zero);

      expect(h.messagingInitializations, 1);
      expect(h.messaging.initialLookups, 2);
      expect(h.foreground.subscriptions, 1);
      expect(h.taps.subscriptions, 1);
      expect(h.messaging.tokens.subscriptions, 1);
      expect(h.plugin.initializations, 1);
      expect(h.plugin.launchLookups, 1);
      expect(taps.map((tap) => tap.deepLink), [
        '/settings/notifications',
        '/groups/group-1/ledger',
        '/groups/group-1/ledger',
      ]);
      expect(h.plugin.shown, hasLength(1));
      expect(h.plugin.shown.single.body, 'Open Collect to view your updates.');
    },
  );

  for (final changeOwner in [true, false]) {
    test(
      '${changeOwner ? 'account' : 'session'} change during retry fences the pending registration',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        await h.service.synchronizeOwner(h.owner);
        h.initializeMessaging = () async =>
            throw StateError('temporary failure');
        await h.service.initialize();
        final started = Completer<void>();
        final gate = Completer<FirebaseMessaging>();
        h.initializeMessaging = () {
          started.complete();
          return gate.future;
        };

        final pending = h.service.registerDevice(h.repository);
        await started.future;
        if (changeOwner) h.owner = _ownerB;
        h.session = 'session-b';
        await h.service.synchronizeOwner(h.owner);
        gate.complete(h.messaging);
        expect(await pending, isFalse);
        expect(h.repository.tokens, isEmpty);
        expect(
          h.service.registrationStatus.value,
          CollectNotificationStatus.notRequested,
        );

        expect(await h.service.registerDevice(h.repository), isTrue);
        expect(h.repository.tokens, [_token]);
        if (changeOwner) {
          final taps = <CollectNotificationIntent>[];
          final subscription = h.service.notificationTapPayloads.listen(
            taps.add,
          );
          addTearDown(subscription.cancel);
          h.taps.add(_message(_ownerA));
          h.taps.add(_message(_ownerB));
          h.foreground.add(_message(_ownerA));
          h.foreground.add(_message(_ownerB));
          await Future<void>.delayed(Duration.zero);
          expect(taps, hasLength(1));
          expect(taps.single.recipientId, _ownerB);
          expect(h.plugin.shown, hasLength(1));
        }
      },
    );
  }

  test(
    'dispose during Firebase setup prevents late handler installation',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final started = Completer<void>();
      final gate = Completer<FirebaseMessaging>();
      h.initializeMessaging = () {
        started.complete();
        return gate.future;
      };

      final pending = h.service.initialize();
      await started.future;
      await h.service.dispose();
      gate.complete(h.messaging);
      await pending;
      await h.service.initialize();

      expect(h.messagingInitializations, 1);
      expect(h.foreground.subscriptions, 0);
      expect(h.taps.subscriptions, 0);
      expect(h.messaging.tokens.subscriptions, 0);
      expect(h.messaging.initialLookups, 0);
      expect(h.plugin.shown, isEmpty);
    },
  );

  test(
    'dispose during initial remote lookup cancels handlers and drops the tap',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.service.synchronizeOwner(h.owner);
      final started = Completer<void>();
      final gate = Completer<RemoteMessage?>();
      h.messaging.initialAction = () {
        started.complete();
        return gate.future;
      };
      final taps = <CollectNotificationIntent>[];
      final subscription = h.service.notificationTapPayloads.listen(taps.add);
      addTearDown(subscription.cancel);

      final pending = h.service.initialize();
      await started.future;
      await h.service.dispose();
      gate.complete(_message(_ownerA));
      await pending;
      await h.service.initialize();
      h.taps.add(_message(_ownerA));
      h.foreground.add(_message(_ownerA));
      h.messaging.tokens.add('late-synthetic-token');
      await Future<void>.delayed(Duration.zero);

      expect(taps, isEmpty);
      expect(h.foreground.hasListener, isFalse);
      expect(h.taps.hasListener, isFalse);
      expect(h.messaging.tokens.hasListener, isFalse);
      expect(h.messaging.initialLookups, 1);
      expect(h.plugin.shown, isEmpty);
      expect(h.repository.tokens, isEmpty);
    },
  );

  test(
    'dispose during local launch lookup prevents iOS native setup',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final h = _Harness();
      addTearDown(h.dispose);
      var nativeLookups = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_nativeChannel, (call) async {
            nativeLookups++;
            return null;
          });
      final started = Completer<void>();
      final gate = Completer<NotificationAppLaunchDetails?>();
      h.plugin.launchAction = () {
        started.complete();
        return gate.future;
      };

      final pending = h.service.initialize();
      await started.future;
      await h.service.dispose();
      gate.complete(null);
      await pending;
      await h.service.initialize();

      expect(nativeLookups, 0);
      expect(h.plugin.android.channels, isEmpty);
      expect(h.messagingInitializations, 0);
    },
  );

  test(
    'iOS deferred permission result still initializes native notifications',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final h = _Harness();
      addTearDown(h.dispose);
      h.plugin.initializeAction = () async => false;
      var nativeLookups = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_nativeChannel, (call) async {
            if (call.method != 'getInitialNotification') return null;
            nativeLookups++;
            return _message(_ownerA).data;
          });
      await h.service.synchronizeOwner(h.owner);
      final taps = <CollectNotificationIntent>[];
      final subscription = h.service.notificationTapPayloads.listen(taps.add);
      addTearDown(subscription.cancel);

      await h.service.initialize();
      await h.service.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(nativeLookups, 1);
      expect(h.plugin.initializations, 1);
      expect(h.plugin.launchLookups, 1);
      expect(taps, hasLength(1));
      expect(taps.single.recipientId, _ownerA);
      expect(
        h.service.registrationStatus.value,
        CollectNotificationStatus.notRequested,
      );
    },
  );

  test(
    'iOS native launch lookup retries without replaying successful setup',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final h = _Harness();
      addTearDown(h.dispose);
      await h.service.synchronizeOwner(h.owner);
      var nativeLookups = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_nativeChannel, (call) async {
            if (call.method != 'getInitialNotification') return null;
            nativeLookups++;
            if (nativeLookups == 1) throw PlatformException(code: 'temporary');
            return _message(_ownerA).data;
          });
      final taps = <CollectNotificationIntent>[];
      final subscription = h.service.notificationTapPayloads.listen(taps.add);
      addTearDown(subscription.cancel);

      await h.service.initialize();
      await h.service.initialize();
      await h.service.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(nativeLookups, 2);
      expect(h.plugin.initializations, 1);
      expect(h.plugin.launchLookups, 1);
      expect(taps, hasLength(1));
      expect(taps.single.recipientId, _ownerA);
      expect(h.messagingInitializations, 0);
    },
  );
}

class _Harness {
  _Harness() {
    initializeMessaging = () async => messaging;
    service = CollectNotificationService(
      plugin: plugin,
      nativeChannel: _nativeChannel,
      authenticatedUserId: () => owner,
      authenticatedSessionId: () => session,
      androidMessagingInitializer: () {
        messagingInitializations++;
        return initializeMessaging();
      },
      androidForegroundMessages: foreground,
      androidTapMessages: taps,
    );
  }

  final plugin = _Plugin();
  final messaging = _Messaging();
  final foreground = _TrackedStream<RemoteMessage>();
  final taps = _TrackedStream<RemoteMessage>();
  final repository = _Repository();
  late final CollectNotificationService service;
  late Future<FirebaseMessaging> Function() initializeMessaging;
  int messagingInitializations = 0;
  String? owner = _ownerA;
  String? session = 'session-a';

  Future<void> dispose() async {
    await service.dispose();
    await foreground.close();
    await taps.close();
    await messaging.tokens.close();
  }
}

class _TrackedStream<T> extends Stream<T> {
  final _controller = StreamController<T>.broadcast();
  int subscriptions = 0;
  bool get hasListener => _controller.hasListener;
  void add(T event) => _controller.add(event);
  Future<void> close() async => _controller.close();

  @override
  StreamSubscription<T> listen(
    void Function(T)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    subscriptions++;
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

class _Messaging implements FirebaseMessaging {
  final tokens = _TrackedStream<String>();
  Future<RemoteMessage?> Function() initialAction = () async => null;
  int initialLookups = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Stream<String> get onTokenRefresh => tokens;

  @override
  Future<RemoteMessage?> getInitialMessage() {
    initialLookups++;
    return initialAction();
  }

  @override
  Future<void> setAutoInitEnabled(bool enabled) async {}

  @override
  Future<String?> getToken({
    String? vapidKey,
    String? serviceWorkerScriptPath,
  }) async => _token;
}

class _Plugin implements FlutterLocalNotificationsPlugin {
  final android = _AndroidPlugin();
  Future<bool?> Function() initializeAction = () async => true;
  Future<NotificationAppLaunchDetails?> Function() launchAction = () async =>
      null;
  int initializations = 0;
  int launchLookups = 0;
  final shown = <({String? title, String? body, String? payload})>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #resolvePlatformSpecificImplementation) {
      return android;
    }
    return super.noSuchMethod(invocation);
  }

  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) {
    initializations++;
    return initializeAction();
  }

  @override
  Future<NotificationAppLaunchDetails?> getNotificationAppLaunchDetails() {
    launchLookups++;
    return launchAction();
  }

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async {
    shown.add((title: title, body: body, payload: payload));
  }
}

class _AndroidPlugin implements AndroidFlutterLocalNotificationsPlugin {
  final channels = <AndroidNotificationChannel>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> createNotificationChannel(
    AndroidNotificationChannel channel,
  ) async {
    channels.add(channel);
  }

  @override
  Future<bool?> areNotificationsEnabled() async => true;

  @override
  Future<bool?> requestNotificationsPermission() async => true;
}

class _Repository implements CollectRepository {
  final tokens = <String>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> registerNotificationDevice({
    required String platform,
    required String provider,
    required String token,
    required String environment,
  }) async {
    tokens.add(token);
  }

  @override
  bool isNotificationDeviceRegistered({
    required String provider,
    required String token,
  }) => tokens.contains(token);
}
