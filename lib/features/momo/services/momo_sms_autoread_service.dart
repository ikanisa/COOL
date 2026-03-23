import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:another_telephony/telephony.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env_config.dart';
import '../../../core/services/app_access_service.dart';
import '../../../core/services/crashlytics_service.dart';
import '../../../core/services/hive_runtime.dart';
import '../../../core/services/operational_health_service.dart';
import '../repositories/momo_sms_ingestion_repository.dart';
import 'momo_sms_sync_support.dart';

const _retryQueueBoxName = 'momo_sms_retry_queue';
const _retryQueueMaxSize = 200;
const _syncStateBoxName = 'momo_sms_sync_state';
const _retryQueueTelemetryThresholds = <int>{1, 10, 25, 50, 100, 200};

typedef MomoSmsPermissionStatusReader = Future<PermissionStatus> Function();
typedef MomoSmsPermissionRequester = Future<PermissionStatus> Function();
typedef MomoSmsAutoreadSupportChecker = bool Function();
typedef MomoSmsInboxLoader = Future<List<SmsMessage>> Function(DateTime cutoff);

@pragma('vm:entry-point')
Future<void> momoSmsBackgroundMessageHandler(SmsMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await _MomoSmsBackgroundProcessor.handle(message);
}

enum MomoInboxSyncTrigger { initialPermissionGrant, manual }

class MomoInboxSyncResult {
  const MomoInboxSyncResult({
    required this.scannedMessages,
    required this.uploadedMessages,
    required this.duplicateMessages,
    this.oldestMessageAt,
    this.newestMessageAt,
    this.incremental = false,
  });

  final int scannedMessages;
  final int uploadedMessages;
  final int duplicateMessages;
  final DateTime? oldestMessageAt;
  final DateTime? newestMessageAt;
  final bool incremental;
}

class MomoSmsAutoreadService {
  MomoSmsAutoreadService({
    required SupabaseClient client,
    required AppAccessService appAccessService,
    Telephony? telephony,
    MomoSmsIngestionRepository? ingestionRepository,
    CrashlyticsService? crashlytics,
    OperationalHealthService? operationalHealthService,
    OpenHiveBox<String>? openBox,
    MomoSmsSyncStateStore? syncStateStore,
    MomoSmsSyncRunAuditWriter? syncRunAuditWriter,
    Future<bool> Function()? consentCallback,
    MomoSmsPermissionStatusReader? smsPermissionStatus,
    MomoSmsPermissionRequester? requestSmsPermission,
    MomoSmsAutoreadSupportChecker? supportsSmsAutoread,
    MomoSmsInboxLoader? inboxLoader,
  }) : _client = client,
       _appAccessService = appAccessService,
       _telephony = telephony ?? Telephony.instance,
       _ingestionRepository =
           ingestionRepository ?? MomoSmsIngestionRepository(client: client),
       _crashlytics = crashlytics,
       _operationalHealthService =
           operationalHealthService ?? OperationalHealthService(client: client),
       _openBox = openBox ?? openHiveBox<String>,
       _syncStateStore =
           syncStateStore ??
           MomoSmsSyncStateStore(
             openBox: openBox ?? openHiveBox<String>,
             boxName: _syncStateBoxName,
           ),
       _syncRunAuditWriter =
           syncRunAuditWriter ??
           MomoSmsSyncRunAuditWriter.supabase(
             client: client,
             crashlytics: crashlytics,
           ),
       _consentCallback = consentCallback,
       _smsPermissionStatus =
           smsPermissionStatus ?? (() => Permission.sms.status),
       _requestSmsPermission =
           requestSmsPermission ?? (() => Permission.sms.request()),
       _supportsSmsAutoreadOverride = supportsSmsAutoread,
       _inboxLoader = inboxLoader;

  final SupabaseClient _client;
  final AppAccessService _appAccessService;
  final Telephony _telephony;
  final MomoSmsIngestionRepository _ingestionRepository;
  final CrashlyticsService? _crashlytics;
  final OperationalHealthService _operationalHealthService;
  final OpenHiveBox<String> _openBox;
  final MomoSmsSyncStateStore _syncStateStore;
  final MomoSmsSyncRunAuditWriter _syncRunAuditWriter;
  final Future<bool> Function()? _consentCallback;
  final MomoSmsPermissionStatusReader _smsPermissionStatus;
  final MomoSmsPermissionRequester _requestSmsPermission;
  final MomoSmsAutoreadSupportChecker? _supportsSmsAutoreadOverride;
  final MomoSmsInboxLoader? _inboxLoader;

  static const _initialInboxSyncLookback = Duration(days: 365);

  bool _isListening = false;
  bool _isSyncingInbox = false;
  bool _requestedPermissionThisLaunch = false;
  String? _activeUserId;
  String? _initialSyncScheduledForUserId;

  Future<void> refresh({
    bool forcePermissionRequest = false,
    Future<bool> Function()? onShowRationale,
  }) async {
    if (!_supportsSmsAutoread) {
      await stop();
      return;
    }

    if (!EnvConfig.enableAndroidMomoSmsAutoread) {
      await stop();
      return;
    }

    final session = _client.auth.currentSession;
    if (session == null) {
      await stop(resetPermissionPromptState: true);
      return;
    }

    final smsEnabledInApp = await _appAccessService.isEnabled(
      AppAccessPermission.sms,
    );
    if (!smsEnabledInApp) {
      await stop();
      return;
    }

    final permissionGranted = await _ensureSmsPermission(
      forceRequest: forcePermissionRequest,
      onShowRationale: onShowRationale ?? _consentCallback,
    );
    if (!permissionGranted) {
      await stop();
      return;
    }

    if (!_isListening || _activeUserId != session.user.id) {
      _telephony.listenIncomingSms(
        onNewMessage: _handleForegroundMessage,
        onBackgroundMessage: momoSmsBackgroundMessageHandler,
      );
      _isListening = true;
      _activeUserId = session.user.id;
      await _crashlytics?.log(
        'momo_sms: Android SMS autoread active for ${session.user.id}',
      );
    }

    final syncState = await _readSyncState(session.user.id);
    if (!syncState.hasInitialBackfill &&
        _initialSyncScheduledForUserId != session.user.id) {
      _initialSyncScheduledForUserId = session.user.id;
      unawaited(_runInitialInboxSync());
    }

    // Drain any queued messages from previous background failures (G8).
    unawaited(_drainRetryQueue());
  }

  Future<void> stop({bool resetPermissionPromptState = false}) async {
    if (_supportsSmsAutoread && _isListening) {
      _telephony.listenIncomingSms(
        onNewMessage: _ignoreIncomingMessage,
        listenInBackground: false,
      );
    }

    _isListening = false;
    _activeUserId = null;
    _initialSyncScheduledForUserId = null;

    if (resetPermissionPromptState) {
      _requestedPermissionThisLaunch = false;
    }
  }

  void dispose() {
    unawaited(stop());
  }

  /// Drains the Hive-based retry queue of captures that failed during
  /// background processing (G8). Called on each successful [refresh].
  Future<void> _drainRetryQueue() async {
    try {
      final box = await _openBox(_retryQueueBoxName);
      if (box.isEmpty) return;

      final queuedBefore = box.length;
      final keys = box.keys.toList();
      for (final key in keys) {
        final json = box.get(key);
        if (json == null) continue;

        try {
          final map = jsonDecode(json) as Map<String, dynamic>;
          final capture = MomoSmsCapture(
            sender: map['sender'] as String,
            body: map['body'] as String,
            deviceMessageKey: map['deviceMessageKey'] as String,
            receivedAt: DateTime.parse(map['receivedAt'] as String),
            ingestionSource: map['ingestionSource'] as String,
          );
          await _ingestionRepository.ingestCapture(capture: capture);
          await box.delete(key);
        } catch (error) {
          // Leave in queue for next drain attempt.
          debugPrint('[MoMo SMS] retry failed for key=$key: $error');
        }
      }
      final queuedAfter = box.length;
      await _reportRetryQueueDrain(
        queuedBefore: queuedBefore,
        queuedAfter: queuedAfter,
      );
    } catch (error) {
      debugPrint('[MoMo SMS] retry queue drain failed: $error');
      await _recordSmsIngestOperationalEvent(
        _operationalHealthService,
        status: OperationalHealthStatus.error,
        severity: OperationalHealthSeverity.critical,
        issueCode: 'retry_queue_drain_failed',
        message:
            'SMS retry queue drain failed before all captures could retry.',
      );
    }
  }

  Future<bool> _ensureSmsPermission({
    required bool forceRequest,
    Future<bool> Function()? onShowRationale,
  }) async {
    final status = await _smsPermissionStatus();
    if (status.isGranted) {
      return true;
    }

    if (status.isPermanentlyDenied || status.isRestricted) {
      return false;
    }

    if (!forceRequest && _requestedPermissionThisLaunch) {
      return false;
    }

    // Show pre-permission consent disclosure (Google Play requirement).
    if (onShowRationale != null) {
      final confirmed = await onShowRationale();
      if (!confirmed) {
        return false;
      }
    }

    _requestedPermissionThisLaunch = true;
    final requestStatus = await _requestSmsPermission();
    return requestStatus.isGranted;
  }

  void _handleForegroundMessage(SmsMessage message) {
    unawaited(
      _ingestMessage(
        message,
        ingestionSource: 'android_sms_listener_foreground',
      ),
    );
  }

  void _ignoreIncomingMessage(SmsMessage _) {}

  Future<void> _runInitialInboxSync() async {
    try {
      await syncInbox(trigger: MomoInboxSyncTrigger.initialPermissionGrant);
    } catch (error, stackTrace) {
      _initialSyncScheduledForUserId = null;
      await _crashlytics?.recordError(
        error,
        stackTrace: stackTrace,
        reason: 'momo_sms_initial_inbox_sync_failed',
      );
    }
  }

  Future<MomoInboxSyncResult> syncInbox({
    required MomoInboxSyncTrigger trigger,
  }) async {
    if (!_supportsSmsAutoread) {
      throw const MomoSmsSyncException('Android only');
    }
    if (!EnvConfig.enableAndroidMomoSmsAutoread) {
      throw const MomoSmsSyncException('Android SMS sync is disabled.');
    }
    if (_isSyncingInbox) {
      throw const MomoSmsSyncException('Sync already running');
    }

    final session = _client.auth.currentSession;
    if (session == null) {
      throw const MomoSmsSyncException('Sign in first');
    }

    final smsEnabledInApp = await _appAccessService.isEnabled(
      AppAccessPermission.sms,
    );
    if (!smsEnabledInApp) {
      throw const MomoSmsSyncException('Enable SMS sync first');
    }

    final permissionGranted = await _ensureSmsPermission(
      forceRequest: false,
      onShowRationale: _consentCallback,
    );
    if (!permissionGranted) {
      throw const MomoSmsSyncException('SMS access required');
    }

    _isSyncingInbox = true;
    final scanStartedAt = DateTime.now().toUtc();
    final syncState = await _readSyncState(session.user.id);
    final historicalCutoff = scanStartedAt.subtract(_initialInboxSyncLookback);
    final cutoff = trigger == MomoInboxSyncTrigger.initialPermissionGrant
        ? historicalCutoff
        : MomoSmsSyncPlanner.resolveManualCutoff(
            syncState: syncState,
            historicalCutoff: historicalCutoff,
          );
    final incremental =
        trigger == MomoInboxSyncTrigger.manual &&
        cutoff.isAfter(historicalCutoff);

    try {
      final messages = await _loadCandidateInboxMessages(cutoff: cutoff);

      var scannedMessages = 0;
      var uploadedMessages = 0;
      var duplicateMessages = 0;
      DateTime? oldestMessageAt;
      DateTime? newestMessageAt;
      final processedMessageKeys = <String>{};

      for (final message in messages) {
        final capture = MomoSmsIngestionRepository.captureFromDeviceMessage(
          sender: message.address,
          body: message.body,
          timestampMillis: message.date,
          ingestionSource: trigger == MomoInboxSyncTrigger.manual
              ? 'android_sms_manual_sync'
              : 'android_sms_initial_sync',
        );
        if (capture == null) {
          continue;
        }
        if (capture.receivedAt.isBefore(cutoff)) {
          break;
        }
        if (!processedMessageKeys.add(capture.deviceMessageKey)) {
          continue;
        }

        scannedMessages += 1;
        oldestMessageAt = _olderOf(oldestMessageAt, capture.receivedAt);
        newestMessageAt = _newerOf(newestMessageAt, capture.receivedAt);
        final result = await _ingestionRepository.ingestCapture(
          capture: capture,
        );
        if (result == null) {
          continue;
        }
        if (result.inserted) {
          uploadedMessages += 1;
        } else {
          duplicateMessages += 1;
        }
      }

      final latestKnownMessageAt = _newerOf(
        syncState.latestKnownMessageAt,
        newestMessageAt,
      );
      final scanCompletedAt = DateTime.now().toUtc();
      await _writeSyncState(
        session.user.id,
        MomoSmsSyncState(
          initialBackfillCompletedAt:
              trigger == MomoInboxSyncTrigger.initialPermissionGrant
              ? scanCompletedAt
              : syncState.initialBackfillCompletedAt,
          lastSuccessfulSyncAt: scanCompletedAt,
          latestKnownMessageAt: latestKnownMessageAt,
        ),
      );
      await _recordSyncRun(
        userId: session.user.id,
        trigger: trigger,
        status: 'succeeded',
        lookbackDays: MomoSmsSyncPlanner.lookbackDaysFor(
          cutoff: cutoff,
          now: scanStartedAt,
        ),
        incremental: incremental,
        scanStartedAt: scanStartedAt,
        scanCompletedAt: scanCompletedAt,
        scannedMessages: scannedMessages,
        uploadedMessages: uploadedMessages,
        duplicateMessages: duplicateMessages,
        oldestMessageAt: oldestMessageAt,
        newestMessageAt: newestMessageAt,
        latestKnownMessageAt: latestKnownMessageAt,
      );
      await _crashlytics?.log(
        'momo_sms: ${trigger.name} scanned=$scannedMessages '
        'uploaded=$uploadedMessages duplicates=$duplicateMessages',
      );
      return MomoInboxSyncResult(
        scannedMessages: scannedMessages,
        uploadedMessages: uploadedMessages,
        duplicateMessages: duplicateMessages,
        oldestMessageAt: oldestMessageAt,
        newestMessageAt: newestMessageAt,
        incremental: incremental,
      );
    } catch (error, stackTrace) {
      await _recordSyncRun(
        userId: session.user.id,
        trigger: trigger,
        status: 'failed',
        lookbackDays: MomoSmsSyncPlanner.lookbackDaysFor(
          cutoff: cutoff,
          now: scanStartedAt,
        ),
        incremental: incremental,
        scanStartedAt: scanStartedAt,
        scanCompletedAt: DateTime.now().toUtc(),
        errorMessage: error.toString(),
        latestKnownMessageAt: syncState.latestKnownMessageAt,
      );
      await _crashlytics?.recordError(
        error,
        stackTrace: stackTrace,
        reason: 'momo_sms_inbox_sync_failed',
      );
      rethrow;
    } finally {
      _isSyncingInbox = false;
    }
  }

  Future<void> _ingestMessage(
    SmsMessage message, {
    required String ingestionSource,
  }) async {
    await _reportSenderDriftIfNeeded(
      sender: message.address,
      body: message.body,
      ingestionSource: ingestionSource,
    );
    final capture = MomoSmsIngestionRepository.captureFromDeviceMessage(
      sender: message.address,
      body: message.body,
      timestampMillis: message.date,
      ingestionSource: ingestionSource,
    );
    if (capture == null) {
      return;
    }

    try {
      await _ingestionRepository.ingestCapture(capture: capture);
    } catch (error, stackTrace) {
      await _queueRetryCapture(capture);
      await _crashlytics?.recordError(
        error,
        stackTrace: stackTrace,
        reason: 'momo_sms_ingestion_failed',
      );
    }
  }

  Future<List<SmsMessage>> _loadCandidateInboxMessages({
    required DateTime cutoff,
  }) async {
    if (_inboxLoader != null) {
      return _inboxLoader(cutoff);
    }

    final cutoffMillis = cutoff.millisecondsSinceEpoch.toString();
    const senderIds = MomoSmsIngestionRepository.approvedInboxSenderIds;
    final messages = <SmsMessage>[];

    for (final senderId in senderIds) {
      final filter = SmsFilter.where(
        SmsColumn.ADDRESS,
      ).equals(senderId).and(SmsColumn.DATE).greaterThanOrEqualTo(cutoffMillis);
      final patternMessages = await _telephony.getInboxSms(
        columns: const [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
        filter: filter,
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      );
      messages.addAll(patternMessages);
    }

    messages.sort((a, b) => (b.date ?? 0).compareTo(a.date ?? 0));
    return messages;
  }

  bool get _supportsSmsAutoread {
    final override = _supportsSmsAutoreadOverride;
    if (override != null) {
      return override();
    }
    if (kIsWeb) {
      return false;
    }
    return Platform.isAndroid;
  }

  Future<MomoSmsSyncState> _readSyncState(String userId) {
    return _syncStateStore.read(userId);
  }

  Future<void> _writeSyncState(String userId, MomoSmsSyncState state) {
    return _syncStateStore.write(userId, state);
  }

  Future<void> _recordSyncRun({
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
    await _syncRunAuditWriter.record(
      MomoSmsSyncRunRecord(
        userId: userId,
        trigger: _syncTriggerValue(trigger),
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
      ),
    );
  }

  Future<void> _queueRetryCapture(MomoSmsCapture capture) async {
    try {
      final box = await _openBox(_retryQueueBoxName);
      final alreadyQueued = box.containsKey(capture.deviceMessageKey);
      if (!alreadyQueued && box.length >= _retryQueueMaxSize) {
        await _recordSmsIngestOperationalEvent(
          _operationalHealthService,
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
      await _reportRetryQueueThreshold(queueSize: box.length);
    } catch (error) {
      debugPrint('[MoMo SMS] retry queue write failed: $error');
    }
  }

  DateTime? _olderOf(DateTime? left, DateTime? right) {
    if (left == null) {
      return right;
    }
    if (right == null) {
      return left;
    }
    return left.isBefore(right) ? left : right;
  }

  DateTime? _newerOf(DateTime? left, DateTime? right) {
    if (left == null) {
      return right;
    }
    if (right == null) {
      return left;
    }
    return left.isAfter(right) ? left : right;
  }

  String _syncTriggerValue(MomoInboxSyncTrigger trigger) {
    return switch (trigger) {
      MomoInboxSyncTrigger.initialPermissionGrant => 'initial_permission_grant',
      MomoInboxSyncTrigger.manual => 'manual',
    };
  }

  Future<void> _reportSenderDriftIfNeeded({
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
      _operationalHealthService,
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

  Future<void> _reportRetryQueueThreshold({required int queueSize}) async {
    if (!_retryQueueTelemetryThresholds.contains(queueSize)) {
      return;
    }

    await _recordSmsIngestOperationalEvent(
      _operationalHealthService,
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

  Future<void> _reportRetryQueueDrain({
    required int queuedBefore,
    required int queuedAfter,
  }) async {
    if (queuedBefore <= 0) {
      return;
    }

    final drainedCount = queuedBefore - queuedAfter;
    final cleared = queuedAfter == 0;
    await _recordSmsIngestOperationalEvent(
      _operationalHealthService,
      status: cleared
          ? OperationalHealthStatus.ok
          : OperationalHealthStatus.warn,
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
}

class MomoSmsSyncException implements Exception {
  const MomoSmsSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _MomoSmsBackgroundProcessor {
  static bool _hiveInitialized = false;
  static bool _supabaseInitialized = false;
  static const InitializeHive _initializeHive = initializeHiveRuntime;
  static const OpenHiveBox<bool> _openAppAccessBox = openHiveBox<bool>;
  static const OpenHiveBox<String> _openRetryQueueBox = openHiveBox<String>;

  static Future<void> handle(SmsMessage message) async {
    if (kIsWeb || !Platform.isAndroid) {
      return;
    }

    if (!EnvConfig.enableAndroidMomoSmsAutoread) {
      return;
    }

    await _ensureHiveInitialized();
    final appAccessService = AppAccessService(openBox: _openAppAccessBox);
    final smsEnabledInApp = await appAccessService.isEnabled(
      AppAccessPermission.sms,
    );
    if (!smsEnabledInApp) {
      return;
    }

    SupabaseClient? client;
    try {
      client = await _ensureSupabaseClient();
    } catch (_) {
      return;
    }
    if (client == null || client.auth.currentUser?.id == null) {
      return;
    }

    final capture = MomoSmsIngestionRepository.captureFromDeviceMessage(
      sender: message.address,
      body: message.body,
      timestampMillis: message.date,
      ingestionSource: 'android_sms_listener_background',
    );
    if (capture == null) {
      await _reportBackgroundSenderDriftIfNeeded(
        client: client,
        sender: message.address,
        body: message.body,
      );
      return;
    }

    try {
      final repository = MomoSmsIngestionRepository(client: client);
      await repository.ingestCapture(capture: capture);
    } catch (error) {
      debugPrint(
        '[MoMo SMS] background ingestion failed, queueing for retry: $error',
      );
      // Queue the capture for retry on next foreground refresh (G8).
      try {
        final box = await _openRetryQueueBox(_retryQueueBoxName);
        final alreadyQueued = box.containsKey(capture.deviceMessageKey);
        if (alreadyQueued || box.length < _retryQueueMaxSize) {
          final payload = jsonEncode({
            'sender': capture.sender,
            'body': capture.body,
            'deviceMessageKey': capture.deviceMessageKey,
            'receivedAt': capture.receivedAt.toUtc().toIso8601String(),
            'ingestionSource': capture.ingestionSource,
          });
          await box.put(capture.deviceMessageKey, payload);
          final queueSize = box.length;
          if (_retryQueueTelemetryThresholds.contains(queueSize)) {
            await _recordSmsIngestOperationalEvent(
              OperationalHealthService(client: client),
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
        } else {
          await _recordSmsIngestOperationalEvent(
            OperationalHealthService(client: client),
            status: OperationalHealthStatus.error,
            severity: OperationalHealthSeverity.critical,
            issueCode: 'retry_queue_full',
            message: 'SMS retry queue is full; new capture was dropped.',
            metadata: <String, dynamic>{
              'queued_before': box.length,
              'max_queue': _retryQueueMaxSize,
            },
          );
        }
      } catch (queueError) {
        debugPrint('[MoMo SMS] retry queue write failed: $queueError');
      }
    }
  }

  static Future<void> _ensureHiveInitialized() async {
    if (_hiveInitialized) {
      return;
    }
    await _initializeHive();
    _hiveInitialized = true;
  }

  static Future<SupabaseClient?> _ensureSupabaseClient() async {
    if (EnvConfig.criticalConfigurationError != null) {
      return null;
    }

    if (!_supabaseInitialized) {
      try {
        await Supabase.initialize(
          url: EnvConfig.supabaseUrl,
          anonKey: EnvConfig.supabaseAnonKey,
        );
      } catch (error) {
        final message = error.toString().toLowerCase();
        if (!message.contains('already initialized')) {
          return null;
        }
      }
      _supabaseInitialized = true;
    }

    return Supabase.instance.client;
  }
}

Future<void> _recordSmsIngestOperationalEvent(
  OperationalHealthService operationalHealthService, {
  required OperationalHealthStatus status,
  OperationalHealthSeverity? severity,
  String? issueCode,
  required String message,
  Map<String, dynamic> metadata = const <String, dynamic>{},
}) {
  return operationalHealthService.recordEvent(
    service: 'sms_ingest',
    component: 'android_sms_autoread',
    status: status,
    severity: severity,
    issueCode: issueCode,
    message: message,
    metadata: metadata,
  );
}

Future<void> _reportBackgroundSenderDriftIfNeeded({
  required SupabaseClient client,
  required String? sender,
  required String? body,
}) async {
  final metadata = MomoSmsIngestionRepository.senderDriftTelemetry(
    sender: sender,
    body: body,
  );
  if (metadata == null) {
    return;
  }

  await _recordSmsIngestOperationalEvent(
    OperationalHealthService(client: client),
    status: OperationalHealthStatus.warn,
    severity: OperationalHealthSeverity.warning,
    issueCode: 'approved_sender_drift',
    message:
        'Possible M-Money confirmation matched transactional patterns from an unapproved sender ID.',
    metadata: <String, dynamic>{
      ...metadata,
      'ingestion_source': 'android_sms_listener_background',
    },
  );
}
