import 'dart:async';

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/env/app_env.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/collect_theme_controller.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
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

  Future<void> pumpState(
    WidgetTester tester,
    _StateSpec spec,
    CollectRepository repository,
  ) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
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
          if (spec.usesReviewAuth)
            appEnvProvider.overrideWithValue(_reviewAuthEnv),
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
        // ignore: avoid_print
        print('collect_state_uat:start:${spec.name}:${spec.route}');
        final repository = spec.createRepository();
        if (spec.name == 'contribution-review-existing') {
          await repository.createPaymentIntent(
            const PaymentIntentDraft(
              collectionId: 'col-church',
              amountRwf: 12345,
            ),
          );
        }
        await pumpState(tester, spec, repository);
        await _prepareState(tester, spec);

        expect(tester.takeException(), isNull, reason: spec.name);
        expect(find.byType(CollectApp), findsOneWidget, reason: spec.name);
        expect(
          find.textContaining(spec.expectedText),
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
        // ignore: avoid_print
        print('collect_state_uat:pass:${spec.name}:${spec.route}');
      }
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

Future<void> _prepareState(WidgetTester tester, _StateSpec spec) async {
  switch (spec.name) {
    case 'auth-phone-empty':
    case 'groups-empty':
    case 'activity-empty':
    case 'contribution-entry-empty':
    case 'account-delete-disabled':
    case 'offline-recovery':
    case 'sync-recovery':
    case 'missing-group':
      return;
    case 'auth-phone-valid':
      await tester.enterText(find.byType(TextField).first, '+250700000001');
      await _pumpFrames(tester, count: 3);
      return;
    case 'auth-otp-empty':
    case 'auth-otp-invalid':
      await tester.enterText(find.byType(TextField).first, '+250700000001');
      await _pumpFrames(tester, count: 2);
      await tester.tap(find.text('Send WhatsApp code'));
      await _pumpFrames(tester, count: 4);
      if (spec.name == 'auth-otp-invalid') {
        await tester.enterText(find.byType(TextField).first, '000000');
        await _pumpFrames(tester, count: 2);
        await tester.tap(find.text('Verify and continue'));
        await _pumpFrames(tester, count: 4);
      }
      return;
    case 'contribution-entry-valid':
    case 'contribution-review':
    case 'contribution-review-existing':
      final amountController = tester
          .widget<TextField>(_amountTextField())
          .controller;
      expect(amountController, isNotNull);
      amountController!.value = const TextEditingValue(
        text: '12,345',
        selection: TextSelection.collapsed(offset: 6),
      );
      await _pumpFrames(tester, count: 3);
      if (spec.name != 'contribution-entry-valid') {
        await tester.tap(
          find.widgetWithText(FilledButton, 'Review contribution'),
        );
        await _pumpFrames(tester, count: 5);
      }
      return;
    case 'account-delete-enabled':
    case 'account-delete-confirmation':
      await tester.tap(find.text('I no longer use Collect'));
      await _pumpFrames(tester, count: 3);
      if (spec.name == 'account-delete-confirmation') {
        await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
        await _pumpFrames(tester, count: 5);
      }
      return;
  }
  throw StateError('Unsupported material state: ${spec.name}');
}

Finder _amountTextField() => find.descendant(
  of: find.byType(AmountEntryPanel),
  matching: find.byType(TextField),
);

Future<void> _pumpFrames(WidgetTester tester, {int count = 14}) async {
  for (var index = 0; index < count; index += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
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

ThemeMode get _uatThemeMode => switch (_uatThemeModeName) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  'system' => ThemeMode.system,
  _ => throw StateError('Unsupported UAT theme mode: $_uatThemeModeName'),
};

double get _uatTextScale => double.parse(_uatTextScaleName);

const _reviewAuthEnv = AppEnv(
  supabaseUrl: '',
  supabaseAnonKey: '',
  publicUrl: '',
  adminAppUrl: '',
  enableSmsReader: false,
  enableAndroidSmsAccess: false,
  enableAdminPanel: false,
  enableAdminDevTools: false,
  authCaptchaEnabled: false,
  authCaptchaProvider: '',
  authCaptchaSiteKey: '',
  appReviewAuthEnabled: true,
  appReviewAuthPhone: '+250700000001',
  appReviewAuthOtp: '135790',
);

const _stateSpecs = <_StateSpec>[
  _StateSpec(
    'auth-phone-empty',
    '/auth',
    'Sign in',
    repositoryKind: _RepositoryKind.reviewAuth,
    usesReviewAuth: true,
  ),
  _StateSpec(
    'auth-phone-valid',
    '/auth',
    'Send WhatsApp code',
    repositoryKind: _RepositoryKind.reviewAuth,
    usesReviewAuth: true,
  ),
  _StateSpec(
    'auth-otp-empty',
    '/auth',
    'Verify and continue',
    repositoryKind: _RepositoryKind.reviewAuth,
    usesReviewAuth: true,
  ),
  _StateSpec(
    'auth-otp-invalid',
    '/auth',
    'Authentication failed',
    repositoryKind: _RepositoryKind.reviewAuth,
    usesReviewAuth: true,
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
    '/groups/col-church/contribute',
    'Review contribution',
  ),
  _StateSpec(
    'contribution-entry-valid',
    '/groups/col-church/contribute',
    'Review contribution',
    expectedFieldValue: '12,345',
  ),
  _StateSpec(
    'contribution-review',
    '/groups/col-church/contribute',
    'Contribute with MoMo',
  ),
  _StateSpec(
    'contribution-review-existing',
    '/groups/col-church/contribute',
    'Contribution already pending',
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

enum _RepositoryKind { fixture, empty, reviewAuth }

class _StateSpec {
  const _StateSpec(
    this.name,
    this.route,
    this.expectedText, {
    this.repositoryKind = _RepositoryKind.fixture,
    this.usesReviewAuth = false,
    this.expectedFieldValue,
  });

  final String name;
  final String route;
  final String expectedText;
  final _RepositoryKind repositoryKind;
  final bool usesReviewAuth;
  final String? expectedFieldValue;

  CollectRepository createRepository() => switch (repositoryKind) {
    _RepositoryKind.fixture => CollectRepository.fixture(),
    _RepositoryKind.empty => CollectRepository.fixture(seeded: false),
    _RepositoryKind.reviewAuth => CollectRepository.appReviewDemo(),
  };
}
