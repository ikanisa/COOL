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
  subtitle: 'Microfinance in Rwanda',
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

  group('BankSourceCard', () {
    testWidgets('renders source title and description', (tester) async {
      final config = bankConfigForSlug('urwego');

      await tester.pumpWidget(_wrap(
        BankSourceCard(config: config),
      ));

      expect(find.text('Official Urwego content'), findsOneWidget);
      expect(find.textContaining('Supabase partner data'), findsOneWidget);
    });
  });

  group('BankSupportCard', () {
    testWidgets('renders support heading and items', (tester) async {
      final config = bankConfigForSlug('urwego');

      await tester.pumpWidget(_wrap(
        BankSupportCard(partner: _testPartner, config: config),
      ));

      expect(find.text('Need help choosing a service?'), findsOneWidget);
      expect(find.text('Phone'), findsOneWidget);
      expect(find.text('WhatsApp'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
    });
  });

  group('bankConfigForSlug', () {
    test('returns urwego config for known slug', () {
      final config = bankConfigForSlug('urwego');
      expect(config.sourceTitle, contains('Urwego'));
    });

    test('returns equity config for equity slug', () {
      final config = bankConfigForSlug('equity');
      expect(config.sourceTitle, contains('Equity'));
    });

    test('falls back to urwego for unknown slug', () {
      final config = bankConfigForSlug('unknown-bank');
      expect(config.sourceTitle, contains('Urwego'));
    });
  });

  group('normalizeBankCategory', () {
    test('normalizes known categories', () {
      expect(normalizeBankCategory('digital'), 'digital');
      expect(normalizeBankCategory('payment'), 'payments');
      expect(normalizeBankCategory('payments'), 'payments');
      expect(normalizeBankCategory('transfer'), 'payments');
      expect(normalizeBankCategory('savings'), 'savings');
      expect(normalizeBankCategory('agri'), 'agri');
      expect(normalizeBankCategory('agriculture'), 'agri');
    });

    test('falls back to support for unknown categories', () {
      expect(normalizeBankCategory('xyz'), 'support');
      expect(normalizeBankCategory(''), 'support');
    });
  });

  group('groupBankServices', () {
    test('groups and orders services by category', () {
      const services = [
        PartnerService(
          id: '1', partnerId: 'p1', title: 'S1', category: 'savings'),
        PartnerService(
          id: '2', partnerId: 'p1', title: 'S2', category: 'digital'),
        PartnerService(
          id: '3', partnerId: 'p1', title: 'S3', category: 'savings'),
      ];

      final grouped = groupBankServices(services);

      // digital comes before savings in bankCategoryOrder
      expect(grouped[0].key, 'digital');
      expect(grouped[0].value.length, 1);
      expect(grouped[1].key, 'savings');
      expect(grouped[1].value.length, 2);
    });
  });
}
