import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/bank_admin_models.dart';

class BankAdminRepository {
  BankAdminRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  Future<BankAdminWorkspaceSnapshot> loadWorkspaceSnapshot(
    String partnerId,
  ) async {
    final trimmedPartnerId = partnerId.trim();
    if (trimmedPartnerId.isEmpty) {
      return const BankAdminWorkspaceSnapshot();
    }

    final groupsFuture = loadCustodyGroupsPage(trimmedPartnerId, limit: 50);
    final membersFuture = loadCustodyMembersPage(trimmedPartnerId, limit: 50);
    final contributionsFuture = loadCustodyContributionsPage(
      trimmedPartnerId,
      limit: 50,
    );
    final allocationsFuture = loadAllocationReviewPage(trimmedPartnerId);

    final results = await Future.wait<Object>([
      groupsFuture,
      membersFuture,
      contributionsFuture,
      allocationsFuture,
    ]);

    return BankAdminWorkspaceSnapshot(
      groups: results[0] as BankAdminPage<BankAdminGroupSummary>,
      members: results[1] as BankAdminPage<BankAdminMemberRecord>,
      contributions: results[2] as BankAdminPage<BankAdminContributionRecord>,
      allocations: results[3] as BankAdminPage<BankAdminAllocationReviewItem>,
    );
  }

  Future<BankAdminPage<BankAdminGroupSummary>> loadCustodyGroupsPage(
    String partnerId, {
    String? search,
    int limit = 1000,
    int offset = 0,
  }) async {
    final rows = _asListOfMaps(
      await _client.rpc(
        'get_bank_custody_groups',
        params: <String, dynamic>{
          'p_partner_id': partnerId,
          'p_search': _trimToNull(search),
          'p_limit': limit,
          'p_offset': offset,
        },
      ),
    );
    return BankAdminPage<BankAdminGroupSummary>(
      entries: rows.map(BankAdminGroupSummary.fromJson).toList(growable: false),
      totalCount: _extractTotalCount(rows),
    );
  }

  Future<BankAdminPage<BankAdminMemberRecord>> loadCustodyMembersPage(
    String partnerId, {
    String? groupId,
    String? search,
    int limit = 1000,
    int offset = 0,
  }) async {
    final rows = _asListOfMaps(
      await _client.rpc(
        'get_bank_custody_group_members',
        params: <String, dynamic>{
          'p_partner_id': partnerId,
          'p_group_id': _trimToNull(groupId),
          'p_search': _trimToNull(search),
          'p_limit': limit,
          'p_offset': offset,
        },
      ),
    );
    return BankAdminPage<BankAdminMemberRecord>(
      entries: rows.map(BankAdminMemberRecord.fromJson).toList(growable: false),
      totalCount: _extractTotalCount(rows),
    );
  }

  Future<BankAdminPage<BankAdminContributionRecord>>
  loadCustodyContributionsPage(
    String partnerId, {
    String? groupId,
    String? status,
    int limit = 1000,
    int offset = 0,
  }) async {
    final rows = _asListOfMaps(
      await _client.rpc(
        'get_bank_custody_contributions',
        params: <String, dynamic>{
          'p_partner_id': partnerId,
          'p_group_id': _trimToNull(groupId),
          'p_status': _trimToNull(status),
          'p_limit': limit,
          'p_offset': offset,
        },
      ),
    );
    return BankAdminPage<BankAdminContributionRecord>(
      entries: rows
          .map(BankAdminContributionRecord.fromJson)
          .toList(growable: false),
      totalCount: _extractTotalCount(rows),
    );
  }

  Future<BankAdminPage<BankAdminAllocationReviewItem>> loadAllocationReviewPage(
    String partnerId, {
    int limit = 1000,
    int offset = 0,
  }) async {
    final rows = _asListOfMaps(
      await _client.rpc(
        'get_bank_manual_review_allocations',
        params: <String, dynamic>{
          'p_partner_id': partnerId,
          'p_limit': limit,
          'p_offset': offset,
        },
      ),
    );
    return BankAdminPage<BankAdminAllocationReviewItem>(
      entries: rows
          .map(BankAdminAllocationReviewItem.fromJson)
          .toList(growable: false),
      totalCount: _extractTotalCount(rows),
    );
  }

  Future<void> allocateManualReviewToGroupContribution({
    required String partnerId,
    required String reviewId,
    required String groupId,
    required String memberUserId,
    String? note,
  }) async {
    await _client.rpc(
      'bank_allocate_manual_review_allocation',
      params: <String, dynamic>{
        'p_partner_id': partnerId,
        'p_review_id': reviewId,
        'p_group_id': groupId,
        'p_member_user_id': memberUserId,
        'p_note': _trimToNull(note),
      },
    );
  }

  Future<void> rejectManualReviewAllocation({
    required String partnerId,
    required String reviewId,
    String? note,
  }) async {
    await _client.rpc(
      'bank_reject_manual_review_allocation',
      params: <String, dynamic>{
        'p_partner_id': partnerId,
        'p_review_id': reviewId,
        'p_note': _trimToNull(note),
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Analytics
  // ═══════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> fetchBankAnalytics(String partnerId) async {
    final result = await _client.rpc(
      'get_bank_analytics_summary',
      params: {'p_partner_id': partnerId},
    );
    if (result is Map<String, dynamic>) return result;
    return const <String, dynamic>{};
  }

  // ═══════════════════════════════════════════════════════════════
  // AI Allocation Support
  // ═══════════════════════════════════════════════════════════════

  /// Accepts an AI-suggested allocation by reading metadata from the
  /// reconciliation and delegating to the existing allocation RPC.
  Future<void> acceptSuggestedAllocation({
    required String partnerId,
    required String reviewId,
    String? note,
  }) async {
    await _client.rpc(
      'bank_accept_suggested_allocation',
      params: {
        'p_partner_id': partnerId,
        'p_review_id': reviewId,
        'p_note': _trimToNull(note),
      },
    );
  }

  /// Adds a new member to a group by phone number.
  /// Returns the new member's user_id and display_name.
  Future<Map<String, dynamic>> addMemberToGroup({
    required String partnerId,
    required String groupId,
    required String phone,
    String? displayName,
  }) async {
    final result = await _client.rpc(
      'bank_add_member_to_group',
      params: {
        'p_partner_id': partnerId,
        'p_group_id': groupId,
        'p_phone': phone,
        'p_display_name': _trimToNull(displayName),
      },
    );
    final rows = _asListOfMaps(result);
    return rows.isNotEmpty ? rows.first : const <String, dynamic>{};
  }

  /// Searches group members for the allocation modal type-ahead.
  Future<List<BankAdminMemberRecord>> searchMembers(
    String partnerId, {
    String? groupId,
    required String search,
  }) async {
    final page = await loadCustodyMembersPage(
      partnerId,
      groupId: groupId,
      search: search,
      limit: 20,
    );
    return page.entries;
  }

  /// Triggers the AI allocation Edge Function.
  Future<void> triggerAiAllocation(String partnerId) async {
    await _client.functions.invoke(
      'allocate-contributions',
      body: {'partner_id': partnerId},
    );
  }
}

List<Map<String, dynamic>> _asListOfMaps(dynamic value) {
  if (value is List) {
    return value
        .whereType<Map<dynamic, dynamic>>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }
  return const <Map<String, dynamic>>[];
}

int _extractTotalCount(List<Map<String, dynamic>> rows) {
  if (rows.isEmpty) {
    return 0;
  }
  final value = rows.first['total_count'];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? rows.length;
}

String? _trimToNull(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}
