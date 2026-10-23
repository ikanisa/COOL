import '../fixtures/collect_repository_fixture.dart';

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:collect_app/core/security/sms_access_channel.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/providers/collect_app_state.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    const channel = MethodChannel('flutter.baseflow.com/permissions/methods');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'checkPermissionStatus') return 0;
          if (call.method == 'requestPermissions') return <int, int>{};
          return false;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/permissions/methods'),
          null,
        );
  });
  for (final country in ['RW', 'DE']) {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets(
        '$country / $platform offers SMS uploads only on Android without a MoMo profile',
        (tester) async {
          final repository = FixtureCollectRepository(
            profileOverride: CollectProfile(
              id: 'local-user',
              publicId: '038491',
              whatsappPhone: '+250788123456',
              countryCode: country,
              currencyCode: country == 'RW' ? 'RWF' : 'EUR',
            ),
          );
          final router = createAppRouter(
            initialLocation: '/settings/permissions',
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                collectBackendClientProvider.overrideWithValue(null),
                appRouterProvider.overrideWithValue(router),
                collectRepositoryProvider.overrideWith((ref) => repository),
              ],
              child: const CollectApp(),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.text('M-Money SMS'),
            platform == TargetPlatform.android ? findsOneWidget : findsNothing,
          );
          expect(find.text('MoMo receipt SMS'), findsNothing);
          expect(find.text('Rwanda MoMo receipts only'), findsNothing);
          expect(find.text('Retry uploads'), findsNothing);
          expect(find.text('Notifications'), findsOneWidget);
          await tester.scrollUntilVisible(
            find.text('Camera'),
            150,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(find.text('Camera'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(platform),
      );
    }
  }

  for (final platform in TargetPlatform.values) {
    test('$platform only exposes a supported device SMS-granted flag', () {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final repository = _EnabledSmsFixture();
      final container = ProviderContainer(
        overrides: [
          collectRepositoryProvider.overrideWith((ref) => repository),
        ],
      );
      addTearDown(container.dispose);
      expect(
        container.read(momoReceiptCaptureAvailableProvider),
        platform == TargetPlatform.android,
      );
      expect(
        container.read(smsPermissionStatusProvider),
        platform == TargetPlatform.android
            ? SmsPermissionStatus.granted
            : SmsPermissionStatus.unavailable,
      );
    });
  }

  for (final cancel in [false, true]) {
    testWidgets(
      'Android SMS consent ${cancel ? 'cancel' : 'allow'} needs no provider or recipient',
      (tester) async {
        final repository = _PermissionSmsFixture();
        if (!cancel) {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(320, 844);
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        }
        final router = createAppRouter(
          initialLocation: '/settings/permissions',
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              collectBackendClientProvider.overrideWithValue(null),
              appRouterProvider.overrideWithValue(router),
              collectRepositoryProvider.overrideWith((ref) => repository),
            ],
            child: const CollectApp(),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Allow').first);
        await tester.pumpAndSettle();
        expect(find.text('Allow M-Money SMS uploads?'), findsOneWidget);
        expect(
          find.textContaining('Original messages are protected'),
          findsOneWidget,
        );
        expect(
          find.textContaining('never credits a payment automatically'),
          findsOneWidget,
        );
        expect(find.textContaining('pair'), findsNothing);
        expect(find.textContaining('recipient'), findsNothing);
        expect(repository.enableCalls, isEmpty);
        await tester.ensureVisible(
          find.text(cancel ? 'Not now' : 'Allow SMS access'),
        );
        await tester.tap(find.text(cancel ? 'Not now' : 'Allow SMS access'));
        await tester.pumpAndSettle();
        expect(repository.enableCalls, cancel ? isEmpty : ['local-user']);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  testWidgets(
    'denied SMS request stays off and offers a clear retry',
    (tester) async {
      final repository = _PermissionSmsFixture(allowResult: false);
      final router = createAppRouter(initialLocation: '/settings/permissions');
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            collectBackendClientProvider.overrideWithValue(null),
            appRouterProvider.overrideWithValue(router),
            collectRepositoryProvider.overrideWith((ref) => repository),
          ],
          child: const CollectApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Allow').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Allow SMS access'));
      await tester.tap(find.text('Allow SMS access'));
      await tester.pumpAndSettle();
      expect(repository.enabled, isFalse);
      expect(find.text('M-Money SMS access was not enabled.'), findsOneWidget);
      expect(find.text('Allow').first.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'SMS consent cannot carry across an account change',
    (tester) async {
      final repository = _PermissionSmsFixture();
      final router = createAppRouter(initialLocation: '/settings/permissions');
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            collectBackendClientProvider.overrideWithValue(null),
            appRouterProvider.overrideWithValue(router),
            collectRepositoryProvider.overrideWith((ref) => repository),
          ],
          child: const CollectApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Allow').first);
      await tester.pumpAndSettle();
      repository.changeOwner();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Allow SMS access'));
      await tester.tap(find.text('Allow SMS access'));
      await tester.pumpAndSettle();
      expect(repository.enableCalls, isEmpty);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'permanently denied SMS access offers phone settings',
    (tester) async {
      final repository = _PermissionSmsFixture(permanentlyDenied: true);
      final router = createAppRouter(initialLocation: '/settings/permissions');
      addTearDown(router.dispose);
      var settingsCalls = 0;
      const sms = MethodChannel('collect/sms_access');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(sms, (call) async {
            if (call.method == 'openAppSettings') settingsCalls++;
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(sms, null),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            collectBackendClientProvider.overrideWithValue(null),
            appRouterProvider.overrideWithValue(router),
            collectRepositoryProvider.overrideWith((ref) => repository),
          ],
          child: const CollectApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Phone settings').first);
      await tester.pumpAndSettle();
      expect(settingsCalls, 1);
      expect(repository.enableCalls, isEmpty);
      expect(find.text('Allow M-Money SMS uploads?'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  for (final width in [320.0, 430.0]) {
    testWidgets(
      'permission status does not squeeze large titles at width $width',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 844);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final router = createAppRouter(
          initialLocation: '/settings/permissions',
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              collectBackendClientProvider.overrideWithValue(null),
              appRouterProvider.overrideWithValue(router),
              collectRepositoryProvider.overrideWith(
                (ref) => FixtureCollectRepository(),
              ),
            ],
            child: const CollectApp(),
          ),
        );
        await tester.pumpAndSettle();
        final title = find.text('Notifications');
        final paragraph = tester.renderObject<RenderParagraph>(title);
        expect(
          paragraph.getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 13),
          ),
          hasLength(1),
          reason: 'The status must not force a break within Notifications.',
        );
        expect(
          tester
              .getTopLeft(
                find.byKey(const ValueKey('permission_status_Notifications')),
              )
              .dy,
          greaterThan(tester.getBottomLeft(title).dy),
        );
        expect(
          find.text('Control only the device access Collect needs.'),
          findsNothing,
        );
        await tester.scrollUntilVisible(
          find.text('Camera'),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Camera').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }

  testWidgets(
    'parked SMS uploads offer one explicit owner-bound retry at large text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 844);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final repository = _PermissionSmsFixture(
        queueNeedsReview: true,
        initiallyEnabled: true,
      );
      final router = createAppRouter(initialLocation: '/settings/permissions');
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            collectBackendClientProvider.overrideWithValue(null),
            appRouterProvider.overrideWithValue(router),
            collectRepositoryProvider.overrideWith((ref) => repository),
          ],
          child: const CollectApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Originals stay on this phone.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Retry uploads'));
      await tester.tap(find.text('Retry uploads'));
      await tester.pumpAndSettle();
      expect(repository.retryOwners, ['local-user']);
      expect(repository.enableCalls, isEmpty);
      expect(find.text('Retry uploads'), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'parked SMS retry cannot turn withdrawn access back on',
    (tester) async {
      final repository = _PermissionSmsFixture(queueNeedsReview: true);
      final router = createAppRouter(initialLocation: '/settings/permissions');
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            collectBackendClientProvider.overrideWithValue(null),
            appRouterProvider.overrideWithValue(router),
            collectRepositoryProvider.overrideWith((ref) => repository),
          ],
          child: const CollectApp(),
        ),
      );
      await tester.pumpAndSettle();
      final retry = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Retry uploads'),
          matching: find.byType(TextButton),
        ),
      );
      expect(retry.onPressed, isNull);
      expect(repository.retryOwners, isEmpty);
      expect(repository.enableCalls, isEmpty);
      expect(find.textContaining('Allow SMS access to retry'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}

class _EnabledSmsFixture extends FixtureCollectRepository {
  _EnabledSmsFixture() : super() {
    state = state.copyWith(smsAccessEnabled: true);
  }
}

class _PermissionSmsFixture extends FixtureCollectRepository {
  _PermissionSmsFixture({
    this.permanentlyDenied = false,
    this.allowResult = true,
    this.queueNeedsReview = false,
    bool initiallyEnabled = false,
  }) : enabled = initiallyEnabled,
       super(
         profileOverride: const CollectProfile(
           id: 'local-user',
           publicId: '038491',
           whatsappPhone: '+49123456789',
           countryCode: 'DE',
           currencyCode: 'EUR',
         ),
       );

  final bool permanentlyDenied;
  final bool allowResult;
  bool queueNeedsReview;
  final enableCalls = <String?>[];
  final retryOwners = <String?>[];
  bool enabled;

  @override
  Future<SmsAccessStatus> refreshSmsAccessStatus() async => SmsAccessStatus(
    supported: true,
    declared: true,
    enabled: enabled,
    granted: enabled,
    requestedBefore: permanentlyDenied,
    shouldShowRationale: false,
    permanentlyDenied: permanentlyDenied,
    queueOverflowed: false,
    queueNeedsReview: queueNeedsReview,
  );

  @override
  Future<bool> setSmsAccess(bool value, {String? expectedOwnerUserId}) async {
    enableCalls.add(expectedOwnerUserId);
    enabled = value && allowResult;
    state = state.copyWith(smsAccessEnabled: enabled);
    return enabled;
  }

  @override
  Future<int> retryRejectedSmsAccess({String? expectedOwnerUserId}) async {
    retryOwners.add(expectedOwnerUserId);
    queueNeedsReview = false;
    return 1;
  }

  void changeOwner() {
    state = state.copyWith(
      currentProfile: const CollectProfile(
        id: 'another-user',
        publicId: '123456',
        whatsappPhone: '+49123456780',
        countryCode: 'DE',
        currencyCode: 'EUR',
      ),
    );
  }
}
