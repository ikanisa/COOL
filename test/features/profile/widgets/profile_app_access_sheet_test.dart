import 'package:cool_app/core/providers/app_access_provider.dart';
import 'package:cool_app/core/providers/engagement_providers.dart';
import 'package:cool_app/core/services/fcm_service.dart';
import 'package:cool_app/features/profile/widgets/profile_app_access_sheet.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_app_access_service.dart';

class _MemoryFcmPreferenceStore implements FcmPreferenceStore {
  _MemoryFcmPreferenceStore(this.enabled);

  bool enabled;

  @override
  Future<bool> readEnabled() async => enabled;

  @override
  Future<void> writeEnabled(bool enabled) async {
    this.enabled = enabled;
  }
}

class _NoopFcmTokenRepository implements FcmTokenRepository {
  @override
  Future<void> deleteToken({
    required String userId,
    required String token,
  }) async {}

  @override
  Future<void> upsertToken({
    required String userId,
    required String token,
    required String platform,
  }) async {}
}

class _FakeFcmMessagingClient implements FcmMessagingClient {
  _FakeFcmMessagingClient(this.authorizationStatus);

  final FcmAuthorizationStatus authorizationStatus;

  @override
  Future<FcmAuthorizationStatus> getAuthorizationStatus() async {
    return authorizationStatus;
  }

  @override
  Future<RemoteMessage?> getInitialMessage() async => null;

  @override
  Future<String?> getToken() async => null;

  @override
  Stream<RemoteMessage> get onMessage => const Stream.empty();

  @override
  Stream<RemoteMessage> get onMessageOpenedApp => const Stream.empty();

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();

  @override
  void registerBackgroundHandler() {}

  @override
  Future<FcmAuthorizationStatus> requestPermission() async {
    return authorizationStatus;
  }

  @override
  Future<void> deleteToken() async {}

  @override
  Future<void> subscribeToTopic(String topic) async {}

  @override
  Future<void> unsubscribeFromTopic(String topic) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'shows system recovery when notifications are blocked even if in-app toggle is off',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 2560);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final appAccessService = FakeAppAccessService();
      final fcmService = FcmService(
        messagingClient: _FakeFcmMessagingClient(FcmAuthorizationStatus.denied),
        preferenceStore: _MemoryFcmPreferenceStore(false),
        tokenRepository: _NoopFcmTokenRepository(),
        isFirebaseAvailable: () => true,
      );
      addTearDown(fcmService.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appAccessServiceProvider.overrideWithValue(appAccessService),
            fcmServiceProvider.overrideWithValue(fcmService),
          ],
          child: const MaterialApp(
            home: Scaffold(body: ProfileAppAccessSheet()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Blocked in system'), findsOneWidget);
      expect(find.text('Open system settings'), findsOneWidget);
      expect(
        find.text(
          'System notification access is blocked. Open settings to allow push alerts again.',
        ),
        findsOneWidget,
      );
    },
  );
}
