import '../fixtures/collect_repository_fixture.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/collect_theme_controller.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _LargeHistoryRepository extends FixtureCollectRepository {
  _LargeHistoryRepository() : super(fixtureNow: DateTime.utc(2026, 9, 2)) {
    state = state.copyWith(
      contributions: List.generate(
        1000,
        (index) => Contribution(
          id: 'synthetic-$index',
          collectionId: 'qa-private-group',
          amountRwf: index.isEven ? 1000 : 125,
          currency: index.isEven ? 'RWF' : 'EUR',
          supporterLabel: 'Collect ID ${400000 + index}',
          isCurrentUserContribution: true,
          transactionId: 'SYNTHETIC-$index',
          createdAt: DateTime.utc(
            2026,
            9,
            2,
          ).subtract(Duration(minutes: index)),
        ),
      ),
    );
  }

  @override
  Future<List<CollectMember>> membersForCollection(String collectionId) async =>
      List.generate(
        1000,
        (index) => CollectMember(
          publicId: '${400000 + index}',
          role: index == 999 ? 'owner' : 'member',
          status: 'active',
          joinedAt: DateTime.utc(2026, 9, 2),
        ),
      );
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
  final captureKey = GlobalKey();

  Future<void> pumpScreen(WidgetTester tester, String route) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = createAppRouter(initialLocation: route);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          collectRepositoryProvider.overrideWith(
            (ref) => _LargeHistoryRepository(),
          ),
          collectThemeModeProvider.overrideWith(
            (ref) => CollectThemeModeController(initialMode: ThemeMode.dark),
          ),
        ],
        child: RepaintBoundary(key: captureKey, child: const CollectApp()),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
    });
  }

  for (final route in [
    '/activity',
    '/groups/qa-private-group/ledger',
    '/groups/qa-private-group/members',
  ]) {
    testWidgets('$route builds a bounded viewport, not all 1000 rows', (
      tester,
    ) async {
      await pumpScreen(tester, route);
      final rows = find.byType(
        route == '/activity' ? ActivityFeedItem : FinancialListRow,
      );
      expect(rows.evaluate().length, greaterThan(0));
      expect(rows.evaluate().length, lessThan(25));
      final initialCount = rows.evaluate().length;
      final captureDir = Platform.environment['COLLECT_UAT_VOLUME_CAPTURE_DIR'];
      if (captureDir != null) {
        const names = {
          '/activity': '36-large-activity-390.png',
          '/groups/qa-private-group/ledger': '37-large-ledger-390.png',
          '/groups/qa-private-group/members': '38-large-roster-390.png',
        };
        await tester.runAsync(() async {
          final boundary =
              captureKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!;
          await File(
            '$captureDir/${names[route]}',
          ).writeAsBytes(bytes.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(find.textContaining('400999'), findsNothing);
      final initialKeys = tester.widgetList(rows).map((row) => row.key).toSet();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -2200));
      await tester.pumpAndSettle();
      expect(rows.evaluate().length, greaterThan(0));
      expect(rows.evaluate().length, lessThan(25));
      expect(
        tester.widgetList(rows).map((row) => row.key).toSet(),
        isNot(initialKeys),
      );
      final scrolledCount = rows.evaluate().length;
      // Reach the end without searching: virtualization must not truncate.
      for (var attempt = 0; attempt < 5; attempt++) {
        final position = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        position.jumpTo(position.maxScrollExtent);
        await tester.pumpAndSettle();
        if (find.textContaining('400999').evaluate().isNotEmpty) break;
      }
      expect(find.textContaining('400999'), findsWidgets);
      expect(rows.evaluate().length, lessThan(25));
      debugPrint(
        'UAT_VIEWPORT $route total=1000 initial=$initialCount '
        'scrolled=$scrolledCount last=${rows.evaluate().length}',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('$route searches the last record beyond the viewport', (
      tester,
    ) async {
      await pumpScreen(tester, route);
      if (route != '/groups/qa-private-group/members') {
        await tester.tap(
          find.text(route == '/activity' ? 'Search activity' : 'Search'),
        );
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byType(TextField), '400999');
      await tester.pumpAndSettle();
      final rows = find.byType(
        route == '/activity' ? ActivityFeedItem : FinancialListRow,
      );
      expect(rows, findsOneWidget);
      expect(find.textContaining('400999'), findsWidgets);
      if (route != '/groups/qa-private-group/members') {
        expect(find.text('EUR 1.25'), findsWidgets);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('activity totals cover all rows and retain separate currencies', (
    tester,
  ) async {
    await pumpScreen(tester, '/activity');
    expect(find.text('EUR 625.00\nRWF 500,000'), findsOneWidget);
    expect(find.textContaining('1000'), findsWidgets);
    expect(find.text('RWF 562,500'), findsNothing);
  });
}
