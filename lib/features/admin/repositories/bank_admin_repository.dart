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
}

List<Map<String, dynamic>> _asListOfMaps(dynamic value) {
  if (value is List) {
    return value
        .whereType<Map>()
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
