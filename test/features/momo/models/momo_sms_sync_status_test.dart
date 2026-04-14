import 'package:cool_app/features/momo/models/momo_sms_sync_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MomoSmsSyncRunSummary.fromJson', () {
    test('parses a complete succeeded run', () {
      final run = MomoSmsSyncRunSummary.fromJson(<String, dynamic>{
        'id': 'run-001',
        'trigger': 'manual',
        'status': 'succeeded',
        'lookback_days': 30,
        'incremental': true,
        'scan_started_at': '2026-04-10T08:00:00.000Z',
        'scan_completed_at': '2026-04-10T08:01:30.000Z',
        'scanned_messages': 150,
        'uploaded_messages': 12,
        'duplicate_messages': 138,
        'oldest_message_at': '2026-03-11T12:00:00.000Z',
        'newest_message_at': '2026-04-10T07:55:00.000Z',
      });

      expect(run.id, 'run-001');
      expect(run.trigger, 'manual');
      expect(run.isSuccessful, isTrue);
      expect(run.isFailed, isFalse);
      expect(run.isInitialBackfill, isFalse);
      expect(run.lookbackDays, 30);
      expect(run.incremental, isTrue);
      expect(run.scannedMessages, 150);
      expect(run.uploadedMessages, 12);
      expect(run.duplicateMessages, 138);
      expect(run.scanCompletedAt, isNotNull);
      expect(run.errorMessage, isNull);
    });

    test('parses a failed run with error message', () {
      final run = MomoSmsSyncRunSummary.fromJson(<String, dynamic>{
        'id': 'run-002',
        'trigger': 'background',
        'status': 'failed',
        'lookback_days': 7,
        'incremental': false,
        'scan_started_at': '2026-04-10T09:00:00.000Z',
        'error_message': 'SMS permission revoked',
      });

      expect(run.isFailed, isTrue);
      expect(run.isSuccessful, isFalse);
      expect(run.errorMessage, 'SMS permission revoked');
    });

    test('identifies initial backfill trigger', () {
      final run = MomoSmsSyncRunSummary.fromJson(<String, dynamic>{
        'id': 'run-003',
        'trigger': 'initial_permission_grant',
        'status': 'succeeded',
        'lookback_days': 365,
        'incremental': false,
        'scan_started_at': '2026-01-01T00:00:00.000Z',
      });

      expect(run.isInitialBackfill, isTrue);
    });

    test('handles missing fields with defaults', () {
      final run = MomoSmsSyncRunSummary.fromJson(<String, dynamic>{});

      expect(run.id, '');
      expect(run.trigger, 'manual');
      expect(run.status, 'succeeded');
      expect(run.lookbackDays, 365);
      expect(run.incremental, isFalse);
      expect(run.scannedMessages, 0);
      expect(run.uploadedMessages, 0);
    });
  });

  group('MomoSmsSyncStatus.fromRows', () {
    test('parses empty rows as no history', () {
      final status = MomoSmsSyncStatus.fromRows([]);

      expect(status.hasHistory, isFalse);
      expect(status.initialBackfillCompleted, isFalse);
      expect(status.latestRun, isNull);
    });

    test('parses single succeeded row', () {
      final status = MomoSmsSyncStatus.fromRows([
        <String, dynamic>{
          'id': 'run-010',
          'trigger': 'manual',
          'status': 'succeeded',
          'lookback_days': 30,
          'incremental': true,
          'scan_started_at': '2026-04-10T10:00:00.000Z',
          'scan_completed_at': '2026-04-10T10:01:00.000Z',
          'scanned_messages': 50,
          'uploaded_messages': 5,
        },
      ]);

      expect(status.hasHistory, isTrue);
      expect(status.latestRun, isNotNull);
      expect(status.latestRun!.id, 'run-010');
    });

    test('filters out rows with empty ids', () {
      final status = MomoSmsSyncStatus.fromRows([
        <String, dynamic>{
          'id': '',
          'trigger': 'manual',
          'status': 'succeeded',
          'lookback_days': 7,
          'incremental': false,
          'scan_started_at': '2026-04-10T10:00:00.000Z',
        },
      ]);

      expect(status.hasHistory, isFalse);
    });
  });
}
