import 'dart:ui' show Tristate;

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/app/theme/collect_theme_controller.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/collect_repository_fixture.dart';

List<SemanticsNode> _nodes(WidgetTester tester) =>
    find.semantics.byPredicate((_) => true).evaluate().toList();

void _expectHeading(WidgetTester tester, String label, int level) {
  final matches = _nodes(tester).where(
    (node) =>
        node.getSemanticsData().label == label &&
        node.getSemanticsData().headingLevel == level,
  );
  expect(
    matches,
    hasLength(1),
    reason: 'One distinct $label heading at level $level',
  );
  expect(matches.single.getSemanticsData().flagsCollection.isButton, isFalse);
}

Future<GoRouter> _open(WidgetTester tester, String path, double scale) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final router = createAppRouter(initialLocation: path);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        supabaseClientProvider.overrideWithValue(null),
        collectAuthenticatedUserIdProvider.overrideWithValue('local-user'),
        appRouterProvider.overrideWithValue(router),
        collectRepositoryProvider.overrideWith(
          (ref) => FixtureCollectRepository(),
        ),
        collectThemeModeProvider.overrideWith(
          (ref) => CollectThemeModeController(loadPersistedMode: false),
        ),
      ],
      child: const CollectApp(),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    for (final font in {
      'Inter': 'assets/typefaces/Inter-Variable.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  for (final scale in [1.0, 2.0]) {
    for (final page in [
      ('/settings/security', 'Security'),
      ('/settings/notifications', 'Notifications'),
      ('/settings/appearance', 'Appearance'),
      ('/settings/help', 'Help'),
      ('/groups/qa-private-group/members', 'Members'),
    ]) {
      testWidgets(
        '${page.$2} heading wraps with independent Back at ${scale}x',
        (tester) async {
          await _open(tester, page.$1, scale);
          _expectHeading(tester, page.$2, 1);
          final title = find.text(page.$2).first;
          expect(
            tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
            isFalse,
          );
          expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
    for (final legal in [
      ('terms', 'Terms & Conditions', 'Using Collect'),
      ('privacy', 'Privacy Policy', 'Data we collect'),
    ]) {
      testWidgets(
        '${legal.$1} has separate page/section headings and Back at 320px ${scale}x',
        (tester) async {
          final router = await _open(
            tester,
            '/settings/legal/${legal.$1}',
            scale,
          );
          _expectHeading(tester, legal.$2, 1);
          _expectHeading(tester, legal.$3, 2);
          final title = find.text(legal.$2);
          expect(
            tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
            isFalse,
          );
          final back = find.byTooltip('Back');
          expect(back.hitTestable(), findsOneWidget);
          expect(tester.getSize(back).shortestSide, greaterThanOrEqualTo(44));
          await tester.tap(back);
          await tester.pumpAndSettle();
          expect(router.routeInformationProvider.value.uri.path, '/settings');
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'Group header and confirmed hero stay distinct at 320px ${scale}x',
      (tester) async {
        await _open(tester, '/groups/qa-private-group', scale);
        _expectHeading(tester, 'Group', 1);
        expect(
          _nodes(
            tester,
          ).where((node) => node.getSemanticsData().headingLevel == 2),
          isNotEmpty,
        );
        for (final label in ['Contribute', 'Members', 'Share', 'Manage']) {
          final action = find.text(label);
          await tester.ensureVisible(action);
          await tester.pumpAndSettle();
          expect(action.hitTestable(), findsOneWidget);
          expect(
            tester.renderObject<RenderParagraph>(action).didExceedMaxLines,
            isFalse,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final layout in [(320.0, 1.0), (390.0, 1.0), (320.0, 2.0)]) {
    testWidgets(
      'quick action words stay whole at ${layout.$1}px ${layout.$2}x',
      (tester) async {
        await _open(tester, '/groups/qa-private-group', layout.$2);
        tester.view.physicalSize = Size(layout.$1, 568);
        await tester.pumpAndSettle();
        for (final label in ['Contribute', 'Members', 'Share', 'Manage']) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(label),
          );
          final boxes = paragraph.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: label.length),
          );
          expect(
            boxes.map((box) => box.top).toSet(),
            hasLength(1),
            reason: '$label must remain a whole word',
          );
          expect(paragraph.didExceedMaxLines, isFalse);
        }
        final first = tester.getRect(find.text('Contribute'));
        final third = tester.getRect(find.text('Share'));
        if (layout.$1 == 390 && layout.$2 == 1) {
          expect(third.top, closeTo(first.top, 0.1));
        } else {
          expect(third.top, greaterThan(first.bottom));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'keyboard Back and header action remain independently reachable',
    (tester) async {
      var shared = 0;
      final router = GoRouter(
        initialLocation: '/detail',
        routes: [
          GoRoute(
            path: '/detail',
            builder: (_, _) => Scaffold(
              body: ScreenHeader(
                title: 'Group activity',
                subtitle: 'Confirmed activity',
                actions: [
                  IconButton(
                    tooltip: 'Share group',
                    onPressed: () => shared++,
                    icon: const Icon(Icons.share),
                  ),
                ],
              ),
            ),
          ),
          GoRoute(
            path: '/home',
            builder: (_, _) => const Scaffold(body: Text('Home destination')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
      );
      await tester.pumpAndSettle();
      _expectHeading(tester, 'Group activity', 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(shared, 1);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Home destination'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'quick actions retain semantics focus and disabled actions stay inert',
    (tester) async {
      var shares = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: CollectHeroQuickActionRow(
              actions: [
                CollectHeroQuickAction(
                  icon: Icons.share,
                  label: 'Share',
                  onTap: () => shares++,
                ),
                const CollectHeroQuickAction(
                  icon: Icons.edit,
                  label: 'Manage',
                  onTap: null,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final share = find.semantics.byLabel('Share');
      final disabled = find.semantics.byLabel('Manage');
      expect(share.evaluate(), hasLength(1));
      expect(
        disabled.evaluate().single.getSemanticsData().hasAction(
          SemanticsAction.tap,
        ),
        isFalse,
      );
      expect(
        disabled.evaluate().single.getSemanticsData().hasAction(
          SemanticsAction.focus,
        ),
        isFalse,
      );
      tester.semantics.performAction(share, SemanticsAction.focus);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(shares, 1);
      await tester.tap(find.text('Manage'));
      await tester.pump();
      expect(shares, 1);
    },
  );

  testWidgets(
    'overview profile search and action retain keyboard focus without duplicate names',
    (tester) async {
      final taps = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: CollectScreenTopChrome(
              onAvatarTap: () => taps.add('Profile'),
              onSearchTap: () => taps.add('Search groups'),
              searchLabel: 'Search groups',
              actions: [
                CollectChromeAction(
                  icon: Icons.refresh,
                  tooltip: 'Refresh data',
                  onPressed: () => taps.add('Refresh data'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in ['Profile', 'Search groups', 'Refresh data']) {
        final button = find.semantics.byPredicate((node) {
          final data = node.getSemanticsData();
          return data.label == label || data.tooltip == label;
        });
        expect(button.evaluate(), hasLength(1), reason: label);
        tester.semantics.performAction(button, SemanticsAction.focus);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
      }
      expect(taps, ['Profile', 'Search groups', 'Refresh data']);
    },
  );

  testWidgets(
    'bottom navigation retains semantic keyboard focus and route meaning',
    (tester) async {
      final router = await _open(tester, '/groups/qa-private-group', 2);
      for (final destination in [
        ('Home', '/home'),
        ('Groups', '/groups/qa-private-group'),
        ('Activity', '/activity'),
        ('Profile', '/settings'),
      ]) {
        final button = find.semantics.byPredicate((node) {
          final data = node.getSemanticsData();
          return data.label == destination.$1 &&
              data.flagsCollection.isSelected != Tristate.none;
        });
        expect(button.evaluate(), hasLength(1));
        tester.semantics.performAction(button, SemanticsAction.focus);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, destination.$2);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Members search keeps focus with 2x text and keyboard insets', (
    tester,
  ) async {
    await _open(tester, '/groups/qa-private-group/members', 2);
    final field = find.byType(TextField);
    await tester.tap(field);
    tester.view.viewInsets = const FakeViewPadding(bottom: 220);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.enterText(field, '038');
    await tester.pumpAndSettle();
    expect(field.hitTestable(), findsOneWidget);
    expect(tester.getRect(field).bottom, lessThanOrEqualTo(348));
    expect(FocusManager.instance.primaryFocus, isNotNull);
    expect(tester.takeException(), isNull);
  });

  for (final content in [
    (
      'Updates unavailable',
      'Could not refresh data. Check your connection and try again.',
    ),
    ('No groups yet', 'Find a public group and start contributing.'),
    (
      'Data refreshed',
      'The latest data refresh completed. This does not confirm a payment.',
    ),
  ]) {
    testWidgets(
      'state panel announces ${content.$1} once and preserves action focus',
      (tester) async {
        var opened = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: MinimalStatePanel(
                icon: CollectIcons.sync,
                title: content.$1,
                message: content.$2,
                primaryAction: const CollectButton(
                  label: 'Refreshing data',
                  onPressed: null,
                ),
                secondaryAction: CollectButton(
                  label: 'View groups',
                  onPressed: () => opened++,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        _expectHeading(tester, content.$1, 2);
        expect(
          _nodes(
            tester,
          ).where((node) => node.getSemanticsData().label.contains(content.$2)),
          hasLength(1),
        );
        final disabled = find.semantics.byLabel('Refreshing data');
        expect(
          disabled.evaluate().single.getSemanticsData().hasAction(
            SemanticsAction.tap,
          ),
          isFalse,
        );
        final active = find.semantics.byLabel('View groups');
        tester.semantics.performAction(active, SemanticsAction.focus);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(opened, 1);
      },
    );
  }
}
