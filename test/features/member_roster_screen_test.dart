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

class _RosterRepository extends CollectRepository {
  _RosterRepository() : super.fixture(fixtureNow: DateTime.utc(2026, 9, 2));
  @override
  Future<List<CollectMember>> membersForCollection(String collectionId) async =>
      [
        CollectMember(
          publicId: '123456',
          role: 'owner',
          status: 'active',
          joinedAt: DateTime.utc(2026, 9, 1),
          amountScope: 'shared',
          contributionTotals: const {'RWF': 500},
        ),
        CollectMember(
          publicId: '038491',
          role: 'admin',
          status: 'active',
          joinedAt: DateTime.utc(2026, 9, 2),
          amountScope: 'own',
          contributionTotals: const {'EUR': 12345, 'RWF': 3000},
        ),
        CollectMember(
          publicId: '234567',
          role: 'receiver',
          status: 'active',
          joinedAt: DateTime.utc(2026, 9, 1),
        ),
        CollectMember(
          publicId: '345678',
          role: 'viewer',
          status: 'invited',
          joinedAt: DateTime.utc(2026, 9, 2),
        ),
      ];
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
  Future<GlobalKey> pumpRoster(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = createAppRouter(
      initialLocation: '/groups/col-church/members',
    );
    final key = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          collectRepositoryProvider.overrideWith((ref) => _RosterRepository()),
          collectThemeModeProvider.overrideWith(
            (ref) => CollectThemeModeController(initialMode: ThemeMode.dark),
          ),
        ],
        child: RepaintBoundary(
          key: key,
          child: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: const CollectApp(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
    });
    return key;
  }

  for (final width in [320.0, 390.0, 430.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'roster distinguishes roles and safe amounts at $width dp ${scale}x',
        (tester) async {
          final key = await pumpRoster(tester, width: width, scale: scale);
          expect(find.text('Admin · Active'), findsOneWidget);
          expect(find.text('Owner · Active'), findsOneWidget);
          expect(find.text('EUR 123.45\nRWF 3,000'), findsOneWidget);
          expect(find.text('Your contributions'), findsOneWidget);
          expect(find.text('Shared contributions'), findsOneWidget);
          expect(find.text('RWF 0'), findsNothing);
          expect(find.text('RWF 15,345'), findsNothing);
          // Large text legitimately puts later rows outside the lazy viewport.
          // Walk the whole roster instead of requiring off-screen widgets.
          final observed = <String>{};
          for (final subtitle in [
            'Admin · Active',
            'Owner · Active',
            'Receiver · Active',
            'Viewer · Invited',
          ]) {
            await tester.scrollUntilVisible(
              find.text(subtitle),
              180,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            expect(find.text(subtitle), findsOneWidget);
            observed.addAll(
              tester
                  .widgetList<FinancialListRow>(find.byType(FinancialListRow))
                  .map((row) => row.title),
            );
            expect(find.text('RWF 0'), findsNothing);
            expect(find.text('RWF 15,345'), findsNothing);
            expect(tester.takeException(), isNull);
          }
          expect(observed.toList(), ['038491', '123456', '234567', '345678']);
          expect(tester.takeException(), isNull);
          final capture = Platform.environment['COLLECT_UAT_CAPTURE_DIR'];
          if (capture != null && width == 390 && scale == 1) {
            tester
                .state<ScrollableState>(find.byType(Scrollable).first)
                .position
                .jumpTo(0);
            await tester.pumpAndSettle();
            await tester.runAsync(() async {
              final boundary =
                  key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage(pixelRatio: 1);
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.png,
              ))!;
              await File(
                '$capture/34-member-roster-390.png',
              ).writeAsBytes(bytes.buffer.asUint8List());
              image.dispose();
            });
          }
        },
      );
    }
  }
  testWidgets(
    'roster search is numeric and amount sorting is currency-specific',
    (tester) async {
      await pumpRoster(tester);
      await tester.tap(find.text('Collect ID').last);
      await tester.pumpAndSettle();
      expect(find.text('RWF amount'), findsOneWidget);
      expect(find.text('EUR amount'), findsOneWidget);
      expect(find.text('Top'), findsNothing);
      await tester.tap(find.text('EUR amount'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<FinancialListRow>(find.byType(FinancialListRow))
            .first
            .title,
        '038491',
      );
      await tester.enterText(find.byType(TextField), '234567');
      await tester.pumpAndSettle();
      final row = tester.widget<FinancialListRow>(
        find.byType(FinancialListRow),
      );
      expect(row.title, '234567');
      expect(row.amounts, isEmpty);
      expect(find.textContaining('RWF'), findsNothing);
      expect(find.text('No members found'), findsNothing);
    },
  );
}
