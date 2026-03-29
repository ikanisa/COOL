// ignore_for_file: avoid_redundant_argument_values

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/brand/app_brand.dart';
import 'package:cool_app/shared/widgets/cool_brand_mark.dart';
import 'package:cool_app/shared/widgets/cool_status_card.dart';
import 'package:cool_app/shared/widgets/group_card.dart';
import 'package:cool_app/shared/widgets/member_row.dart';
import 'package:cool_app/shared/widgets/rs_tier_badge.dart';
import 'package:cool_app/shared/widgets/vehicle_chip.dart';
import 'package:cool_app/shared/widgets/wa_button.dart';
import 'package:cool_app/shared/widgets/whatsapp_hint_chip.dart';
import 'package:cool_app/core/status/models/cool_status.dart';
import 'package:cool_app/features/rayon/models/rs_models.dart';

/// Accessibility smoke tests.
///
/// These verify that key shared widgets expose a [Semantics] node with a
/// non-empty label so TalkBack / VoiceOver can announce them. They do NOT
/// verify exact label wording (that changes with data), only that a label
/// exists.
void main() {
  Widget harness(Widget child) => ProviderScope(
    child: MaterialApp(home: Scaffold(body: child)),
  );

  // ── Helper: find a Semantics node with a non-empty label ────────────
  bool hasNonEmptySemantics(WidgetTester tester) {
    final semanticsNodes = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .where((s) => s.properties.label?.isNotEmpty ?? false);
    return semanticsNodes.isNotEmpty;
  }

  group('Accessibility — Semantics labels present', () {
    testWidgets('CoolBrandMark has Semantics', (tester) async {
      await tester.pumpWidget(harness(const CoolBrandMark()));
      expect(
        find.bySemanticsLabel(const AppBranding.rayon().logoSemanticLabel),
        findsOneWidget,
      );
      expect(hasNonEmptySemantics(tester), isTrue);
    });

    testWidgets('CoolStatusCard has Semantics', (tester) async {
      await tester.pumpWidget(
        harness(
          CoolStatusCard(
            status: CoolStatus(
              id: 'status-1',
              userId: 'u1',
              totalPoints: 100,
              tier: FanTier.blue,
              currentStreak: 5,
              longestStreak: 10,
              streakGraceRemaining: 1,
              seasonPoints: 50,
              updatedAt: DateTime(2026, 1, 1),
              createdAt: DateTime(2026, 1, 1),
            ),
          ),
        ),
      );
      expect(hasNonEmptySemantics(tester), isTrue);
    });

    testWidgets('WaButton has Semantics', (tester) async {
      await tester.pumpWidget(harness(WaButton(onTap: () {})));
      expect(hasNonEmptySemantics(tester), isTrue);
    });

    testWidgets('WhatsAppHintChip has Semantics', (tester) async {
      await tester.pumpWidget(harness(const WhatsAppHintChip()));
      expect(hasNonEmptySemantics(tester), isTrue);
    });

    testWidgets('VehicleChip has Semantics', (tester) async {
      await tester.pumpWidget(
        harness(VehicleChip(label: '🚗 Car', isSelected: true, onTap: () {})),
      );
      expect(hasNonEmptySemantics(tester), isTrue);
    });

    testWidgets('MemberRow has Semantics', (tester) async {
      await tester.pumpWidget(
        harness(
          const MemberRow(
            userId: 'user1',
            contributionAmount: 5000,
            displayName: 'Alice Test',
          ),
        ),
      );
      expect(hasNonEmptySemantics(tester), isTrue);
    });

    testWidgets('GroupCard has Semantics', (tester) async {
      await tester.pumpWidget(
        harness(
          GroupCard(
            name: 'Test Group',
            type: 'saving',
            visibility: 'public',
            amount: 10000,
            memberCount: 5,
            targetAmount: 50000,
            onTap: () {},
          ),
        ),
      );
      expect(hasNonEmptySemantics(tester), isTrue);
    });

    testWidgets('RsTierBadge has Semantics', (tester) async {
      await tester.pumpWidget(harness(const RsTierBadge(tier: FanTier.gold)));
      expect(hasNonEmptySemantics(tester), isTrue);
    });
  });
}
