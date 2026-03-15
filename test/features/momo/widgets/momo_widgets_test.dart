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

void _noop() {}

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

      expect(find.text('Send Money'), findsWidgets);
      expect(
        find.text('Launches Rwanda MoMo USSD to complete the transfer.'),
        findsOneWidget,
      );
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
      final buttons = find.text('Send Money');
      // The button text may appear multiple times (heading + button)
      await tester.tap(buttons.last);
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('shows local display when momo number is stored in E.164', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          MomoSendMoneyCard(
            country: _rwanda,
            momoNumber: '+250781234567',
            onSendTap: () {},
          ),
        ),
      );

      expect(find.text('From 0781234567'), findsOneWidget);
      expect(find.text('From +250781234567'), findsNothing);
    });
  });

  group('MomoToolsCard', () {
    testWidgets('renders all 5 tool rows', (tester) async {
      await tester.pumpWidget(
        _wrap(
          MomoToolsCard(
            country: _rwanda,
            momoNumber: '0781234567',
            onOpenStatements: () {},
            onOpenQrCode: () {},
            onRequestPayment: () {},
            onScanQr: () {},
            onOpenNfcTools: () {},
          ),
        ),
      );

      expect(find.text('More tools'), findsOneWidget);
      expect(find.text('Statements'), findsOneWidget);
      expect(find.text('Full-screen QR'), findsOneWidget);
      expect(find.text('Request payment'), findsOneWidget);
      expect(find.text('Scan QR'), findsOneWidget);
      expect(find.text('NFC tools'), findsOneWidget);
      expect(find.text('Open your receive QR for 0781234567.'), findsOneWidget);
    });

    testWidgets('calls correct callback for each row', (tester) async {
      String? tappedRow;

      await tester.pumpWidget(
        _wrap(
          MomoToolsCard(
            country: _rwanda,
            momoNumber: '0781234567',
            onOpenStatements: () => tappedRow = 'statements',
            onOpenQrCode: () => tappedRow = 'qr',
            onRequestPayment: () => tappedRow = 'request',
            onScanQr: () => tappedRow = 'scan',
            onOpenNfcTools: () => tappedRow = 'nfc',
          ),
        ),
      );

      await tester.tap(find.text('Statements'));
      await tester.pump();
      expect(tappedRow, 'statements');

      await tester.tap(find.text('Full-screen QR'));
      await tester.pump();
      expect(tappedRow, 'qr');

      await tester.tap(find.text('Request payment'));
      await tester.pump();
      expect(tappedRow, 'request');

      await tester.tap(find.text('Scan QR'));
      await tester.pump();
      expect(tappedRow, 'scan');

      await tester.tap(find.text('NFC tools'));
      await tester.pump();
      expect(tappedRow, 'nfc');
    });

    testWidgets('shows local QR subtitle when momo number is stored in E.164', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          MomoToolsCard(
            country: _rwanda,
            momoNumber: '+250781234567',
            onOpenStatements: () {},
            onOpenQrCode: () {},
            onRequestPayment: () {},
            onScanQr: () {},
            onOpenNfcTools: () {},
          ),
        ),
      );

      expect(find.text('Open your receive QR for 0781234567.'), findsOneWidget);
      expect(find.text('+250781234567'), findsNothing);
    });
  });

  group('MomoPaymentSafetyCard', () {
    testWidgets('renders trust cues for fees approval and receipts', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const MomoPaymentSafetyCard()));

      expect(find.text('Before you pay'), findsOneWidget);
      expect(find.text('Fees show before confirmation'), findsOneWidget);
      expect(find.text('You approve on your phone'), findsOneWidget);
      expect(find.text('Receipts land in statements'), findsOneWidget);
    });
  });

  group('MomoInboxSyncCard', () {
    testWidgets('renders the inbox-backed sync architecture clearly', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const MomoInboxSyncCard(
            isAndroidSmsAvailable: true,
            isSyncing: false,
            onSyncTap: _noop,
          ),
        ),
      );

      expect(find.text('Inbox-backed sync'), findsOneWidget);
      expect(
        find.text('Import M-Money SMS from the last 12 months.'),
        findsOneWidget,
      );
      expect(
        find.text('Each new M-Money SMS is sent to Supabase right away.'),
        findsOneWidget,
      );
      expect(find.text('Sync SMS'), findsOneWidget);
    });

    testWidgets('disables sync action on non-Android platforms', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const MomoInboxSyncCard(
            isAndroidSmsAvailable: false,
            isSyncing: false,
            onSyncTap: _noop,
          ),
        ),
      );

      expect(find.text('Inbox sync is Android-only'), findsOneWidget);
      expect(find.text('Sync SMS'), findsOneWidget);
      expect(
        tester
            .widget<AbsorbPointer>(
              find.descendant(
                of: find.byType(MomoInboxSyncCard),
                matching: find.byType(AbsorbPointer),
              ),
            )
            .absorbing,
        isTrue,
      );
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
            momoNumber: '0781234567',
            momoCode: '123456',
          ),
        ),
      );

      expect(find.text('Get paid by QR'), findsOneWidget);
      expect(find.text('MoMo Number'), findsWidgets);
      expect(find.text('0781234567'), findsWidgets);
      expect(find.text('Receive QR · Rwanda · RWF'), findsOneWidget);
      expect(find.text('Generate payment QR'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).last, '5000');
      await tester.pump();

      expect(find.text('Receive QR · Rwanda · RWF'), findsOneWidget);

      await tester.tap(find.text('Generate payment QR'));
      await tester.pump();

      expect(find.text('Payment QR · Rwanda · RWF'), findsOneWidget);
    });
  });
}
