import 'package:cool_app/core/theme/app_theme.dart';
import 'package:cool_app/features/partners/models/partner.dart';
import 'package:cool_app/features/partners/widgets/partner_brand_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('partner brand mark falls back to emoji for unknown partners', (
    tester,
  ) async {
    const partner = Partner(
      id: 'partner-1',
      name: 'Unknown Partner',
      slug: 'unknown-partner',
      category: PartnerCategory.organization,
      country: 'RW',
      emoji: '🧩',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: Center(child: PartnerBrandMark(partner: partner)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('🧩'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PartnerBrandMark),
        matching: find.byType(DecoratedBox),
      ),
      findsOneWidget,
    );
  });
}
