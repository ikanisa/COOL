import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/app_logger.dart';
import '../../../core/utils/supabase_query_helpers.dart' as sq;
import '../models/momo_sms_sync_status.dart';

const _log = AppLogger('MoMoSMS');

class MomoSmsSyncStatusRepository {
  MomoSmsSyncStatusRepository({required SupabaseClient client})
    : _client = client;

  final SupabaseClient _client;

  Future<MomoSmsSyncStatus> loadStatus(String userId) async {
    if (userId.trim().isEmpty) {
      return const MomoSmsSyncStatus();
    }

    try {
      final rows = await sq.guarded(
        () => _client
            .from('momo_sms_sync_runs')
            .select(
              'id, trigger, status, lookback_days, incremental, scan_started_at, '
              'scan_completed_at, scanned_messages, uploaded_messages, '
              'duplicate_messages, oldest_message_at, newest_message_at, '
              'latest_known_message_at, error_message',
            )
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(20),
        label: 'momoSmsSyncStatus',
      );

      return MomoSmsSyncStatus.fromRows(sq.asListOfMaps(rows));
    } catch (error) {
      _log.warn('Sync status unavailable: $error');
      return const MomoSmsSyncStatus();
    }
  }
}

// Local _asListOfMaps removed — now using shared `sq.asListOfMaps` from
// core/utils/supabase_query_helpers.dart
