import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/admin/core/admin_models.dart';
import 'package:collect_app/admin/shared/components/admin_data_table.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _captureKey = Key('admin-record-reflow-capture');
const _longTitle =
    'Synthetic record awaiting a complete review of its Rwanda MoMo allocation';
const _longValue =
    'The operator must review the complete retained allocation and its '
    'supporting evidence before selecting the appropriate next action.';

void main() {
  setUpAll(() async {
    await Future.wait([
      (FontLoader('Inter')
            ..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf')))
          .load(),
      (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load(),
    ]);
  });

  testWidgets('desktop monetary cells share a right aligned value edge', (
    tester,
  ) async {
    await _host(
      tester,
      width: 1440,
      theme: AppTheme.light(),
      rows: [
        _row('First receipt', amount: 'RWF 1000'),
        _row('Second receipt', amount: 'RWF 1250000'),
      ],
    );
    final first = tester.getRect(find.text('RWF 1,000'));
    final second = tester.getRect(find.text('RWF 1,250,000'));
    expect(first.right, closeTo(second.right, 0.01));
    expect(tester.takeException(), isNull);
    await _capture(tester, 'desktop-light-right-aligned');
  });

  for (final theme in {
    'light': AppTheme.light(),
    'dark': AppTheme.dark(),
  }.entries) {
    for (final width in [320.0, 1440.0]) {
      testWidgets(
        '${theme.key} ${width}px 3.2x records keep complete text and reachable actions',
        (tester) async {
          var opens = 0;
          await _host(
            tester,
            width: width,
            scale: 3.2,
            theme: theme.value,
            rows: [_row(_longTitle, amount: _longValue)],
            onOpen: (_) => opens++,
          );
          expect(
            find.byKey(const Key('admin-compact-record-list')),
            findsOneWidget,
          );
          for (final value in [
            _longTitle,
            _longValue,
            'Awaiting confirmation',
            '1 Oct 2026 · 02:00 · Africa/Kigali',
          ]) {
            final text = find.text(value);
            expect(text, findsOneWidget);
            final paragraph = tester.renderObject<RenderParagraph>(text);
            expect(paragraph.didExceedMaxLines, isFalse, reason: value);
          }
          expect(tester.takeException(), isNull);
          await _capture(tester, '${theme.key}-${width.toInt()}-3.2x-top');
          final open = find.byTooltip('Open $_longTitle');
          await tester.ensureVisible(open);
          await tester.tap(open);
          expect(opens, 1);
          await tester.ensureVisible(
            find.text('1 Oct 2026 · 02:00 · Africa/Kigali'),
          );
          await tester.pumpAndSettle();
          final bottom = tester.getRect(
            find.text('1 Oct 2026 · 02:00 · Africa/Kigali'),
          );
          expect(bottom.top, greaterThanOrEqualTo(0));
          expect(bottom.bottom, lessThanOrEqualTo(900));
          expect(tester.takeException(), isNull);
          await _capture(tester, '${theme.key}-${width.toInt()}-3.2x-bottom');
        },
      );
    }
  }
}

AdminTableRowData _row(String title, {required String amount}) =>
    AdminTableRowData(
      id: title,
      title: title,
      subtitle: 'Synthetic operator evidence',
      status: 'awaiting_confirmation',
      amount: amount,
      createdAt: DateTime.parse('2026-10-01T00:00:00Z'),
    );

Future<void> _host(
  WidgetTester tester, {
  required double width,
  required ThemeData theme,
  required List<AdminTableRowData> rows,
  double scale = 1,
  ValueChanged<AdminTableRowData>? onOpen,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: RepaintBoundary(
        key: _captureKey,
        child: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: AdminDataTable(
                rows: rows,
                valueLabel: scale == 1 ? 'Amount' : 'Detail',
                onOpen: onOpen,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['COLLECT_ADMIN_REFLOW_CAPTURE_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(directory).createSync(recursive: true);
    File('$directory/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
