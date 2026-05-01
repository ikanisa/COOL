import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/country_catalog.dart';
import '../../../core/utils/supabase_query_helpers.dart' as sq;
import '../../auth/models/user_profile.dart';
import '../models/group_access_snapshot.dart';
import '../models/group.dart';
import '../models/group_invite_preview.dart';
import '../models/group_join_result.dart';
import '../models/group_member_allocation_option.dart';
import '../models/group_member_preview.dart';

class GroupRepository {
  GroupRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  Future<List<Group>> getMyGroups(String userId, {String? country}) async {
    if (userId.trim().isEmpty) {
      return const <Group>[];
    }

    final rows = sq.asListOfMaps(
      await sq.guarded(
        () => _client
            .from('group_members')
            .select('joined_at, groups!inner(*)')
            .eq('user_id', userId)
            .order('joined_at', ascending: false),
        label: 'getMyGroups',
      ),
    );

    return rows
        .map((row) => row['groups'])
        .whereType<Map<dynamic, dynamic>>()
        .map((group) => Group.fromJson(Map<String, dynamic>.from(group)))
        .toList(growable: false);
  }

  Future<List<Group>> getPublicGroups(
    String searchQuery, {
    String? country,
  }) async {
    var query = _client.from('groups').select().eq('visibility', 'public');

    final normalizedCountry = sq.trimToNull(country);
    if (normalizedCountry != null) {
      query = query.or('country.is.null,country.eq.$normalizedCountry');
    }

    final normalizedSearch = sq.trimToNull(searchQuery);
    if (normalizedSearch != null) {
      final escapedSearch = sq.escapeLike(normalizedSearch);
      query = query.or(
        'name.ilike.%$escapedSearch%,description.ilike.%$escapedSearch%',
      );
    }

    final rows = sq.asListOfMaps(
      await sq.guarded(
        () => query
            .order('member_count', ascending: false)
            .order('updated_at', ascending: false),
        label: 'getPublicGroups',
      ),
    );

    return rows.map(Group.fromJson).toList(growable: false);
  }

  Future<Group?> getGroupById(String groupId) async {
    final normalizedGroupId = sq.trimToNull(groupId);
    if (normalizedGroupId == null) {
      return null;
    }

    final row = await sq.guarded(
      () => _client
          .from('groups')
          .select()
          .eq('id', normalizedGroupId)
          .maybeSingle(),
      label: 'getGroupById',
    );

    if (row == null) {
      return null;
    }

    return Group.fromJson(Map<String, dynamic>.from(row));
  }

  Future<GroupAccessSnapshot?> getGroupAccessSnapshot(String groupId) async {
    final normalizedGroupId = sq.trimToNull(groupId);
    if (normalizedGroupId == null) {
      return null;
    }

    final rows = sq.asListOfMaps(
      await sq.guarded(
        () => _client.rpc(
          'get_group_access_snapshot',
          params: <String, dynamic>{'p_group_id': normalizedGroupId},
        ),
        timeout: sq.kSupabaseRpcTimeout,
        label: 'getGroupAccessSnapshot',
      ),
    );
    if (rows.isEmpty) {
      return null;
    }
    return GroupAccessSnapshot.fromJson(rows.first);
  }

  Future<List<GroupMemberPreview>> getGroupMemberPreview(
    String groupId, {
    int limit = 100,
  }) async {
    final normalizedGroupId = sq.trimToNull(groupId);
    if (normalizedGroupId == null) {
      return const <GroupMemberPreview>[];
    }

    final rows = sq.asListOfMaps(
      await sq.guarded(
        () => _client.rpc(
          'get_group_members_preview',
          params: <String, dynamic>{
            'p_group_id': normalizedGroupId,
            'p_limit': limit,
          },
        ),
        timeout: sq.kSupabaseRpcTimeout,
        label: 'getGroupMemberPreview',
      ),
    );

    return rows.map(GroupMemberPreview.fromJson).toList(growable: false);
  }

  Future<List<GroupMemberAllocationOption>> getGroupMemberAllocationOptions(
    String groupId,
  ) async {
    final normalizedGroupId = sq.trimToNull(groupId);
    if (normalizedGroupId == null) {
      return const <GroupMemberAllocationOption>[];
    }

    final rows = sq.asListOfMaps(
      await sq.guarded(
        () => _client
            .from('group_members')
            .select('user_id, display_name')
            .eq('group_id', normalizedGroupId)
            .order('display_name', ascending: true),
        label: 'getGroupMemberAllocationOptions',
      ),
    );

    return rows
        .map(GroupMemberAllocationOption.fromJson)
        .where((member) => member.userId.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<void> allocateTransactionToMember({
    required String ledgerId,
    required String groupId,
    required String memberUserId,
  }) async {
    final normalizedLedgerId = sq.trimToNull(ledgerId);
    final normalizedGroupId = sq.trimToNull(groupId);
    final normalizedMemberUserId = sq.trimToNull(memberUserId);
    if (normalizedLedgerId == null ||
        normalizedGroupId == null ||
        normalizedMemberUserId == null) {
      throw StateError('Ledger, group, and member ids are required.');
    }

    await sq.guarded(
      () => _client.rpc(
        'allocate_transaction_to_member',
        params: <String, dynamic>{
          'p_ledger_id': normalizedLedgerId,
          'p_group_id': normalizedGroupId,
          'p_member_user_id': normalizedMemberUserId,
        },
      ),
      timeout: sq.kSupabaseRpcTimeout,
      label: 'allocateTransactionToMember',
    );
  }

  Future<void> unallocateTransaction({
    required String ledgerId,
    required String groupId,
  }) async {
    final normalizedLedgerId = sq.trimToNull(ledgerId);
    final normalizedGroupId = sq.trimToNull(groupId);
    if (normalizedLedgerId == null || normalizedGroupId == null) {
      throw StateError('Ledger and group ids are required.');
    }

    await sq.guarded(
      () => _client.rpc(
        'unallocate_transaction',
        params: <String, dynamic>{
          'p_ledger_id': normalizedLedgerId,
          'p_group_id': normalizedGroupId,
        },
      ),
      timeout: sq.kSupabaseRpcTimeout,
      label: 'unallocateTransaction',
    );
  }

  Future<Group> createGroup({
    required UserProfile creator,
    required String name,
    required String visibility,
    required String type,
    String? description,
    int? targetAmount,
    int? monthlyContribution,
    MomoRecipientType? customMomoRouteType,
    String? customRecipientValue,
    String? frequency,
  }) async {
    final normalizedName = sq.trimToNull(name);
    if (normalizedName == null) {
      throw StateError('Group name is required.');
    }

    // Use custom MoMo values when provided, otherwise fall back to creator
    final routeType = customMomoRouteType ?? creator.effectiveMomoRouteType;
    final recipientValue =
        sq.trimToNull(customRecipientValue) ??
        sq.trimToNull(creator.momoRecipientValue);
    final response = await sq.guarded(
      () => _client.rpc(
        'create_group_atomic',
        params: <String, dynamic>{
          'p_name': normalizedName,
          'p_visibility': visibility.trim().toLowerCase(),
          'p_type': type.trim().toLowerCase(),
          'p_description': sq.trimToNull(description),
          'p_country': sq.trimToNull(creator.country),
          'p_target_amount': targetAmount ?? 0,
          'p_monthly_contribution': monthlyContribution,
          'p_momo_number': routeType == MomoRecipientType.phoneNumber
              ? recipientValue
              : null,
          'p_receiving_momo_code': routeType == MomoRecipientType.code
              ? recipientValue
              : null,
          'p_receiving_momo_route_type': _serializeRecipientType(routeType),
          if (frequency != null)
            'p_cycle_days': _frequencyToCycleDays(frequency),
        },
      ),
      timeout: sq.kSupabaseRpcTimeout,
      label: 'createGroup',
    );

    final payload = sq.asMap(response);
    final status = payload['status']?.toString() ?? 'error';
    if (status != 'success') {
      throw StateError(
        payload['message']?.toString() ?? 'Could not create group.',
      );
    }

    final groupId = sq.trimToNull(payload['group_id']?.toString());
    if (groupId == null) {
      throw StateError('Group creation did not return a valid group id.');
    }

    final group = await getGroupById(groupId);
    if (group == null) {
      throw StateError('Group was created but could not be loaded.');
    }

    return group;
  }

  Future<Group> updateGroupSavingsSettings({
    required String groupId,
    required String name,
    String? description,
    int? targetAmount,
    int? monthlyContribution,
    String? frequency,
    MomoRecipientType? customMomoRouteType,
    String? customRecipientValue,
  }) async {
    final normalizedGroupId = sq.trimToNull(groupId);
    final normalizedName = sq.trimToNull(name);
    if (normalizedGroupId == null) {
      throw StateError('Group id is required.');
    }
    if (normalizedName == null) {
      throw StateError('Group name is required.');
    }

    final response = await sq.guarded(
      () => _client.rpc(
        'update_group_savings_settings',
        params: <String, dynamic>{
          'p_group_id': normalizedGroupId,
          'p_name': normalizedName,
          'p_description': description,
          'p_target_amount': targetAmount,
          'p_monthly_contribution': monthlyContribution,
          'p_frequency': sq.trimToNull(frequency),
          'p_receiving_momo_route_type': _serializeRecipientType(
            customMomoRouteType,
          ),
          'p_recipient_value': sq.trimToNull(customRecipientValue),
        },
      ),
      timeout: sq.kSupabaseRpcTimeout,
      label: 'updateGroupSavingsSettings',
    );

    final payload = sq.asMap(response);
    final status = payload['status']?.toString() ?? 'error';
    if (status != 'success') {
      throw StateError(
        payload['message']?.toString() ?? 'Could not update group settings.',
      );
    }

    final group = await getGroupById(normalizedGroupId);
    if (group == null) {
      throw StateError(
        'Group settings were saved but the group could not be reloaded.',
      );
    }

    return group;
  }

  Future<GroupInvitePreview?> getInvitePreview(String inviteCode) async {
    final normalizedInviteCode = sq.trimToNull(inviteCode)?.toUpperCase();
    if (normalizedInviteCode == null) {
      return null;
    }

    final response = await sq.guarded(
      () => _client.rpc(
        'get_group_invite_preview',
        params: <String, dynamic>{'p_invite_code': normalizedInviteCode},
      ),
      timeout: sq.kSupabaseRpcTimeout,
      label: 'getInvitePreview',
    );
    final payload = sq.asMap(response);
    if (payload.isEmpty) {
      return null;
    }
    return GroupInvitePreview.fromJson(payload);
  }

  Future<GroupJoinResult> joinGroupViaInvite(String inviteCode) async {
    final normalizedInviteCode = sq.trimToNull(inviteCode)?.toUpperCase();
    if (normalizedInviteCode == null) {
      throw StateError('Invite code is required.');
    }

    final response = await sq.guarded(
      () => _client.rpc(
        'join_group_via_invite',
        params: <String, dynamic>{'p_invite_code': normalizedInviteCode},
      ),
      timeout: sq.kSupabaseRpcTimeout,
      label: 'joinGroupViaInvite',
    );
    return GroupJoinResult.fromJson(sq.asMap(response));
  }

  Future<GroupJoinResult> joinPublicGroup({
    required Group group,
    required UserProfile user,
  }) async {
    final groupId = sq.trimToNull(group.id);
    if (groupId == null) {
      throw StateError('Group id is required.');
    }

    final response = await sq.guarded(
      () => _client.rpc(
        'join_public_group',
        params: <String, dynamic>{'p_group_id': groupId},
      ),
      timeout: sq.kSupabaseRpcTimeout,
      label: 'joinPublicGroup',
    );
    return GroupJoinResult.fromJson(sq.asMap(response));
  }
}

// Local helpers removed — now using shared `sq.*` functions from
// core/utils/supabase_query_helpers.dart

String? _serializeRecipientType(MomoRecipientType? type) {
  return switch (type) {
    MomoRecipientType.phoneNumber => 'phone_number',
    MomoRecipientType.code => 'code',
    null => null,
  };
}

int _frequencyToCycleDays(String frequency) {
  switch (frequency.trim().toLowerCase()) {
    case 'daily':
      return 1;
    case 'weekly':
      return 7;
    case 'one_off':
      return 0;
    case 'monthly':
    default:
      return 30;
  }
}
