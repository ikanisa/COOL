import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/supabase_query_helpers.dart' as sq;
import '../models/nexus_recommendation.dart';

/// Data access for the `ai_content` table.
///
/// Public-facing methods return only `approved + active` content.
/// Admin methods operate on all statuses.
class NexusRepository {
  NexusRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;
  static const _table = 'ai_content';

  // ── Public-facing ─────────────────────────────────────────

  /// Fetch approved + active recommendations, optionally filtered by country.
  Future<List<NexusRecommendation>> fetchRecommendations({
    String? country,
  }) async {
    var query = _client
        .from(_table)
        .select()
        .eq('status', 'approved')
        .eq('is_active', true);

    if (country != null) {
      query = query.or('country.is.null,country.eq.$country');
    }

    final rows = sq.asListOfMaps(
      await sq.guarded(
        () => query.order('sort_order', ascending: false),
        label: 'nexusRecommendations',
      ),
    );
    return rows.map(NexusRecommendation.fromJson).toList(growable: false);
  }

  // ── Admin ─────────────────────────────────────────────────

  /// Fetch all content items (any status) for admin management.
  Future<List<NexusRecommendation>> fetchAll({
    AiContentStatus? statusFilter,
  }) async {
    var query = _client.from(_table).select();

    if (statusFilter != null) {
      query = query.eq('status', statusFilter.dbValue);
    }

    final rows = sq.asListOfMaps(
      await sq.guarded(
        () => query.order('created_at', ascending: false),
        label: 'nexusAllContent',
      ),
    );
    return rows.map(NexusRecommendation.fromJson).toList(growable: false);
  }

  /// Create or update a content item.
  Future<void> upsert(NexusRecommendation item) async {
    final json = item.toJson();
    json['created_by'] = _client.auth.currentUser?.id;

    if (item.id.isEmpty) {
      json.remove('id');
      await sq.guarded(
        () => _client.from(_table).insert(json),
        label: 'nexusInsert',
      );
    } else {
      await sq.guarded(
        () => _client.from(_table).update(json).eq('id', item.id),
        label: 'nexusUpdate',
      );
    }
  }

  /// Set status to `approved`.
  Future<void> approve(String id) async {
    await sq.guarded(
      () => _client
          .from(_table)
          .update({
            'status': AiContentStatus.approved.dbValue,
            'reviewed_by': _client.auth.currentUser?.id,
            'reviewed_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id),
      label: 'nexusApprove',
    );
  }

  /// Set status to `rejected`.
  Future<void> reject(String id) async {
    await sq.guarded(
      () => _client
          .from(_table)
          .update({
            'status': AiContentStatus.rejected.dbValue,
            'reviewed_by': _client.auth.currentUser?.id,
            'reviewed_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id),
      label: 'nexusReject',
    );
  }

  /// Toggle `is_active` flag on approved content.
  Future<void> toggleActive(String id, {required bool isActive}) async {
    await sq.guarded(
      () => _client.from(_table).update({'is_active': isActive}).eq('id', id),
      label: 'nexusToggleActive',
    );
  }

  /// Delete a content item.
  Future<void> delete(String id) async {
    await sq.guarded(
      () => _client.from(_table).delete().eq('id', id),
      label: 'nexusDelete',
    );
  }
}
