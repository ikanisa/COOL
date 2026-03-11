import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/momo_sms_parser.dart';

class MomoSmsIngestionResult {
  const MomoSmsIngestionResult({
    required this.rawSmsId,
    required this.deviceMessageKey,
    required this.alreadyExisted,
    required this.parseRequested,
  });

  final String rawSmsId;
  final String deviceMessageKey;
  final bool alreadyExisted;
  final bool parseRequested;
}

class MomoSmsIngestionRepository {
  MomoSmsIngestionRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<MomoSmsIngestionResult?> ingestTransaction(
    MomoTransaction transaction,
  ) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return null;
    }

    final deviceMessageKey = buildDeviceMessageKey(transaction);

    final existing = await _client
        .from('momo_sms_raw')
        .select('id, parse_status')
        .eq('user_id', userId)
        .eq('device_message_key', deviceMessageKey)
        .maybeSingle();

    if (existing != null) {
      final rawSmsId = existing['id']?.toString() ?? '';
      final parseStatus = existing['parse_status']?.toString() ?? 'pending';
      final parseRequested = await _requestParseIfNeeded(
        rawSmsId: rawSmsId,
        parseStatus: parseStatus,
      );
      return MomoSmsIngestionResult(
        rawSmsId: rawSmsId,
        deviceMessageKey: deviceMessageKey,
        alreadyExisted: true,
        parseRequested: parseRequested,
      );
    }

    final inserted = await _client
        .from('momo_sms_raw')
        .insert(<String, dynamic>{
          'user_id': userId,
          'device_message_key': deviceMessageKey,
          'sender': transaction.sender,
          'sms_body': transaction.rawMessage,
          'provider': transaction.provider,
          'country': transaction.country,
          'sms_received_at': transaction.receivedAt.toIso8601String(),
          // These are device-side heuristic hints only. The canonical parse
          // happens in the backend AI pipeline (`parse-momo-sms`).
          'detected_tx_type': transaction.type.name,
          'detected_amount': transaction.amountRwf,
          'detected_tx_id': transaction.transactionId,
          'ingestion_source': 'android_sms_listener',
          'parse_status': 'pending',
        })
        .select('id')
        .single();

    final rawSmsId = inserted['id']?.toString() ?? '';
    final parseRequested = await _requestParseIfNeeded(
      rawSmsId: rawSmsId,
      parseStatus: 'pending',
    );

    return MomoSmsIngestionResult(
      rawSmsId: rawSmsId,
      deviceMessageKey: deviceMessageKey,
      alreadyExisted: false,
      parseRequested: parseRequested,
    );
  }

  String buildDeviceMessageKey(MomoTransaction transaction) {
    final id = transaction.transactionId?.trim();
    if (id != null && id.isNotEmpty) {
      return 'id:${transaction.provider}:$id';
    }

    return 'raw:${transaction.provider}:${transaction.rawMessage.trim()}';
  }

  Future<bool> _requestParseIfNeeded({
    required String rawSmsId,
    required String parseStatus,
  }) async {
    if (rawSmsId.isEmpty) {
      return false;
    }

    if (parseStatus == 'processing' || parseStatus == 'parsed') {
      return false;
    }

    try {
      // The edge function performs the AI-backed parse with server-side keys.
      await _client.functions.invoke(
        'parse-momo-sms',
        body: <String, dynamic>{'rawSmsId': rawSmsId},
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
