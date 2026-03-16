import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/features/partners/models/partner.dart';
import 'package:cool_app/features/partners/models/partner_service.dart';
import 'package:cool_app/features/partners/widgets/bank_partner_config.dart';
import 'package:cool_app/features/partners/widgets/bank_partner_widgets.dart';

// ── test helpers ──────────────────────────────────────────────────────────

const _testPartner = Partner(
  id: 'p1',
  name: 'Urwego Finance',
  slug: 'urwego',
  category: PartnerCategory.bank,
  country: 'RW',
  message: 'Microfinance in Rwanda',
  description: 'Full bank description',
);

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));
}

// ── tests ─────────────────────────────────────────────────────────────────

void main() {
  group('BankHero', () {
    testWidgets('renders partner name and description', (tester) async {
      final config = bankConfigForSlug('urwego');

      await tester.pumpWidget(_wrap(
        BankHero(partner: _testPartner, config: config),
      ));

      expect(find.text('Urwego Finance'), findsOneWidget);
      expect(find.text('Full bank description'), findsOneWidget);
      expect(find.text('Microfinance in Rwanda'), findsOneWidget);
      expect(find.text('Official partner content'), findsOneWidget);
    });

    testWidgets('uses defaultDescription when partner has no description',
        (tester) async {
      const partnerNoDesc = Partner(
        id: 'p2',
        name: 'Test Bank',
        slug: 'urwego',
        category: PartnerCategory.bank,
        country: 'RW',
      );
      final config = bankConfigForSlug('urwego');

      await tester.pumpWidget(_wrap(
        BankHero(partner: partnerNoDesc, config: config),
      ));

      expect(find.textContaining('digital banking'), findsOneWidget);
    });
  });

  group('BankQuickActionGrid', () {
    testWidgets('renders 4 quick action tiles', (tester) async {
      final config = bankConfigForSlug('urwego');

      await tester.pumpWidget(_wrap(
        BankQuickActionGrid(partner: _testPartner, config: config),
      ));

      // Urwego has 4 quick actions
      expect(find.text('Products'), findsOneWidget);
      expect(find.text('Internet Banking'), findsOneWidget);
      expect(find.text('Call Urwego'), findsOneWidget);
      expect(find.text('Locations'), findsOneWidget);
    });
  });
}
