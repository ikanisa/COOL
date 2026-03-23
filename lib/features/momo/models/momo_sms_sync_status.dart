class MomoSmsSyncRunSummary {
  const MomoSmsSyncRunSummary({
    required this.id,
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
  });

  final String id;
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

  bool get isInitialBackfill => trigger == 'initial_permission_grant';
  bool get isSuccessful => status == 'succeeded';
  bool get isFailed => status == 'failed';

  factory MomoSmsSyncRunSummary.fromJson(Map<String, dynamic> json) {
    return MomoSmsSyncRunSummary(
      id: json['id']?.toString() ?? '',
      trigger: json['trigger']?.toString() ?? 'manual',
      status: json['status']?.toString() ?? 'succeeded',
      lookbackDays: _asInt(json['lookback_days'], fallback: 365),
      incremental: json['incremental'] == true,
      scanStartedAt:
          _parseDateTime(json['scan_started_at']) ?? DateTime.now().toUtc(),
      scanCompletedAt: _parseDateTime(json['scan_completed_at']),
      scannedMessages: _asInt(json['scanned_messages']),
      uploadedMessages: _asInt(json['uploaded_messages']),
      duplicateMessages: _asInt(json['duplicate_messages']),
      oldestMessageAt: _parseDateTime(json['oldest_message_at']),
      newestMessageAt: _parseDateTime(json['newest_message_at']),
      latestKnownMessageAt: _parseDateTime(json['latest_known_message_at']),
      errorMessage: _nonEmpty(json['error_message']),
    );
  }
}

class MomoSmsSyncStatus {
  const MomoSmsSyncStatus({
    this.latestRun,
    this.latestSuccessfulRun,
    this.initialBackfillRun,
  });

  final MomoSmsSyncRunSummary? latestRun;
  final MomoSmsSyncRunSummary? latestSuccessfulRun;
  final MomoSmsSyncRunSummary? initialBackfillRun;

  bool get hasHistory =>
      latestRun != null ||
      latestSuccessfulRun != null ||
      initialBackfillRun != null;

  bool get initialBackfillCompleted => initialBackfillRun?.isSuccessful == true;

  factory MomoSmsSyncStatus.fromRows(List<Map<String, dynamic>> rows) {
    final summaries = rows
        .map(MomoSmsSyncRunSummary.fromJson)
        .where((summary) => summary.id.isNotEmpty)
        .toList(growable: false);

    MomoSmsSyncRunSummary? latestSuccessfulRun;
    MomoSmsSyncRunSummary? initialBackfillRun;
    for (final summary in summaries) {
      latestSuccessfulRun ??= summary.isSuccessful ? summary : null;
      initialBackfillRun ??= summary.isInitialBackfill && summary.isSuccessful
          ? summary
          : null;
    }

    return MomoSmsSyncStatus(
      latestRun: summaries.isEmpty ? null : summaries.first,
      latestSuccessfulRun: latestSuccessfulRun,
      initialBackfillRun: initialBackfillRun,
    );
  }
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

DateTime? _parseDateTime(dynamic value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString())?.toUtc();
}

String? _nonEmpty(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
