import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env_config.dart';
import '../../../core/services/app_access_service.dart';
import '../../../core/services/crashlytics_service.dart';
import '../../../core/services/hive_runtime.dart';
import 'momo_sms_native_bridge.dart';
import 'momo_sms_sync_support.dart';

typedef MomoSmsPermissionStatusReader = Future<PermissionStatus> Function();
typedef MomoSmsPermissionRequester = Future<PermissionStatus> Function();
typedef MomoSmsAutoreadSupportChecker = bool Function();

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
    CrashlyticsService? crashlytics,
    OpenHiveBox<String>? openBox,
    MomoSmsSyncStateStore? syncStateStore,
    MomoSmsSyncRunAuditWriter? syncRunAuditWriter,
    Future<bool> Function()? consentCallback,
    MomoSmsPermissionStatusReader? smsPermissionStatus,
    MomoSmsPermissionRequester? requestSmsPermission,
    MomoSmsAutoreadSupportChecker? supportsSmsAutoread,
    MomoSmsNativeBridge? nativeBridge,
    Future<List<String>> Function()? approvedSenderLoader,
  }) : _client = client,
       _appAccessService = appAccessService,
       _crashlytics = crashlytics,
       _syncStateStore =
           syncStateStore ??
           MomoSmsSyncStateStore(openBox: openBox ?? openHiveBox),
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
       _nativeBridge = nativeBridge ?? MomoSmsNativeBridge(),
       _approvedSenderLoader = approvedSenderLoader;

  final SupabaseClient _client;
  final AppAccessService _appAccessService;
  final CrashlyticsService? _crashlytics;
  final MomoSmsSyncStateStore _syncStateStore;
  final MomoSmsSyncRunAuditWriter _syncRunAuditWriter;
  final Future<bool> Function()? _consentCallback;
  final MomoSmsPermissionStatusReader _smsPermissionStatus;
  final MomoSmsPermissionRequester _requestSmsPermission;
  final MomoSmsAutoreadSupportChecker? _supportsSmsAutoreadOverride;
  final MomoSmsNativeBridge _nativeBridge;
  final Future<List<String>> Function()? _approvedSenderLoader;

  static const _initialInboxSyncLookback = Duration(days: 365);
  static const _fallbackApprovedSenderTokens = <String>[
    'mmoney',
    'mmoneyalerts',
    'mobilemoney',
    'momo',
    'momoalerts',
    'mtnmomo',
    'mtnmomorwanda',
  ];

  bool _requestedPermissionThisLaunch = false;
  String? _initialSyncScheduledForUserId;

  Future<void> refresh({
    bool forcePermissionRequest = false,
    Future<bool> Function()? onShowRationale,
  }) async {
    if (!_supportsSmsAutoread || !EnvConfig.enableAndroidMomoSmsAutoread) {
      await stop(clearPipelineSession: false);
      return;
    }

    final session = _client.auth.currentSession;
    if (session == null) {
      await stop(
        resetPermissionPromptState: true,
        clearPipelineSession: true,
      );
      return;
    }

    final smsEnabledInApp = await _appAccessService.isEnabled(
      AppAccessPermission.sms,
    );
    if (!smsEnabledInApp) {
      await stop(clearPipelineSession: true);
      return;
    }

    final permissionGranted = await _ensureSmsPermission(
      forceRequest: forcePermissionRequest,
      onShowRationale: onShowRationale ?? _consentCallback,
    );
    if (!permissionGranted) {
      await stop(clearPipelineSession: true);
      return;
    }

    await _configureNativePipeline(session);

    unawaited(() async {
      try {
        await _nativeBridge.syncPendingNow();
      } catch (error, stack) {
        await _crashlytics?.recordError(
          error,
          stackTrace: stack,
          reason: 'momo_sms_native_pending_sync_failed',
        );
      }
    }());

    final syncState = await _readSyncState(session.user.id);
    if (!syncState.hasInitialBackfill &&
        _initialSyncScheduledForUserId != session.user.id) {
      _initialSyncScheduledForUserId = session.user.id;
      unawaited(_runInitialInboxSync());
    }
  }

  Future<void> stop({
    bool resetPermissionPromptState = false,
    bool clearPipelineSession = true,
  }) async {
    if (clearPipelineSession) {
      await _nativeBridge.clearSession();
    } else {
      await _nativeBridge.configure(
        const MomoSmsNativePipelineConfig(
          enabled: false,
          supabaseUrl: EnvConfig.supabaseUrl,
          supabaseAnonKey: EnvConfig.supabaseAnonKey,
        ),
      );
    }
    _initialSyncScheduledForUserId = null;
    if (resetPermissionPromptState) {
      _requestedPermissionThisLaunch = false;
    }
  }

  void dispose() {
    unawaited(stop(clearPipelineSession: false));
  }

  Future<MomoInboxSyncResult> syncInbox({
    required MomoInboxSyncTrigger trigger,
    ValueChanged<int>? onProgress,
  }) async {
    if (!_supportsSmsAutoread) {
      throw const MomoSmsSyncException('Android only');
    }
    if (!EnvConfig.enableAndroidMomoSmsAutoread) {
      throw const MomoSmsSyncException('Android SMS sync is disabled.');
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

    await _configureNativePipeline(session);
    final scanStartedAt = DateTime.now().toUtc();
    final syncState = await _readSyncState(session.user.id);
    final historicalCutoff = scanStartedAt.subtract(_initialInboxSyncLookback);
    final isReinstallRecovery =
        trigger == MomoInboxSyncTrigger.manual &&
        !syncState.hasInitialBackfill &&
        syncState.lastSuccessfulSyncAt == null;

    final cutoff =
        trigger == MomoInboxSyncTrigger.initialPermissionGrant ||
            isReinstallRecovery
        ? historicalCutoff
        : MomoSmsSyncPlanner.resolveManualCutoff(
            syncState: syncState,
            historicalCutoff: historicalCutoff,
          );
    final incremental =
        trigger == MomoInboxSyncTrigger.manual &&
        !isReinstallRecovery &&
        cutoff.isAfter(historicalCutoff);

    try {
      final result = await _nativeBridge.syncInbox(
        cutoff: cutoff,
        trigger: _momoSmsSyncTriggerValue(trigger),
      );
      onProgress?.call(result.scannedMessages);

      if (result.rateLimited) {
        await _recordSyncRun(
          userId: session.user.id,
          trigger: trigger,
          status: 'rate_limited',
          lookbackDays: MomoSmsSyncPlanner.lookbackDaysFor(
            cutoff: cutoff,
            now: scanStartedAt,
          ),
          incremental: incremental,
          scanStartedAt: scanStartedAt,
          scanCompletedAt: DateTime.now().toUtc(),
          scannedMessages: result.scannedMessages,
          uploadedMessages: result.uploadedMessages,
          duplicateMessages: result.duplicateMessages,
          oldestMessageAt: result.oldestMessageAt,
          newestMessageAt: result.newestMessageAt,
          latestKnownMessageAt: _newerOf(
            syncState.latestKnownMessageAt,
            result.newestMessageAt,
          ),
          errorMessage: 'Rate-limited after ${result.scannedMessages} messages',
        );
      } else {
        final completedAt = DateTime.now().toUtc();
        final latestKnownMessageAt = _newerOf(
          syncState.latestKnownMessageAt,
          result.newestMessageAt,
        );
        await _writeSyncState(
          session.user.id,
          MomoSmsSyncState(
            initialBackfillCompletedAt:
                trigger == MomoInboxSyncTrigger.initialPermissionGrant
                ? completedAt
                : syncState.initialBackfillCompletedAt,
            lastSuccessfulSyncAt: completedAt,
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
          scanCompletedAt: completedAt,
          scannedMessages: result.scannedMessages,
          uploadedMessages: result.uploadedMessages,
          duplicateMessages: result.duplicateMessages,
          oldestMessageAt: result.oldestMessageAt,
          newestMessageAt: result.newestMessageAt,
          latestKnownMessageAt: latestKnownMessageAt,
        );
      }

      return MomoInboxSyncResult(
        scannedMessages: result.scannedMessages,
        uploadedMessages: result.uploadedMessages,
        duplicateMessages: result.duplicateMessages,
        oldestMessageAt: result.oldestMessageAt,
        newestMessageAt: result.newestMessageAt,
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
        latestKnownMessageAt: syncState.latestKnownMessageAt,
        errorMessage: error.toString(),
      );
      await _crashlytics?.recordError(
        error,
        stackTrace: stackTrace,
        reason: 'momo_sms_native_inbox_sync_failed',
      );
      rethrow;
    }
  }

  Future<int> getRetryQueueSize() async {
    final status = await _nativeBridge.getQueueStatus();
    return status.pendingCount + status.failedCount;
  }

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
    if (onShowRationale != null) {
      final confirmed = await onShowRationale();
      if (!confirmed) {
        return false;
      }
    }
    _requestedPermissionThisLaunch = true;
    return (await _requestSmsPermission()).isGranted;
  }

  Future<List<String>> _loadApprovedSenderTokens() async {
    final approvedSenderLoader = _approvedSenderLoader;
    if (approvedSenderLoader != null) {
      final normalizedTokens = _normalizeApprovedSenderTokens(
        await approvedSenderLoader(),
      );
      if (normalizedTokens.isNotEmpty) {
        return normalizedTokens;
      }
    }
    try {
      final rows = await _client
          .from('momo_sms_sender_allowlist')
          .select('sender_token')
          .eq('active', true)
          .order('sort_order');
      final tokens = _normalizeApprovedSenderTokens(
        rows.map((dynamic row) => row['sender_token']?.toString() ?? ''),
      );
      if (tokens.isNotEmpty) {
        return tokens;
      }
    } catch (error, stackTrace) {
      await _crashlytics?.recordError(
        error,
        stackTrace: stackTrace,
        reason: 'momo_sms_sender_allowlist_load_failed',
      );
    }
    return _fallbackApprovedSenderTokens;
  }

  Future<void> _configureNativePipeline(Session session) async {
    final approvedSenderTokens = await _loadApprovedSenderTokens();
    await _nativeBridge.configure(
      MomoSmsNativePipelineConfig(
        enabled: true,
        userId: session.user.id,
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        accessTokenExpiresAtEpochSeconds: session.expiresAt,
        supabaseUrl: EnvConfig.supabaseUrl,
        supabaseAnonKey: EnvConfig.supabaseAnonKey,
        approvedSenders: approvedSenderTokens,
      ),
    );
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
        metadata: <String, dynamic>{
          'platform': Platform.operatingSystem,
          'os_version': Platform.operatingSystemVersion,
          'pipeline': 'native_android_sms',
        },
      ),
    );
  }
}

class MomoSmsSyncException implements Exception {
  const MomoSmsSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

String _momoSmsSyncTriggerValue(MomoInboxSyncTrigger trigger) {
  return switch (trigger) {
    MomoInboxSyncTrigger.initialPermissionGrant => 'initial_permission_grant',
    MomoInboxSyncTrigger.manual => 'manual',
  };
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

List<String> _normalizeApprovedSenderTokens(Iterable<String> tokens) {
  return tokens
      .map(_normalizeSenderToken)
      .where((String token) => token.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
}

String _normalizeSenderToken(String raw) {
  return raw.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9]'), '');
}
