import '../test/fixtures/collect_repository_fixture.dart';

import 'dart:async';

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/collect_theme_controller.dart';
import 'package:collect_app/core/supabase/auth_otp_gateway.dart';
import 'package:collect_app/features/payments/contribution_flow_screen.dart';
import 'package:collect_app/features/status/native_permission_sheets.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
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

  Future<void> pumpState(
    WidgetTester tester,
    _StateSpec spec,
    CollectRepository repository,
  ) async {
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    } on MissingPluginException {
      // Desktop-style test bindings may not expose a native input channel.
    } on PlatformException {
      // The next app frame is still safe to render without a native IME.
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFrames(tester, count: 6);
    activeRouter?.dispose();

    final router = createAppRouter(initialLocation: spec.route);
    activeRouter = router;
    await tester.pumpWidget(
      ProviderScope(
        key: ValueKey('collect-material-state-${spec.name}'),
        overrides: [
          appRouterProvider.overrideWithValue(router),
          collectRepositoryProvider.overrideWith((ref) => repository),
          collectThemeModeProvider.overrideWith(
            (ref) => CollectThemeModeController(
              initialMode: _uatThemeMode,
              loadPersistedMode: false,
            ),
          ),
          if (spec.usesFakeAuth)
            authOtpGatewayProvider.overrideWithValue(
              const _MaterialStateAuthOtpGateway(),
            ),
        ],
        child: const CollectApp(),
      ),
    );
    await _pumpFrames(tester);
  }

  testWidgets(
    'material mobile states render deterministically for comparison evidence',
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
        // ignore: avoid_print
        print('collect_state_uat:screenshots-disabled:surface-timeout');
      } on MissingPluginException {
        screenshotsEnabled = false;
      } on PlatformException {
        screenshotsEnabled = false;
      }

      // ignore: avoid_print
      print(
        'collect_state_uat:variant:$_uatVariantName:'
        'theme=$_uatThemeModeName:'
        'textScale=$_uatTextScale:'
        'highContrast=$_uatHighContrast:'
        'reducedMotion=$_uatReducedMotion',
      );

      for (final spec in _stateSpecs) {
        if (_uatStateFilter.isNotEmpty && spec.name != _uatStateFilter) {
          continue;
        }
        // ignore: avoid_print
        print('collect_state_uat:start:${spec.name}:${spec.route}');
        final repository = spec.createRepository();
        await pumpState(tester, spec, repository);
        await _prepareState(tester, spec);

        expect(tester.takeException(), isNull, reason: spec.name);
        expect(find.byType(CollectApp), findsOneWidget, reason: spec.name);
        expect(
          find.textContaining(spec.visibleMarker),
          findsWidgets,
          reason: '${spec.name} visible state marker',
        );
        if (spec.expectedFieldValue != null) {
          expect(
            tester.widget<TextField>(_amountTextField()).controller?.text,
            spec.expectedFieldValue,
            reason: '${spec.name} field value',
          );
        }
        expect(find.text('Screen not found'), findsNothing, reason: spec.name);
        expect(
          find.text('This screen is unavailable.'),
          findsNothing,
          reason: spec.name,
        );

        FocusManager.instance.primaryFocus?.unfocus();
        await _pumpFrames(tester, count: 4);
        if (screenshotsEnabled) {
          try {
            await binding.takeScreenshot('mobile_state_${spec.name}');
          } on MissingPluginException {
            screenshotsEnabled = false;
          } on PlatformException {
            screenshotsEnabled = false;
          }
        }
        await _inspectSheetToEnd(tester, binding, spec, screenshotsEnabled);
        if (spec.name == 'auth-otp-invalid') {
          final position = tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position;
          var page = 0;
          while (position.extentAfter > 1) {
            expect(
              page,
              lessThan(20),
              reason: 'bounded error-guidance traversal',
            );
            position.jumpTo(
              (position.pixels + position.viewportDimension * 0.7).clamp(
                position.minScrollExtent,
                position.maxScrollExtent,
              ),
            );
            await _pumpFrames(tester, count: 3);
            page++;
            if (screenshotsEnabled) {
              await binding.takeScreenshot(
                'detail_auth-otp-invalid_scroll_$page',
              );
            }
          }
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Change number'));
          await _pumpFrames(tester, count: 4);
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('auth_whatsapp_phone_input')),
            160,
            scrollable: find.byType(Scrollable).first,
          );
          expect(
            tester
                .widget<TextField>(find.byType(TextField).first)
                .controller
                ?.text,
            '788123456',
          );
          expect(find.text('Authentication failed'), findsNothing);
          // ignore: avoid_print
          print(
            'collect_state_uat:error-end:auth-otp-invalid:pages=$page:change-number=pass',
          );
        }
        if (const [
          'home-discovery',
          'home-joined',
          'home-mixed',
        ].contains(spec.name)) {
          await tester.scrollUntilVisible(
            find.text('Featured groups'),
            160,
            scrollable: find.byType(Scrollable).first,
          );
          await _pumpFrames(tester, count: 3);
          expect(find.text('Featured groups').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          if (screenshotsEnabled) {
            await binding.takeScreenshot('detail_${spec.name}_featured');
          }
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  axisDirectionToAxis(widget.axisDirection) == Axis.horizontal,
            ),
            findsNothing,
          );
          final featuredBuriMunsi = find.descendant(
            of: find.byKey(const ValueKey('home_featured_groups')),
            matching: find.text('Buri Munsi'),
          );
          await tester.scrollUntilVisible(
            featuredBuriMunsi,
            160,
            scrollable: find.byType(Scrollable).first,
          );
          await _pumpFrames(tester, count: 5);
          expect(find.text('Buri Munsi').hitTestable(), findsWidgets);
          if (screenshotsEnabled) {
            await binding.takeScreenshot('detail_${spec.name}_featured_next');
          }
        }
        // ignore: avoid_print
        print('collect_state_uat:pass:${spec.name}:${spec.route}');
      }
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

Future<void> _prepareState(WidgetTester tester, _StateSpec spec) async {
  if (spec.usesFakeAuth && spec.name != 'auth-phone-empty') {
    // On a short 320dp viewport the lazy ListView has not built the phone
    // field yet. Reach it using the same scroll available to the user.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('auth_whatsapp_phone_input')),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await _pumpFrames(tester, count: 2);
  }
  switch (spec.name) {
    case 'camera-recovery-sheet':
    case 'sms-recovery-sheet':
      final context = tester.element(find.byType(Scaffold).last);
      unawaited(
        spec.name == 'camera-recovery-sheet'
            ? showCameraAccessSheet(context, onRetry: () {})
            : showSmsAccessSheet(context, onRetry: () {}),
      );
      await _pumpFrames(tester, count: 4);
      return;
    case 'auth-phone-empty':
    case 'groups-empty':
    case 'activity-empty':
    case 'contribution-entry-empty':
    case 'account-delete-disabled':
    case 'offline-recovery':
    case 'sync-recovery':
    case 'missing-group':
    case 'home-discovery':
    case 'home-joined':
    case 'home-mixed':
    case 'home-empty':
    case 'home-loading':
    case 'home-error':
    case 'home-offline':
      return;
    case 'contribution-quick-pick':
      await _pumpUntilVisible(tester, _amountTextField());
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await _pumpFrames(tester, count: 6);
      await tester.ensureVisible(find.text('2,000'));
      await _pumpFrames(tester, count: 2);
      await tester.tap(find.text('2,000'));
      await _pumpFrames(tester, count: 3);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Continue to MoMo'),
            )
            .onPressed,
        isNotNull,
      );
      return;
    case 'sms-consent-sheet':
      if (defaultTargetPlatform != TargetPlatform.android) return;
      await tester.ensureVisible(find.text('Review and allow'));
      await tester.tap(find.text('Review and allow'));
      await _pumpFrames(tester, count: 4);
      expect(find.text('Not now'), findsOneWidget);
      return;
    case 'auth-phone-valid':
      await tester.enterText(find.byType(TextField).first, '788123456');
      await _pumpFrames(tester, count: 3);
      return;
    case 'auth-phone-confirmation':
      await tester.enterText(find.byType(TextField).first, '788123456');
      await _pumpFrames(tester, count: 2);
      await tester.tap(find.text('Send WhatsApp code'));
      await _pumpFrames(tester, count: 4);
      return;
    case 'auth-otp-empty':
    case 'auth-otp-invalid':
      await tester.enterText(find.byType(TextField).first, '788123456');
      await _pumpFrames(tester, count: 2);
      await tester.tap(find.text('Send WhatsApp code'));
      await _pumpFrames(tester, count: 4);
      await tester.ensureVisible(find.text('Confirm and send'));
      await _pumpFrames(tester, count: 2);
      await tester.tap(find.text('Confirm and send'));
      await _pumpFrames(tester, count: 4);
      if (spec.name == 'auth-otp-invalid') {
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('auth_otp_digit_0')),
          160,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.enterText(find.byType(TextField).first, '000000');
        await _pumpFrames(tester, count: 2);
        await tester.tap(find.text('Verify and continue'));
        await _pumpFrames(tester, count: 4);
        expect(
          find.text('Authentication failed').hitTestable(),
          findsOneWidget,
          reason: 'The OTP failure must be revealed without another scroll.',
        );
      }
      return;
    case 'contribution-entry-valid':
    case 'contribution-review':
    case 'contribution-invalid-amount':
    case 'bank-contribution-entry-valid':
    case 'bank-contribution-review':
    case 'bank-contribution-invalid-amount':
      await _pumpUntilVisible(tester, _amountTextField());
      final isBank = spec.repositoryKind == _RepositoryKind.diaspora;
      final invalid = spec.name.endsWith('invalid-amount');
      final amountText = invalid
          ? (isBank ? '0.00' : '0')
          : (isBank ? '12.34' : '1234');
      await tester.enterText(_amountTextField().first, amountText);
      await _pumpFrames(tester, count: 3);
      if (!spec.name.endsWith('entry-valid')) {
        if (invalid) {
          final amountField = tester.widget<TextField>(
            _amountTextField().first,
          );
          expect(amountField.controller?.text, amountText);
          expect(amountField.onSubmitted, isNotNull);
          amountField.onSubmitted!.call(amountText);
          await _pumpFrames(tester, count: 5);
          return;
        }
        final reviewButton = find.widgetWithText(
          FilledButton,
          isBank ? 'Review transfer' : 'Continue to MoMo',
        );
        expect(reviewButton, findsOneWidget);
        await tester.ensureVisible(reviewButton);
        await tester.tap(reviewButton);
        await _pumpFrames(tester, count: 5);
      }
      return;
    case 'account-delete-enabled':
    case 'account-delete-confirmation':
      await tester.tap(find.text('I no longer use Collect'));
      await _pumpFrames(tester, count: 3);
      if (spec.name == 'account-delete-confirmation') {
        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Submit'));
        await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
        await _pumpFrames(tester, count: 5);
      }
      return;
  }
  throw StateError('Unsupported material state: ${spec.name}');
}

// Additional captures retain overlapping viewports through the entire sheet.
// These are diagnostic fixture interactions, not OS permission or release
// acceptance evidence. The safe secondary action is the only action invoked.
Future<void> _inspectSheetToEnd(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  _StateSpec spec,
  bool screenshotsEnabled,
) async {
  final secondaryLabel = switch (spec.name) {
    'sms-consent-sheet' => 'Not now',
    'account-delete-confirmation' => 'Cancel',
    'auth-phone-confirmation' => 'Edit number',
    'camera-recovery-sheet' => 'Scan again',
    'sms-recovery-sheet' => 'Retry',
    _ => null,
  };
  if (secondaryLabel == null ||
      (spec.name == 'sms-consent-sheet' &&
          defaultTargetPlatform != TargetPlatform.android)) {
    return;
  }
  final sheet = find.byType(BottomSheet);
  final scrollable = find.descendant(
    of: sheet,
    matching: find.byType(Scrollable),
  );
  expect(scrollable, findsWidgets, reason: '${spec.name} scrollable content');
  // The first descendant is the sheet's outer scroll view. Selectable phone
  // text also owns an inner Scrollable that must not drive sheet traversal.
  final position = tester.state<ScrollableState>(scrollable.first).position;
  var page = 0;
  while (position.extentAfter > 1) {
    expect(page, lessThan(20), reason: 'bounded sheet traversal');
    final next = (position.pixels + position.viewportDimension * 0.7).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    position.jumpTo(next);
    await _pumpFrames(tester, count: 3);
    expect(tester.takeException(), isNull, reason: spec.name);
    if (screenshotsEnabled) {
      await binding.takeScreenshot('detail_${spec.name}_scroll_${++page}');
    } else {
      page++;
    }
  }
  final secondary = find.descendant(
    of: sheet,
    matching: find.text(secondaryLabel),
  );
  expect(secondary.hitTestable(), findsOneWidget);
  await tester.tap(secondary);
  await _pumpFrames(tester, count: 6);
  expect(find.byType(BottomSheet), findsNothing);
  expect(tester.takeException(), isNull, reason: '${spec.name} dismissal');
  // ignore: avoid_print
  print(
    'collect_state_uat:sheet-end:${spec.name}:pages=$page:secondary=$secondaryLabel',
  );
}

Finder _amountTextField() => find.descendant(
  of: find.byType(ContributionFlowScreen),
  matching: find.byType(TextField),
);

Future<void> _pumpFrames(WidgetTester tester, {int count = 14}) async {
  for (var index = 0; index < count; index += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpUntilVisible(
  WidgetTester tester,
  Finder finder, {
  int maxFrames = 30,
}) async {
  for (var index = 0; index < maxFrames; index += 1) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsWidgets);
}

const _uatVariantName = String.fromEnvironment(
  'COLLECT_UAT_VARIANT_NAME',
  defaultValue: 'material-state-dark',
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
const _uatStateFilter = String.fromEnvironment(
  'COLLECT_UAT_STATE_FILTER',
  defaultValue: '',
);

ThemeMode get _uatThemeMode => switch (_uatThemeModeName) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  'system' => ThemeMode.system,
  _ => throw StateError('Unsupported UAT theme mode: $_uatThemeModeName'),
};

double get _uatTextScale => double.parse(_uatTextScaleName);

const _stateSpecs = <_StateSpec>[
  _StateSpec('camera-recovery-sheet', '/settings/permissions', 'Camera access'),
  _StateSpec('sms-recovery-sheet', '/settings/permissions', 'SMS access'),
  _StateSpec(
    'home-discovery',
    '/home',
    'Featured groups',
    homeScenario: 'discovery',
  ),
  _StateSpec('home-joined', '/home', 'My groups', homeScenario: 'joined'),
  _StateSpec('home-mixed', '/home', 'My groups', homeScenario: 'mixed'),
  _StateSpec('home-empty', '/home', 'No groups yet', homeScenario: 'empty'),
  _StateSpec('home-loading', '/home', 'Loading', homeScenario: 'loading'),
  _StateSpec(
    'home-error',
    '/home',
    'Could not load data',
    homeScenario: 'error',
  ),
  _StateSpec('home-offline', '/home', 'Offline', homeScenario: 'offline'),
  _StateSpec(
    'contribution-quick-pick',
    '/groups/qa-private-group/contribute',
    'Quick pick',
    expectedFieldValue: '2,000',
  ),
  _StateSpec(
    'sms-consent-sheet',
    '/settings/permissions',
    'Allow MoMo receipt SMS access?',
  ),
  _StateSpec(
    'auth-phone-empty',
    '/auth',
    "Let's get started!",
    repositoryKind: _RepositoryKind.empty,
    usesFakeAuth: true,
  ),
  _StateSpec(
    'auth-phone-valid',
    '/auth',
    'Send WhatsApp code',
    repositoryKind: _RepositoryKind.empty,
    usesFakeAuth: true,
  ),
  _StateSpec(
    'auth-phone-confirmation',
    '/auth',
    'Confirm your number',
    repositoryKind: _RepositoryKind.empty,
    usesFakeAuth: true,
  ),
  _StateSpec(
    'auth-otp-empty',
    '/auth',
    'Verify and continue',
    repositoryKind: _RepositoryKind.empty,
    usesFakeAuth: true,
  ),
  _StateSpec(
    'auth-otp-invalid',
    '/auth',
    'Authentication failed',
    repositoryKind: _RepositoryKind.empty,
    usesFakeAuth: true,
  ),
  _StateSpec(
    'groups-empty',
    '/groups',
    'No groups yet',
    repositoryKind: _RepositoryKind.empty,
  ),
  _StateSpec(
    'activity-empty',
    '/activity',
    'No activity yet',
    repositoryKind: _RepositoryKind.empty,
  ),
  _StateSpec(
    'contribution-entry-empty',
    '/groups/qa-private-group/contribute',
    'Continue to MoMo',
  ),
  _StateSpec(
    'contribution-entry-valid',
    '/groups/qa-private-group/contribute',
    'Continue to MoMo',
    expectedFieldValue: '1,234',
  ),
  _StateSpec(
    'contribution-review',
    '/groups/qa-private-group/contribute',
    'Open MoMo USSD',
  ),
  _StateSpec(
    'contribution-invalid-amount',
    '/groups/qa-private-group/contribute',
    'Enter an amount above RWF 0.',
  ),
  _StateSpec(
    'bank-contribution-entry-valid',
    '/groups/qa-private-group/contribute',
    'Review transfer',
    repositoryKind: _RepositoryKind.diaspora,
    expectedFieldValue: '12.34',
  ),
  _StateSpec(
    'bank-contribution-review',
    '/groups/qa-private-group/contribute',
    'Open Revolut',
    repositoryKind: _RepositoryKind.diaspora,
  ),
  _StateSpec(
    'bank-contribution-invalid-amount',
    '/groups/qa-private-group/contribute',
    'Enter a valid amount above EUR 0.00.',
    repositoryKind: _RepositoryKind.diaspora,
  ),
  _StateSpec(
    'account-delete-disabled',
    '/settings/account/delete',
    'Select a reason to submit',
  ),
  _StateSpec(
    'account-delete-enabled',
    '/settings/account/delete',
    'Ready to submit',
  ),
  _StateSpec(
    'account-delete-confirmation',
    '/settings/account/delete',
    'Submit delete request?',
  ),
  _StateSpec('offline-recovery', '/offline', 'You are offline'),
  _StateSpec('sync-recovery', '/sync', 'Sync needs attention'),
  _StateSpec(
    'missing-group',
    '/groups/missing/contribute',
    'Group is not available',
  ),
];

enum _RepositoryKind { fixture, empty, diaspora }

class _StateSpec {
  const _StateSpec(
    this.name,
    this.route,
    this.expectedText, {
    this.repositoryKind = _RepositoryKind.fixture,
    this.usesFakeAuth = false,
    this.expectedFieldValue,
    this.homeScenario,
  });

  final String name;
  final String route;
  final String expectedText;
  final _RepositoryKind repositoryKind;
  final bool usesFakeAuth;
  final String? expectedFieldValue;
  final String? homeScenario;

  String get visibleMarker =>
      name == 'sms-consent-sheet' &&
          defaultTargetPlatform != TargetPlatform.android
      ? 'App permissions'
      : expectedText;

  CollectRepository createRepository() => homeScenario != null
      ? _HomeParityRepository(homeScenario!)
      : switch (repositoryKind) {
          _RepositoryKind.fixture => FixtureCollectRepository(),
          _RepositoryKind.empty => FixtureCollectRepository(seeded: false),
          _RepositoryKind.diaspora => FixtureCollectRepository(
            profileOverride: const CollectProfile(
              id: 'local-user',
              publicId: '038491',
              whatsappPhone: '+250788123456',
              countryCode: 'DE',
              currencyCode: 'EUR',
              revolutAccount: '000123456789',
            ),
          ),
        };
}

class _HomeParityRepository extends FixtureCollectRepository {
  _HomeParityRepository(String scenario) : super() {
    final publicGroups = state.collections
        .where((item) => item.isPublic)
        .toList();
    state = state.copyWith(
      contributions: [],
      paymentIntents: [],
      collectionSummaries: {},
      collections: switch (scenario) {
        'discovery' => publicGroups,
        'joined' =>
          publicGroups
              .map((item) => item.copyWith(isCurrentUserMember: true))
              .toList(),
        'mixed' => [
          publicGroups.first.copyWith(isCurrentUserMember: true),
          publicGroups.last,
        ],
        'empty' || 'loading' || 'error' => [],
        _ => state.collections,
      },
      isLoading: scenario == 'loading',
      lastError: scenario == 'error' ? 'Fixture read failed' : null,
      usingStaleCache: scenario == 'offline',
    );
  }
}

class _MaterialStateAuthOtpGateway implements AuthOtpGateway {
  const _MaterialStateAuthOtpGateway();

  @override
  Future<void> sendWhatsAppOtp({
    required String phone,
    String? captchaToken,
  }) async {}

  @override
  Future<void> verifyWhatsAppOtp({
    required String phone,
    required String otp,
    String? captchaToken,
  }) async {
    throw const FormatException('Invalid OTP');
  }
}
