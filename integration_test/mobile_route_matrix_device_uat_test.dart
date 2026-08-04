import 'dart:async';

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/collect_theme_controller.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  GoRouter? activeRouter;
  tearDown(() {
    activeRouter?.dispose();
    activeRouter = null;
  });

  Future<GoRouter> pumpRoute(WidgetTester tester, _RouteSpec spec) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    activeRouter?.dispose();

    final route = spec.route;
    final router = createAppRouter(initialLocation: route);
    activeRouter = router;
    await tester.pumpWidget(
      ProviderScope(
        key: ValueKey('collect-route-harness-${spec.name}'),
        overrides: [
          appRouterProvider.overrideWithValue(router),
          collectRepositoryProvider.overrideWith(
            (ref) => CollectRepository.fixture(),
          ),
          collectThemeModeProvider.overrideWith(
            (ref) => CollectThemeModeController(
              initialMode: _uatThemeMode,
              loadPersistedMode: false,
            ),
          ),
        ],
        child: const CollectApp(),
      ),
    );
    for (var i = 0; i < 14; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return router;
  }

  testWidgets(
    'all mobile routes resolve and render natively without UI exceptions',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = _uatTextScale;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(
            highContrast: _uatHighContrast,
            disableAnimations: _uatReducedMotion,
            accessibleNavigation: _uatReducedMotion,
          );
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      var screenshotsEnabled = true;
      try {
        await binding.convertFlutterSurfaceToImage().timeout(
          const Duration(seconds: 12),
        );
        await tester.pump();
      } on TimeoutException {
        screenshotsEnabled = false;
        // Printed progress distinguishes a screenshot-only device limitation
        // from route rendering failures in the retained UAT log.
        // ignore: avoid_print
        print('collect_route_uat:screenshots-disabled:surface-timeout');
      } on MissingPluginException {
        screenshotsEnabled = false;
      } on PlatformException {
        screenshotsEnabled = false;
      }
      // Emitted after the driver is connected so the harness can reject
      // screenshots that were compiled for a different declared variant.
      // ignore: avoid_print
      print(
        'collect_route_uat:variant:$_uatVariantName:'
        'theme=$_uatThemeModeName:'
        'textScale=$_uatTextScale:'
        'highContrast=$_uatHighContrast:'
        'reducedMotion=$_uatReducedMotion',
      );

      for (final spec in _routeSpecs) {
        // Printed progress is retained in the UAT log for route-level triage.
        // ignore: avoid_print
        print('collect_route_uat:start:${spec.name}:${spec.route}');
        final router = await pumpRoute(tester, spec);
        if (spec.extraPumpBeforeAssert > Duration.zero) {
          await tester.pump(spec.extraPumpBeforeAssert);
        }
        final expectedText = spec.expectedVisibleText;
        if (expectedText != null) {
          // A timer-driven redirect can update GoRouter at the end of a pump,
          // leaving its outgoing page visible until later transition frames.
          // Wait only for the declared marker and keep the wait bounded so a
          // genuinely wrong route still fails instead of hanging evidence.
          for (
            var attempt = 0;
            attempt < 20 &&
                find.textContaining(expectedText).evaluate().isEmpty;
            attempt += 1
          ) {
            await tester.pump(const Duration(milliseconds: 100));
          }
        }
        expect(tester.takeException(), isNull, reason: spec.route);
        expect(find.byType(CollectApp), findsOneWidget, reason: spec.route);
        expect(
          router.routeInformationProvider.value.uri.path,
          spec.expectedResolvedPath,
          reason: '${spec.route} resolved path',
        );
        if (expectedText != null) {
          expect(
            find.textContaining(expectedText),
            findsWidgets,
            reason: '${spec.route} visible route marker',
          );
        }
        expect(find.text('Screen not found'), findsNothing, reason: spec.route);
        expect(
          find.text('This screen is unavailable.'),
          findsNothing,
          reason: spec.route,
        );
        if (screenshotsEnabled) {
          try {
            await binding.takeScreenshot('mobile_route_${spec.name}');
          } on MissingPluginException {
            screenshotsEnabled = false;
          } on PlatformException {
            screenshotsEnabled = false;
          }
        }
        // ignore: avoid_print
        print('collect_route_uat:pass:${spec.name}:${spec.route}');
      }
    },
    timeout: const Timeout(Duration(minutes: 14)),
  );
}

const _uatVariantName = String.fromEnvironment(
  'COLLECT_UAT_VARIANT_NAME',
  defaultValue: 'default-dark',
);
const _uatThemeModeName = String.fromEnvironment(
  'COLLECT_UAT_THEME_MODE',
  defaultValue: 'dark',
);
const _uatTextScaleName = String.fromEnvironment(
  'COLLECT_UAT_TEXT_SCALE',
  defaultValue: '1.0',
);
const _uatHighContrast = bool.fromEnvironment(
  'COLLECT_UAT_HIGH_CONTRAST',
  defaultValue: false,
);
const _uatReducedMotion = bool.fromEnvironment(
  'COLLECT_UAT_REDUCED_MOTION',
  defaultValue: false,
);

ThemeMode get _uatThemeMode => switch (_uatThemeModeName) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  'system' => ThemeMode.system,
  _ => throw StateError('Unsupported UAT theme mode: $_uatThemeModeName'),
};

double get _uatTextScale => double.parse(_uatTextScaleName);

const _routeSpecs = <_RouteSpec>[
  _RouteSpec(
    'root-redirect',
    '/',
    'entry',
    expectedPath: '/auth',
    expectedText: 'Sign in',
    extraPumpBeforeAssert: Duration(milliseconds: 1000),
  ),
  _RouteSpec('auth', '/auth', 'workflow', expectedText: 'Sign in'),
  _RouteSpec(
    'profile-edit',
    '/settings/profile',
    'workflow',
    expectedText: 'Edit profile',
  ),
  _RouteSpec('home', '/home', 'primary', expectedText: 'RWF 35,000'),
  _RouteSpec('offline', '/offline', 'utility', expectedText: 'Offline mode'),
  _RouteSpec('sync', '/sync', 'utility', expectedText: 'Sync status'),
  _RouteSpec('groups', '/groups', 'primary', expectedText: 'Groups'),
  _RouteSpec(
    'contribute-entry',
    '/contribute',
    'primary',
    expectedText: 'Choose a group',
  ),
  _RouteSpec('activity', '/activity', 'primary', expectedText: 'Activity'),
  _RouteSpec(
    'group-create',
    '/groups/create',
    'workflow',
    expectedText: 'Create group',
    iosResolvedPath: '/groups',
    iosExpectedText: 'Groups',
  ),
  _RouteSpec('group-scan', '/groups/scan', 'workflow'),
  _RouteSpec(
    'group-detail',
    '/groups/col-church',
    'workflow',
    expectedText: 'St Michel building fund',
  ),
  _RouteSpec(
    'share',
    '/groups/col-church/share',
    'workflow',
    expectedText: 'Group QR',
  ),
  _RouteSpec(
    'invite',
    '/groups/col-church/invite',
    'compatibility',
    expectedPath: '/groups/col-church/share',
    expectedText: 'Group QR',
  ),
  _RouteSpec(
    'shared-group-link',
    '/c/st-michel-building-fund',
    'entry',
    expectedPath: '/groups/col-church',
    expectedText: 'St Michel building fund',
  ),
  _RouteSpec(
    'app-share-entry',
    '/app',
    'compatibility',
    expectedPath: '/home',
    expectedText: 'RWF 35,000',
  ),
  _RouteSpec(
    'app-invite-link',
    '/invite/038491',
    'compatibility',
    expectedPath: '/home',
    expectedText: 'RWF 35,000',
  ),
  _RouteSpec(
    'share-invalid',
    '/share/invalid',
    'utility',
    expectedPath: '/groups',
    expectedText: 'Groups',
  ),
  _RouteSpec(
    'share-expired',
    '/share/expired',
    'utility',
    expectedPath: '/groups',
    expectedText: 'Groups',
  ),
  _RouteSpec(
    'share-expired-request',
    '/share/expired/request',
    'utility',
    expectedPath: '/groups',
    expectedText: 'Groups',
  ),
  _RouteSpec(
    'contribution',
    '/groups/col-church/contribute',
    'workflow',
    expectedText: 'Review contribution',
  ),
  _RouteSpec(
    'ledger',
    '/groups/col-church/ledger',
    'workflow',
    expectedText: 'Ledger',
  ),
  _RouteSpec(
    'manage',
    '/groups/col-church/manage',
    'workflow',
    expectedText: 'Group settings',
  ),
  _RouteSpec(
    'group-profile',
    '/groups/col-church/profile',
    'workflow',
    expectedText: 'Group profile',
  ),
  _RouteSpec(
    'members',
    '/groups/col-church/members',
    'workflow',
    expectedText: 'Members',
  ),
  _RouteSpec(
    'settings',
    '/settings',
    'primary',
    expectedText: 'Account details',
  ),
  _RouteSpec(
    'settings-notifications',
    '/settings/notifications',
    'utility',
    expectedText: 'Notifications',
  ),
  _RouteSpec(
    'settings-appearance',
    '/settings/appearance',
    'utility',
    expectedText: 'Appearance',
  ),
  _RouteSpec(
    'settings-security',
    '/settings/security',
    'utility',
    expectedText: 'Security',
  ),
  _RouteSpec(
    'account',
    '/settings/account',
    'utility',
    expectedText: 'Account',
  ),
  _RouteSpec(
    'account-delete',
    '/settings/account/delete',
    'utility',
    expectedText: 'Delete request',
  ),
  _RouteSpec(
    'privacy-alias',
    '/settings/privacy',
    'utility',
    expectedPath: '/settings/legal/privacy',
    expectedText: 'Privacy Policy',
  ),
  _RouteSpec('help', '/settings/help', 'utility', expectedText: 'Help'),
  _RouteSpec(
    'legal-privacy',
    '/settings/legal/privacy',
    'utility',
    expectedText: 'Privacy Policy',
  ),
  _RouteSpec(
    'legal-terms',
    '/settings/legal/terms',
    'utility',
    expectedText: 'Terms & Conditions',
  ),
];

class _RouteSpec {
  const _RouteSpec(
    this.name,
    this.route,
    this.routeClass, {
    this.expectedPath,
    this.expectedText,
    this.iosResolvedPath,
    this.iosExpectedText,
    this.extraPumpBeforeAssert = Duration.zero,
  });

  final String name;
  final String route;
  final String routeClass;
  final String? expectedPath;
  final String? expectedText;
  final String? iosResolvedPath;
  final String? iosExpectedText;
  final Duration extraPumpBeforeAssert;

  bool get isProductScreen => routeClass != 'compatibility';

  bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

  String get expectedResolvedPath => _isIos && iosResolvedPath != null
      ? iosResolvedPath!
      : expectedPath ?? route;

  String? get expectedVisibleText =>
      _isIos && iosExpectedText != null ? iosExpectedText : expectedText;
}
