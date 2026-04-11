import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_repository_helpers.dart';

/// Admin repository for centralized savings group management.
///
/// Wraps the `admin_*` RPC functions for savings group CRUD,
/// member management, and manual contribution allocation.
class AdminSavingsRepository with AdminRepositoryHelpers {
  AdminSavingsRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  @override
  SupabaseClient get client => _client;

  // ── Read ─────────────────────────────────────────────────────────────

  /// Fetches detailed savings + community groups with members and totals.
  Future<Map<String, dynamic>> fetchSavingsGroupsDetail() async {
    final data = await _client.rpc('admin_get_savings_groups_detail');
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw StateError('Expected admin_get_savings_groups_detail to return JSON.');
  }

  // ── Create ───────────────────────────────────────────────────────────

  /// Creates a new savings group with centralized MoMo code.
  Future<Map<String, dynamic>> createSavingsGroup({
    required String name,
    String? description,
    int? targetAmount,
    int? monthlyContribution,
    String? frequency,
  }) async {
    final data = await _client.rpc(
      'admin_create_savings_group',
      params: <String, dynamic>{
        'p_name': name.trim(),
        'p_description': description?.trim(),
        'p_target_amount': targetAmount ?? 0,
        'p_monthly_contribution': monthlyContribution,
        'p_frequency': frequency?.trim() ?? 'monthly',
      },
    );
    return _asMap(data);
  }

  // ── Update ───────────────────────────────────────────────────────────

  /// Updates savings group properties.
  Future<Map<String, dynamic>> updateSavingsGroup({
    required String groupId,
    String? name,
    String? description,
    int? targetAmount,
    int? monthlyContribution,
    String? frequency,
    bool? isClosed,
  }) async {
    final data = await _client.rpc(
      'admin_update_savings_group',
      params: <String, dynamic>{
        'p_group_id': groupId.trim(),
        'p_name': name?.trim(),
        'p_description': description?.trim(),
        'p_target_amount': targetAmount,
        'p_monthly_contribution': monthlyContribution,
        'p_frequency': frequency?.trim(),
        'p_is_closed': isClosed,
      },
    );
    return _asMap(data);
  }

  // ── Member Management ────────────────────────────────────────────────

  /// Adds a single member to a group.
  Future<Map<String, dynamic>> addGroupMember({
    required String groupId,
    required String userId,
    String? displayName,
  }) async {
    final data = await _client.rpc(
      'admin_add_group_member',
      params: <String, dynamic>{
        'p_group_id': groupId.trim(),
        'p_user_id': userId.trim(),
        'p_display_name': displayName?.trim(),
      },
    );
    return _asMap(data);
  }

  /// Removes a member from a group.
  Future<Map<String, dynamic>> removeGroupMember({
    required String groupId,
    required String userId,
  }) async {
    final data = await _client.rpc(
      'admin_remove_group_member',
      params: <String, dynamic>{
        'p_group_id': groupId.trim(),
        'p_user_id': userId.trim(),
      },
    );
    return _asMap(data);
  }

  /// Bulk-adds members by phone number.
  /// [members] is a list of `{ "phone": "...", "display_name": "..." }`.
  Future<Map<String, dynamic>> bulkAddGroupMembers({
    required String groupId,
    required List<Map<String, String>> members,
  }) async {
    final data = await _client.rpc(
      'admin_bulk_add_group_members',
      params: <String, dynamic>{
        'p_group_id': groupId.trim(),
        'p_members': members,
      },
    );
    return _asMap(data);
  }

  // ── Allocations ──────────────────────────────────────────────────────

  /// Manually allocates a savings contribution for a member.
  Future<Map<String, dynamic>> allocateSavingsContribution({
    required String groupId,
    required String memberUserId,
    required int amount,
    String? reference,
    String? note,
  }) async {
    final data = await _client.rpc(
      'admin_allocate_savings_contribution',
      params: <String, dynamic>{
        'p_group_id': groupId.trim(),
        'p_member_user_id': memberUserId.trim(),
        'p_amount': amount,
        'p_reference': reference?.trim(),
        'p_note': note?.trim(),
      },
    );
    return _asMap(data);
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }
}
