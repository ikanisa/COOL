import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/config/country_catalog.dart';
import 'package:cool_app/features/momo/widgets/momo_cards_widgets.dart';
import 'package:cool_app/features/momo/widgets/momo_qr_nfc_widgets.dart';
import 'package:cool_app/l10n/app_localizations.dart';

// ── test helpers ──────────────────────────────────────────────────────────

final _rwanda = CoolCountryCatalog.resolve(country: 'RW');

Widget _wrap(Widget child) {
  return MaterialApp(
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

// ── tests ─────────────────────────────────────────────────────────────────

void main() {
  group('MomoSendMoneyCard', () {
    testWidgets('renders country info and momo number', (tester) async {
      await tester.pumpWidget(
        _wrap(
          MomoSendMoneyCard(
            country: _rwanda,
            momoNumber: '0781234567',
            onSendTap: () {},
          ),
        ),
      );

      expect(find.text('Send Money'), findsWidgets);
      expect(
        find.text('Launches Rwanda MoMo USSD to complete the transfer.'),
        findsOneWidget,
      );
      expect(find.textContaining('RWF'), findsOneWidget);
      expect(find.text('From 0781234567'), findsOneWidget);
    });

    testWidgets('calls onSendTap when button is pressed', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        _wrap(
          MomoSendMoneyCard(
            country: _rwanda,
            momoNumber: '0781234567',
            onSendTap: () => tapped = true,
          ),
        ),
      );

      // Find and tap the CoolButton with label 'Send money'
      final buttons = find.text('Send Money');
      // The button text may appear multiple times (heading + button)
      await tester.tap(buttons.last);
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('shows local display when momo number is stored in E.164', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          MomoSendMoneyCard(
            country: _rwanda,
            momoNumber: '+250781234567',
            onSendTap: () {},
          ),
        ),
      );

      expect(find.text('From 0781234567'), findsOneWidget);
      expect(find.text('From +250781234567'), findsNothing);
    });
  });

  group('MomoToolsCard', () {
    testWidgets('renders all 5 tool rows', (tester) async {
      await tester.pumpWidget(
        _wrap(
          MomoToolsCard(
            country: _rwanda,
            momoNumber: '0781234567',
            onOpenStatements: () {},
            onOpenQrCode: () {},
            onRequestPayment: () {},
            onScanQr: () {},
            onOpenNfcTools: () {},
          ),
        ),
      );

      expect(find.text('More tools'), findsOneWidget);
      expect(find.text('Statements'), findsOneWidget);
      expect(find.text('MoMo QR'), findsOneWidget);
      expect(find.text('Request payment'), findsOneWidget);
      expect(find.text('Scan QR'), findsOneWidget);
      expect(find.text('NFC tools'), findsOneWidget);
      expect(find.text('0781234567'), findsOneWidget);
    });

    testWidgets('calls correct callback for each row', (tester) async {
      String? tappedRow;

      await tester.pumpWidget(
        _wrap(
          MomoToolsCard(
            country: _rwanda,
            momoNumber: '0781234567',
            onOpenStatements: () => tappedRow = 'statements',
            onOpenQrCode: () => tappedRow = 'qr',
            onRequestPayment: () => tappedRow = 'request',
            onScanQr: () => tappedRow = 'scan',
            onOpenNfcTools: () => tappedRow = 'nfc',
          ),
        ),
      );

      await tester.tap(find.text('Statements'));
      await tester.pump();
      expect(tappedRow, 'statements');

      await tester.tap(find.text('MoMo QR'));
      await tester.pump();
      expect(tappedRow, 'qr');

      await tester.tap(find.text('Request payment'));
      await tester.pump();
      expect(tappedRow, 'request');

      await tester.tap(find.text('Scan QR'));
      await tester.pump();
      expect(tappedRow, 'scan');

      await tester.tap(find.text('NFC tools'));
      await tester.pump();
      expect(tappedRow, 'nfc');
    });

    testWidgets('shows local QR subtitle when momo number is stored in E.164', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          MomoToolsCard(
            country: _rwanda,
            momoNumber: '+250781234567',
            onOpenStatements: () {},
            onOpenQrCode: () {},
            onRequestPayment: () {},
            onScanQr: () {},
            onOpenNfcTools: () {},
          ),
        ),
      );

      expect(find.text('0781234567'), findsOneWidget);
      expect(find.text('+250781234567'), findsNothing);
    });
  });

  group('MomoToolRow', () {
    testWidgets('renders icon, title, subtitle, and chevron', (tester) async {
      await tester.pumpWidget(
        _wrap(
          MomoToolRow(
            icon: Icons.receipt_long_rounded,
            title: 'Statements',
            subtitle: 'Wallet and savings activity',
            onTap: () {},
          ),
        ),
      );

      expect(find.text('Statements'), findsOneWidget);
      expect(find.text('Wallet and savings activity'), findsOneWidget);
      expect(find.byIcon(Icons.receipt_long_rounded), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward_ios_rounded), findsOneWidget);
    });

    testWidgets('calls onTap when pressed', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        _wrap(
          MomoToolRow(
            icon: Icons.qr_code_2_rounded,
            title: 'QR Code',
            subtitle: '0781234567',
            onTap: () => tapped = true,
          ),
        ),
      );

      await tester.tap(find.text('QR Code'));
      await tester.pump();
      expect(tapped, isTrue);
    });
  });

  group('MomoQrCodeCard', () {
    testWidgets('generates payment QR only after manual confirmation', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          MomoQrCodeCard(
            country: _rwanda,
            momoNumber: '0781234567',
            momoCode: '123456',
          ),
        ),
      );

      expect(find.text('Recipient profile QR · Rwanda · RWF'), findsOneWidget);
      expect(find.text('Generate payment QR'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).last, '5000');
      await tester.pump();

      expect(find.text('Recipient profile QR · Rwanda · RWF'), findsOneWidget);

      await tester.tap(find.text('Generate payment QR'));
      await tester.pump();

      expect(find.text('Manual payment QR · Rwanda · RWF'), findsOneWidget);
    });
  });
}
