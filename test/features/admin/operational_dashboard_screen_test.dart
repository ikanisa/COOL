import 'package:cool_app/features/admin/providers/admin_providers.dart';
import 'package:cool_app/features/admin/screens/operational_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('renders release dashboard, triage issues, and recent signals', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminOperationalReleaseDashboardProvider.overrideWith(
            (ref) async => <Map<String, dynamic>>[
              <String, dynamic>{
                'service_key': 'sms_ingest',
                'label': 'SMS Ingest',
                'health_status': 'healthy',
                'ok_count_24h': 4,
                'warn_count_24h': 0,
                'error_count_24h': 0,
                'issue_count': 0,
                'last_signal_at': '2026-03-13T09:00:00Z',
                'summary': '4 ok, 0 warn, 0 error events in the last 24 hours.',
              },
              <String, dynamic>{
                'service_key': 'payment_sync',
                'label': 'Payment Sync',
                'health_status': 'failing',
                'ok_count_24h': 0,
                'warn_count_24h': 0,
                'error_count_24h': 0,
                'issue_count': 2,
                'last_signal_at': '2026-03-13T10:15:00Z',
                'summary': '2 payment-sync issues currently need triage.',
              },
            ],
          ),
          adminOperationalTriageIssuesProvider.overrideWith(
            (ref) async => <Map<String, dynamic>>[
              <String, dynamic>{
                'issue_id': 'payment-sync:1',
                'issue_type': 'failed_payment_sync',
                'severity': 'critical',
                'service': 'payment_sync',
                'title': 'Payment sync is still pending',
                'detail':
                    'Payment reference RS-TICKET-123 has been pending for 28 minutes and has not reconciled.',
                'subject_table': 'pending_transactions',
                'subject_id': 'pending-1',
                'reference': 'RS-TICKET-123',
                'first_seen_at': '2026-03-13T09:47:00Z',
                'last_seen_at': '2026-03-13T10:15:00Z',
              },
            ],
          ),
          adminRecentOperationalHealthEventsProvider.overrideWith(
            (ref) async => <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'event-1',
                'service': 'wallet_sync',
                'component': 'wallet-issuer',
                'status': 'ok',
                'severity': 'info',
                'issue_code': null,
                'message': 'Google Wallet pass prepared successfully.',
                'function_name': 'wallet-issuer',
                'occurred_at': '2026-03-13T10:16:00Z',
              },
            ],
          ),
        ],
        child: const MaterialApp(home: OperationalDashboardScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Release Dashboard'), findsOneWidget);
    expect(find.text('SMS Ingest'), findsOneWidget);
    expect(find.text('Payment Sync'), findsOneWidget);
    expect(find.text('Payment sync is still pending'), findsOneWidget);
    expect(
      find.text('Google Wallet pass prepared successfully.'),
      findsOneWidget,
    );
  });
}
