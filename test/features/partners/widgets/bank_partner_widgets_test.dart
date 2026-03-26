import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/features/partners/models/partner.dart';
import 'package:cool_app/features/partners/models/partner_service.dart';
import 'package:cool_app/features/partners/widgets/bank_partner_widgets.dart';

// ── test helpers ──────────────────────────────────────────────────────────

const _testPartner = Partner(
  id: 'p1',
  name: 'Urwego Finance',
  slug: 'urwego',
  category: PartnerCategory.bank,
  country: 'RW',
  subtitle: 'Microfinance in Rwanda',
  description: 'Full bank description',
);

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

// ── tests ─────────────────────────────────────────────────────────────────

void main() {
  group('BankHero', () {
    testWidgets('renders partner name and description', (tester) async {
      await tester.pumpWidget(_wrap(const BankHero(partner: _testPartner)));

      expect(find.text('Urwego Finance'), findsOneWidget);
      expect(find.text('Full bank description'), findsOneWidget);
    });

    testWidgets('uses defaultDescription when partner has no description', (
      tester,
    ) async {
      const partnerNoDesc = Partner(
        id: 'p2',
        name: 'Test Bank',
        slug: 'urwego',
        category: PartnerCategory.bank,
        country: 'RW',
      );
      await tester.pumpWidget(_wrap(const BankHero(partner: partnerNoDesc)));

      expect(find.text('Trusted financial partner.'), findsOneWidget);
    });
  });

  group('BankServiceGrid', () {
    testWidgets('renders only the group savings custodian action', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const BankServiceGrid(
            partner: _testPartner,
            services: <PartnerService>[],
          ),
        ),
      );

      expect(find.text('Group Savings Custodian'), findsOneWidget);
      expect(find.text('Open custodian flow'), findsOneWidget);
      expect(find.text('Open Account'), findsNothing);
      expect(find.text('Get a Loan'), findsNothing);
    });
  });
}
