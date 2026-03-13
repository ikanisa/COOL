import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/operational_health_service.dart';

class MomoSmsCapture {
  const MomoSmsCapture({
    required this.sender,
    required this.body,
    required this.receivedAt,
    required this.deviceMessageKey,
    required this.ingestionSource,
    this.provider,
    this.country,
    this.detectedTxType,
    this.detectedAmount,
    this.detectedTxId,
  });

  final String sender;
  final String body;
  final DateTime receivedAt;
  final String deviceMessageKey;
  final String ingestionSource;
  final String? provider;
  final String? country;
  final String? detectedTxType;
  final int? detectedAmount;
  final String? detectedTxId;
}

class MomoSmsIngestionResult {
  const MomoSmsIngestionResult({
    required this.rawSmsId,
    required this.inserted,
    required this.parseQueued,
  });

  final String rawSmsId;
  final bool inserted;
  final bool parseQueued;
}

class MomoSmsIngestionRepository {
  MomoSmsIngestionRepository({
    required SupabaseClient client,
    OperationalHealthService? operationalHealthService,
  }) : _client = client,
       _operationalHealthService =
           operationalHealthService ??
           OperationalHealthService(client: client);

  final SupabaseClient _client;
  final OperationalHealthService _operationalHealthService;

  static const approvedInboxSenderIds = <String>[
    'M-Money',
    'M Money',
    'MobileMoney',
    'Mobile Money',
    'MoMo',
    'MOMO',
    'MTN MoMo',
    'MTN MOMO',
  ];

  static const _normalizedApprovedSenderTokens = <String>{
    'mmoney',
    'mobilemoney',
    'momo',
    'mtnmomo',
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
    return _normalizedApprovedSenderTokens.any(
      (token) => normalizedSender == token || normalizedSender.contains(token),
    );
  }

  static MomoSmsCapture? captureFromDeviceMessage({
    required String? sender,
    required String? body,
    int? timestampMillis,
    String? provider,
    String? country,
    String ingestionSource = 'android_sms_listener',
  }) {
    final trimmedSender = sender?.trim() ?? '';
    final trimmedBody = _normalizeWhitespace(body ?? '');
    final approvedSender = isApprovedSender(trimmedSender);
    if (trimmedBody.isEmpty || !approvedSender) {
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
      provider: _emptyToNull(provider),
      country: _emptyToNull(country),
      ingestionSource: ingestionSource,
      detectedTxType: _detectTransactionType(trimmedBody),
      detectedAmount: _detectAmount(trimmedBody),
      detectedTxId: _detectTransactionId(trimmedBody),
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

  static bool looksLikeTransactionMessage(String body) {
    final normalized = body.toLowerCase();
    final transactionSignals = <String>[
      'payment',
      'paid',
      'received',
      'withdraw',
      'cash power',
      'airtime',
      'bundle',
      'transfer',
      'transferred',
      'merchant',
      'confirmed',
      'txid',
      'transaction id',
      'reference',
      'ref:',
    ];
    return transactionSignals.any(normalized.contains);
  }

  Future<MomoSmsIngestionResult?> ingestCapture({
    required MomoSmsCapture capture,
    String? userId,
  }) async {
    final resolvedUserId = userId ?? currentUserId;
    if (resolvedUserId == null || resolvedUserId.isEmpty) {
      return null;
    }

    final existing = await _client
        .from('momo_sms_raw')
        .select('id, parse_status')
        .eq('user_id', resolvedUserId)
        .eq('device_message_key', capture.deviceMessageKey)
        .maybeSingle();

    if (existing != null) {
      final existingId = existing['id']?.toString();
      if (existingId == null || existingId.isEmpty) {
        return null;
      }
      final parseQueued = await _queueParseIfNeeded(
        rawSmsId: existingId,
        parseStatus: existing['parse_status']?.toString(),
      );
      return MomoSmsIngestionResult(
        rawSmsId: existingId,
        inserted: false,
        parseQueued: parseQueued,
      );
    }

    final inserted = await _client
        .from('momo_sms_raw')
        .insert(<String, dynamic>{
          'user_id': resolvedUserId,
          'device_message_key': capture.deviceMessageKey,
          'sender': capture.sender,
          'sms_body': capture.body,
          'provider': capture.provider,
          'country': capture.country,
          'sms_received_at': capture.receivedAt.toIso8601String(),
          'detected_tx_type': capture.detectedTxType,
          'detected_amount': capture.detectedAmount,
          'detected_tx_id': capture.detectedTxId,
          'ingestion_source': capture.ingestionSource,
          'parse_status': 'pending',
        })
        .select('id')
        .single();

    final rawSmsId = inserted['id']?.toString();
    if (rawSmsId == null || rawSmsId.isEmpty) {
      return null;
    }

    bool parseQueued;
    try {
      parseQueued = await _queueParseIfNeeded(rawSmsId: rawSmsId);
    } catch (error) {
      await _operationalHealthService.recordEvent(
        service: 'sms_ingest',
        component: 'momo_sms_ingestion',
        status: OperationalHealthStatus.error,
        issueCode: 'parse_queue_failed',
        message: 'MoMo SMS was captured, but parse queueing failed.',
        userId: resolvedUserId,
        subjectType: 'momo_sms_raw',
        subjectId: rawSmsId,
        metadata: <String, dynamic>{
          'ingestion_source': capture.ingestionSource,
          'sender': capture.sender,
          'error': error.toString(),
        },
      );
      rethrow;
    }

    await _operationalHealthService.recordEvent(
      service: 'sms_ingest',
      component: 'momo_sms_ingestion',
      status: parseQueued
          ? OperationalHealthStatus.ok
          : OperationalHealthStatus.warn,
      severity: parseQueued
          ? OperationalHealthSeverity.info
          : OperationalHealthSeverity.warning,
      issueCode: parseQueued ? null : 'parse_queue_skipped',
      message: parseQueued
          ? 'MoMo SMS captured and parse queued.'
          : 'MoMo SMS captured, but parse queueing was skipped.',
      userId: resolvedUserId,
      subjectType: 'momo_sms_raw',
      subjectId: rawSmsId,
      metadata: <String, dynamic>{
        'ingestion_source': capture.ingestionSource,
        'sender': capture.sender,
        'provider': capture.provider,
        'country': capture.country,
      },
    );

    return MomoSmsIngestionResult(
      rawSmsId: rawSmsId,
      inserted: true,
      parseQueued: parseQueued,
    );
  }

  Future<bool> _queueParseIfNeeded({
    required String rawSmsId,
    String? parseStatus,
  }) async {
    final normalizedParseStatus = (parseStatus ?? 'pending').trim();
    if (normalizedParseStatus == 'processing' ||
        normalizedParseStatus == 'parsed' ||
        normalizedParseStatus == 'ignored') {
      return false;
    }

    final response = await _client.functions.invoke(
      'parse-momo-sms',
      body: <String, dynamic>{'rawSmsId': rawSmsId},
    );

    final data = response.data;
    if (data is Map && data['success'] == false) {
      throw StateError(
        data['message']?.toString() ??
            'Failed to queue M-Money SMS parsing for $rawSmsId.',
      );
    }
    return true;
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

  static String? _detectTransactionType(String body) {
    final normalized = body.toLowerCase();
    if (normalized.contains('cash power')) {
      return 'cash_power';
    }
    if (normalized.contains('withdraw')) {
      return 'withdrawal';
    }
    if (normalized.contains('bank transfer') ||
        normalized.contains('transferred')) {
      return 'transfer';
    }
    if (normalized.contains('airtime') || normalized.contains('bundle')) {
      return 'airtime';
    }
    if (normalized.contains('received')) {
      return 'cash_in';
    }
    if (normalized.contains('payment')) {
      return 'payment';
    }
    return null;
  }

  static int? _detectAmount(String body) {
    final patterns = <RegExp>[
      RegExp(
        r'(?:payment of|received|withdraw(?:al)? of|airtime of|cash power of|transfer(?:red)? of)\s*([0-9][0-9,.\s]*)',
        caseSensitive: false,
      ),
      RegExp(
        r'([0-9][0-9,.\s]*)\s*(?:RWF|FRW)',
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(body);
      final rawAmount = match?.group(1);
      if (rawAmount == null || rawAmount.isEmpty) {
        continue;
      }

      final digitsOnly = rawAmount.replaceAll(RegExp(r'[^0-9]'), '');
      final parsed = int.tryParse(digitsOnly);
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }

    return null;
  }

  static String? _detectTransactionId(String body) {
    final match = RegExp(
      r'(?:ft(?:\s+id)?|tx(?:n|id)?|transaction(?:\s+id)?|ref(?:erence)?)'
      r'[^A-Za-z0-9]{0,6}([A-Za-z0-9-]{4,})',
      caseSensitive: false,
    ).firstMatch(body);
    final txId = match?.group(1)?.trim();
    return txId == null || txId.isEmpty ? null : txId;
  }
}
