import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/country_catalog.dart';
import '../../auth/models/user_profile.dart';
import '../models/group_access_snapshot.dart';
import '../models/group.dart';
import '../models/group_invite_preview.dart';
import '../models/group_join_result.dart';

class GroupRepository {
  GroupRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  SupabaseClient get client => _client;

  Future<List<Group>> getMyGroups(String userId, {String? country}) async {
    if (userId.trim().isEmpty) {
      return const <Group>[];
    }

    final rows = _asListOfMaps(
      await _client
          .from('group_members')
          .select('joined_at, groups!inner(*)')
          .eq('user_id', userId)
          .order('joined_at', ascending: false),
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

    final normalizedCountry = _trimToNull(country);
    if (normalizedCountry != null) {
      query = query.or('country.is.null,country.eq.$normalizedCountry');
    }

    final normalizedSearch = _trimToNull(searchQuery);
    if (normalizedSearch != null) {
      final escapedSearch = _escapeLike(normalizedSearch);
      query = query.or(
        'name.ilike.%$escapedSearch%,description.ilike.%$escapedSearch%',
      );
    }

    final rows = _asListOfMaps(
      await query
          .order('member_count', ascending: false)
          .order('updated_at', ascending: false),
    );

    return rows.map(Group.fromJson).toList(growable: false);
  }

  Future<Group?> getGroupById(String groupId) async {
    final normalizedGroupId = _trimToNull(groupId);
    if (normalizedGroupId == null) {
      return null;
    }

    final row = await _client
        .from('groups')
        .select()
        .eq('id', normalizedGroupId)
        .maybeSingle();

    if (row == null) {
      return null;
    }

    return Group.fromJson(Map<String, dynamic>.from(row));
  }

  Future<GroupAccessSnapshot?> getGroupAccessSnapshot(String groupId) async {
    final normalizedGroupId = _trimToNull(groupId);
    if (normalizedGroupId == null) {
      return null;
    }

    final rows = _asListOfMaps(
      await _client.rpc(
        'get_group_access_snapshot',
        params: <String, dynamic>{'p_group_id': normalizedGroupId},
      ),
    );
    if (rows.isEmpty) {
      return null;
    }
    return GroupAccessSnapshot.fromJson(rows.first);
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
    final normalizedName = _trimToNull(name);
    if (normalizedName == null) {
      throw StateError('Group name is required.');
    }

    // Use custom MoMo values when provided, otherwise fall back to creator
    final routeType = customMomoRouteType ?? creator.effectiveMomoRouteType;
    final recipientValue =
        _trimToNull(customRecipientValue) ??
        _trimToNull(creator.momoRecipientValue);
    final response = await _client.rpc(
      'create_group_atomic',
      params: <String, dynamic>{
        'p_name': normalizedName,
        'p_visibility': visibility.trim().toLowerCase(),
        'p_type': type.trim().toLowerCase(),
        'p_description': _trimToNull(description),
        'p_country': _trimToNull(creator.country),
        'p_target_amount': targetAmount ?? 0,
        'p_monthly_contribution': monthlyContribution,
        'p_momo_number': routeType == MomoRecipientType.phoneNumber
            ? recipientValue
            : null,
        'p_receiving_momo_code': routeType == MomoRecipientType.code
            ? recipientValue
            : null,
        'p_receiving_momo_route_type': _serializeRecipientType(routeType),
        if (frequency != null) 'p_frequency': frequency.trim().toLowerCase(),
      },
    );

    final payload = _asMap(response);
    final status = payload['status']?.toString() ?? 'error';
    if (status != 'success') {
      throw StateError(
        payload['message']?.toString() ?? 'Could not create group.',
      );
    }

    final groupId = _trimToNull(payload['group_id']?.toString());
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
    final normalizedGroupId = _trimToNull(groupId);
    final normalizedName = _trimToNull(name);
    if (normalizedGroupId == null) {
      throw StateError('Group id is required.');
    }
    if (normalizedName == null) {
      throw StateError('Group name is required.');
    }

    final response = await _client.rpc(
      'update_group_savings_settings',
      params: <String, dynamic>{
        'p_group_id': normalizedGroupId,
        'p_name': normalizedName,
        'p_description': description,
        'p_target_amount': targetAmount,
        'p_monthly_contribution': monthlyContribution,
        'p_frequency': _trimToNull(frequency),
        'p_receiving_momo_route_type': _serializeRecipientType(
          customMomoRouteType,
        ),
        'p_recipient_value': _trimToNull(customRecipientValue),
      },
    );

    final payload = _asMap(response);
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
    final normalizedInviteCode = _trimToNull(inviteCode)?.toUpperCase();
    if (normalizedInviteCode == null) {
      return null;
    }

    final response = await _client.rpc(
      'get_group_invite_preview',
      params: <String, dynamic>{'p_invite_code': normalizedInviteCode},
    );
    final payload = _asMap(response);
    if (payload.isEmpty) {
      return null;
    }
    return GroupInvitePreview.fromJson(payload);
  }

  Future<GroupJoinResult> joinGroupViaInvite(String inviteCode) async {
    final normalizedInviteCode = _trimToNull(inviteCode)?.toUpperCase();
    if (normalizedInviteCode == null) {
      throw StateError('Invite code is required.');
    }

    final response = await _client.rpc(
      'join_group_via_invite',
      params: <String, dynamic>{'p_invite_code': normalizedInviteCode},
    );
    return GroupJoinResult.fromJson(_asMap(response));
  }

  Future<GroupJoinResult> joinPublicGroup({
    required Group group,
    required UserProfile user,
  }) async {
    final groupId = _trimToNull(group.id);
    if (groupId == null) {
      throw StateError('Group id is required.');
    }

    final existing = await _client
        .from('group_members')
        .select('id')
        .eq('group_id', groupId)
        .eq('user_id', user.id)
        .maybeSingle();
    if (existing != null) {
      return GroupJoinResult(status: 'already_member', groupId: groupId);
    }

    await _client.from('group_members').insert(<String, dynamic>{
      'group_id': groupId,
      'user_id': user.id,
      'display_name': user.displayUserId,
      'is_admin': false,
      'is_anonymous': false,
      'contribution_amount': 0,
    });

    return GroupJoinResult(status: 'joined', groupId: groupId);
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

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return const <String, dynamic>{};
}

String? _trimToNull(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

String _escapeLike(String value) {
  return value.replaceAll('%', r'\%').replaceAll(',', r'\,');
}

String? _serializeRecipientType(MomoRecipientType? type) {
  return switch (type) {
    MomoRecipientType.phoneNumber => 'phone_number',
    MomoRecipientType.code => 'code',
    null => null,
  };
}
