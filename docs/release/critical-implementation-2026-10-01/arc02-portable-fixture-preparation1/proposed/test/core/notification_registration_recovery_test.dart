import 'dart:async';
import 'dart:ui' as ui;

import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/notifications/collect_notification_service.dart';
import 'package:collect_app/features/settings/app_permissions_screen.dart';
import 'package:collect_app/features/status/native_permission_sheets.dart';
import 'package:collect_app/shared/providers/collect_app_state.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/test_capture_paths.dart';

const _a = '99910000-0000-4000-8000-000000000001';
const _b = '99910000-0000-4000-8000-000000000002';
const _candidate = CollectNotificationRegistration(
  platform: 'ios',
  provider: 'apns',
  token: 'synthetic-device-token',
  environment: 'sandbox',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final entry in {
      'Inter': 'assets/typefaces/Inter-Variable.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(
        entry.key,
      )..addFont(rootBundle.load(entry.value))).load();
    }
  });
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/permissions/methods'),
          (call) async => call.method == 'openAppSettings' ? true : 1,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/permissions/methods'),
          null,
        );
  });

  test(
    'permission denial is separate from unavailable provider and network retry',
    () async {
      final h = await _Harness.create();
      h.service.allowed = false;
      expect(await h.service.enableDevice(h.repo), isFalse);
      expect(h.status, CollectNotificationStatus.permissionDenied);
      expect(h.repo.tokens, isEmpty);
      h.service.allowed = true;
      h.service.candidate = null;
      expect(await h.service.registerDevice(h.repo), isFalse);
      expect(h.status, CollectNotificationStatus.unavailable);
      h.service.candidate = _candidate;
      h.repo.action = (_) async =>
          throw StateError('synthetic private provider detail');
      expect(await h.service.registerDevice(h.repo), isFalse);
      expect(h.status, CollectNotificationStatus.retryRequired);
      expect(h.status.message, isNot(contains('private')));
    },
  );

  test(
    'connection remains pending until server acknowledgement and retries unchanged token',
    () async {
      final h = await _Harness.create();
      final gate = Completer<void>();
      h.repo.action = (_) => gate.future;
      final pending = h.service.registerDevice(h.repo);
      await Future<void>.delayed(Duration.zero);
      expect(h.status, CollectNotificationStatus.checking);
      gate.completeError(StateError('network unavailable'));
      expect(await pending, isFalse);
      expect(h.status, CollectNotificationStatus.retryRequired);
      h.repo.action = (_) async {};
      expect(await h.service.registerDevice(h.repo), isTrue);
      expect(h.status, CollectNotificationStatus.ready);
      expect(h.repo.tokens, [_candidate.token, _candidate.token]);
    },
  );

  test(
    'a no-op repository result cannot announce a connected device',
    () async {
      final h = await _Harness.create();
      h.repo.acknowledges = false;
      expect(await h.service.registerDevice(h.repo), isFalse);
      expect(h.status, CollectNotificationStatus.retryRequired);
    },
  );

  for (final error in [
    StateError('Sign in again to register notifications on this device.'),
    const PostgrestException(
      message: 'notification_registration_session_stale',
      code: '42501',
    ),
  ]) {
    test(
      'stale session maps to fresh-login recovery for ${error.runtimeType}',
      () async {
        final h = await _Harness.create();
        h.repo.action = (_) async => throw error;
        expect(await h.service.registerDevice(h.repo), isFalse);
        expect(h.status, CollectNotificationStatus.signInRequired);
        h.session = 'new-session';
        await h.service.synchronizeOwner(h.owner);
        expect(h.status, CollectNotificationStatus.notRequested);
        h.repo.action = (_) async {};
        expect(await h.service.registerDevice(h.repo), isTrue);
      },
    );
  }

  for (final sameUser in [false, true]) {
    test(
      'late old-session error cannot replace ${sameUser ? 'same-user new session' : 'new account'} status',
      () async {
        final h = await _Harness.create();
        final gate = Completer<void>();
        h.repo.action = (_) => gate.future;
        final pending = h.service.registerDevice(h.repo);
        await Future<void>.delayed(Duration.zero);
        h.owner = sameUser ? _a : _b;
        h.session = 'session-b';
        await h.service.synchronizeOwner(h.owner);
        h.repo.action = (_) async {};
        expect(await h.service.registerDevice(h.repo), isTrue);
        gate.completeError(
          StateError('Sign in again to register notifications on this device.'),
        );
        expect(await pending, isFalse);
        expect(h.status, CollectNotificationStatus.ready);
      },
    );
  }

  test(
    'direct auth change fences permission result before synchronization',
    () async {
      final h = await _Harness.create();
      h.service.permissionGate = Completer<bool>();
      final pending = h.service.enableDevice(h.repo);
      h.owner = _b;
      h.session = 'session-b';
      h.service.permissionGate!.complete(true);
      expect(await pending, isFalse);
      expect(h.repo.tokens, isEmpty);
      await h.service.synchronizeOwner(_b);
      expect(h.status, CollectNotificationStatus.notRequested);
    },
  );

  test(
    'new token acknowledgement wins over delayed old token failure',
    () async {
      final h = await _Harness.create();
      final gate = Completer<void>();
      h.repo.action = (token) =>
          token == _candidate.token ? gate.future : Future.value();
      final original = h.service.registerDevice(h.repo);
      await Future<void>.delayed(Duration.zero);
      h.service.candidate = const CollectNotificationRegistration(
        platform: 'ios',
        provider: 'apns',
        token: 'rotated-device-token',
        environment: 'sandbox',
      );
      expect(await h.service.registerDevice(h.repo), isTrue);
      gate.completeError(StateError('old network error'));
      expect(await original, isFalse);
      expect(h.status, CollectNotificationStatus.ready);
    },
  );

  test('permission revoked on resume removes connected status', () async {
    final h = await _Harness.create();
    expect(await h.service.registerDevice(h.repo), isTrue);
    h.service.allowed = false;
    expect(await h.service.registerDevice(h.repo), isFalse);
    expect(h.status, CollectNotificationStatus.permissionDenied);
  });

  test(
    'native token refresh publishes failure and retries the rotated token on resume',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      const channel = MethodChannel('app.cool.mobile/notifications');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => switch (call.method) {
          'requestRemoteRegistration' => _candidate.token,
          'getRemoteEnvironment' => 'sandbox',
          _ => null,
        },
      );
      final service = _NativeService();
      final repo = _Repository();
      addTearDown(() async {
        await service.dispose();
        repo.dispose();
        messenger.setMockMethodCallHandler(channel, null);
        debugDefaultTargetPlatformOverride = null;
      });
      await service.synchronizeOwner(_a);
      expect(await service.registerDevice(repo), isTrue);
      final failed = Completer<void>();
      void changed() {
        if (service.registrationStatus.value ==
                CollectNotificationStatus.retryRequired &&
            !failed.isCompleted) {
          failed.complete();
        }
      }

      service.registrationStatus.addListener(changed);
      repo.action = (_) async => throw StateError('network unavailable');
      final delivered = Completer<void>();
      // This simulates an incoming APNs method-channel token callback.
      // ignore: deprecated_member_use
      messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('remoteToken', 'rotated-native-token'),
        ),
        (_) => delivered.complete(),
      );
      await delivered.future.timeout(const Duration(seconds: 3));
      await failed.future.timeout(const Duration(seconds: 3));
      repo.action = (_) async {};
      expect(await service.registerDevice(repo), isTrue);
      expect(repo.tokens, [
        _candidate.token,
        'rotated-native-token',
        'rotated-native-token',
      ]);
      service.registrationStatus.removeListener(changed);
    },
  );

  testWidgets(
    'settings shows network recovery, retries and waits for acknowledgement',
    (tester) async {
      final h = await _Harness.create();
      h.repo.action = (_) async => throw StateError('private server content');
      await _pumpSettings(tester, h);
      expect(
        find.text(CollectNotificationStatus.retryRequired.message),
        findsOneWidget,
      );
      expect(find.textContaining('private server'), findsNothing);
      final gate = Completer<void>();
      h.repo.action = (_) => gate.future;
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(find.text('Connecting'), findsOneWidget);
      expect(find.text(CollectNotificationStatus.ready.message), findsNothing);
      gate.complete();
      await tester.pumpAndSettle();
      expect(
        find.text(CollectNotificationStatus.ready.message),
        findsOneWidget,
      );
      expect(h.repo.tokens.toSet(), {_candidate.token});
    },
  );

  testWidgets(
    'a stalled connection becomes retryable and a late response cannot announce success',
    (tester) async {
      final h = await _Harness.create();
      final gate = Completer<void>();
      h.repo.action = (_) => gate.future;
      await _pumpSettings(tester, h);
      expect(find.text('Connecting'), findsOneWidget);
      await tester.pump(const Duration(seconds: 21));
      await tester.pump();
      expect(find.text('Retry'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text(CollectNotificationStatus.ready.message), findsNothing);
      h.repo.action = (_) async {};
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(
        find.text(CollectNotificationStatus.ready.message),
        findsOneWidget,
      );
    },
  );

  testWidgets('settings offers phone settings when permission is denied', (
    tester,
  ) async {
    final h = await _Harness.create();
    h.service.allowed = false;
    await _pumpSettings(tester, h);
    expect(
      find.text(CollectNotificationStatus.permissionDenied.message),
      findsOneWidget,
    );
    expect(find.text('Phone settings'), findsWidgets);
    expect(h.repo.tokens, isEmpty);
  });

  testWidgets(
    'stale session has a working sign-in action and large text stays usable',
    (tester) async {
      final h = await _Harness.create();
      h.repo.action = (_) async => throw const PostgrestException(
        message: 'notification_registration_session_stale',
        code: '42501',
      );
      await _pumpSettings(tester, h, scale: 2, width: 320);
      expect(find.text('Sign in again'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Sign in again'));
      await tester.tap(find.text('Sign in again'));
      await tester.pumpAndSettle();
      expect(h.repo.signOuts, 1);
      expect(find.text('Synthetic sign-in'), findsOneWidget);
    },
  );

  testWidgets(
    'permission sheet reports connection failure instead of false success',
    (tester) async {
      final h = await _Harness.create();
      h.repo.action = (_) async => throw StateError('network unavailable');
      await _pumpSettings(tester, h, sheet: true);
      await tester.tap(find.text('Review notifications'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enable'));
      await tester.pumpAndSettle();
      expect(
        find.text(CollectNotificationStatus.retryRequired.message),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
      h.repo.action = (_) async {};
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsNothing);
      expect(h.status, CollectNotificationStatus.ready);
      expect(h.service.confirmationNotifications, 0);
    },
  );

  testWidgets(
    'pending permission sheet prevents duplicate activation and respects dismissal',
    (tester) async {
      final h = await _Harness.create();
      final gate = Completer<void>();
      h.repo.action = (_) => gate.future;
      await _pumpSettings(tester, h, sheet: true);
      await tester.tap(find.text('Review notifications'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enable'));
      await tester.pump();
      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Enable'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNull);
      expect(h.repo.tokens, hasLength(1));
      Navigator.of(
        tester.element(find.text('Enable')),
        rootNavigator: true,
      ).pop();
      await tester.pumpAndSettle();
      gate.completeError(StateError('network unavailable'));
      await tester.pumpAndSettle();
      expect(find.text('Review notifications'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    },
  );

  testWidgets('new account receives no old permission sheet failure', (
    tester,
  ) async {
    final h = await _Harness.create();
    final gate = Completer<void>();
    h.repo.action = (_) => gate.future;
    await _pumpSettings(tester, h, sheet: true);
    await tester.tap(find.text('Review notifications'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enable'));
    await tester.pump();
    h.owner = _b;
    h.session = 'session-b';
    await h.service.synchronizeOwner(_b);
    gate.completeError(StateError('network unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsNothing);
    expect(
      find.text(CollectNotificationStatus.retryRequired.message),
      findsNothing,
    );
  });

  testWidgets(
    'recovery settings dark and enlarged light captures have no overflow',
    (tester) async {
      final h = await _Harness.create();
      h.repo.action = (_) async => throw StateError('network unavailable');
      for (final dark in [false, true]) {
        await _pumpSettings(
          tester,
          h,
          dark: dark,
          scale: dark ? 1 : 1.6,
          width: 390,
        );
        expect(tester.takeException(), isNull);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = collectTestCaptureFile(
            'settings-${dark ? 'dark' : 'large-light'}.png',
          );
          await file.writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    },
  );
}

class _Harness {
  String owner = _a, session = 'session-a';
  late _Service service;
  final _Repository repo = _Repository();
  CollectNotificationStatus get status => service.registrationStatus.value;
  static Future<_Harness> create() async {
    final h = _Harness();
    h.service = _Service(() => h.owner, () => h.session);
    await h.service.synchronizeOwner(_a);
    addTearDown(() {
      unawaited(h.service.dispose());
      if (h.repo.mounted) h.repo.dispose();
    });
    return h;
  }
}

class _Service extends CollectNotificationService {
  _Service(String? Function() owner, String? Function() session)
    : super(
        plugin: _Plugin(),
        authenticatedUserId: owner,
        authenticatedSessionId: session,
      );
  bool allowed = true;
  Completer<bool>? permissionGate;
  CollectNotificationRegistration? candidate = _candidate;
  int confirmationNotifications = 0;
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> requestPermission() async =>
      permissionGate == null ? allowed : await permissionGate!.future;
  @override
  Future<bool> areNotificationsEnabled() async => allowed;
  @override
  Future<CollectNotificationRegistration?> registration() async => candidate;
  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
    String? eventType,
  }) async {
    confirmationNotifications++;
  }
}

class _Repository extends CollectRepository {
  _Repository()
    : super.fixture(
        initialState: const CollectState(
          currentProfile: null,
          collections: [],
          paymentIntents: [],
          contributions: [],
        ),
      );
  final tokens = <String>[];
  Future<void> Function(String) action = (_) async {};
  bool acknowledges = true;
  String? ackToken;
  int signOuts = 0;
  @override
  Future<void> registerNotificationDevice({
    required String platform,
    required String provider,
    required String token,
    required String environment,
  }) async {
    tokens.add(token);
    await action(token);
    if (acknowledges) ackToken = token;
  }

  @override
  bool isNotificationDeviceRegistered({
    required String provider,
    required String token,
  }) => acknowledges && ackToken == token;
  @override
  Future<void> signOut() async {
    signOuts++;
  }
}

Future<void> _pumpSettings(
  WidgetTester tester,
  _Harness h, {
  bool sheet = false,
  double scale = 1,
  double width = 390,
  bool dark = false,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => sheet
            ? Consumer(
                builder: (context, ref, _) => Scaffold(
                  body: TextButton(
                    onPressed: () =>
                        showNotificationSettingsSheet(context, ref),
                    child: const Text('Review notifications'),
                  ),
                ),
              )
            : const AppPermissionsScreen(),
      ),
      GoRoute(
        path: '/auth',
        builder: (_, _) => const Scaffold(body: Text('Synthetic sign-in')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        collectNotificationServiceProvider.overrideWithValue(h.service),
        collectRepositoryProvider.overrideWith((ref) => h.repo),
        momoReceiptCaptureAvailableProvider.overrideWithValue(false),
      ],
      child: RepaintBoundary(
        key: const ValueKey('capture'),
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _Plugin implements FlutterLocalNotificationsPlugin {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async => true;
  @override
  Future<NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async => null;
  @override
  Future<void> cancelAll() async {}
}

class _NativeService extends CollectNotificationService {
  _NativeService()
    : super(
        plugin: _Plugin(),
        authenticatedUserId: () => _a,
        authenticatedSessionId: () => 'session-a',
      );
  @override
  Future<bool> areNotificationsEnabled() async => true;
}
