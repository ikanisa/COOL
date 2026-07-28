import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../shared/repositories/collect_repository.dart';
import '../security/hash_utils.dart';

final collectNotificationServiceProvider = Provider<CollectNotificationService>(
  (ref) => CollectNotificationService(),
);

class CollectNotificationRegistration {
  const CollectNotificationRegistration({
    required this.platform,
    required this.tokenHash,
    required this.tokenLastFour,
  });

  final String platform;
  final String tokenHash;
  final String tokenLastFour;
}

class CollectNotificationService {
  CollectNotificationService({
    FlutterLocalNotificationsPlugin? plugin,
    SharedPreferencesAsync? preferences,
  }) : this._(plugin ?? FlutterLocalNotificationsPlugin(), preferences);

  CollectNotificationService._(this._plugin, this._preferences);

  static const _installTokenKey = 'collect.notification.install_token.v1';
  static const _androidChannelId = 'collect_group_updates';
  static const _androidChannelName = 'Collect group updates';
  static const _androidChannelDescription =
      'Contribution confirmations, payment reminders, group updates, and security notices.';
  static const _positiveNotificationIdMask = 2147483647;

  final FlutterLocalNotificationsPlugin _plugin;
  final SharedPreferencesAsync? _preferences;
  final _uuid = const Uuid();
  Future<void>? _initializing;

  Future<void> initialize() {
    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    if (kIsWeb) return;
    try {
      const android = AndroidInitializationSettings('@drawable/transparent');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const settings = InitializationSettings(android: android, iOS: ios);
      await _plugin.initialize(settings: settings);
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _androidChannelId,
              _androidChannelName,
              description: _androidChannelDescription,
              importance: Importance.high,
            ),
          );
    } catch (_) {
      // Widget tests and unsupported platforms do not register native plugins.
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

  Future<CollectNotificationRegistration> registration() async {
    final token = await _installToken();
    return CollectNotificationRegistration(
      platform: _platformName,
      tokenHash: HashUtils.sha256Hex('collect-notification:$token'),
      tokenLastFour: token.substring(token.length - 4),
    );
  }

  Future<void> registerDevice(CollectRepository repository) async {
    final registration = await this.registration();
    await repository.registerNotificationDevice(
      platform: registration.platform,
      tokenHash: registration.tokenHash,
      tokenLastFour: registration.tokenLastFour,
    );
  }

  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    await initialize();
    if (kIsWeb) return;
    try {
      await _plugin.show(
        id: _notificationId(title, body),
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _androidChannelId,
            _androidChannelName,
            channelDescription: _androidChannelDescription,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
          ),
          iOS: DarwinNotificationDetails(
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

  Future<String> _installToken() async {
    final preferences = _preferences ?? SharedPreferencesAsync();
    final existing = await preferences.getString(_installTokenKey);
    if (existing != null && existing.trim().isNotEmpty) return existing;
    final token = '$_platformName-${_uuid.v4()}';
    await preferences.setString(_installTokenKey, token);
    return token;
  }

  int _notificationId(String title, String body) {
    final digest = sha1.convert('$title|$body'.codeUnits).bytes;
    return digest.take(4).fold<int>(0, (value, byte) => (value << 8) + byte) &
        _positiveNotificationIdMask;
  }

  String get _platformName {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => 'web',
    };
  }
}
