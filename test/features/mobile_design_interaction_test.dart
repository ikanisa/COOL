import '../fixtures/collect_repository_fixture.dart';

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/core/notifications/collect_notification_service.dart';
import 'package:collect_app/core/security/sms_access_channel.dart';
import 'package:collect_app/core/widgets/collect_shell.dart';
import 'package:collect_app/features/auth/widgets/auth_screen_widgets.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
  });

  Future<void> open(
    WidgetTester tester,
    String route,
    CollectRepository repository,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = createAppRouter(initialLocation: route);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          collectRepositoryProvider.overrideWith((ref) => repository),
          collectNotificationServiceProvider.overrideWithValue(
            _NotificationService(),
          ),
        ],
        child: const CollectApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('system bars follow explicit and system appearance changes', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await open(tester, '/settings/appearance', FixtureCollectRepository());

    SystemUiOverlayStyle systemBars() => tester
        .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
        )
        .value;

    expect(systemBars().statusBarIconBrightness, Brightness.light);
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(systemBars().statusBarIconBrightness, Brightness.dark);
    expect(systemBars().statusBarBrightness, Brightness.light);
    expect(systemBars().systemNavigationBarIconBrightness, Brightness.dark);
    expect(systemBars().systemNavigationBarColor, CollectColors.light.canvas);

    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(systemBars().statusBarIconBrightness, Brightness.light);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(systemBars().statusBarIconBrightness, Brightness.dark);
    expect(tester.takeException(), isNull);
  });

  testWidgets('country picker blocks shell navigation and keeps large names', (
    tester,
  ) async {
    await open(tester, '/settings/profile', FixtureCollectRepository());
    tester.view.physicalSize = const Size(320, 568);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile_country_picker')));
    await tester.pumpAndSettle();
    final home = find.byKey(const ValueKey('collect-nav-home'));
    expect(home.hitTestable(), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('auth_country_search_input')),
      'American Samoa',
    );
    await tester.pumpAndSettle();
    final name = find.byKey(const ValueKey('auth_country_name_AS_1684'));
    final paragraph = tester.renderObject<RenderParagraph>(name);
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(paragraph.textScaler.scale(14), 28);
    expect(name.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.byType(AuthCountryPickerSheet))).pop();
    await tester.pumpAndSettle();
    expect(home.hitTestable(), findsOneWidget);
  });

  testWidgets('member filters keep complete labels at 200% text', (
    tester,
  ) async {
    await open(
      tester,
      '/groups/qa-private-group/members',
      FixtureCollectRepository(),
    );
    tester.view.physicalSize = const Size(320, 568);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    for (final label in ['MEMBERS', 'SORT', 'Collect ID']) {
      final target = find.text(label);
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      expect(
        tester.renderObject<RenderParagraph>(target).didExceedMaxLines,
        isFalse,
      );
      expect(target.hitTestable(), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('legal page title remains complete at 200% text', (tester) async {
    await open(tester, '/settings/legal/terms', FixtureCollectRepository());
    tester.view.physicalSize = const Size(320, 568);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    final title = find.text('Terms & Conditions');
    expect(
      tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow safety notices preserve the complete consequence', (
    tester,
  ) async {
    const message =
        'Confirm the MoMo number or code and provider before creating the payee. They can never be edited afterward; deactivate the payee if it must no longer receive contributions.';
    await tester.pumpWidget(
      MaterialApp(
        theme: CollectTheme.dark(),
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 220,
              child: InfoSecurityBanner(
                title: 'Route becomes immutable',
                message: message,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .renderObject<RenderParagraph>(find.text(message))
          .didExceedMaxLines,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Activity group filter reaches the final group at large text', (
    tester,
  ) async {
    await open(tester, '/activity', _ManyGroupsRepository());
    tester.view.physicalSize = const Size(320, 568);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filter by group'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final lastGroup = find.text('Synthetic group 40');
    await tester.ensureVisible(lastGroup);
    await tester.pumpAndSettle();
    expect(lastGroup.hitTestable(), findsOneWidget);
    await tester.tap(lastGroup);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byTooltip('Group filter'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'confirmation preserves full actions with keyboard and large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var commits = 0;
      const confirmLabel = 'Confirm transfer of group ownership';
      await tester.pumpWidget(
        MaterialApp(
          theme: CollectTheme.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              viewInsets: const EdgeInsets.only(bottom: 220),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                child: const Text('Review'),
                onPressed: () async {
                  if (await showCollectConfirmationSheet(
                    context: context,
                    title: 'Transfer ownership?',
                    message: 'The selected member will become the group owner.',
                    confirmLabel: confirmLabel,
                  )) {
                    commits++;
                  }
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      expect(commits, 0);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(commits, 0);
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(confirmLabel));
      await tester.pumpAndSettle();
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.text(confirmLabel),
          matching: find.byType(RichText),
        ),
      );
      expect(paragraph.didExceedMaxLines, isFalse);
      await tester.tap(find.text(confirmLabel));
      await tester.pumpAndSettle();
      expect(commits, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('account sign-out row opens confirmation through semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final repository = FixtureCollectRepository();
      await open(tester, '/settings/account', repository);
      final node = tester.getSemantics(find.bySemanticsLabel('Sign out'));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.tap,
      );
      await tester.pumpAndSettle();
      expect(find.text('Sign out?'), findsOneWidget);
      expect(repository.state.currentProfile, isNotNull);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('group chooser navigates to contribution through semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final repository = FixtureCollectRepository();
      final collection = repository.state.collections.first;
      await open(tester, '/contribute', repository);
      final node = tester.getSemantics(
        find.bySemanticsLabel(RegExp('^${RegExp.escape(collection.title)},')),
      );
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.tap,
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CollectApp)),
      );
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '/groups/${collection.id}/contribute',
      );
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('notification switches remain operable through semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final repository = FixtureCollectRepository();
      await open(tester, '/settings/notifications', repository);
      final before = repository.state.notificationPreferences.groupUpdates;
      final node = tester.getSemantics(
        find.bySemanticsLabel(
          'Group updates. Membership and group-management changes.',
        ),
      );
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.tap,
      );
      await tester.pumpAndSettle();
      expect(repository.state.notificationPreferences.groupUpdates, !before);
      expect(
        find.text('Membership and group-management changes.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('Appearance preview tracks Home dark light and high contrast', (
    tester,
  ) async {
    await open(tester, '/settings/appearance', FixtureCollectRepository());
    BoxDecoration previewDecoration() =>
        tester
                .widget<Container>(
                  find.byKey(const ValueKey('appearance-live-preview')),
                )
                .decoration!
            as BoxDecoration;
    expect(
      (previewDecoration().gradient! as LinearGradient).colors.first,
      CollectColors.referenceAccountHighlight,
    );
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(
      (previewDecoration().gradient! as LinearGradient).colors.first
          .computeLuminance(),
      greaterThan(0.7),
    );
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(highContrast: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpAndSettle();
    expect(previewDecoration().gradient, isNull);
    expect(tester.takeException(), isNull);
  });

  for (final textScale in [1.0, 2.0]) {
    testWidgets(
      'compact permissions retain complete SMS consent at text scale $textScale',
      (tester) async {
        const channel = MethodChannel(
          'flutter.baseflow.com/permissions/methods',
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async => call.method == 'checkPermissionStatus' ? 0 : null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        final repository = _ConsentRepository();
        await open(tester, '/settings/permissions', repository);
        expect(find.text('Camera').hitTestable(), findsOneWidget);
        expect(find.text('Notifications').hitTestable(), findsOneWidget);
        expect(repository.smsRequests, 0);
        if (textScale == 2) {
          tester.view.physicalSize = const Size(320, 640);
          tester.platformDispatcher.textScaleFactorTestValue = textScale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Review and allow'));
        }
        expect(
          tester
              .widget<TextButton>(
                find.widgetWithText(TextButton, 'Review and allow'),
              )
              .onPressed,
          isNotNull,
        );
        await tester.tap(find.text('Review and allow'));
        await tester.pumpAndSettle();
        expect(find.text('Allow MoMo receipt SMS access?'), findsOneWidget);
        expect(
          find.textContaining('does not read inbox history'),
          findsOneWidget,
        );
        final explanation = find.textContaining('parsing and reconciliation.');
        expect(tester.widget<Text>(explanation).maxLines, isNull);
        expect(
          tester.renderObject<RenderParagraph>(explanation).didExceedMaxLines,
          isFalse,
        );
        expect(repository.smsRequests, 0);
        await tester.ensureVisible(find.text('Not now'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Not now'));
        await tester.pumpAndSettle();
        expect(repository.smsRequests, 0);
        expect(find.text('Allow MoMo receipt SMS access?'), findsNothing);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  for (final country in ['RW', 'DE']) {
    testWidgets('$country amount retains every digit at 320dp and 200% text', (
      tester,
    ) async {
      final repository = FixtureCollectRepository(
        profileOverride: CollectProfile(
          id: 'local-user',
          publicId: '038491',
          whatsappPhone: '+250788123456',
          countryCode: country,
          currencyCode: country == 'RW' ? 'RWF' : 'EUR',
          momoNumber: '0788123456',
          revolutAccount: '000123456789',
        ),
      );
      await open(tester, '/groups/qa-private-group/contribute', repository);
      tester.view.physicalSize = const Size(320, 844);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      final field = find.byType(TextField).first;
      for (final amount
          in country == 'RW'
              ? ['1234', '2000', '999999999']
              : ['12.34', '999999999.99']) {
        await tester.enterText(field, amount);
        await tester.pump();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        final editable = tester
            .state<EditableTextState>(find.byType(EditableText).first)
            .renderEditable;
        final painter = TextPainter(
          text: editable.text,
          textScaler: editable.textScaler,
          textDirection: editable.textDirection,
        )..layout();
        expect(
          painter.width,
          lessThanOrEqualTo(editable.size.width - 3),
          reason: amount,
        );
        painter.dispose();
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('sign-in action labels fit completely at 320dp and 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final otpSent in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: CollectTheme.dark(),
          home: Scaffold(
            body: AuthActionDock(
              otpSent: otpSent,
              submitting: false,
              resendRemaining: 0,
              canSubmit: true,
              canResend: true,
              onSubmit: () {},
              onAnotherNumber: () {},
              onResend: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in [
        otpSent ? 'Verify and continue' : 'Send WhatsApp code',
        if (otpSent) ...['Change number', 'Resend'],
      ]) {
        final text = find.text(label);
        final button = find.ancestor(
          of: text,
          matching: find.byType(TextButton),
        );
        final paragraph = tester.renderObject<RenderParagraph>(text);
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason:
              '$label / ${tester.widget<Text>(text).maxLines} / ${paragraph.size}',
        );
        final textRect = tester.getRect(text);
        final buttonRect = tester.getRect(button);
        expect(textRect.top, greaterThanOrEqualTo(buttonRect.top + 8));
        expect(textRect.bottom, lessThanOrEqualTo(buttonRect.bottom - 8));
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('large-text section and empty-state headings do not truncate', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: CollectTheme.dark(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SectionHeader(
                  title: 'My groups',
                  actionLabel: 'View all',
                  onAction: () {},
                ),
                const EmptyIllustrationState(
                  icon: Icons.group,
                  title: 'No groups yet',
                  message: 'Create a group.',
                ),
                const EmptyIllustrationState(
                  icon: Icons.history,
                  title: 'No activity yet',
                  message: 'No confirmed contributions.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in ['My groups', 'No groups yet', 'No activity yet']) {
      expect(
        tester
            .renderObject<RenderParagraph>(find.text(label))
            .didExceedMaxLines,
        isFalse,
        reason: label,
      );
    }
    expect(tester.takeException(), isNull);
  });

  for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
    testWidgets(
      'section action reflows without splitting large-text words $direction',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: CollectTheme.dark(),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Directionality(
                textDirection: direction,
                child: Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SectionHeader(
                      title: 'Featured groups',
                      actionLabel: 'View all',
                      onAction: () => taps++,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final title = find.text('Featured groups');
        final action = find.widgetWithText(TextButton, 'View all');
        final paragraph = tester.renderObject<RenderParagraph>(title);
        expect(
          paragraph.getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 8),
          ),
          hasLength(1),
          reason: 'Featured stays a whole word',
        );
        expect(
          tester.getRect(action).top,
          greaterThanOrEqualTo(tester.getRect(title).bottom),
        );
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
        await tester.tap(action);
        expect(taps, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('group profile saves only changed valid fields', (tester) async {
    final repository = FixtureCollectRepository();
    await open(tester, '/groups/qa-private-group/profile', repository);
    final save = find.widgetWithText(FilledButton, 'Save');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    final name = find.byType(TextField).first;
    final original = repository.collectionById('qa-private-group').title;
    await tester.enterText(name, '');
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(name, 'Updated group');
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.enterText(name, original);
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    expect(find.text('Rwanda MoMo receiver'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Paying to'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Paying to').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('group photo library cancels safely and saves a selected photo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final repository = FixtureCollectRepository();
    final original = repository.collectionById('qa-private-group');
    await open(tester, '/groups/qa-private-group/profile', repository);
    final title = find.byWidgetPredicate(
      (widget) => widget is Text && widget.data == original.title,
    );
    await tester.ensureVisible(title);
    expect(
      tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
      isFalse,
    );
    await tester.ensureVisible(find.byTooltip('Upload image'));
    await tester.tap(find.byTooltip('Upload image'));
    await tester.pumpAndSettle();
    expect(find.text('Rwanda collection'), findsOneWidget);
    await tester.tap(find.byTooltip('Close photo collection'));
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Save');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    expect(repository.collectionById(original.id).imageUrl, original.imageUrl);
    await tester.tap(find.byTooltip('Upload image'));
    await tester.pumpAndSettle();
    final photo = find.text('Community savings');
    await tester.scrollUntilVisible(
      photo,
      160,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(photo);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remove image'), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    expect(repository.collectionById(original.id).imageUrl, original.imageUrl);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(
      repository.collectionById(original.id).imageUrl,
      startsWith('data:image/png;base64,'),
    );
    expect(tester.takeException(), isNull);
  });

  for (final savedHex in ['#8885F0', '#3CD070', '#D38B96', '#FF5E43']) {
    testWidgets('editing a group preserves saved colour $savedHex', (
      tester,
    ) async {
      final repository = FixtureCollectRepository();
      final group = repository.collectionById('qa-private-group');
      await repository.updateCollectionProfile(
        collectionId: group.id,
        title: group.title,
        description: group.description,
        recurringCadence: group.recurringCadence,
        isPublic: group.isPublic,
        accentColorHex: savedHex,
      );
      await open(tester, '/groups/qa-private-group/profile', repository);
      final save = find.widgetWithText(FilledButton, 'Save');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.enterText(find.byType(TextField).first, 'Updated QA group');
      await tester.pump();
      await tester.tap(save);
      await tester.pumpAndSettle();
      final updated = repository.collectionById(group.id);
      expect(updated.title, 'Updated QA group');
      expect(updated.accentColorHex, savedHex);
      expect(CollectColors.groupColorHexForDisplay(savedHex), isNot(savedHex));
      expect(tester.takeException(), isNull);
    });
  }

  for (final path in ['/home', '/groups', '/activity', '/settings']) {
    testWidgets('$path preserves the four navigation identities', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CollectShell(
            currentPath: path,
            onNavigate: (_) {},
            child: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final title in ['Home', 'Groups', 'Activity', 'Profile']) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.byIcon(CollectIcons.activity), findsOneWidget);
      expect(find.byIcon(CollectIcons.profile), findsOneWidget);
      expect(find.byIcon(CollectIcons.ledger), findsNothing);
      expect(find.byIcon(CollectIcons.settings), findsNothing);
    });
  }
}

class _ConsentRepository extends FixtureCollectRepository {
  _ConsentRepository() : super();

  int smsRequests = 0;

  @override
  Future<SmsAccessStatus> refreshSmsAccessStatus() async =>
      const SmsAccessStatus.unavailable();

  @override
  Future<bool> setSmsAccess(bool enabled) async {
    smsRequests += 1;
    return false;
  }
}

class _NotificationService extends CollectNotificationService {
  @override
  Future<bool> areNotificationsEnabled() async => false;
}

class _ManyGroupsRepository extends FixtureCollectRepository {
  _ManyGroupsRepository() : super(fixtureCollectionCount: 40) {
    state = state.copyWith(
      collections: List.generate(
        40,
        (index) => state.collections[index].copyWith(
          title: 'Synthetic group ${index + 1}',
        ),
      ),
    );
  }
}
