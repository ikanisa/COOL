part of 'momo_sms_autoread_service.dart';

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

    final capture = MomoSmsIngestionRepository.captureFromDeviceMessage(
      sender: message.address,
      body: message.body,
      timestampMillis: message.date,
      ingestionSource: 'android_sms_listener_background',
    );
    if (capture == null) {
      SupabaseClient? driftClient;
      try {
        driftClient = await _ensureSupabaseClient();
      } catch (_) {
        return;
      }
      if (driftClient != null) {
        await _reportBackgroundSenderDriftIfNeeded(
          client: driftClient,
          sender: message.address,
          body: message.body,
        );
      }
      return;
    }

    try {
      final box = await _openRetryQueueBox(_retryQueueBoxName);
      if (box.length < _retryQueueMaxSize) {
        final payload = jsonEncode({
          'sender': capture.sender,
          'body': capture.body,
          'deviceMessageKey': capture.deviceMessageKey,
          'receivedAt': capture.receivedAt.toUtc().toIso8601String(),
          'ingestionSource': capture.ingestionSource,
        });
        await box.put(capture.deviceMessageKey, payload);
      }
    } catch (_) {
      // Continue with ingestion attempt even if the pre-queue write fails.
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

    try {
      final repository = MomoSmsIngestionRepository(client: client);
      await repository.ingestCapture(capture: capture);

      try {
        final box = await _openRetryQueueBox(_retryQueueBoxName);
        await box.delete(capture.deviceMessageKey);
      } catch (_) {
        // The retry drain path will de-duplicate this later.
      }
    } catch (error) {
      debugPrint(
        '[MoMo SMS] background ingestion failed, capture already queued '
        'for retry: $error',
      );
      try {
        final box = await _openRetryQueueBox(_retryQueueBoxName);
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
      } catch (queueError) {
        debugPrint('[MoMo SMS] retry queue telemetry failed: $queueError');
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
