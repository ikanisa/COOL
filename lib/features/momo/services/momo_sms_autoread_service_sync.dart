part of 'momo_sms_autoread_service.dart';

extension _MomoSmsAutoreadServiceSync on MomoSmsAutoreadService {
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
      await _syncInboxInternal(
        trigger: MomoInboxSyncTrigger.initialPermissionGrant,
      );
    } catch (error, stackTrace) {
      _initialSyncScheduledForUserId = null;
      await _crashlytics?.recordError(
        error,
        stackTrace: stackTrace,
        reason: 'momo_sms_initial_inbox_sync_failed',
      );
    }
  }

  Future<MomoInboxSyncResult> _syncInboxInternal({
    required MomoInboxSyncTrigger trigger,
    ValueChanged<int>? onProgress,
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
    final historicalCutoff = scanStartedAt.subtract(
      MomoSmsAutoreadService._initialInboxSyncLookback,
    );

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

    if (isReinstallRecovery) {
      await _crashlytics?.log(
        'momo_sms: reinstall recovery detected, forcing full 365-day scan',
      );
    }

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
        onProgress?.call(scannedMessages);
        oldestMessageAt = _olderOf(oldestMessageAt, capture.receivedAt);
        newestMessageAt = _newerOf(newestMessageAt, capture.receivedAt);

        try {
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
        } on MomoSmsRateLimitException {
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
            scannedMessages: scannedMessages,
            uploadedMessages: uploadedMessages,
            duplicateMessages: duplicateMessages,
            oldestMessageAt: oldestMessageAt,
            newestMessageAt: newestMessageAt,
            latestKnownMessageAt: _newerOf(
              syncState.latestKnownMessageAt,
              newestMessageAt,
            ),
            errorMessage: 'Rate-limited after $scannedMessages messages',
          );
          await _crashlytics?.log(
            'momo_sms: rate-limited after $scannedMessages messages '
            '(uploaded=$uploadedMessages)',
          );
          return MomoInboxSyncResult(
            scannedMessages: scannedMessages,
            uploadedMessages: uploadedMessages,
            duplicateMessages: duplicateMessages,
            oldestMessageAt: oldestMessageAt,
            newestMessageAt: newestMessageAt,
            incremental: incremental,
          );
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

    final perSenderResults = await Future.wait(
      senderIds.map((senderId) async {
        final filter = SmsFilter.where(SmsColumn.ADDRESS)
            .equals(senderId)
            .and(SmsColumn.DATE)
            .greaterThanOrEqualTo(cutoffMillis);
        return _telephony.getInboxSms(
          columns: const [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
          filter: filter,
          sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
        );
      }),
    );

    final messages = perSenderResults.expand((m) => m).toList()
      ..sort((a, b) => (b.date ?? 0).compareTo(a.date ?? 0));
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
    return _recordMomoSmsSyncRun(
      this,
      userId: userId,
      trigger: trigger,
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
    );
  }

  Future<void> _queueRetryCapture(MomoSmsCapture capture) {
    return _queueMomoSmsRetryCapture(this, capture);
  }

  DateTime? _olderOf(DateTime? left, DateTime? right) {
    return _olderMomoSmsTimestamp(left, right);
  }

  DateTime? _newerOf(DateTime? left, DateTime? right) {
    return _newerMomoSmsTimestamp(left, right);
  }

  Future<void> _reportSenderDriftIfNeeded({
    required String? sender,
    required String? body,
    required String ingestionSource,
  }) async {
    return _reportMomoSenderDriftIfNeeded(
      this,
      sender: sender,
      body: body,
      ingestionSource: ingestionSource,
    );
  }

  Future<void> _reportRetryQueueDrain({
    required int queuedBefore,
    required int queuedAfter,
  }) async {
    return _reportMomoRetryQueueDrain(
      this,
      queuedBefore: queuedBefore,
      queuedAfter: queuedAfter,
    );
  }
}
