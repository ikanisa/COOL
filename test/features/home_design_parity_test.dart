import '../fixtures/collect_repository_fixture.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/collect_theme_controller.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/widgets/collect_group_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _HomeDesignRepository extends FixtureCollectRepository {
  _HomeDesignRepository(String scenario) : super() {
    final publicGroups = state.collections.where((item) => item.isPublic);
    state = state.copyWith(
      contributions: [],
      paymentIntents: [],
      collectionSummaries: {},
      collections: switch (scenario) {
        'discovery' => publicGroups.toList(),
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

  void updateFeaturedGroup(String id, {String? title, bool? isPublic}) {
    state = state.copyWith(
      collections: [
        for (final item in state.collections)
          if (item.id == id)
            item.copyWith(title: title, isPublic: isPublic)
          else
            item,
      ],
    );
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  const captureKey = ValueKey('home-design-capture');

  test('Featured groups follow backend records after joining and edits', () {
    final repository = _HomeDesignRepository('joined');
    final container = ProviderContainer(
      overrides: [collectRepositoryProvider.overrideWith((ref) => repository)],
    );
    addTearDown(container.dispose);
    final groups = container.read(featuredCollectionsProvider);
    expect(groups.length, 2);
    expect(groups.every((group) => group.isCurrentUserMember), isTrue);
    final changedId = groups.first.id;
    repository.updateFeaturedGroup(changedId, title: 'Updated public group');
    expect(
      container.read(featuredCollectionsProvider).first.title,
      'Updated public group',
    );
    repository.updateFeaturedGroup(changedId, isPublic: false);
    expect(
      container.read(featuredCollectionsProvider).map((group) => group.id),
      isNot(contains(changedId)),
    );
    expect(
      container.read(homeCollectionsProvider).map((group) => group.id),
      contains(changedId),
    );
  });

  Future<void> pumpHome(
    WidgetTester tester,
    String scenario, {
    Size size = const Size(390, 844),
    double textScale = 1,
    ThemeMode theme = ThemeMode.dark,
    String route = '/home',
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final router = createAppRouter(initialLocation: route);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          collectRepositoryProvider.overrideWith(
            (ref) => _HomeDesignRepository(scenario),
          ),
          collectThemeModeProvider.overrideWith(
            (ref) => CollectThemeModeController(
              initialMode: theme,
              loadPersistedMode: false,
            ),
          ),
        ],
        child: const RepaintBoundary(key: captureKey, child: CollectApp()),
      ),
    );
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final path = Platform.environment['COLLECT_DESIGN_CAPTURE_DIR'];
    if (path == null) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(captureKey),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory(path)..createSync(recursive: true);
      File(
        '${dir.path}/home-$name.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final scenario in ['discovery', 'joined', 'mixed']) {
    testWidgets('Home $scenario keeps the reviewed group cards', (
      tester,
    ) async {
      await pumpHome(tester, scenario);
      expect(find.byType(GroupListPanel), findsNothing);
      final cards = tester.widgetList<GroupCard>(find.byType(GroupCard));
      expect(cards, isNotEmpty);
      expect(
        cards.every((card) => card.variant == GroupCardVariant.publicDiscovery),
        isTrue,
      );
      expect(find.text('Ikimina'), findsNothing);
      expect(find.text('Sport'), findsNothing);
      if (scenario == 'joined') {
        expect(find.text('My groups'), findsOneWidget);
        expect(find.byTooltip('Contribute to Gikundiro'), findsWidgets);
      } else if (scenario == 'discovery') {
        expect(find.text('My groups'), findsNothing);
        expect(find.byTooltip('Contribute & Join Gikundiro'), findsOneWidget);
      } else {
        expect(find.text('My groups'), findsOneWidget);
      }
      await tester.scrollUntilVisible(
        find.text('Featured groups'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Featured groups'), findsOneWidget);
      expect(find.text('Public groups'), findsNothing);
      await tester.ensureVisible(find.text('Featured groups'));
      await tester.pumpAndSettle();
      expect(
        find.byTooltip(
          scenario == 'discovery'
              ? 'Contribute & Join Gikundiro'
              : 'Contribute to Gikundiro',
        ),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
      await capture(tester, scenario);
    });
  }

  for (final scenario in ['empty', 'loading', 'error', 'offline']) {
    testWidgets('Home $scenario has an explicit truthful state', (
      tester,
    ) async {
      await pumpHome(tester, scenario);
      if (scenario == 'empty') {
        expect(find.text('No groups yet'), findsOneWidget);
        expect(find.text('Featured groups'), findsNothing);
      }
      if (scenario == 'loading' || scenario == 'error') {
        expect(find.text('RWF 0'), findsNothing);
      }
      expect(find.text('Connection needs attention'), findsNothing);
      expect(tester.takeException(), isNull);
      await capture(tester, scenario);
    });
  }

  for (final width in [320.0, 393.0, 430.0, 800.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Joined Home fits $width at text scale $scale', (
        tester,
      ) async {
        await pumpHome(
          tester,
          'joined',
          size: Size(width, 844),
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
        await capture(tester, 'joined-${width.toInt()}-${scale}x');
        final myCards = find.descendant(
          of: find.byKey(const ValueKey('home_my_groups')),
          matching: find.byType(GroupCard),
        );
        expect(myCards, findsNWidgets(2));
        final homeCards = [
          for (final card in myCards.evaluate())
            tester.getRect(find.byElementPredicate((item) => item == card)),
        ];
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                axisDirectionToAxis(widget.axisDirection) == Axis.horizontal,
          ),
          findsNothing,
          reason: 'Home group cards use vertical scrolling like Groups',
        );
        await tester.scrollUntilVisible(
          find.text('Featured groups'),
          160,
          scrollable: find.byType(Scrollable).first,
        );
        final featuredCards = find.descendant(
          of: find.byKey(const ValueKey('home_featured_groups')),
          matching: find.byType(GroupCard),
        );
        expect(featuredCards, findsNWidgets(2));
        for (final card in featuredCards.evaluate()) {
          homeCards.add(
            tester.getRect(find.byElementPredicate((item) => item == card)),
          );
        }
        await tester.ensureVisible(
          find.byKey(const ValueKey('home_featured_groups')),
        );
        await tester.pumpAndSettle();
        await capture(tester, 'featured-${width.toInt()}-${scale}x');
        await pumpHome(
          tester,
          'joined',
          size: Size(width, 844),
          textScale: scale,
          route: '/groups',
        );
        final groupsCard = tester.getRect(find.byType(GroupCard).first);
        await capture(tester, 'groups-${width.toInt()}-${scale}x');
        for (final card in homeCards) {
          expect(
            card.width,
            closeTo(groupsCard.width, 0.01),
            reason: 'Home cards span the same column width as Groups',
          );
          expect(card.height, closeTo(groupsCard.height, 0.01));
        }
        expect(
          homeCards.first.left,
          closeTo(groupsCard.left, 0.01),
          reason: 'Home and Groups share the same page inset',
        );
      });
    }
  }

  testWidgets('Joined Home keeps its presentation in light mode', (
    tester,
  ) async {
    await pumpHome(tester, 'joined', theme: ThemeMode.light);
    expect(find.byType(GroupListPanel), findsNothing);
    expect(tester.takeException(), isNull);
    await capture(tester, 'joined-light');
  });

  testWidgets('Joined card still opens its group', (tester) async {
    await pumpHome(tester, 'joined');
    await tester.tap(find.text('Gikundiro').first);
    await tester.pumpAndSettle();
    expect(find.text('Contribute & Join'), findsNothing);
    expect(find.text('Contribute'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
