import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/momo_sms_sync_status.dart';

class MomoSmsSyncStatusRepository {
  MomoSmsSyncStatusRepository({required SupabaseClient client})
    : _client = client;

  final SupabaseClient _client;

  Future<MomoSmsSyncStatus> loadStatus(String userId) async {
    if (userId.trim().isEmpty) {
      return const MomoSmsSyncStatus();
    }

    try {
      final rows = await _client
          .from('momo_sms_sync_runs')
          .select(
            'id, trigger, status, lookback_days, incremental, scan_started_at, '
            'scan_completed_at, scanned_messages, uploaded_messages, '
            'duplicate_messages, oldest_message_at, newest_message_at, '
            'latest_known_message_at, error_message',
          )
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(20);

      return MomoSmsSyncStatus.fromRows(_asListOfMaps(rows));
    } catch (error) {
      debugPrint('[MoMo SMS] sync status unavailable: $error');
      return const MomoSmsSyncStatus();
    }
  }
}

List<Map<String, dynamic>> _asListOfMaps(dynamic value) {
  if (value is! List) {
    return const <Map<String, dynamic>>[];
  }

  return value
      .whereType<Map<dynamic, dynamic>>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList(growable: false);
}
