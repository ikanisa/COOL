import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/country_catalog.dart';
import 'admin_repository_helpers.dart';

part 'admin_momo_ops_repository_validation.dart';

/// Admin repository for MoMo operational views: sender inventory, operational
/// summary, manual review queue, health events, and MoMo validation.
class AdminMomoOpsRepository with AdminRepositoryHelpers {
  AdminMomoOpsRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  @override
  SupabaseClient get client => _client;

  // ── MoMo SMS Operational Summary ──────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchMomoSmsOperationalSummary() async {
    final data = await guarded(
      () => _client.rpc('get_momo_sms_operational_summary'),
      timeout: rpcTimeout,
      label: 'adminMomoSmsOperationalSummary',
    );
    return asListOfMaps(data);
  }

  // ── MoMo SMS Sender Inventory ─────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchMomoSmsSenderInventory({
    int limit = 20,
    bool includeApproved = false,
  }) async {
    final data = await guarded(
      () => _client.rpc(
        'get_momo_sms_sender_inventory',
        params: <String, dynamic>{
          'p_limit': limit,
          'p_include_approved': includeApproved,
        },
      ),
      timeout: rpcTimeout,
      label: 'adminMomoSmsSenderInventory',
    );
    return asListOfMaps(data);
  }

  Future<void> acknowledgeMomoSmsSenderInventory({
    required String senderToken,
    String? note,
  }) async {
    await guarded(
      () => _client.rpc(
        'admin_acknowledge_momo_sms_sender_inventory',
        params: <String, dynamic>{
          'p_sender_token': senderToken,
          'p_note': trimmed(note),
        },
      ),
      timeout: rpcTimeout,
      label: 'adminAcknowledgeMomoSender',
    );
  }

  Future<int> acknowledgeMomoSmsSenderInventoryBatch({
    required List<String> senderTokens,
    String? note,
  }) async {
    if (senderTokens.isEmpty) {
      return 0;
    }

    final data = await guarded(
      () => _client.rpc(
        'admin_acknowledge_momo_sms_sender_inventory_batch',
        params: <String, dynamic>{
          'p_sender_tokens': senderTokens,
          'p_note': trimmed(note),
        },
      ),
      timeout: rpcTimeout,
      label: 'adminAcknowledgeMomoSenderBatch',
    );
    final rows = asListOfMaps(data);
    if (rows.isEmpty) {
      return 0;
    }
    return asInt(rows.first['acknowledged_count']);
  }

  // ── MoMo SMS Manual Review Queue ──────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchMomoSmsManualReviewQueue({
    int limit = 50,
    int offset = 0,
  }) async {
    final data = await guarded(
      () => _client.rpc(
        'get_momo_sms_manual_review_queue',
        params: <String, dynamic>{'p_limit': limit, 'p_offset': offset},
      ),
      timeout: rpcTimeout,
      label: 'adminMomoManualReviewQueue',
    );
    return asListOfMaps(data);
  }

  Future<void> rejectMomoSmsManualReview({
    required String reviewId,
    String? note,
  }) async {
    await guarded(
      () => _client.rpc(
        'admin_reject_momo_sms_manual_review',
        params: <String, dynamic>{
          'p_review_id': reviewId,
          'p_note': trimmed(note),
        },
      ),
      timeout: rpcTimeout,
      label: 'adminRejectMomoReview',
    );
  }

  Future<int> rejectMomoSmsManualReviewBatch({
    required List<String> reviewIds,
    String? note,
  }) async {
    if (reviewIds.isEmpty) {
      return 0;
    }

    final data = await guarded(
      () => _client.rpc(
        'admin_reject_momo_sms_manual_review_batch',
        params: <String, dynamic>{
          'p_review_ids': reviewIds,
          'p_note': trimmed(note),
        },
      ),
      timeout: rpcTimeout,
      label: 'adminRejectMomoReviewBatch',
    );
    final rows = asListOfMaps(data);
    if (rows.isEmpty) {
      return 0;
    }
    return asInt(rows.first['rejected_count']);
  }

  // ── Health Events ─────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchRecentOperationalHealthEvents({
    int limit = 40,
  }) async {
    final data = await guarded(
      () => _client.rpc(
        'get_recent_operational_health_events',
        params: <String, dynamic>{'p_limit': limit},
      ),
      timeout: rpcTimeout,
      label: 'adminOperationalHealthEvents',
    );
    return asListOfMaps(data);
  }

  // ── MoMo Validation Issues ────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchMomoValidationIssues() async {
    try {
      final data = await guarded(
        () => _client.rpc('get_momo_validation_issues'),
        timeout: rpcTimeout,
        label: 'adminMomoValidationIssues',
      );
      return _normalizeIssueRows(data);
    } on PostgrestException catch (error) {
      if (!isMissingSchemaObjectError(error)) {
        rethrow;
      }
    }

    try {
      return await _deriveMomoValidationIssuesLocally();
    } on PostgrestException catch (error) {
      if (!isMissingSchemaObjectError(error)) {
        rethrow;
      }
    } catch (_) {
      // Fall through to a synthetic compatibility issue row.
    }

    return <Map<String, dynamic>>[
      _issueRow(
        recordType: 'system',
        recordId: 'legacy-schema',
        issueCode: 'validation_backend_unavailable',
        issueMessage:
            'This backend is missing the tables or columns required to audit MoMo validation issues. Apply the latest compatibility migration to enable server-side validation diagnostics.',
      ),
    ];
  }

  Future<Map<String, dynamic>> repairMomoValidationIssue({
    required String recordType,
    required String recordId,
    required String issueCode,
  }) async {
    dynamic data;
    try {
      data = await guarded(
        () => _client.rpc(
          'repair_momo_validation_issue',
          params: <String, dynamic>{
            'p_record_type': recordType,
            'p_record_id': recordId,
            'p_issue_code': issueCode,
          },
        ),
        timeout: rpcTimeout,
        label: 'adminRepairMomoValidationIssue',
      );
    } on PostgrestException catch (error) {
      if (!isMissingSchemaObjectError(error)) {
        rethrow;
      }
      return <String, dynamic>{
        'status': 'unavailable',
        'record_type': recordType,
        'record_id': recordId,
        'issue_code': issueCode,
        'message':
            'Repair tools are unavailable on this backend until the compatibility migration is applied.',
      };
    }

    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    throw StateError('Expected repair_momo_validation_issue to return JSON.');
  }
}
