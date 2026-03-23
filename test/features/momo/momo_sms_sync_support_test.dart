import 'dart:io';

import 'package:cool_app/core/services/crashlytics_service.dart';
import 'package:cool_app/features/momo/services/momo_sms_sync_support.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('cool_sms_sync_support');
    Hive.init(hiveDir.path);
  });

  tearDown(() async {
    const boxName = 'momo_sms_sync_state';
    if (Hive.isBoxOpen(boxName)) {
      await Hive.box<String>(boxName).clear();
      await Hive.box<String>(boxName).close();
    }
    await Hive.deleteBoxFromDisk(boxName);
  });

  tearDownAll(() async {
    await hiveDir.delete(recursive: true);
  });

  group('MomoSmsSyncStateStore', () {
    test('persists and restores sync state per user', () async {
      final store = MomoSmsSyncStateStore(openBox: Hive.openBox<String>);
      final initialBackfillCompletedAt = DateTime.utc(2026, 3, 22, 10, 0, 0);
      final lastSuccessfulSyncAt = DateTime.utc(2026, 3, 22, 10, 5, 0);
      final latestKnownMessageAt = DateTime.utc(2026, 3, 22, 9, 55, 0);

      await store.write(
        'user-1',
        MomoSmsSyncState(
          initialBackfillCompletedAt: initialBackfillCompletedAt,
          lastSuccessfulSyncAt: lastSuccessfulSyncAt,
          latestKnownMessageAt: latestKnownMessageAt,
        ),
      );
      await store.write('user-2', const MomoSmsSyncState());

      final restored = await store.read('user-1');
      final otherUserState = await store.read('user-2');

      expect(restored.hasInitialBackfill, isTrue);
      expect(restored.initialBackfillCompletedAt, initialBackfillCompletedAt);
      expect(restored.lastSuccessfulSyncAt, lastSuccessfulSyncAt);
      expect(restored.latestKnownMessageAt, latestKnownMessageAt);
      expect(otherUserState.hasInitialBackfill, isFalse);
      expect(otherUserState.latestKnownMessageAt, isNull);

      final box = await Hive.openBox<String>('momo_sms_sync_state');
      expect(box.containsKey(store.keyForUser('user-1')), isTrue);
      expect(box.containsKey(store.keyForUser('user-2')), isTrue);
    });

    test('returns empty state when stored payload is invalid', () async {
      final store = MomoSmsSyncStateStore(openBox: Hive.openBox<String>);
      final box = await Hive.openBox<String>('momo_sms_sync_state');
      await box.put(store.keyForUser('user-1'), '{not-json');

      final restored = await store.read('user-1');

      expect(restored.hasInitialBackfill, isFalse);
      expect(restored.lastSuccessfulSyncAt, isNull);
      expect(restored.latestKnownMessageAt, isNull);
    });
  });

  group('MomoSmsSyncPlanner', () {
    test('manual sync uses 12-hour overlap from latest known message', () {
      final historicalCutoff = DateTime.utc(2025, 3, 22, 10, 0, 0);
      final latestKnownMessageAt = DateTime.utc(2026, 3, 20, 18, 30, 0);

      final cutoff = MomoSmsSyncPlanner.resolveManualCutoff(
        syncState: MomoSmsSyncState(latestKnownMessageAt: latestKnownMessageAt),
        historicalCutoff: historicalCutoff,
      );

      expect(
        cutoff,
        latestKnownMessageAt.subtract(MomoSmsSyncPlanner.overlapWindow),
      );
    });

    test(
      'manual sync falls back to historical cutoff when overlap is older',
      () {
        final historicalCutoff = DateTime.utc(2025, 3, 22, 10, 0, 0);
        final latestKnownMessageAt = historicalCutoff.add(
          const Duration(hours: 8),
        );

        final cutoff = MomoSmsSyncPlanner.resolveManualCutoff(
          syncState: MomoSmsSyncState(
            latestKnownMessageAt: latestKnownMessageAt,
          ),
          historicalCutoff: historicalCutoff,
        );

        expect(cutoff, historicalCutoff);
        expect(
          MomoSmsSyncPlanner.lookbackDaysFor(
            cutoff: historicalCutoff,
            now: historicalCutoff.add(const Duration(days: 400)),
          ),
          365,
        );
      },
    );
  });

  group('MomoSmsSyncRunAuditWriter', () {
    test('serializes sync run inserts with expected payload shape', () async {
      Map<String, dynamic>? insertedRow;
      final scanStartedAt = DateTime.utc(2026, 3, 22, 10, 0, 0);
      final scanCompletedAt = DateTime.utc(2026, 3, 22, 10, 2, 0);
      final oldestMessageAt = DateTime.utc(2026, 3, 21, 8, 0, 0);
      final newestMessageAt = DateTime.utc(2026, 3, 22, 9, 59, 0);
      final latestKnownMessageAt = DateTime.utc(2026, 3, 22, 9, 59, 0);

      final writer = MomoSmsSyncRunAuditWriter(
        insert: (row) async => insertedRow = Map<String, dynamic>.from(row),
      );

      await writer.record(
        MomoSmsSyncRunRecord(
          userId: 'user-1',
          trigger: 'manual',
          status: 'succeeded',
          lookbackDays: 2,
          incremental: true,
          scanStartedAt: scanStartedAt,
          scanCompletedAt: scanCompletedAt,
          scannedMessages: 3,
          uploadedMessages: 2,
          duplicateMessages: 1,
          oldestMessageAt: oldestMessageAt,
          newestMessageAt: newestMessageAt,
          latestKnownMessageAt: latestKnownMessageAt,
        ),
      );

      expect(insertedRow, isNotNull);
      expect(insertedRow!['user_id'], 'user-1');
      expect(insertedRow!['trigger'], 'manual');
      expect(insertedRow!['status'], 'succeeded');
      expect(insertedRow!['lookback_days'], 2);
      expect(insertedRow!['incremental'], isTrue);
      expect(insertedRow!['scanned_messages'], 3);
      expect(insertedRow!['uploaded_messages'], 2);
      expect(insertedRow!['duplicate_messages'], 1);
      expect(insertedRow!['scan_started_at'], scanStartedAt.toIso8601String());
      expect(
        insertedRow!['scan_completed_at'],
        scanCompletedAt.toIso8601String(),
      );
      expect(
        insertedRow!['oldest_message_at'],
        oldestMessageAt.toIso8601String(),
      );
      expect(
        insertedRow!['newest_message_at'],
        newestMessageAt.toIso8601String(),
      );
      expect(
        insertedRow!['latest_known_message_at'],
        latestKnownMessageAt.toIso8601String(),
      );
      expect(insertedRow!['error_message'], isNull);
    });

    test('reports insert failures to crashlytics without rethrowing', () async {
      final crashlytics = _FakeCrashlyticsService();
      final writer = MomoSmsSyncRunAuditWriter(
        insert: (_) async => throw StateError('db down'),
        crashlytics: crashlytics,
      );

      await writer.record(
        MomoSmsSyncRunRecord(
          userId: 'user-1',
          trigger: 'manual',
          status: 'failed',
          lookbackDays: 1,
          incremental: false,
          scanStartedAt: DateTime.utc(2026, 3, 22, 10, 0, 0),
          errorMessage: 'db down',
        ),
      );

      expect(crashlytics.recordedReasons, ['momo_sms_sync_run_audit_failed']);
      expect(crashlytics.recordedErrors.single, isA<StateError>());
    });
  });
}

class _FakeCrashlyticsService extends CrashlyticsService {
  final List<dynamic> recordedErrors = <dynamic>[];
  final List<String?> recordedReasons = <String?>[];

  @override
  Future<void> recordError(
    dynamic error, {
    StackTrace? stackTrace,
    String? reason,
    bool fatal = false,
  }) async {
    recordedErrors.add(error);
    recordedReasons.add(reason);
  }
}
