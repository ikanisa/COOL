import '../fixtures/collect_repository_fixture.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/collect_theme_controller.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RosterRepository extends FixtureCollectRepository {
  _RosterRepository({this.members})
    : super(fixtureNow: DateTime.utc(2026, 9, 2));

  final List<CollectMember>? members;
  int reads = 0;

  void markScopeUncertain() => state = state.copyWith(memberScopeUncertain: true);

  @override
  Future<List<CollectMember>> membersForCollection(String collectionId) async {
    reads++;
    return members ?? [
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
          contributionTotals: const {'RWF': 3000},
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
    List<CollectMember>? members,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = createAppRouter(
      initialLocation: '/groups/qa-private-group/members',
    );
    final key = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collectBackendClientProvider.overrideWithValue(null),
          appRouterProvider.overrideWithValue(router),
          collectRepositoryProvider.overrideWith(
            (ref) => _RosterRepository(members: members),
          ),
          collectThemeModeProvider.overrideWith(
            (ref) => CollectThemeModeController(initialMode: ThemeMode.dark),
          ),
        ],
        child: RepaintBoundary(
          key: key,
          child: MediaQuery(
            data: MediaQueryData.fromView(
              tester.view,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: const CollectApp(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final searchContext = tester.element(find.byType(TextField));
    expect(MediaQuery.sizeOf(searchContext), Size(width, 844));
    expect(MediaQuery.textScalerOf(searchContext).scale(1), scale);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
    });
    return key;
  }

  testWidgets('unverified membership does not render an empty roster', (
    tester,
  ) async {
    final repository = _RosterRepository()..markScopeUncertain();
    final router = createAppRouter(
      initialLocation: '/groups/qa-private-group/members',
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collectBackendClientProvider.overrideWithValue(null),
          appRouterProvider.overrideWithValue(router),
          collectRepositoryProvider.overrideWith((ref) => repository),
          collectThemeModeProvider.overrideWith(
            (ref) => CollectThemeModeController(initialMode: ThemeMode.dark),
          ),
        ],
        child: const CollectApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No members yet'), findsNothing);
    expect(find.text('Could not load data'), findsOneWidget);
    expect(repository.reads, 0);
  });

  for (final width in [320.0, 390.0, 430.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'roster distinguishes roles and safe amounts at $width dp ${scale}x',
        (tester) async {
          final key = await pumpRoster(tester, width: width, scale: scale);
          expect(find.text('Admin · Active'), findsOneWidget);
          expect(find.text('Owner · Active'), findsOneWidget);
          expect(find.text('RWF 3,000'), findsOneWidget);
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
  testWidgets('roster search is numeric and amount sorting is RWF-specific', (
    tester,
  ) async {
    await pumpRoster(tester);
    await tester.tap(find.text('Collect ID').last);
    await tester.pumpAndSettle();
    expect(find.text('RWF amount'), findsOneWidget);
    expect(find.text('EUR amount'), findsNothing);
    expect(find.text('Top'), findsNothing);
    await tester.tap(find.text('RWF amount'));
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
    final row = tester.widget<FinancialListRow>(find.byType(FinancialListRow));
    expect(row.title, '234567');
    expect(row.amounts, isEmpty);
    expect(row.amounts, isEmpty);
    expect(find.text('No members found'), findsNothing);
  });

  testWidgets('an empty owner filter remains visible and can be cleared', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    await pumpRoster(
      tester,
      members: [
        CollectMember(
          publicId: '111111',
          role: 'member',
          status: 'active',
          joinedAt: DateTime.utc(2026, 9, 1),
        ),
      ],
    );

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Owner'));
    await tester.pumpAndSettle();

    expect(find.text('No members in this filter'), findsOneWidget);
    expect(find.text('No members yet'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Members Owner')), findsWidgets);
    final clear = find.widgetWithText(CollectButton, 'Clear filter');
    await tester.ensureVisible(clear);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('Clear filter')), findsWidgets);
    await tester.tap(clear);
    await tester.pumpAndSettle();

    expect(find.text('No members in this filter'), findsNothing);
    await tester.ensureVisible(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('Members All')), findsWidgets);
    expect(find.text('111111'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty search can be cleared to restore results', (
    tester,
  ) async {
    await pumpRoster(tester);
    await tester.enterText(find.byType(TextField), '999999');
    await tester.pumpAndSettle();

    expect(find.text('No members found'), findsOneWidget);
    expect(
      find.text('No Collect ID or role matches that search.'),
      findsOneWidget,
    );
    expect(find.text('No members yet'), findsNothing);
    final clear = find.widgetWithText(CollectButton, 'Clear search');
    await tester.ensureVisible(clear);
    await tester.tap(clear);
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    expect(find.text('No members found'), findsNothing);
    expect(find.text('038491'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('roster search keeps focus as results disappear and return', (
    tester,
  ) async {
    await pumpRoster(tester);
    final field = find.byType(TextField);
    final editable = find.descendant(
      of: field,
      matching: find.byType(EditableText),
    );
    await tester.showKeyboard(field);
    await tester.pump();
    final focus = tester.widget<EditableText>(editable).focusNode;
    expect(focus.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '999999',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );
    await tester.pump();
    expect(find.text('No members found'), findsOneWidget);
    expect(tester.widget<EditableText>(editable).focusNode, same(focus));
    expect(focus.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '038491',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );
    await tester.pump();
    expect(find.text('No members found'), findsNothing);
    final rows = tester.widgetList<FinancialListRow>(
      find.byType(FinancialListRow),
    );
    expect(rows, hasLength(1));
    expect(rows.single.title, '038491');
    expect(tester.widget<EditableText>(editable).focusNode, same(focus));
    expect(focus.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty combined search and filter can be cleared at large text', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    await pumpRoster(tester, width: 320, scale: 2);
    await tester.enterText(find.byType(TextField), '038491');
    await tester.pumpAndSettle();
    tester.binding.focusManager.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('All'));
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Owner'));
    await tester.pumpAndSettle();

    expect(find.text('No members found'), findsOneWidget);
    expect(
      find.text('No members match this search and filter.'),
      findsOneWidget,
    );
    final clear = find.widgetWithText(CollectButton, 'Clear search and filter');
    await tester.ensureVisible(clear);
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp('Clear search and filter')),
      findsWidgets,
    );
    await tester.tap(clear);
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    await tester.ensureVisible(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('Members All')), findsWidgets);
    expect(find.text('No members found'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty member list keeps its distinct empty state', (
    tester,
  ) async {
    await pumpRoster(tester, members: []);

    expect(find.text('No members yet'), findsOneWidget);
    expect(find.text('No members found'), findsNothing);
    expect(find.text('No members in this filter'), findsNothing);
    expect(find.widgetWithText(CollectButton, 'Clear filter'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
