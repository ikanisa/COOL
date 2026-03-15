import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/features/partners/models/partner.dart';
import 'package:cool_app/features/partners/models/partner_service.dart';
import 'package:cool_app/features/partners/widgets/prisma_partner_config.dart';
import 'package:cool_app/features/partners/widgets/prisma_partner_widgets.dart';

// ── test helpers ──────────────────────────────────────────────────────────

const _testPartner = Partner(
  id: 'p2',
  name: 'PRISMA by IKANISA',
  slug: 'prisma',
  category: PartnerCategory.organization,
  country: 'RW',
  emoji: '⚖️',
);

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));
}

// ── tests ─────────────────────────────────────────────────────────────────

void main() {
  group('PrismaHeroCard', () {
    testWidgets('renders partner name and IKANISA badge', (tester) async {
      await tester.pumpWidget(_wrap(
        const PrismaHeroCard(partner: _testPartner),
      ));

      expect(find.text('PRISMA by IKANISA'), findsOneWidget);
      expect(find.text('Official IKANISA content'), findsOneWidget);
    });

    testWidgets('renders hero pills', (tester) async {
      await tester.pumpWidget(_wrap(
        const PrismaHeroCard(partner: _testPartner),
      ));

      expect(find.text('Legal, Tax & Compliance'), findsOneWidget);
      expect(find.text('Audit, Insurance & Risk'), findsOneWidget);
      expect(find.text('Rwanda Jurisdiction'), findsOneWidget);
    });
  });

  group('PrismaStatsCard', () {
    testWidgets('renders stat tiles', (tester) async {
      await tester.pumpWidget(_wrap(const PrismaStatsCard()));

      expect(find.text('IKANISA at a glance'), findsOneWidget);
      expect(find.text('9'), findsOneWidget);
      expect(find.text('AI Agents'), findsOneWidget);
      expect(find.text('28K+'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('14'), findsOneWidget);
    });
  });

  group('PrismaValuesCard', () {
    testWidgets('renders all 5 values', (tester) async {
      await tester.pumpWidget(_wrap(const PrismaValuesCard()));

      expect(find.text('How the platform works'), findsOneWidget);
      expect(find.text('Zero Hallucination'), findsOneWidget);
      expect(find.text('Jurisdiction Locked'), findsOneWidget);
      expect(find.text('Rwanda Professional Standards'), findsOneWidget);
    });
  });

  group('PrismaSupportCard', () {
    testWidgets('renders support heading and contact lines', (tester) async {
      await tester.pumpWidget(_wrap(
        const PrismaSupportCard(partner: _testPartner),
      ));

      expect(find.text('Get in touch'), findsOneWidget);
      expect(find.text('Rwanda WhatsApp'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Open Rwanda Desk'), findsOneWidget);
    });
  });

  group('normalizePrismaCategory', () {
    test('normalizes known categories', () {
      expect(normalizePrismaCategory('rwanda_agent'), 'rwanda_agent');
      expect(normalizePrismaCategory('compliance_agent'), 'capability');
      expect(normalizePrismaCategory('legacy_agent'), 'capability');
      expect(normalizePrismaCategory('capability'), 'capability');
      expect(normalizePrismaCategory('service'), 'capability');
      expect(normalizePrismaCategory('support'), 'support');
    });

    test('falls back to capability for unknown categories', () {
      expect(normalizePrismaCategory('xyz'), 'capability');
    });
  });

  group('groupPrismaServices', () {
    test('groups and orders services by category', () {
      const services = [
        PartnerService(
          id: '1',
          partnerId: 'p2',
          title: 'S1',
          category: 'compliance_agent',
        ),
        PartnerService(
          id: '2', partnerId: 'p2', title: 'S2', category: 'rwanda_agent'),
        PartnerService(
          id: '3', partnerId: 'p2', title: 'S3', category: 'legacy_agent'),
      ];

      final grouped = groupPrismaServices(services);

      // rwanda_agent comes before capability in prismaCategoryOrder.
      expect(grouped[0].key, 'rwanda_agent');
      expect(grouped[0].value.length, 1);
      expect(grouped[1].key, 'capability');
      expect(grouped[1].value.length, 2);
    });
  });
}
