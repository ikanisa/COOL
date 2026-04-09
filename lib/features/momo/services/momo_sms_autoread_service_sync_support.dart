part of 'momo_sms_autoread_service.dart';

Future<void> _recordMomoSmsSyncRun(
  MomoSmsAutoreadService service, {
  required String userId,
  required MomoInboxSyncTrigger trigger,
  required String status,
  required int lookbackDays,
  required bool incremental,
  required DateTime scanStartedAt,
  DateTime? scanCompletedAt,
  int scannedMessages = 0,
  int uploadedMessages = 0,
  int duplicateMessages = 0,
  DateTime? oldestMessageAt,
  DateTime? newestMessageAt,
  DateTime? latestKnownMessageAt,
  String? errorMessage,
}) async {
  final deviceMetadata = <String, dynamic>{
    'platform': Platform.operatingSystem,
    'os_version': Platform.operatingSystemVersion,
  };

  await service._syncRunAuditWriter.record(
    MomoSmsSyncRunRecord(
      userId: userId,
      trigger: _momoSmsSyncTriggerValue(trigger),
      status: status,
      lookbackDays: lookbackDays,
      incremental: incremental,
      scanStartedAt: scanStartedAt,
      scanCompletedAt: scanCompletedAt,
      scannedMessages: scannedMessages,
      uploadedMessages: uploadedMessages,
      duplicateMessages: duplicateMessages,
      oldestMessageAt: oldestMessageAt,
      newestMessageAt: newestMessageAt,
      latestKnownMessageAt: latestKnownMessageAt,
      errorMessage: errorMessage,
      metadata: deviceMetadata,
    ),
  );
}

DateTime? _olderMomoSmsTimestamp(DateTime? left, DateTime? right) {
  if (left == null) {
    return right;
  }
  if (right == null) {
    return left;
  }
  return left.isBefore(right) ? left : right;
}

DateTime? _newerMomoSmsTimestamp(DateTime? left, DateTime? right) {
  if (left == null) {
    return right;
  }
  if (right == null) {
    return left;
  }
  return left.isAfter(right) ? left : right;
}

String _momoSmsSyncTriggerValue(MomoInboxSyncTrigger trigger) {
  return switch (trigger) {
    MomoInboxSyncTrigger.initialPermissionGrant => 'initial_permission_grant',
    MomoInboxSyncTrigger.manual => 'manual',
  };
}

Future<void> _reportMomoSenderDriftIfNeeded(
  MomoSmsAutoreadService service, {
  required String? sender,
  required String? body,
  required String ingestionSource,
}) async {
  final metadata = MomoSmsIngestionRepository.senderDriftTelemetry(
    sender: sender,
    body: body,
  );
  if (metadata == null) {
    return;
  }

  await _recordSmsIngestOperationalEvent(
    service._operationalHealthService,
    status: OperationalHealthStatus.warn,
    severity: OperationalHealthSeverity.warning,
    issueCode: 'approved_sender_drift',
    message:
        'Possible M-Money confirmation matched transactional patterns from an unapproved sender ID.',
    metadata: <String, dynamic>{
      ...metadata,
      'ingestion_source': ingestionSource,
    },
  );
}

Future<void> _reportMomoRetryQueueThreshold(
  MomoSmsAutoreadService service, {
  required int queueSize,
}) async {
  if (!_retryQueueTelemetryThresholds.contains(queueSize)) {
    return;
  }

  await _recordSmsIngestOperationalEvent(
    service._operationalHealthService,
    status: OperationalHealthStatus.warn,
    severity: OperationalHealthSeverity.warning,
    issueCode: 'retry_queue_backlog',
    message: 'SMS retry queue has pending captures awaiting retry.',
    metadata: <String, dynamic>{
      'queued_after': queueSize,
      'max_queue': _retryQueueMaxSize,
    },
  );
}

Future<void> _reportMomoRetryQueueDrain(
  MomoSmsAutoreadService service, {
  required int queuedBefore,
  required int queuedAfter,
}) async {
  if (queuedBefore <= 0) {
    return;
  }

  final drainedCount = queuedBefore - queuedAfter;
  final cleared = queuedAfter == 0;
  await _recordSmsIngestOperationalEvent(
    service._operationalHealthService,
    status: cleared ? OperationalHealthStatus.ok : OperationalHealthStatus.warn,
    severity: cleared
        ? OperationalHealthSeverity.info
        : OperationalHealthSeverity.warning,
    issueCode: cleared ? 'retry_queue_drained' : 'retry_queue_backlog',
    message: cleared
        ? 'SMS retry queue drained successfully.'
        : 'SMS retry queue still has pending captures after drain.',
    metadata: <String, dynamic>{
      'queued_before': queuedBefore,
      'queued_after': queuedAfter,
      'drained_count': drainedCount,
      'max_queue': _retryQueueMaxSize,
    },
  );
}

Future<void> _queueMomoSmsRetryCapture(
  MomoSmsAutoreadService service,
  MomoSmsCapture capture,
) async {
  try {
    final box = await service._openBox(_retryQueueBoxName);
    final alreadyQueued = box.containsKey(capture.deviceMessageKey);
    if (!alreadyQueued && box.length >= _retryQueueMaxSize) {
      await _recordSmsIngestOperationalEvent(
        service._operationalHealthService,
        status: OperationalHealthStatus.error,
        severity: OperationalHealthSeverity.critical,
        issueCode: 'retry_queue_full',
        message: 'SMS retry queue is full; new capture was dropped.',
        metadata: <String, dynamic>{
          'queued_before': box.length,
          'max_queue': _retryQueueMaxSize,
        },
      );
      return;
    }

    await box.put(
      capture.deviceMessageKey,
      jsonEncode({
        'sender': capture.sender,
        'body': capture.body,
        'deviceMessageKey': capture.deviceMessageKey,
        'receivedAt': capture.receivedAt.toUtc().toIso8601String(),
        'ingestionSource': capture.ingestionSource,
      }),
    );
    await _reportMomoRetryQueueThreshold(service, queueSize: box.length);
  } catch (error) {
    debugPrint('[MoMo SMS] retry queue write failed: $error');
  }
}
