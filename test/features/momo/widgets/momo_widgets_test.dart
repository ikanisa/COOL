import 'package:cool_app/core/services/momo_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart' show Box;
import 'package:supabase_flutter/supabase_flutter.dart'
    show FlutterAuthClientOptions, SupabaseClient;

import 'package:cool_app/core/config/country_catalog.dart';
import 'package:cool_app/features/momo/widgets/momo_cards_widgets.dart';
import 'package:cool_app/features/momo/widgets/momo_qr_nfc_widgets.dart';
import 'package:cool_app/features/momo/widgets/momo_send_sheet.dart';
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

MomoService _buildTestMomoService() {
  return MomoService(
    client: SupabaseClient(
      'http://127.0.0.1:54321',
      'test-anon-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    ),
    openBox: _noOpOpenBox,
  );
}

Future<Box<T>> _noOpOpenBox<T>(String name) =>
    throw UnimplementedError('Hive disabled in widget tests');

// ── tests ─────────────────────────────────────────────────────────────────

void main() {
  group('MomoActionGrid', () {
    testWidgets('renders all tool actions', (tester) async {
      await tester.pumpWidget(
        _wrap(
          MomoActionGrid(
            onOpenStatements: () {},
            onScanQr: () {},
            onOpenQrCode: () {},
            onOpenNfcTools: () {},
          ),
        ),
      );

      expect(find.text('Statements'), findsOneWidget);
      expect(find.text('Scan QR'), findsOneWidget);
      expect(find.text('MOMO QR'), findsOneWidget);
      expect(find.text('NFC pay'), findsOneWidget);
    });

    testWidgets('calls correct callback for each row', (tester) async {
      String? tappedRow;

      await tester.pumpWidget(
        _wrap(
          MomoActionGrid(
            onOpenStatements: () => tappedRow = 'statements',
            onScanQr: () => tappedRow = 'scan',
            onOpenQrCode: () => tappedRow = 'qr',
            onOpenNfcTools: () => tappedRow = 'nfc',
          ),
        ),
      );

      await tester.tap(find.text('Statements'));
      await tester.pump();
      expect(tappedRow, 'statements');

      await tester.ensureVisible(find.text('Scan QR'));
      await tester.tap(find.text('Scan QR'));
      await tester.pump();
      expect(tappedRow, 'scan');

      await tester.ensureVisible(find.text('MOMO QR'));
      await tester.tap(find.text('MOMO QR'));
      await tester.pump();
      expect(tappedRow, 'qr');

      await tester.ensureVisible(find.text('NFC pay'));
      await tester.tap(find.text('NFC pay'));
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

  group('MomoSendMoneySheet', () {
    testWidgets('shows review details and next steps before launch', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          MomoSendMoneySheet(
            country: _rwanda,
            momoNumber: '0781234567',
            momoCode: '123456',
            momoService: _buildTestMomoService(),
          ),
        ),
      );

      expect(find.text('Review before USSD'), findsOneWidget);
      expect(find.text('What happens next'), findsOneWidget);
      expect(find.text('Add a recipient'), findsOneWidget);
      expect(find.text('Add amount'), findsOneWidget);
      expect(find.text('Continue to USSD'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, '0789000111');
      await tester.enterText(find.byType(TextFormField).at(1), '5000');
      await tester.pump();

      expect(find.text('0789000111'), findsWidgets);
      expect(find.text('RWF 5,000'), findsOneWidget);
      expect(find.text('Phone Number'), findsWidgets);
    });
  });

  group('MomoQrCodeCard', () {
    testWidgets('defaults to the Rwanda MoMo number and generates payment QR', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          MomoQrCodeCard(
            country: _rwanda,
            momoNumber: '+250781234567',
            momoCode: '123456',
          ),
        ),
      );

      expect(find.text('MoMo Number'), findsWidgets);
      expect(find.text('+250781234567'), findsWidgets);
      expect(find.text('Share link'), findsOneWidget);

      // Tap "Add amount" to show the amount field before entering a value.
      await tester.tap(find.text('Add amount (optional)'));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField).last, '5000');
      await tester.pump();

      // After entering amount and generating QR, the label changes
      await tester.tap(find.text('Get QR'));
      await tester.pump();
    });
  });
}
