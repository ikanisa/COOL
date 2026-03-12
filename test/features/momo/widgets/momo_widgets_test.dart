import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/config/country_catalog.dart';
import 'package:cool_app/features/momo/widgets/momo_cards_widgets.dart';

// ── test helpers ──────────────────────────────────────────────────────────

const _rwanda = CoolCountry(
  isoCode: 'RW',
  dialCode: '+250',
  name: 'Rwanda',
  flagEmoji: '🇷🇼',
  currencyCode: 'RWF',
  currencyName: 'Rwandan franc',
  momoUssdTemplate: '*182*1*1*{recipient}*{amount}#',
);

Widget _wrap(Widget child) {
  return MaterialApp(
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

      expect(find.text('Send money'), findsWidgets);
      expect(find.text('Opens Rwanda USSD.'), findsOneWidget);
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
      final buttons = find.text('Send money');
      // The button text may appear multiple times (heading + button)
      await tester.tap(buttons.last);
      await tester.pump();
      expect(tapped, isTrue);
    });
  });

  group('MomoToolsCard', () {
    testWidgets('renders all 3 tool rows', (tester) async {
      await tester.pumpWidget(
        _wrap(
          MomoToolsCard(
            momoNumber: '0781234567',
            onOpenStatements: () {},
            onOpenQrCode: () {},
            onOpenNfcTools: () {},
          ),
        ),
      );

      expect(find.text('More tools'), findsOneWidget);
      expect(find.text('Statements'), findsOneWidget);
      expect(find.text('My QR code'), findsOneWidget);
      expect(find.text('NFC tools'), findsOneWidget);
      expect(find.text('0781234567'), findsOneWidget);
    });

    testWidgets('calls correct callback for each row', (tester) async {
      String? tappedRow;

      await tester.pumpWidget(
        _wrap(
          MomoToolsCard(
            momoNumber: '0781234567',
            onOpenStatements: () => tappedRow = 'statements',
            onOpenQrCode: () => tappedRow = 'qr',
            onOpenNfcTools: () => tappedRow = 'nfc',
          ),
        ),
      );

      await tester.tap(find.text('Statements'));
      await tester.pump();
      expect(tappedRow, 'statements');

      await tester.tap(find.text('My QR code'));
      await tester.pump();
      expect(tappedRow, 'qr');

      await tester.tap(find.text('NFC tools'));
      await tester.pump();
      expect(tappedRow, 'nfc');
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
}
