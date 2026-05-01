import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/crashlytics_service.dart';
import '../../../core/services/hive_runtime.dart';
import '../../../core/utils/app_logger.dart';

const _log = AppLogger('MoMoSMS');

DateTime? _parseSyncDateTime(dynamic value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return DateTime.tryParse(value)?.toUtc();
}

class MomoSmsSyncState {
  const MomoSmsSyncState({
    this.initialBackfillCompletedAt,
    this.lastSuccessfulSyncAt,
    this.latestKnownMessageAt,
  });

  final DateTime? initialBackfillCompletedAt;
  final DateTime? lastSuccessfulSyncAt;
  final DateTime? latestKnownMessageAt;

  bool get hasInitialBackfill => initialBackfillCompletedAt != null;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'initialBackfillCompletedAt': initialBackfillCompletedAt
          ?.toUtc()
          .toIso8601String(),
      'lastSuccessfulSyncAt': lastSuccessfulSyncAt?.toUtc().toIso8601String(),
      'latestKnownMessageAt': latestKnownMessageAt?.toUtc().toIso8601String(),
    };
  }

  factory MomoSmsSyncState.fromJson(Map<String, dynamic> json) {
    return MomoSmsSyncState(
      initialBackfillCompletedAt: _parseSyncDateTime(
        json['initialBackfillCompletedAt'],
      ),
      lastSuccessfulSyncAt: _parseSyncDateTime(json['lastSuccessfulSyncAt']),
      latestKnownMessageAt: _parseSyncDateTime(json['latestKnownMessageAt']),
    );
  }
}

class MomoSmsSyncStateStore {
  const MomoSmsSyncStateStore({
    required OpenHiveBox<String> openBox,
    this.boxName = 'momo_sms_sync_state',
  }) : _openBox = openBox;

  final OpenHiveBox<String> _openBox;
  final String boxName;

  @visibleForTesting
  String keyForUser(String userId) => 'user:$userId';

  Future<MomoSmsSyncState> read(String userId) async {
    try {
      final box = await _openBox(boxName);
      final payload = box.get(keyForUser(userId));
      if (payload == null || payload.trim().isEmpty) {
        return const MomoSmsSyncState();
      }

      final decoded = jsonDecode(payload);
      if (decoded is! Map) {
        return const MomoSmsSyncState();
      }

      return MomoSmsSyncState.fromJson(Map<String, dynamic>.from(decoded));
    } catch (error) {
      _log.warn('Could not read sync state: $error');
      return const MomoSmsSyncState();
    }
  }

  Future<void> write(String userId, MomoSmsSyncState state) async {
    try {
      final box = await _openBox(boxName);
      await box.put(keyForUser(userId), jsonEncode(state.toJson()));
    } catch (error) {
      _log.warn('Could not persist sync state: $error');
    }
  }
}

class MomoSmsSyncPlanner {
  const MomoSmsSyncPlanner._();

  static const overlapWindow = Duration(hours: 12);

  static DateTime resolveManualCutoff({
    required MomoSmsSyncState syncState,
    required DateTime historicalCutoff,
  }) {
    final latestKnownMessageAt = syncState.latestKnownMessageAt;
    if (latestKnownMessageAt == null) {
      return historicalCutoff;
    }

    final overlapCutoff = latestKnownMessageAt.toUtc().subtract(overlapWindow);
    return overlapCutoff.isAfter(historicalCutoff)
        ? overlapCutoff
        : historicalCutoff;
  }

  static int lookbackDaysFor({
    required DateTime cutoff,
    required DateTime now,
  }) {
    final days = now.difference(cutoff).inDays;
    if (days <= 0) {
      return 0;
    }
    if (days >= 365) {
      return 365;
    }
    return days;
  }
}

class MomoSmsSyncRunRecord {
  const MomoSmsSyncRunRecord({
    required this.userId,
    required this.trigger,
    required this.status,
    required this.lookbackDays,
    required this.incremental,
    required this.scanStartedAt,
    this.scanCompletedAt,
    this.scannedMessages = 0,
    this.uploadedMessages = 0,
    this.duplicateMessages = 0,
    this.oldestMessageAt,
    this.newestMessageAt,
    this.latestKnownMessageAt,
    this.errorMessage,
    this.metadata,
  });

  final String userId;
  final String trigger;
  final String status;
  final int lookbackDays;
  final bool incremental;
  final DateTime scanStartedAt;
  final DateTime? scanCompletedAt;
  final int scannedMessages;
  final int uploadedMessages;
  final int duplicateMessages;
  final DateTime? oldestMessageAt;
  final DateTime? newestMessageAt;
  final DateTime? latestKnownMessageAt;
  final String? errorMessage;
  final Map<String, dynamic>? metadata;

  Map<String, dynamic> toInsertRow() {
    return <String, dynamic>{
      'user_id': userId,
      'trigger': trigger,
      'status': status,
      'lookback_days': lookbackDays,
      'incremental': incremental,
      'scan_started_at': scanStartedAt.toUtc().toIso8601String(),
      'scan_completed_at': scanCompletedAt?.toUtc().toIso8601String(),
      'scanned_messages': scannedMessages,
      'uploaded_messages': uploadedMessages,
      'duplicate_messages': duplicateMessages,
      'oldest_message_at': oldestMessageAt?.toUtc().toIso8601String(),
      'newest_message_at': newestMessageAt?.toUtc().toIso8601String(),
      'latest_known_message_at': latestKnownMessageAt
          ?.toUtc()
          .toIso8601String(),
      'error_message': errorMessage,
      if (metadata != null && metadata!.isNotEmpty) 'metadata': metadata,
    };
  }
}

typedef MomoSmsSyncRunInsert = Future<void> Function(Map<String, dynamic> row);

class MomoSmsSyncRunAuditWriter {
  MomoSmsSyncRunAuditWriter({
    required MomoSmsSyncRunInsert insert,
    CrashlyticsService? crashlytics,
  }) : _insert = insert,
       _crashlytics = crashlytics;

  factory MomoSmsSyncRunAuditWriter.supabase({
    required SupabaseClient client,
    CrashlyticsService? crashlytics,
  }) {
    return MomoSmsSyncRunAuditWriter(
      insert: (row) async {
        await client.from('momo_sms_sync_runs').insert(row);
      },
      crashlytics: crashlytics,
    );
  }

  final MomoSmsSyncRunInsert _insert;
  final CrashlyticsService? _crashlytics;

  Future<void> record(MomoSmsSyncRunRecord run) async {
    try {
      await _insert(run.toInsertRow());
    } catch (error, stackTrace) {
      _log.warn('Could not record sync run: $error');
      await _crashlytics?.recordError(
        error,
        stackTrace: stackTrace,
        reason: 'momo_sms_sync_run_audit_failed',
      );
    }
  }
}
