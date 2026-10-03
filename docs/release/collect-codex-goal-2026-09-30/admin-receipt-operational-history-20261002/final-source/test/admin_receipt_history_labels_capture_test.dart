import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_receipt_operational_history_models.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'admin_receipt_operational_history_test.dart' as history;

const renderKey = ValueKey('operational-history-root-render');

Future<void> capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(renderKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File('../proof/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final width in [1440.0, 390.0]) {
    for (final dark in [false, true]) {
      final state = '${width.toInt()}-${dark ? 'dark' : 'light'}';
      testWidgets('actual history labels and headings render at $state', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        try {
          final repository = history.Repository();
          final run = history.fixture('run-closed');
          final container = ProviderContainer(
            overrides: [
              adminRepositoryProvider.overrideWithValue(repository),
              adminIdentityProvider.overrideWith((_) async => history.owner),
              adminAuthSessionScopeProvider.overrideWith(
                (_) => history.Sessions(),
              ),
              adminClockProvider.overrideWithValue(
                () => historyInstant(
                  history.fixture('evidence-events')['checked_at'],
                ),
              ),
            ],
          );
          addTearDown(container.dispose);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: RepaintBoundary(
                key: renderKey,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: dark ? CollectTheme.dark() : CollectTheme.light(),
                  home: Scaffold(
                    body: AdminReceiptOperationalRunPage(
                      runId: run['run_id'] as String,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Actions per run: 10'), findsOneWidget);
          expect(find.text('SMS segments per run: 20'), findsOneWidget);
          expect(find.text('Actions reserved for this run: 2'), findsOneWidget);
          expect(
            find.text('SMS segments reserved for this run: 0'),
            findsOneWidget,
          );
          expect(find.text('Global actions reserved: 2'), findsOneWidget);
          expect(find.text('Device SMS segments reserved: 0'), findsOneWidget);
          expect(find.textContaining('run_actions:'), findsNothing);
          expect(find.textContaining('global_sms_segments:'), findsNothing);
          expect(find.textContaining('operations_budget_conflict'), findsNothing);
          expect(find.textContaining('request row'), findsNothing);
          final checkedAt = tester.widget<Text>(
            find.textContaining('Checked '),
          );
          expect(RegExp('Africa/Kigali').allMatches(checkedAt.data!).length, 1);
          expect(tester.takeException(), isNull);
          await capture(tester, 'run-$state');
          await tester.ensureVisible(find.text('Reserved usage'));
          await tester.pumpAndSettle();
          expect(
            tester
                .getSemantics(find.text('Reserved usage'))
                .flagsCollection
                .isHeader,
            isTrue,
          );
          expect(tester.takeException(), isNull);
          await capture(tester, 'usage-$state');
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          semantics.dispose();
        }
      });
    }
  }
}
