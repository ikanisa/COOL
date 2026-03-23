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

  static bool looksLikePotentialMomoTransactionalBody(String? body) {
    final normalizedBody = _normalizeWhitespace(body ?? '').toLowerCase();
    if (normalizedBody.isEmpty) {
      return false;
    }

    final hasCurrencySignal =
        normalizedBody.contains('rwf') ||
        normalizedBody.contains('frw') ||
        RegExp(r'\b\d[\d,.\s]*\s*(rwf|frw)\b').hasMatch(normalizedBody);
    if (!hasCurrencySignal) {
      return false;
    }

    final hasTxReference = _hasTxReferenceSignal(normalizedBody);
    final hasBalanceSignal = _hasBalanceSignal(normalizedBody);
    final hasFeeSignal = _hasFeeSignal(normalizedBody);
    final hasOutcomeSignal = _hasOutcomeSignal(normalizedBody);
    final hasBrandSignal = _hasBrandSignal(normalizedBody);

    return (hasTxReference &&
            (hasBalanceSignal || hasFeeSignal || hasOutcomeSignal)) ||
        (hasBrandSignal && hasBalanceSignal && hasOutcomeSignal);
  }

  static Map<String, dynamic>? senderDriftTelemetry({
    required String? sender,
    required String? body,
  }) {
    final trimmedSender = sender?.trim() ?? '';
    final normalizedBody = _normalizeWhitespace(body ?? '');
    if (trimmedSender.isEmpty ||
        normalizedBody.isEmpty ||
        isApprovedSender(trimmedSender) ||
        !looksLikePotentialMomoTransactionalBody(normalizedBody)) {
      return null;
    }

    final lowercaseBody = normalizedBody.toLowerCase();
    final senderKind = RegExp(r'^\+?\d+$').hasMatch(trimmedSender)
        ? 'msisdn'
        : 'alias';
    final hasTxReference = _hasTxReferenceSignal(lowercaseBody);
    final hasBalanceSignal = _hasBalanceSignal(lowercaseBody);
    final hasFeeSignal = _hasFeeSignal(lowercaseBody);
    final hasOutcomeSignal = _hasOutcomeSignal(lowercaseBody);
    final hasBrandSignal = _hasBrandSignal(lowercaseBody);
    return <String, dynamic>{
      'sender_display': trimmedSender,
      'sender_token': _normalizeSender(trimmedSender),
      'sender_kind': senderKind,
      'message_length': normalizedBody.length,
      'has_tx_reference': hasTxReference,
      'contains_txid': lowercaseBody.contains('txid'),
      'contains_balance': hasBalanceSignal,
      'contains_fee_signal': hasFeeSignal,
      'contains_outcome_signal': hasOutcomeSignal,
      'contains_brand_signal': hasBrandSignal,
      'signal_count': [
        hasTxReference,
        hasBalanceSignal,
        hasFeeSignal,
        hasOutcomeSignal,
        hasBrandSignal,
      ].where((value) => value).length,
      'contains_rwf':
          lowercaseBody.contains('rwf') || lowercaseBody.contains('frw'),
    };
  }

  static bool _hasTxReferenceSignal(String normalizedBody) {
    return normalizedBody.contains('txid') ||
        normalizedBody.contains('financial transaction') ||
        normalizedBody.contains('ft id');
  }

  static bool _hasBalanceSignal(String normalizedBody) {
    return normalizedBody.contains('new balance') ||
        normalizedBody.contains('balance:') ||
        normalizedBody.contains('balance ');
  }

  static bool _hasFeeSignal(String normalizedBody) {
    return normalizedBody.contains('fee was') ||
        normalizedBody.contains('fee:');
  }

  static bool _hasOutcomeSignal(String normalizedBody) {
    return normalizedBody.contains('payment of') ||
        normalizedBody.contains('you have received') ||
        normalizedBody.contains('withdrawn') ||
        normalizedBody.contains('transferred') ||
        normalizedBody.contains('bank deposit') ||
        normalizedBody.contains('cash power') ||
        normalizedBody.contains('bundle');
  }

  static bool _hasBrandSignal(String normalizedBody) {
    return normalizedBody.contains('momo') ||
        normalizedBody.contains('mobile money') ||
        normalizedBody.contains('m-money');
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
