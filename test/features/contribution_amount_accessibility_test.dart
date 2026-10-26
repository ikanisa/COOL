import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/features/payments/contribution_amount_widgets.dart';
import 'package:collect_app/features/payments/contribution_flow_screen.dart';
import 'package:collect_app/l10n/collect_localizations.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/collect_repository_fixture.dart';

const _captureKey = ValueKey('product_payment_capture');
const _maximumDigits = '9007199254740991';
const _maximumFormatted = '9,007,199,254,740,991';

class _PaymentRepository extends FixtureCollectRepository {
  bool failPreparation = false;
  int preparations = 0;

  @override
  Future<PaymentIntentModel> createPaymentIntent(PaymentIntentDraft draft) {
    preparations++;
    if (failPreparation) throw StateError('Synthetic preparation failed');
    return super.createPaymentIntent(draft);
  }
}

Future<void> _pumpFlow(
  WidgetTester tester, {
  _PaymentRepository? repository,
  Size size = const Size(390, 844),
  double scale = 1,
  double keyboardHeight = 0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: ProviderScope(
        overrides: [
          collectRepositoryProvider.overrideWith(
            (ref) => repository ?? _PaymentRepository(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const ContributionFlowScreen(collectionId: 'qa-private-group'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('PRODUCT_PAYMENT_CAPTURE')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final pixels = await boundary.toImage(pixelRatio: 1);
    final bytes = await pixels.toByteData(format: ui.ImageByteFormat.png);
    pixels.dispose();
    final folder = Directory('.cache/test-captures/product-payment-captures');
    await folder.create(recursive: true);
    await File(
      '${folder.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
  });
}

Future<void> _revealAction(WidgetTester tester, Finder action) async {
  if (action.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      action,
      80,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 40,
    );
  }
  await tester.ensureVisible(action);
  await tester.pumpAndSettle();
}

void _expectCompleteReadableValue(WidgetTester tester, Finder finder) {
  final text = tester.widget<Text>(finder);
  expect(text.data!.replaceAll('\u200b', ''), 'RWF $_maximumFormatted');
  expect(text.semanticsLabel, 'RWF $_maximumFormatted');
  expect(text.style!.fontSize, greaterThanOrEqualTo(20));
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: finder, matching: find.byType(RichText)),
  );
  expect(paragraph.didExceedMaxLines, isFalse);
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.data!.length),
  );
  expect(boxes, isNotEmpty);
  for (final box in boxes) {
    expect(box.left, greaterThanOrEqualTo(-0.01));
    expect(box.right, lessThanOrEqualTo(paragraph.size.width + 0.01));
    expect(box.bottom, lessThanOrEqualTo(paragraph.size.height + 0.01));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
  });

  testWidgets(
    'amount error belongs to the stable field and clears on editing',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pumpFlow(tester, size: const Size(320, 568), scale: 2);
        final field = find.byType(TextField);
        final before = tester
            .getSemantics(find.byType(EditableText))
            .getSemanticsData();
        expect(before.label, 'Contribution amount, RWF');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        final invalid = tester
            .getSemantics(find.byType(EditableText))
            .getSemanticsData();
        expect(invalid.label, before.label);
        final expectedError = CollectLocalizations.of(
          tester.element(field),
        ).text('enterAmountAboveZero');
        expect(invalid.hint, contains(expectedError));
        expect(invalid.validationResult, ui.SemanticsValidationResult.invalid);
        expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
        final error = find.text(expectedError);
        await tester.ensureVisible(error);
        await tester.pumpAndSettle();
        expect(error.hitTestable(), findsOneWidget);
        await _capture(tester, 'compact-validation-200');
        await tester.enterText(field, '1000');
        await tester.pumpAndSettle();
        final corrected = tester
            .getSemantics(find.byType(EditableText))
            .getSemanticsData();
        expect(corrected.label, before.label);
        expect(corrected.hint, isNot(contains(expectedError)));
        expect(corrected.validationResult, ui.SemanticsValidationResult.none);
        expect(error, findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  for (final scale in [1.0, 2.0]) {
    for (final size in [const Size(320, 568), const Size(740, 360)]) {
      testWidgets(
        'maximum RWF entry stays readable at $size and $scale with keyboard',
        (tester) async {
          await _pumpFlow(
            tester,
            size: size,
            scale: scale,
            keyboardHeight: size.width == 320 ? 240 : 260,
          );
          final field = find.byType(TextField);
          final initialFontSize = tester
              .widget<TextField>(field)
              .style!
              .fontSize;
          await tester.enterText(field, _maximumDigits);
          await tester.pumpAndSettle();
          final edited = tester.widget<TextField>(field);
          expect(edited.controller!.text, _maximumFormatted);
          expect(edited.style!.fontSize, initialFontSize);
          expect(edited.focusNode!.hasFocus, isTrue);
          final readback = find.byKey(
            const ValueKey('contribution_amount_full_value'),
          );
          _expectCompleteReadableValue(tester, readback);
          await tester.ensureVisible(readback);
          await tester.pumpAndSettle();
          if (size.width == 320 && scale == 2) {
            await _capture(tester, 'compact-entry-200-keyboard');
          }
          final action = find.widgetWithText(FilledButton, 'Continue to MoMo');
          await _revealAction(tester, action);
          expect(action.hitTestable(), findsOneWidget);
          expect(tester.widget<FilledButton>(action).onPressed, isNotNull);
          expect(edited.focusNode!.hasFocus, isTrue);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('review shows the complete maximum amount at compact 200% text', (
    tester,
  ) async {
    await _pumpFlow(tester, size: const Size(320, 568), scale: 2);
    await tester.enterText(find.byType(TextField), _maximumDigits);
    await tester.pumpAndSettle();
    final continueAction = find.widgetWithText(
      FilledButton,
      'Continue to MoMo',
    );
    await _revealAction(tester, continueAction);
    await tester.tap(continueAction);
    await tester.pumpAndSettle();
    expect(find.byType(ContributionAmountValue), findsOneWidget);
    final amount = find.byKey(const ValueKey('contribution_review_full_value'));
    _expectCompleteReadableValue(tester, amount);
    await tester.ensureVisible(amount);
    await tester.pumpAndSettle();
    await _capture(tester, 'compact-review-200');
    final openAction = find.widgetWithText(FilledButton, 'Open MoMo USSD');
    await _revealAction(tester, openAction);
    expect(openAction.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'preparation error is a live status and retains the entered amount',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final repository = _PaymentRepository()..failPreparation = true;
        await _pumpFlow(tester, repository: repository);
        await tester.enterText(find.byType(TextField), '5000');
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Continue to MoMo'));
        await tester.pumpAndSettle();
        final status = find.bySemanticsLabel(
          'MoMo could not continue. Synthetic preparation failed',
        );
        expect(status, findsOneWidget);
        expect(
          tester.getSemantics(status).flagsCollection.isLiveRegion,
          isTrue,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '5,000',
        );
        expect(repository.preparations, 1);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'USSD handoff announces only the opened request and provider-check recovery',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        var launches = 0;
        const channel = MethodChannel('collect/momo_ussd');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (_) async {
          launches++;
          return true;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        final repository = _PaymentRepository();
        await _pumpFlow(tester, repository: repository);
        final recordedBefore = repository.state.contributions.toList();
        final totalsBefore = repository.state.historyPage?.ownTotals;
        await tester.enterText(find.byType(TextField), '5000');
        await tester.pumpAndSettle();
        await _capture(tester, 'normal-entry');
        await tester.tap(find.widgetWithText(FilledButton, 'Continue to MoMo'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Open MoMo USSD'));
        await tester.pumpAndSettle();
        final status = find.bySemanticsLabel(RegExp('^MoMo request opened\\.'));
        await _revealAction(tester, status);
        expect(status, findsOneWidget);
        expect(
          tester.getSemantics(status).flagsCollection.isLiveRegion,
          isTrue,
        );
        final statusLabel = tester.getSemantics(status).label;
        expect(
          statusLabel,
          contains('Opening MoMo does not confirm a transfer.'),
        );
        expect(statusLabel, contains('Check the result with your provider'));
        expect(statusLabel, contains('refresh Activity'));
        expect(
          statusLabel,
          contains('A receipt SMS alone does not verify settlement.'),
        );
        expect(statusLabel, isNot(contains('confirmed')));
        expect(statusLabel, isNot(contains('parsed and allocated')));
        expect(launches, 1);
        expect(repository.preparations, 2);
        expect(repository.state.contributions, orderedEquals(recordedBefore));
        expect(repository.state.historyPage?.ownTotals, totalsBefore);
        expect(
          repository.state.paymentIntents.any(
            (intent) =>
                intent.expectedAmountMinor == 5000 &&
                intent.status == 'pending',
          ),
          isTrue,
        );
        await tester.ensureVisible(status);
        await tester.pumpAndSettle();
        await _capture(tester, 'pending-status');
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );
}
