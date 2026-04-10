import 'package:flutter/services.dart';

class MomoSmsNativePipelineConfig {
  const MomoSmsNativePipelineConfig({
    required this.enabled,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    this.userId,
    this.accessToken,
    this.refreshToken,
    this.accessTokenExpiresAtEpochSeconds,
    this.approvedSenders,
  });

  final bool enabled;
  final String supabaseUrl;
  final String supabaseAnonKey;
  final String? userId;
  final String? accessToken;
  final String? refreshToken;
  final int? accessTokenExpiresAtEpochSeconds;
  final List<String>? approvedSenders;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'enabled': enabled,
      'userId': userId,
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'accessTokenExpiresAtEpochSeconds': accessTokenExpiresAtEpochSeconds,
      'supabaseUrl': supabaseUrl,
      'supabaseAnonKey': supabaseAnonKey,
      'approvedSenders': approvedSenders,
    };
  }
}

class MomoSmsNativeQueueStatus {
  const MomoSmsNativeQueueStatus({
    this.pendingCount = 0,
    this.failedCount = 0,
    this.syncedCount = 0,
    this.totalCount = 0,
  });

  final int pendingCount;
  final int failedCount;
  final int syncedCount;
  final int totalCount;

  factory MomoSmsNativeQueueStatus.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      return const MomoSmsNativeQueueStatus();
    }
    return MomoSmsNativeQueueStatus(
      pendingCount: _asInt(map['pendingCount']),
      failedCount: _asInt(map['failedCount']),
      syncedCount: _asInt(map['syncedCount']),
      totalCount: _asInt(map['totalCount']),
    );
  }
}

class MomoSmsNativeSyncOutcome {
  const MomoSmsNativeSyncOutcome({
    this.uploadedMessages = 0,
    this.duplicateMessages = 0,
    this.failedMessages = 0,
    this.rateLimited = false,
    this.lastError,
  });

  final int uploadedMessages;
  final int duplicateMessages;
  final int failedMessages;
  final bool rateLimited;
  final String? lastError;

  factory MomoSmsNativeSyncOutcome.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      return const MomoSmsNativeSyncOutcome();
    }
    return MomoSmsNativeSyncOutcome(
      uploadedMessages: _asInt(map['uploadedMessages']),
      duplicateMessages: _asInt(map['duplicateMessages']),
      failedMessages: _asInt(map['failedMessages']),
      rateLimited: _asBool(map['rateLimited']),
      lastError: map['lastError']?.toString(),
    );
  }
}

class MomoSmsNativeInboxSyncResult {
  const MomoSmsNativeInboxSyncResult({
    this.scannedMessages = 0,
    this.uploadedMessages = 0,
    this.duplicateMessages = 0,
    this.queuedMessages = 0,
    this.oldestMessageAt,
    this.newestMessageAt,
    this.rateLimited = false,
  });

  final int scannedMessages;
  final int uploadedMessages;
  final int duplicateMessages;
  final int queuedMessages;
  final DateTime? oldestMessageAt;
  final DateTime? newestMessageAt;
  final bool rateLimited;

  factory MomoSmsNativeInboxSyncResult.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      return const MomoSmsNativeInboxSyncResult();
    }
    return MomoSmsNativeInboxSyncResult(
      scannedMessages: _asInt(map['scannedMessages']),
      uploadedMessages: _asInt(map['uploadedMessages']),
      duplicateMessages: _asInt(map['duplicateMessages']),
      queuedMessages: _asInt(map['queuedMessages']),
      oldestMessageAt: _parseDate(map['oldestMessageAt']),
      newestMessageAt: _parseDate(map['newestMessageAt']),
      rateLimited: _asBool(map['rateLimited']),
    );
  }
}

class MomoSmsNativeBridge {
  MomoSmsNativeBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('app.cool.mobile/momo_sms');

  final MethodChannel _channel;

  Future<void> configure(MomoSmsNativePipelineConfig config) async {
    await _channel.invokeMethod<void>('configurePipeline', config.toMap());
  }

  Future<void> clearSession() async {
    await _channel.invokeMethod<void>('clearPipelineSession');
  }

  Future<MomoSmsNativeQueueStatus> getQueueStatus() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getQueueStatus',
    );
    return MomoSmsNativeQueueStatus.fromMap(raw);
  }

  Future<MomoSmsNativeSyncOutcome> syncPendingNow() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'syncPendingNow',
    );
    return MomoSmsNativeSyncOutcome.fromMap(raw);
  }

  Future<MomoSmsNativeInboxSyncResult> syncInbox({
    required DateTime cutoff,
    required String trigger,
  }) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'syncInbox',
      <String, dynamic>{
        'cutoffIso': cutoff.toUtc().toIso8601String(),
        'trigger': trigger,
      },
    );
    return MomoSmsNativeInboxSyncResult.fromMap(raw);
  }
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

bool _asBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  final raw = value?.toString().toLowerCase();
  return raw == 'true' || raw == '1';
}

DateTime? _parseDate(Object? value) {
  final raw = value?.toString();
  if (raw == null || raw.trim().isEmpty) {
    return null;
  }
  return DateTime.tryParse(raw)?.toUtc();
}
