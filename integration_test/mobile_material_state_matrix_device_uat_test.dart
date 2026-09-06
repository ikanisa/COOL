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
import 'package:collect_app/shared/widgets/collect_group_cards.dart';
import 'package:collect_app/shared/widgets/collect_group_photo_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import '../test/fixtures/mobile_matrix_capture.dart';

void main() {
  final binding = MobileMatrixCapture.initialize();
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
          ...MobileMatrixCapture.overrides,
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
        child: MobileMatrixCapture.wrap(const CollectApp()),
      ),
    );
    await _pumpFrames(tester);
  }

  testWidgets(
    'material mobile states render deterministically for comparison evidence',
    (tester) async {
      await binding.prepare(tester);
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
        if (spec.name == 'home-discovery' && screenshotsEnabled) {
          await binding.takeScreenshot('detail_home-discovery_top');
        }
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
        if (spec.name == 'home-joined' || spec.name == 'home-mixed') {
          // At large text the shared hero and first group fill the viewport.
          // Retain that top view, then frame the membership section so the
          // two-member and one-member cases are visibly distinguishable.
          final myGroups = find.byKey(const ValueKey('home_my_groups'));
          expect(
            find.descendant(of: myGroups, matching: find.byType(GroupCard)),
            findsNWidgets(spec.name == 'home-joined' ? 2 : 1),
          );
          if (screenshotsEnabled) {
            await binding.takeScreenshot('detail_${spec.name}_top');
          }
          await Scrollable.ensureVisible(
            tester.element(find.text('My groups')),
            alignment: 0,
          );
          await _pumpFrames(tester, count: 3);
          expect(find.text('My groups').hitTestable(), findsOneWidget);
        }
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
            find.text('Featured Groups'),
            160,
            scrollable: find.byType(Scrollable).first,
          );
          await _pumpFrames(tester, count: 3);
          expect(find.text('Featured Groups').hitTestable(), findsOneWidget);
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
      await binding.finish(tester);
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

Future<void> _prepareState(WidgetTester tester, _StateSpec spec) async {
  // iOS retains its production Android-only creation guard. These four
  // cases verify the redirect, rather than fabricating an iOS creation flow.
  if (spec.creationStep != null &&
      defaultTargetPlatform != TargetPlatform.android) {
    expect(find.text('Create group'), findsNothing);
    expect(find.text('Groups'), findsWidgets);
    return;
  }
  if (spec.inputText != null ||
      spec.actionText != null ||
      spec.actionTooltip != null ||
      spec.actionKey != null ||
      spec.creationStep != null) {
    if (spec.inputText != null) {
      if (spec.name == 'groups-no-results') {
        await tester.tap(find.byTooltip('Search groups'));
        await _pumpFrames(tester, count: 4);
      }
      final field = find.byType(TextField).first;
      await tester.ensureVisible(field);
      await tester.enterText(field, spec.inputText!);
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await _pumpFrames(tester, count: 5);
    }
    if (spec.creationStep != null) {
      for (var step = 0; step < spec.creationStep!; step++) {
        final next = find.widgetWithText(FilledButton, 'Continue');
        await tester.ensureVisible(next);
        await _pumpFrames(tester, count: 3);
        expect(next.hitTestable(), findsOneWidget);
        await tester.tap(next);
        await _pumpFrames(tester, count: 5);
      }
    }
    final Finder? action = spec.actionText != null
        ? find.text(spec.actionText!).last
        : spec.actionTooltip != null
        ? find.byTooltip(spec.actionTooltip!)
        : spec.actionKey != null
        ? find.byKey(ValueKey(spec.actionKey!))
        : null;
    if (action != null) {
      await tester.ensureVisible(action);
      await _pumpFrames(tester, count: 3);
      expect(action.hitTestable(), findsOneWidget, reason: spec.name);
      await tester.tap(action);
      await _pumpFrames(tester, count: 6);
    }
    if (spec.name == 'group-photo-selected') {
      final sheet = find.byType(CollectGroupPhotoSheet);
      final scrollable = find
          .descendant(of: sheet, matching: find.byType(Scrollable))
          .first;
      final choice = find.text('Community savings');
      await tester.scrollUntilVisible(choice, 160, scrollable: scrollable);
      await _pumpFrames(tester, count: 3);
      await tester.tap(choice);
      for (var frame = 0; frame < 40; frame++) {
        await _pumpFrames(tester, count: 1);
        if (find.byType(CollectGroupPhotoSheet).evaluate().isEmpty &&
            find.byTooltip('Remove image').evaluate().isNotEmpty) {
          break;
        }
      }
      expect(find.byType(CollectGroupPhotoSheet), findsNothing);
      expect(find.byTooltip('Remove image'), findsOneWidget);
      // Text inputs have their own Scrollable. Restore the page scroll as
      // well so the header is mounted before comparing the selected-photo state.
      for (final scrollable in tester.stateList<ScrollableState>(
        find.byType(Scrollable),
      )) {
        if (scrollable.position.axis == Axis.vertical) {
          scrollable.position.jumpTo(scrollable.position.minScrollExtent);
        }
      }
      await _pumpFrames(tester, count: 4);
    }
    return;
  }
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
    case 'home-joined':
    case 'home-mixed':
    case 'home-empty':
    case 'home-loading':
    case 'home-error':
    case 'home-offline':
    case 'groups-loading':
    case 'groups-error':
    case 'groups-offline':
    case 'activity-loading':
    case 'activity-error':
    case 'activity-offline':
      return;
    case 'home-discovery':
      await tester.scrollUntilVisible(
        find.text('Featured Groups'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await _pumpFrames(tester, count: 3);
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
  MobileMatrixCapture binding,
  _StateSpec spec,
  bool screenshotsEnabled,
) async {
  if (spec.name == 'group-photo-collection') {
    final sheet = find.byType(CollectGroupPhotoSheet);
    final scrollable = find
        .descendant(of: sheet, matching: find.byType(Scrollable))
        .first;
    for (final photo in CollectGroupPhoto.collection) {
      final choice = find.byKey(ValueKey('group-photo-${photo.name}'));
      await tester.scrollUntilVisible(choice, 160, scrollable: scrollable);
      await _pumpFrames(tester, count: 5);
      expect(choice.hitTestable(), findsOneWidget);
      if (screenshotsEnabled) {
        await binding.takeScreenshot(
          'detail_group-photo-collection_${photo.asset.split('/').last}',
        );
      }
    }
    await tester.tap(find.byTooltip('Close photo collection'));
    await _pumpFrames(tester, count: 4);
    expect(find.byType(CollectGroupPhotoSheet), findsNothing);
    expect(find.byTooltip('Remove image'), findsNothing);
    return;
  }
  final secondaryLabel = switch (spec.name) {
    'sms-consent-sheet' => 'Not now',
    'account-delete-confirmation' => 'Cancel',
    'account-sign-out-confirmation' => 'Cancel',
    'profile-discard-confirmation' => 'Keep editing',
    'share-replace-confirmation' => 'Keep current link',
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
  await MobileMatrixCapture.flush(tester);
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
  _StateSpec(
    'group-photo-collection',
    '/groups/qa-private-group/profile',
    'Rwanda collection',
    actionTooltip: 'Upload image',
  ),
  _StateSpec(
    'group-photo-selected',
    '/groups/qa-private-group/profile',
    'Group profile',
    actionTooltip: 'Upload image',
  ),
  _StateSpec(
    'account-sign-out-confirmation',
    '/settings/account',
    'Sign out?',
    actionText: 'Sign out',
  ),
  _StateSpec(
    'profile-discard-confirmation',
    '/settings/profile',
    'Discard changes?',
    inputText: '0788000001',
    actionTooltip: 'Back',
  ),
  _StateSpec(
    'profile-country-picker',
    '/settings/profile',
    'Search country',
    actionKey: 'profile_country_picker',
  ),
  _StateSpec(
    'share-replace-confirmation',
    '/groups/qa-private-group/share',
    'Replace invitation link?',
    actionText: 'Replace invitation link',
  ),
  _StateSpec(
    'members-filter',
    '/groups/qa-private-group/members',
    'Filter members',
    actionText: 'All',
  ),
  _StateSpec(
    'members-sort',
    '/groups/qa-private-group/members',
    'Sort members',
    actionText: 'Collect ID',
  ),
  _StateSpec(
    'ledger-group-filter',
    '/groups/qa-private-group/ledger',
    'Filter by group',
    actionTooltip: 'Filter by group',
  ),
  _StateSpec(
    'ledger-sort',
    '/groups/qa-private-group/ledger',
    'Sort ledger',
    actionTooltip: 'Sort ledger',
  ),
  _StateSpec(
    'activity-group-filter',
    '/activity',
    'All groups',
    actionTooltip: 'Filter by group',
  ),
  _StateSpec(
    'groups-no-results',
    '/groups',
    'No matching groups',
    inputText: 'No group matches this search',
  ),
  _StateSpec(
    'group-add-admin',
    '/groups/qa-private-group/manage',
    'Enter the six-digit Collect ID of an active group member.',
    actionText: 'Add admin',
  ),
  _StateSpec(
    'group-transfer-ownership',
    '/groups/qa-private-group/manage',
    'This removes your owner controls.',
    actionText: 'Transfer ownership',
  ),
  _StateSpec(
    'group-archive-confirmation',
    '/groups/qa-private-group/manage',
    'Existing confirmed ledger records stay available.',
    actionText: 'Archive group',
  ),
  _StateSpec(
    'create-group-type',
    '/groups/create',
    'Create group',
    inputText: 'Community support',
    creationStep: 1,
  ),
  _StateSpec(
    'create-group-receiver',
    '/groups/create',
    'MTN MoMo receiver',
    inputText: 'Community support',
    creationStep: 2,
  ),
  _StateSpec(
    'create-group-assets',
    '/groups/create',
    'Group color',
    inputText: 'Community support',
    creationStep: 3,
  ),
  _StateSpec(
    'create-group-review',
    '/groups/create',
    'Review group',
    inputText: 'Community support',
    creationStep: 4,
  ),
  _StateSpec(
    'groups-loading',
    '/groups',
    'Loading groups',
    homeScenario: 'loading',
  ),
  _StateSpec(
    'groups-error',
    '/groups',
    'Could not load data',
    homeScenario: 'error',
  ),
  _StateSpec('groups-offline', '/groups', 'Offline', homeScenario: 'offline'),
  _StateSpec(
    'activity-loading',
    '/activity',
    'Loading activity',
    homeScenario: 'loading',
  ),
  _StateSpec(
    'activity-error',
    '/activity',
    'Could not load data',
    homeScenario: 'error',
  ),
  _StateSpec(
    'activity-offline',
    '/activity',
    'Offline',
    homeScenario: 'offline',
  ),
  _StateSpec('camera-recovery-sheet', '/settings/permissions', 'Camera access'),
  _StateSpec('sms-recovery-sheet', '/settings/permissions', 'SMS access'),
  _StateSpec(
    'home-discovery',
    '/home',
    'Featured Groups',
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
    this.inputText,
    this.actionText,
    this.actionTooltip,
    this.actionKey,
    this.creationStep,
  });

  final String name;
  final String route;
  final String expectedText;
  final _RepositoryKind repositoryKind;
  final bool usesFakeAuth;
  final String? expectedFieldValue;
  final String? homeScenario;
  final String? inputText;
  final String? actionText;
  final String? actionTooltip;
  final String? actionKey;
  final int? creationStep;

  String get visibleMarker {
    if (defaultTargetPlatform != TargetPlatform.android) {
      if (creationStep != null) return 'Groups';
      if (name == 'sms-consent-sheet') return 'App permissions';
    }
    return expectedText;
  }

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
