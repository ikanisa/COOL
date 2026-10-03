import 'dart:async';
import 'dart:convert';

import 'package:collect_app/core/notifications/collect_notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

const _ownerA = '99910000-0000-4000-8000-000000000001';
const _ownerB = '99910000-0000-4000-8000-000000000002';
const _event = '99910000-0000-4000-8000-000000000099';

Map<String, Object?> _payload(String recipient) => {
  'collect_push_version': '2',
  'recipient_id': recipient,
  'collect_event_id': _event,
  'deep_link': '/groups/group-1/ledger',
  'type': 'contribution_confirmed',
  // These adversarial fields must never become a device preview.
  'title': 'Private member name',
  'body': 'RWF 250,000 private contribution',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.linux);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'current owner receives only generic text and a bound tap payload',
    () async {
      final plugin = _NotificationPlugin();
      final service = CollectNotificationService(
        plugin: plugin,
        authenticatedUserId: () => _ownerA,
      );
      addTearDown(service.dispose);
      await service.synchronizeOwner(_ownerA);
      await service.handleForegroundPayload(_payload(_ownerA));
      expect(plugin.shown, hasLength(1));
      expect(plugin.shown.single.title, 'Collect');
      expect(plugin.shown.single.body, 'Open Collect to view your updates.');
      final data = jsonDecode(plugin.shown.single.payload!) as Map;
      expect(data['recipient_id'], _ownerA);
      expect(data['collect_event_id'], _event);
      expect(data.containsKey('body'), isFalse);
      expect(data.containsKey('title'), isFalse);
    },
  );

  for (final invalid in <String, Map<String, Object?>>{
    'wrong owner': _payload(_ownerB),
    'missing owner': _payload(_ownerA)..remove('recipient_id'),
    'malformed owner': _payload(_ownerA)..['recipient_id'] = '../owner',
    'missing contract': _payload(_ownerA)..remove('collect_push_version'),
    'future contract': _payload(_ownerA)..['collect_push_version'] = '3',
    'numeric contract': _payload(_ownerA)..['collect_push_version'] = 2,
    'missing event': _payload(_ownerA)..remove('collect_event_id'),
    'malformed event': _payload(_ownerA)..['collect_event_id'] = 'private text',
  }.entries) {
    test('${invalid.key} cannot display or navigate', () async {
      final plugin = _NotificationPlugin();
      final service = CollectNotificationService(
        plugin: plugin,
        authenticatedUserId: () => _ownerA,
      );
      addTearDown(service.dispose);
      await service.synchronizeOwner(_ownerA);
      final taps = <CollectNotificationIntent>[];
      final subscription = service.notificationTapPayloads.listen(taps.add);
      addTearDown(subscription.cancel);
      await service.handleForegroundPayload(invalid.value);
      service.handleRemoteTap(invalid.value);
      await Future<void>.delayed(Duration.zero);
      expect(plugin.shown, isEmpty);
      expect(taps, isEmpty);
    });
  }

  test(
    'signed-out startup clears existing notifications and denies messages',
    () async {
      final plugin = _NotificationPlugin();
      final service = CollectNotificationService(plugin: plugin);
      addTearDown(service.dispose);
      await service.synchronizeOwner(null);
      expect(plugin.cancellations, 1);
      await service.handleForegroundPayload(_payload(_ownerA));
      expect(plugin.shown, isEmpty);
    },
  );

  test(
    'direct Auth change denies old owner before stream synchronization',
    () async {
      var current = _ownerA;
      final plugin = _NotificationPlugin();
      final service = CollectNotificationService(
        plugin: plugin,
        authenticatedUserId: () => current,
      );
      addTearDown(service.dispose);
      await service.synchronizeOwner(_ownerA);
      current = _ownerB;
      await service.handleForegroundPayload(_payload(_ownerA));
      expect(plugin.shown, isEmpty);
    },
  );

  test(
    'account switch during native initialization cancels old display',
    () async {
      var current = _ownerA;
      final plugin = _NotificationPlugin()
        ..initializationGate = Completer<void>();
      final service = CollectNotificationService(
        plugin: plugin,
        authenticatedUserId: () => current,
      );
      addTearDown(service.dispose);
      await service.synchronizeOwner(_ownerA);
      final display = service.handleForegroundPayload(_payload(_ownerA));
      await plugin.initializationStarted.future;
      current = _ownerB;
      final clear = service.synchronizeOwner(_ownerB);
      plugin.initializationGate!.complete();
      await Future.wait([display, clear]);
      expect(plugin.shown, isEmpty);
      expect(plugin.active, isEmpty);
    },
  );

  test('in-flight old show is cleared before the new owner display', () async {
    var current = _ownerA;
    final plugin = _NotificationPlugin()..firstShowGate = Completer<void>();
    final service = CollectNotificationService(
      plugin: plugin,
      authenticatedUserId: () => current,
    );
    addTearDown(service.dispose);
    await service.synchronizeOwner(_ownerA);
    final oldDisplay = service.handleForegroundPayload(_payload(_ownerA));
    await plugin.firstShowStarted.future;
    current = _ownerB;
    final clear = service.synchronizeOwner(_ownerB);
    final newDisplay = service.handleForegroundPayload(_payload(_ownerB));
    plugin.firstShowGate!.complete();
    await Future.wait([oldDisplay, clear, newDisplay]);
    expect(plugin.active, hasLength(1));
    expect(jsonDecode(plugin.active.single.payload!)['recipient_id'], _ownerB);
    expect(plugin.operations, ['clear', 'show', 'clear', 'show']);
  });

  test(
    'tap remains recipient-bound and old displayed payload is rejected',
    () async {
      var current = _ownerA;
      final plugin = _NotificationPlugin();
      final service = CollectNotificationService(
        plugin: plugin,
        authenticatedUserId: () => current,
      );
      addTearDown(service.dispose);
      await service.synchronizeOwner(_ownerA);
      final taps = <CollectNotificationIntent>[];
      final subscription = service.notificationTapPayloads.listen(taps.add);
      addTearDown(subscription.cancel);
      await service.handleForegroundPayload(_payload(_ownerA));
      plugin.tap(plugin.shown.single.payload);
      await Future<void>.delayed(Duration.zero);
      expect(taps, hasLength(1));
      expect(taps.single.recipientId, _ownerA);
      current = _ownerB;
      plugin.tap(plugin.shown.single.payload);
      service.handleRemoteTap(_payload(_ownerA));
      await Future<void>.delayed(Duration.zero);
      expect(taps, hasLength(1));
    },
  );

  test(
    'legacy private routes and external links cannot select resources',
    () async {
      final plugin = _NotificationPlugin();
      final service = CollectNotificationService(plugin: plugin);
      addTearDown(service.dispose);
      await service.synchronizeOwner(_ownerA);
      await service.initialize();
      final taps = <CollectNotificationIntent>[];
      final subscription = service.notificationTapPayloads.listen(taps.add);
      addTearDown(subscription.cancel);
      plugin.tap('/groups/group-1/ledger');
      service.handleRemoteTap(
        _payload(_ownerA)..['deep_link'] = 'https://evil.example',
      );
      service.handleRemoteTap(
        _payload(_ownerA)..['deep_link'] = '/settings/account/delete',
      );
      plugin.tap('/home');
      await Future<void>.delayed(Duration.zero);
      expect(taps, hasLength(1));
      expect(taps.single.deepLink, '/home');
    },
  );

  test('disposed service clears displays and rejects future work', () async {
    final plugin = _NotificationPlugin();
    final service = CollectNotificationService(plugin: plugin);
    await service.synchronizeOwner(_ownerA);
    await service.handleForegroundPayload(_payload(_ownerA));
    await service.dispose();
    await service.handleForegroundPayload(_payload(_ownerA));
    service.handleRemoteTap(_payload(_ownerA));
    expect(plugin.shown, hasLength(1));
    expect(plugin.active, isEmpty);
  });
}

typedef _Shown = ({String? title, String? body, String? payload});

class _NotificationPlugin implements FlutterLocalNotificationsPlugin {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
  Completer<void>? initializationGate;
  Completer<void>? firstShowGate;
  final initializationStarted = Completer<void>();
  final firstShowStarted = Completer<void>();
  final shown = <_Shown>[];
  final active = <_Shown>[];
  final operations = <String>[];
  int cancellations = 0;
  DidReceiveNotificationResponseCallback? onResponse;

  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {
    onResponse = onDidReceiveNotificationResponse;
    if (!initializationStarted.isCompleted) initializationStarted.complete();
    await initializationGate?.future;
    return true;
  }

  @override
  Future<NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async => null;

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async {
    if (!firstShowStarted.isCompleted) {
      firstShowStarted.complete();
      await firstShowGate?.future;
    }
    operations.add('show');
    final value = (title: title, body: body, payload: payload);
    shown.add(value);
    active.add(value);
  }

  @override
  Future<void> cancelAll() async {
    cancellations++;
    operations.add('clear');
    active.clear();
  }

  void tap(String? payload) => onResponse?.call(
    NotificationResponse(
      notificationResponseType: NotificationResponseType.selectedNotification,
      payload: payload,
    ),
  );
}
