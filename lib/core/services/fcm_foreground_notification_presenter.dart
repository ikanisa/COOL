import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

typedef FcmNotificationSelectHandler = FutureOr<void> Function(String? payload);

abstract class FcmForegroundNotificationPresenter {
  Future<void> initialize({
    required FcmNotificationSelectHandler onSelectNotification,
  });

  Future<void> show({
    required String title,
    required String body,
    String? payload,
  });
}

class NoopFcmForegroundNotificationPresenter
    implements FcmForegroundNotificationPresenter {
  const NoopFcmForegroundNotificationPresenter();

  @override
  Future<void> initialize({
    required FcmNotificationSelectHandler onSelectNotification,
  }) async {}

  @override
  Future<void> show({
    required String title,
    required String body,
    String? payload,
  }) async {}
}

class LocalFcmForegroundNotificationPresenter
    implements FcmForegroundNotificationPresenter {
  LocalFcmForegroundNotificationPresenter({
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const channelId = 'cool_default';
  static const channelName = 'Cool Alerts';
  static const channelDescription =
      'Payment updates, group activity, and partner announcements.';

  final FlutterLocalNotificationsPlugin _plugin;

  bool _isInitialized = false;
  int _nextNotificationId = 1;

  @override
  Future<void> initialize({
    required FcmNotificationSelectHandler onSelectNotification,
  }) async {
    if (_isInitialized) {
      return;
    }

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    await _plugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (response) async {
        await onSelectNotification(response.payload);
      },
    );
    _isInitialized = true;
  }

  @override
  Future<void> show({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_isInitialized) {
      return;
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _plugin.show(
      id: _nextNotificationId++,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }
}
