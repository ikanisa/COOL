import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/features/partners/models/partner.dart';
import 'package:cool_app/features/partners/models/partner_service.dart';
import 'package:cool_app/features/partners/widgets/partner_shared_widgets.dart';

// ── test helpers ──────────────────────────────────────────────────────────

const _testMeta = <String, CategoryMeta>{
  'digital': CategoryMeta(
    title: 'Digital Banking',
    description: 'Digital services description',
    icon: Icons.phone_android,
    accent: Colors.blue,
  ),
  'support': CategoryMeta(
    title: 'Support',
    description: 'Support description',
    icon: Icons.support_agent,
    accent: Colors.green,
  ),
};

const _testPartner = Partner(
  id: 'p1',
  name: 'Test Bank',
  slug: 'test-bank',
  category: PartnerCategory.bank,
  country: 'RW',
);

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));
}

// ── tests ─────────────────────────────────────────────────────────────────

void main() {
  group('PartnerSectionHeader', () {
    testWidgets('renders title and description from meta', (tester) async {
      await tester.pumpWidget(_wrap(
        const PartnerSectionHeader(
          category: 'digital',
          categoryMeta: _testMeta,
        ),
      ));

      expect(find.text('Digital Banking'), findsOneWidget);
      expect(find.text('Digital services description'), findsOneWidget);
      expect(find.byIcon(Icons.phone_android), findsOneWidget);
    });

    testWidgets('falls back to fallbackCategory when missing', (tester) async {
      await tester.pumpWidget(_wrap(
        const PartnerSectionHeader(
          category: 'unknown',
          categoryMeta: _testMeta,
          fallbackCategory: 'support',
        ),
      ));

      expect(find.text('Support'), findsOneWidget);
    });
  });

  group('PartnerHeroPill', () {
    testWidgets('renders icon and label', (tester) async {
      await tester.pumpWidget(
        _wrap(const PartnerHeroPill(icon: Icons.star, label: 'Featured')),
      );

      expect(find.text('Featured'), findsOneWidget);
      expect(find.byIcon(Icons.star), findsOneWidget);
    });
  });

  group('PartnerQuickActionTile', () {
    testWidgets('renders title/subtitle and calls onTap', (tester) async {
      var tapped = false;

      await tester.pumpWidget(_wrap(
        SizedBox(
          height: 200,
          child: PartnerQuickActionTile(
            icon: Icons.public,
            title: 'Website',
            message: 'Open site',
            onTap: () => tapped = true,
          ),
        ),
      ));

      expect(find.text('Website'), findsOneWidget);
      expect(find.text('Open site'), findsOneWidget);

      await tester.tap(find.text('Website'));
      await tester.pump();
      expect(tapped, isTrue);
    });
  });

  group('PartnerSupportLine', () {
    testWidgets('renders icon, label, and value', (tester) async {
      await tester.pumpWidget(_wrap(
        const PartnerSupportLine(
          icon: Icons.phone,
          label: 'Phone',
          value: '+250 788 123 456',
        ),
      ));

      expect(find.text('Phone'), findsOneWidget);
      expect(find.text('+250 788 123 456'), findsOneWidget);
      expect(find.byIcon(Icons.phone), findsOneWidget);
    });
  });

  group('PartnerDetailRow', () {
    testWidgets('renders detail label and value', (tester) async {
      await tester.pumpWidget(_wrap(
        const PartnerDetailRow(
          detail: ServiceDetail(label: 'Rate', value: '5%', icon: '📊'),
          accent: Colors.blue,
        ),
      ));

      expect(find.text('Rate'), findsOneWidget);
      expect(find.text('5%'), findsOneWidget);
    });
  });

  group('PartnerErrorCard', () {
    testWidgets('renders error message', (tester) async {
      await tester.pumpWidget(
        _wrap(const PartnerErrorCard(message: 'Network error')),
      );

      expect(find.text('Network error'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });
  });

  group('PartnerErrorBody', () {
    testWidgets('renders message and optional retry', (tester) async {
      var retried = false;

      await tester.pumpWidget(_wrap(
        PartnerErrorBody(
          message: 'Something went wrong',
          onRetry: () => retried = true,
        ),
      ));

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);

      await tester.tap(find.text('Try Again'));
      await tester.pump();
      expect(retried, isTrue);
    });

    testWidgets('hides retry button when onRetry is null', (tester) async {
      await tester.pumpWidget(
        _wrap(const PartnerErrorBody(message: 'Oops')),
      );

      expect(find.text('Retry'), findsNothing);
    });
  });

  group('PartnerEmptyServicesCard', () {
    testWidgets('renders partner name in message', (tester) async {
      await tester.pumpWidget(
        _wrap(const PartnerEmptyServicesCard(partnerName: 'Acme')),
      );

      expect(
        find.textContaining('Acme'),
        findsOneWidget,
      );
    });
  });

  group('PartnerServiceCard', () {
    testWidgets('renders service title and CTA button', (tester) async {
      String? tappedAction;

      const service = PartnerService(
        id: 's1',
        partnerId: 'p1',
        title: 'Savings Account',
        message: 'Save monthly',
        emoji: '💰',
        category: 'digital',
        ctaLabel: 'Open Now',
        ctaAction: 'web:https://example.com',
      );

      await tester.pumpWidget(_wrap(
        PartnerServiceCard(
          service: service,
          partner: _testPartner,
          categoryMeta: _testMeta,
          normalizeCategory: (raw) => raw,
          onCtaTap: (ctx, {required action, topic}) =>
              tappedAction = action,
        ),
      ));

      expect(find.text('Savings Account'), findsOneWidget);
      expect(find.text('Save monthly'), findsOneWidget);
      expect(find.text('Open Now'), findsOneWidget);

      await tester.tap(find.text('Open Now'));
      await tester.pump();
      expect(tappedAction, 'web:https://example.com');
    });

    testWidgets('hides CTA when ctaAction is null', (tester) async {
      const service = PartnerService(
        id: 's2',
        partnerId: 'p1',
        title: 'Checking Account',
        category: 'digital',
      );

      await tester.pumpWidget(_wrap(
        PartnerServiceCard(
          service: service,
          partner: _testPartner,
          categoryMeta: _testMeta,
          normalizeCategory: (raw) => raw,
          onCtaTap: (ctx, {required action, topic}) {},
        ),
      ));

      expect(find.text('Checking Account'), findsOneWidget);
      // No CTA button when ctaAction is null
      expect(find.text('Open Now'), findsNothing);
    });
  });
}
