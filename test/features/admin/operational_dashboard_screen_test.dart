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
          adminMomoSmsOperationalSummaryProvider.overrideWith(
            (ref) async => <Map<String, dynamic>>[
              <String, dynamic>{
                'metric_key': 'device_sync',
                'label': 'Device Sync',
                'health_status': 'degraded',
                'summary':
                    '3 successful syncs and 1 failed sync were reported in the last 24 hours.',
                'primary_label': '24h Success',
                'primary_value': 3,
                'secondary_label': '24h Fail',
                'secondary_value': 1,
                'tertiary_label': 'Duplicates',
                'tertiary_value': 2,
                'last_signal_at': '2026-03-13T10:10:00Z',
              },
              <String, dynamic>{
                'metric_key': 'sender_inventory',
                'label': 'Sender Inventory',
                'health_status': 'degraded',
                'summary':
                    '1 unsupported sender remains unresolved across 2 raw SMS rows. 0 sender backlogs were already acknowledged.',
                'primary_label': 'Unresolved',
                'primary_value': 1,
                'secondary_label': 'Acknowledged',
                'secondary_value': 0,
                'tertiary_label': 'Raw Rows',
                'tertiary_value': 2,
                'last_signal_at': '2025-12-15T13:36:49Z',
              },
              <String, dynamic>{
                'metric_key': 'migration_safety',
                'label': 'Migration Safety',
                'health_status': 'healthy',
                'summary':
                    'No legacy completed contribution rows remain. 4 sync audit runs are currently stored, and canonical statuses stay limited to pending, confirmed, and failed.',
                'primary_label': 'Legacy Rows',
                'primary_value': 0,
                'secondary_label': 'Distinct Statuses',
                'secondary_value': 3,
                'tertiary_label': 'Sync Audit Rows',
                'tertiary_value': 4,
                'last_signal_at': null,
              },
            ],
          ),
          adminMomoSmsSenderInventoryProvider.overrideWith(
            (ref) async => <Map<String, dynamic>>[
              <String, dynamic>{
                'sender': '+250788767816',
                'sender_token': '250788767816',
                'sender_kind': 'msisdn',
                'approval_status': 'unsupported',
                'raw_count': 2,
                'user_count': 1,
                'pending_raw_count': 1,
                'parsed_count': 1,
                'open_review_count': 0,
                'rejected_count': 1,
                'matched_count': 0,
                'latest_parse_status': 'pending',
                'latest_match_status': 'not_reconciled',
                'last_ingestion_source': 'android_inbox_sync',
                'first_seen_at': '2025-12-15T13:35:05Z',
                'last_seen_at': '2025-12-15T13:36:49Z',
                'resolution_status': null,
                'resolution_note': null,
                'resolved_at': null,
                'total_count': 1,
              },
            ],
          ),
          adminMomoSmsManualReviewQueueProvider.overrideWith(
            (ref) async => <Map<String, dynamic>>[
              <String, dynamic>{
                'review_id': 'review-1',
                'sender': 'M-Money',
                'review_kind': 'unmatched_payment',
                'amount': 5000,
                'currency': 'RWF',
                'notes':
                    'No pending app payment matched the parsed SMS amount and timing.',
                'tx_type': 'cash_in',
                'tx_category': 'cash_in',
                'sms_received_at': '2026-03-13T10:05:00Z',
                'sms_preview':
                    'You have received 5000 RWF from Pacifique ISHIMWE.',
                'total_count': 1,
              },
            ],
          ),
          adminRecentOperationalHealthEventsProvider.overrideWith(
            (ref) async => <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'event-1',
                'service': 'partner_checkout',
                'component': 'rayon_tickets',
                'status': 'ok',
                'severity': 'info',
                'issue_code': null,
                'message': 'Rayon ticket checkout opened successfully.',
                'function_name': null,
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
    await tester.scrollUntilVisible(
      find.text('Device Sync'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Device Sync'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Sender Inventory'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Sender Inventory'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Migration Safety'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Migration Safety'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Sender Audit'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Sender Audit'), findsOneWidget);
    expect(find.text('+250788767816'), findsOneWidget);
    expect(find.text('Acknowledge visible (1)'), findsOneWidget);
    expect(find.text('Acknowledge legacy'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Manual Review Queue'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Manual Review Queue'), findsOneWidget);
    expect(find.text('Close visible (1)'), findsOneWidget);
    expect(find.text('M-Money'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('partner_checkout'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('partner_checkout'), findsOneWidget);
  });

  testWidgets('sender audit collapses acknowledged history by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminOperationalReleaseDashboardProvider.overrideWith(
            (ref) async => const <Map<String, dynamic>>[],
          ),
          adminOperationalTriageIssuesProvider.overrideWith(
            (ref) async => const <Map<String, dynamic>>[],
          ),
          adminMomoSmsOperationalSummaryProvider.overrideWith(
            (ref) async => <Map<String, dynamic>>[
              <String, dynamic>{
                'metric_key': 'sender_inventory',
                'label': 'Sender Inventory',
                'health_status': 'healthy',
                'summary':
                    'All 1 unsupported sender backlogs have been acknowledged. 2 raw SMS rows remain preserved as historical evidence.',
                'primary_label': 'Unresolved',
                'primary_value': 0,
                'secondary_label': 'Acknowledged',
                'secondary_value': 1,
                'tertiary_label': 'Raw Rows',
                'tertiary_value': 2,
                'last_signal_at': '2026-03-22T10:16:00Z',
              },
            ],
          ),
          adminMomoSmsSenderInventoryProvider.overrideWith(
            (ref) async => <Map<String, dynamic>>[
              <String, dynamic>{
                'sender': '+250788767816',
                'sender_token': '250788767816',
                'sender_kind': 'msisdn',
                'approval_status': 'unsupported',
                'raw_count': 2,
                'user_count': 1,
                'pending_raw_count': 0,
                'parsed_count': 1,
                'open_review_count': 0,
                'rejected_count': 1,
                'matched_count': 0,
                'latest_parse_status': 'parsed',
                'latest_match_status': 'rejected',
                'last_ingestion_source': 'android_sms_inbox_recovery',
                'first_seen_at': '2025-12-15T13:35:05Z',
                'last_seen_at': '2025-12-15T13:36:49Z',
                'resolution_status': 'acknowledged_legacy',
                'resolution_note':
                    'Admin acknowledged this unsupported sender as legacy raw SMS history. The sender remains unapproved and stays excluded from active intake policies.',
                'resolved_at': '2026-03-22T10:16:00Z',
                'total_count': 1,
              },
            ],
          ),
          adminMomoSmsManualReviewQueueProvider.overrideWith(
            (ref) async => const <Map<String, dynamic>>[],
          ),
          adminRecentOperationalHealthEventsProvider.overrideWith(
            (ref) async => const <Map<String, dynamic>>[],
          ),
        ],
        child: const MaterialApp(home: OperationalDashboardScreen()),
      ),
    );

    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Sender Audit'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'No unresolved unsupported sender backlogs remain. Switch to Acknowledged (1) to review preserved history.',
      ),
      findsOneWidget,
    );
    expect(find.text('Acknowledge visible (1)'), findsNothing);
    expect(find.text('+250788767816'), findsNothing);

    await tester.tap(find.text('Acknowledged (1)'));
    await tester.pumpAndSettle();

    expect(find.text('+250788767816'), findsOneWidget);
    expect(find.text('ACKNOWLEDGED'), findsOneWidget);
    expect(find.text('Acknowledge legacy'), findsNothing);
  });
}
