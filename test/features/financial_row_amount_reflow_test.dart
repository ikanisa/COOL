import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/utils/money_format.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _maximum = 9007199254740991;

Future<void> _pumpRow(
  WidgetTester tester,
  Widget row, {
  required Size size,
  required double scale,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: CollectCard(child: row),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectCompletePaintedValue(
  WidgetTester tester,
  String value, {
  required double scale,
}) {
  final amount = find.text(value);
  expect(amount, findsOneWidget);
  final text = tester.widget<Text>(amount);
  expect(text.data, value);
  expect(text.style!.fontFamily, 'Inter');
  expect(tester.getSemantics(amount).getSemanticsData().label, contains(value));
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: amount, matching: find.byType(RichText)),
  );
  expect(paragraph.didExceedMaxLines, isFalse);
  expect(paragraph.textScaler.scale(1), closeTo(scale, .001));

  // A full semantic string alone does not prove that its final digits paint.
  // Check all selected glyph boxes and the final digit against actual bounds.
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: value.length),
  );
  expect(boxes, isNotEmpty);
  final finalGlyph = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: value.length - 1, extentOffset: value.length),
  );
  expect(finalGlyph, isNotEmpty);
  for (final box in [...boxes, ...finalGlyph]) {
    expect(box.left, greaterThanOrEqualTo(-.01));
    expect(box.top, greaterThanOrEqualTo(-.01));
    expect(box.right, lessThanOrEqualTo(paragraph.size.width + .01));
    expect(box.bottom, lessThanOrEqualTo(paragraph.size.height + .01));
  }

  // Preserve real text enlargement rather than fitting it back to small paint.
  final origin = paragraph.localToGlobal(Offset.zero);
  final horizontalUnit = paragraph.localToGlobal(const Offset(1, 0)) - origin;
  final verticalUnit = paragraph.localToGlobal(const Offset(0, 1)) - origin;
  expect(horizontalUnit.distance, closeTo(1, .001));
  expect(verticalUnit.distance, closeTo(1, .001));
  expect(tester.takeException(), isNull);
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
  });

  for (final scenario in [
    (size: const Size(320, 640), scale: 1.0),
    (size: const Size(320, 640), scale: 1.6),
    (size: const Size(320, 640), scale: 2.0),
    (size: const Size(390, 844), scale: 1.0),
  ]) {
    for (final activity in [true, false]) {
      testWidgets('${activity ? 'Activity' : 'Ledger'} full signed values at '
          '${scenario.size.width}dp / ${scenario.scale}', (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          for (final amount in [-_maximum, _maximum]) {
            final row = activity
                ? ActivityFeedItem(
                    title: 'Signed history group',
                    meta: 'Recorded reversal · 123456',
                    amount: amount,
                    prioritizeContext: true,
                  )
                : FinancialListRow(
                    title: '123456',
                    subtitle: 'Recorded reversal',
                    meta: '16 Oct 2026',
                    amountRwf: amount,
                  );
            await _pumpRow(
              tester,
              row,
              size: scenario.size,
              scale: scenario.scale,
            );
            _expectCompletePaintedValue(
              tester,
              formatRwf(amount),
              scale: scenario.scale,
            );
          }
        } finally {
          semantics.dispose();
        }
      });
    }
  }

  for (final scale in [1.6, 2.0]) {
    for (final activity in [true, false]) {
      testWidgets(
        '${activity ? 'Activity' : 'Ledger'} full financial status and amount '
        'at 320dp / $scale',
        (tester) async {
          final semantics = tester.ensureSemantics();
          try {
            for (final entry in [
              (status: 'Recorded contribution', amount: _maximum),
              (status: 'Recorded correction', amount: -_maximum),
              (status: 'Recorded reversal', amount: -_maximum),
            ]) {
              final status = entry.status;
              final amount = entry.amount;
              final context = '$status · 123456 · 16 Oct 2026, 14:04';
              final row = activity
                  ? ActivityFeedItem(
                      title: 'Signed history group',
                      meta: context,
                      amount: amount,
                      prioritizeContext: true,
                    )
                  : FinancialListRow(
                      title: '123456',
                      subtitle: status,
                      meta: '16 Oct 2026',
                      amountRwf: amount,
                    );
              await _pumpRow(
                tester,
                row,
                size: const Size(320, 640),
                scale: scale,
              );
              _expectCompletePaintedValue(
                tester,
                activity ? context : status,
                scale: scale,
              );
              _expectCompletePaintedValue(
                tester,
                formatRwf(amount),
                scale: scale,
              );
            }
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }

  testWidgets('supported signed currency totals reflow with enlarged text', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      const totals = {'RWF': -_maximum};
      await _pumpRow(
        tester,
        const FinancialListRow(
          title: '123456',
          meta: 'Recorded activity',
          amounts: totals,
        ),
        size: const Size(320, 640),
        scale: 1.6,
      );
      _expectCompletePaintedValue(
        tester,
        formatCurrencyTotals(totals, separator: '\n'),
        scale: 1.6,
      );
    } finally {
      semantics.dispose();
    }
  });
}
