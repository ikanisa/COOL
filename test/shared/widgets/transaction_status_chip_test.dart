import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/l10n/app_localizations.dart';
import 'package:cool_app/shared/widgets/transaction_status_chip.dart';

Widget _wrap(String status) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Center(child: TransactionStatusChip(status: status)),
    ),
  );
}

Future<void> _expectStatusLabel(
  WidgetTester tester,
  String status,
  String label,
) async {
  await tester.pumpWidget(_wrap(status));
  expect(find.text(label), findsOneWidget);
}

void main() {
  group('TransactionStatusChip', () {
    testWidgets('distinguishes external payment lifecycle states', (
      tester,
    ) async {
      await _expectStatusLabel(tester, 'instruction', 'INSTRUCTION');
      await _expectStatusLabel(tester, 'pending_confirmation', 'PENDING');
      await _expectStatusLabel(tester, 'manual_confirmed', 'MANUAL CONFIRMED');
      await _expectStatusLabel(tester, 'paid', 'PAID');
      await _expectStatusLabel(tester, 'disputed', 'DISPUTED');
      await _expectStatusLabel(tester, 'refunded', 'REFUNDED');
      await _expectStatusLabel(tester, 'cancelled', 'CANCELLED');
    });

    testWidgets('keeps ledger posted status distinct from paid', (
      tester,
    ) async {
      await _expectStatusLabel(tester, 'posted', 'RECEIVED');
    });

    testWidgets('exposes a localized semantics label', (tester) async {
      final semantics = tester.ensureSemantics();

      try {
        await tester.pumpWidget(_wrap('paid'));

        final node = tester.getSemantics(find.byType(TransactionStatusChip));
        expect(node.label, 'Status: PAID');
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('falls back to the raw uppercase status', (tester) async {
      await _expectStatusLabel(tester, 'partner_hold', 'PARTNER_HOLD');
    });
  });
}
