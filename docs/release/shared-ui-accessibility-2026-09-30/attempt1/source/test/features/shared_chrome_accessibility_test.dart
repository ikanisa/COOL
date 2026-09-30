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
}
