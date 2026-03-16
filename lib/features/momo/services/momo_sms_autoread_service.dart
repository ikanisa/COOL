import 'dart:async';
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
import '../repositories/momo_sms_ingestion_repository.dart';

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
  });

  final int scannedMessages;
  final int uploadedMessages;
  final int duplicateMessages;
}

class MomoSmsAutoreadService {
  MomoSmsAutoreadService({
    required SupabaseClient client,
    required AppAccessService appAccessService,
    Telephony? telephony,
    MomoSmsIngestionRepository? ingestionRepository,
    CrashlyticsService? crashlytics,
    Future<bool> Function()? consentCallback,
  }) : _client = client,
       _appAccessService = appAccessService,
       _telephony = telephony ?? Telephony.instance,
       _ingestionRepository =
           ingestionRepository ?? MomoSmsIngestionRepository(client: client),
       _crashlytics = crashlytics,
       _consentCallback = consentCallback;

  final SupabaseClient _client;
  final AppAccessService _appAccessService;
  final Telephony _telephony;
  final MomoSmsIngestionRepository _ingestionRepository;
  final CrashlyticsService? _crashlytics;
  final Future<bool> Function()? _consentCallback;

  static const _initialInboxSyncLookback = Duration(days: 365);

  bool _isListening = false;
  bool _isSyncingInbox = false;
  bool _requestedPermissionThisLaunch = false;
  String? _activeUserId;
  String? _initialSyncCompletedForUserId;

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
      if (_initialSyncCompletedForUserId != session.user.id) {
        unawaited(_runInitialInboxSync());
      }
      await _crashlytics?.log(
        'momo_sms: Android SMS autoread active for ${session.user.id}',
      );
    }
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

    if (resetPermissionPromptState) {
      _requestedPermissionThisLaunch = false;
    }
  }

  void dispose() {
    unawaited(stop());
  }

  Future<bool> _ensureSmsPermission({
    required bool forceRequest,
    Future<bool> Function()? onShowRationale,
  }) async {
    final status = await Permission.sms.status;
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
    final requestStatus = await Permission.sms.request();
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
      throw const MomoSmsSyncException(
        'Android only',
      );
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
      throw const MomoSmsSyncException(
        'Enable SMS sync first',
      );
    }

    final permissionGranted = await _ensureSmsPermission(
      forceRequest: false,
      onShowRationale: _consentCallback,
    );
    if (!permissionGranted) {
      throw const MomoSmsSyncException(
        'SMS access required',
      );
    }

    _isSyncingInbox = true;

    try {
      final now = DateTime.now().toUtc();
      final cutoff = now.subtract(_initialInboxSyncLookback);
      final messages = await _loadCandidateInboxMessages(cutoff: cutoff);

      var scannedMessages = 0;
      var uploadedMessages = 0;
      var duplicateMessages = 0;
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

      _initialSyncCompletedForUserId = session.user.id;
      await _crashlytics?.log(
        'momo_sms: ${trigger.name} scanned=$scannedMessages '
        'uploaded=$uploadedMessages duplicates=$duplicateMessages',
      );
      return MomoInboxSyncResult(
        scannedMessages: scannedMessages,
        uploadedMessages: uploadedMessages,
        duplicateMessages: duplicateMessages,
      );
    } catch (error, stackTrace) {
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
    final cutoffMillis = cutoff.millisecondsSinceEpoch.toString();
    const senderPatterns =
        MomoSmsIngestionRepository.approvedInboxSenderLikePatterns;
    final messages = <SmsMessage>[];

    for (final senderPattern in senderPatterns) {
      final filter = SmsFilter.where(SmsColumn.ADDRESS)
          .like(senderPattern)
          .and(SmsColumn.DATE)
          .greaterThanOrEqualTo(cutoffMillis);
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
    if (kIsWeb) {
      return false;
    }
    return Platform.isAndroid;
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

  static Future<void> handle(SmsMessage message) async {
    try {
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

      final client = await _ensureSupabaseClient();
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
        return;
      }

      final repository = MomoSmsIngestionRepository(client: client);
      await repository.ingestCapture(capture: capture);
    } catch (error) {
      debugPrint('[MoMo SMS] background ingestion skipped after error: $error');
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
