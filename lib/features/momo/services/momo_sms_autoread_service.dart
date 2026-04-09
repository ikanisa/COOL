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

part 'momo_sms_autoread_background.dart';
part 'momo_sms_autoread_service_sync.dart';
part 'momo_sms_autoread_service_sync_support.dart';

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

  Future<MomoInboxSyncResult> syncInbox({
    required MomoInboxSyncTrigger trigger,
    ValueChanged<int>? onProgress,
  }) => _syncInboxInternal(trigger: trigger, onProgress: onProgress);

  Future<int> getRetryQueueSize() async {
    final box = await _openBox(_retryQueueBoxName);
    return box.length;
  }
}

class MomoSmsSyncException implements Exception {
  const MomoSmsSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}
