import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MomoSmsCapture {
  const MomoSmsCapture({
    required this.sender,
    required this.body,
    required this.receivedAt,
    required this.deviceMessageKey,
    required this.ingestionSource,
  });

  final String sender;
  final String body;
  final DateTime receivedAt;
  final String deviceMessageKey;
  final String ingestionSource;
}

class MomoSmsIngestionResult {
  const MomoSmsIngestionResult({
    required this.rawSmsId,
    required this.inserted,
    required this.parseQueued,
    this.otpWhatsAppNumber,
  });

  final String rawSmsId;
  final bool inserted;
  final bool parseQueued;
  final String? otpWhatsAppNumber;
}

class MomoSmsIngestionRepository {
  MomoSmsIngestionRepository({required SupabaseClient client})
    : _client = client;

  final SupabaseClient _client;

  static const approvedInboxSenderIds = <String>[
    'M-Money',
    'M-Money Alerts',
    'M Money',
    'MobileMoney',
    'Mobile Money',
    'MoMo',
    'MoMo Alerts',
    'MOMO',
    'MTN MoMo',
    'MTN MOMO',
    'MTN MoMo Rwanda',
  ];

  static const _normalizedApprovedSenderTokens = <String>{
    'mmoney',
    'mmoneyalerts',
    'mobilemoney',
    'momo',
    'momoalerts',
    'mtnmomo',
    'mtnmomorwanda',
  };

  static const approvedInboxSenderLikePatterns = <String>[
    '%M-Money%',
    '%M Money%',
    '%MobileMoney%',
    '%Mobile Money%',
    '%MoMo%',
    '%MOMO%',
    '%MTN MoMo%',
    '%MTN MOMO%',
  ];

  String? get currentUserId => _client.auth.currentUser?.id;

  static bool isApprovedSender(String? sender) {
    final normalizedSender = _normalizeSender(sender);
    if (normalizedSender.isEmpty) {
      return false;
    }
    // Strict exact match against normalized tokens to avoid false positives 
    // and maintain compliance with declared Play Store SMS sender policies.
    return _normalizedApprovedSenderTokens.contains(normalizedSender);
  }

  static MomoSmsCapture? captureFromDeviceMessage({
    required String? sender,
    required String? body,
    int? timestampMillis,
    String ingestionSource = 'android_sms_listener',
  }) {
    final trimmedSender = sender?.trim() ?? '';
    final trimmedBody = _normalizeWhitespace(body ?? '');
    if (trimmedBody.isEmpty || !isApprovedSender(trimmedSender)) {
      return null;
    }

    final receivedAt = _timestampToUtc(timestampMillis);
    return MomoSmsCapture(
      sender: trimmedSender,
      body: trimmedBody,
      receivedAt: receivedAt,
      deviceMessageKey: buildDeviceMessageKey(
        sender: trimmedSender,
        body: trimmedBody,
        receivedAt: receivedAt,
      ),
      ingestionSource: ingestionSource,
    );
  }

  static String buildDeviceMessageKey({
    required String sender,
    required String body,
    required DateTime receivedAt,
  }) {
    final normalizedSender = _normalizeSender(sender);
    final normalizedBody = _normalizeWhitespace(body);
    final payload =
        '$normalizedSender|${receivedAt.toUtc().toIso8601String()}|'
        '$normalizedBody';
    return sha256.convert(utf8.encode(payload)).toString();
  }

  Future<MomoSmsIngestionResult?> ingestCapture({
    required MomoSmsCapture capture,
    String? userId,
  }) async {
    final resolvedUserId = userId ?? currentUserId;
    if (resolvedUserId == null || resolvedUserId.isEmpty) {
      return null;
    }

    final response = await _client.functions.invoke(
      'sms-ingest',
      body: <String, dynamic>{
        'sender': capture.sender,
        'smsBody': capture.body,
        'smsReceivedAt': capture.receivedAt.toIso8601String(),
        'deviceMessageKey': capture.deviceMessageKey,
        'ingestionSource': capture.ingestionSource,
      },
    );

    final data = response.data;
    if (data is Map && data['success'] == false) {
      throw StateError(
        data['message']?.toString() ?? 'Failed to ingest M-Money SMS.',
      );
    }
    if (data is! Map) {
      throw const FormatException('Unexpected sms-ingest response payload.');
    }

    final rawSmsId = data['rawSmsId']?.toString();
    if (rawSmsId == null || rawSmsId.isEmpty) {
      return null;
    }

    return MomoSmsIngestionResult(
      rawSmsId: rawSmsId,
      inserted: data['inserted'] == true,
      parseQueued: data['parseQueued'] == true,
      otpWhatsAppNumber: _emptyToNull(data['otpWhatsAppNumber']?.toString()),
    );
  }

  static DateTime _timestampToUtc(int? timestampMillis) {
    if (timestampMillis == null || timestampMillis <= 0) {
      return DateTime.now().toUtc();
    }
    return DateTime.fromMillisecondsSinceEpoch(timestampMillis, isUtc: true);
  }

  static String _normalizeSender(String? value) {
    final sender = value?.toLowerCase().trim() ?? '';
    return sender.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static String _normalizeWhitespace(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String? _emptyToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
