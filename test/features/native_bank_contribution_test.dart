import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/features/payments/contribution_flow_screen.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('EUR edits reject invalid amounts whole without truncating value', () {
    const formatter = EuroAmountInputFormatter();
    const old = TextEditingValue(text: '12.34');
    for (final invalid in [
      '12.345',
      '1e3',
      '-123',
      '12abc',
      '1,234.56',
      '1234567890',
      '12..3',
    ]) {
      expect(
        formatter.formatEditUpdate(old, TextEditingValue(text: invalid)),
        old,
        reason: invalid,
      );
    }
    for (final valid in [
      '',
      '0',
      '123',
      '123.',
      '123.45',
      '123,45',
      '999999999.99',
    ]) {
      final edit = TextEditingValue(text: valid);
      expect(formatter.formatEditUpdate(old, edit), edit, reason: valid);
    }
    expect(parseEuroMinor('123.45'), 12345);
    expect(parseEuroMinor('123,45'), 12345);
    expect(parseEuroMinor('0'), isNull);
  });

  for (final width in [320.0, 430.0, 1184.0]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets('bank flow compact and copy-safe at $width / $textScale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = CollectRepository.fixture(
          profileOverride: const CollectProfile(
            id: 'local-user',
            publicId: '038491',
            whatsappPhone: '+250788123456',
            countryCode: 'DE',
            currencyCode: 'EUR',
            revolutLink: 'https://revolut.me/synthetic',
            revolutAccount: 'Synthetic account',
          ),
        );
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              collectRepositoryProvider.overrideWith((ref) => repository),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
              home: const ContributionFlowScreen(collectionId: 'col-church'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byTooltip('Back'), findsOneWidget);
        expect(find.byTooltip('Back to group'), findsNothing);
        expect(find.textContaining('STEP '), findsNothing);
        expect(
          tester
              .getSize(
                find.byKey(const ValueKey('native_bank_contribution_flow')),
              )
              .width,
          lessThanOrEqualTo(430),
        );
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.decoration!.border, InputBorder.none);
        await tester.enterText(find.byType(TextField), '123.45');
        await tester.tap(find.widgetWithText(FilledButton, 'Review transfer'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('EUR 123.45'), findsOneWidget);
        expect(find.text('Open Revolut'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byTooltip('Copy IBAN').hitTestable(),
          100,
        );
        expect(find.byTooltip('Copy IBAN').hitTestable(), findsOneWidget);
        await tester.tap(find.byTooltip('Copy IBAN'));
        await tester.pump();
        expect(copied, 'DE89370400440532013000');
        await tester.scrollUntilVisible(
          find.byTooltip('Copy Exact reference').hitTestable(),
          100,
        );
        expect(
          find.byTooltip('Copy Exact reference').hitTestable(),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('Copy Exact reference'));
        await tester.pump();
        final intent = repository.state.paymentIntents.firstWhere(
          (value) => value.expectedAmountMinor == 12345,
        );
        expect(copied, intent.transferReference);
        expect(intent.status, 'awaiting_transfer');
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Edit amount'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '123.45',
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
