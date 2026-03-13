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
import '../../../core/services/operational_health_service.dart';
import '../repositories/momo_sms_ingestion_repository.dart';

@pragma('vm:entry-point')
Future<void> momoSmsBackgroundMessageHandler(SmsMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await _MomoSmsBackgroundProcessor.handle(message);
}

class MomoSmsAutoreadService {
  MomoSmsAutoreadService({
    required SupabaseClient client,
    required AppAccessService appAccessService,
    Telephony? telephony,
    MomoSmsIngestionRepository? ingestionRepository,
    CrashlyticsService? crashlytics,
    OperationalHealthService? operationalHealthService,
  }) : _client = client,
       _appAccessService = appAccessService,
       _telephony = telephony ?? Telephony.instance,
       _ingestionRepository =
           ingestionRepository ??
           MomoSmsIngestionRepository(client: client),
       _crashlytics = crashlytics,
       _operationalHealthService =
           operationalHealthService ??
           OperationalHealthService(client: client);

  final SupabaseClient _client;
  final AppAccessService _appAccessService;
  final Telephony _telephony;
  final MomoSmsIngestionRepository _ingestionRepository;
  final CrashlyticsService? _crashlytics;
  final OperationalHealthService _operationalHealthService;

  static const _inboxRecoveryCooldown = Duration(minutes: 2);
  // Keep historical inbox access narrowly scoped to recent M-Money recovery.
  static const _inboxRecoveryLookback = Duration(days: 7);
  static const _maxRecoveryMessages = 100;

  bool _isListening = false;
  bool _isRecoveringInbox = false;
  bool _requestedPermissionThisLaunch = false;
  DateTime? _lastInboxRecoveryAt;
  String? _activeUserId;

  Future<void> refresh({bool forcePermissionRequest = false}) async {
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
      unawaited(
        _operationalHealthService.recordEvent(
          service: 'sms_ingest',
          component: 'android_sms_autoread',
          message: 'Android SMS autoread activated.',
          userId: session.user.id,
          metadata: const <String, dynamic>{'mode': 'incoming_listener'},
        ),
      );
    }

    unawaited(_recoverRecentInbox());
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

  Future<bool> _ensureSmsPermission({required bool forceRequest}) async {
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

  Future<void> _recoverRecentInbox() async {
    if (_isRecoveringInbox) {
      return;
    }

    final lastRecoveryAt = _lastInboxRecoveryAt;
    final now = DateTime.now().toUtc();
    if (lastRecoveryAt != null &&
        now.difference(lastRecoveryAt) < _inboxRecoveryCooldown) {
      return;
    }

    _isRecoveringInbox = true;
    _lastInboxRecoveryAt = now;

    try {
      final messages = await _telephony.getInboxSms(
        columns: const [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
        filter: _approvedSenderFilter(),
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      );

      final cutoff = now.subtract(_inboxRecoveryLookback);
      var processedMessages = 0;
      for (final message in messages) {
        if (processedMessages >= _maxRecoveryMessages) {
          break;
        }

        final capture = MomoSmsIngestionRepository.captureFromDeviceMessage(
          sender: message.address,
          body: message.body,
          timestampMillis: message.date,
          ingestionSource: 'android_sms_inbox_recovery',
        );
        if (capture == null) {
          continue;
        }
        if (capture.receivedAt.isBefore(cutoff)) {
          break;
        }

        processedMessages += 1;
        await _ingestionRepository.ingestCapture(capture: capture);
      }

      await _crashlytics?.log(
        'momo_sms: recovered $processedMessages inbox messages',
      );
      if (processedMessages > 0) {
        await _operationalHealthService.recordEvent(
          service: 'sms_ingest',
          component: 'android_sms_inbox_recovery',
          message: 'Recovered recent MoMo SMS messages from inbox.',
          userId: _activeUserId,
          metadata: <String, dynamic>{'processed_messages': processedMessages},
        );
      }
    } catch (error, stackTrace) {
      await _crashlytics?.recordError(
        error,
        stackTrace: stackTrace,
        reason: 'momo_sms_inbox_recovery_failed',
      );
      await _operationalHealthService.recordEvent(
        service: 'sms_ingest',
        component: 'android_sms_inbox_recovery',
        status: OperationalHealthStatus.error,
        issueCode: 'sms_inbox_recovery_failed',
        message: 'Failed to recover MoMo SMS messages from inbox.',
        userId: _activeUserId,
        metadata: <String, dynamic>{'error': error.toString()},
      );
    } finally {
      _isRecoveringInbox = false;
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
      await _operationalHealthService.recordEvent(
        service: 'sms_ingest',
        component: 'android_sms_autoread',
        status: OperationalHealthStatus.error,
        issueCode: 'sms_ingestion_failed',
        message: 'Incoming MoMo SMS ingestion failed.',
        userId: _activeUserId,
        metadata: <String, dynamic>{
          'sender': message.address,
          'ingestion_source': ingestionSource,
          'error': error.toString(),
        },
      );
    }
  }

  SmsFilter? _approvedSenderFilter() {
    final senderPatterns =
        MomoSmsIngestionRepository.approvedInboxSenderLikePatterns;

    SmsFilter? filter;
    for (final senderPattern in senderPatterns) {
      filter = filter == null
          ? SmsFilter.where(SmsColumn.ADDRESS).like(senderPattern)
          : filter.or(SmsColumn.ADDRESS).like(senderPattern);
    }
    return filter;
  }

  bool get _supportsSmsAutoread {
    if (kIsWeb) {
      return false;
    }
    return Platform.isAndroid;
  }
}

class _MomoSmsBackgroundProcessor {
  static bool _hiveInitialized = false;
  static bool _supabaseInitialized = false;
  static final InitializeHive _initializeHive = initializeHiveRuntime;
  static final OpenHiveBox<bool> _openAppAccessBox = openHiveBox<bool>;

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
