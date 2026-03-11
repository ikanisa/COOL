import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/country_catalog.dart';
import '../../momo/services/momo_service.dart';
import '../models/group.dart';
import '../models/group_contribution.dart';
import '../models/group_detail.dart';
import '../models/group_join_result.dart';
import '../models/group_member.dart';

class GroupRepository {
  GroupRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<Group>> getMyGroups(String userId) async {
    final membershipRowsFuture = _client
        .from('group_members')
        .select('group_id')
        .eq('user_id', userId);
    final createdRowsFuture = _client
        .from('groups')
        .select('id')
        .eq('creator_id', userId);
    final membershipRows = _asListOfMaps(await membershipRowsFuture);
    final createdRows = _asListOfMaps(await createdRowsFuture);

    final groupIds = <String>{
      for (final row in membershipRows)
        if ((row['group_id']?.toString() ?? '').isNotEmpty)
          row['group_id'].toString(),
      for (final row in createdRows)
        if ((row['id']?.toString() ?? '').isNotEmpty) row['id'].toString(),
    };

    return _fetchGroupsByIds(groupIds.toList(growable: false));
  }

  Future<GroupDetail?> getGroupById(String id) async {
    final groupRow = await _client
        .from('groups')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (groupRow == null) {
      return null;
    }

    final rawMemberRowsFuture = _client
        .from('group_members')
        .select(
          'user_id, display_name, is_admin, is_anonymous, '
          'contribution_amount, joined_at',
        )
        .eq('group_id', id)
        .order('joined_at', ascending: true);
    final contributionRowsFuture = _client
        .from('group_contributions')
        .select('id, group_id, user_id, amount, status, created_at')
        .eq('group_id', id)
        .order('created_at', ascending: false)
        .limit(10);
    final rawMemberRows = _asListOfMaps(await rawMemberRowsFuture);
    final contributionRows = _asListOfMaps(await contributionRowsFuture);
    final memberNames = <String, String>{
      for (final row in rawMemberRows)
        if ((row['user_id']?.toString() ?? '').isNotEmpty &&
            (row['display_name']?.toString().trim().isNotEmpty ?? false))
          row['user_id'].toString(): row['display_name'].toString().trim(),
    };
    final contributorNames = await _loadContributorNames(
      contributionRows
          .map((row) => row['user_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList(growable: false),
      seedNames: memberNames,
    );

    final members = rawMemberRows
        .map((row) => GroupMember.fromJson(row))
        .toList(growable: false);
    final contributions = contributionRows
        .map(
          (row) => GroupContribution.fromJson(<String, dynamic>{
            ...row,
            'contributor_name':
                contributorNames[row['user_id']?.toString() ?? ''],
          }),
        )
        .toList(growable: false);
    final currentUserId = _client.auth.currentUser?.id;

    return GroupDetail(
      group: Group.fromJson(<String, dynamic>{
        ..._asMap(groupRow),
        'member_count': rawMemberRows.length,
      }),
      members: members,
      recentContributions: contributions,
      isMember:
          currentUserId != null &&
          rawMemberRows.any(
            (row) => row['user_id']?.toString() == currentUserId,
          ),
    );
  }

  Future<GroupDetail?> getGroupByInviteCode(String inviteCode) async {
    final normalizedCode = _normalizeInviteCode(inviteCode);
    if (normalizedCode.isEmpty) {
      return null;
    }

    final rawPreview = await _client.rpc(
      'get_group_invite_preview',
      params: <String, dynamic>{'p_invite_code': normalizedCode},
    );
    final preview = _asMap(rawPreview);
    if (preview.isEmpty) {
      return null;
    }

    final groupId = preview['id']?.toString();
    final isMember = _asBool(preview['is_member']);
    if (isMember && groupId != null && groupId.isNotEmpty) {
      return getGroupById(groupId);
    }

    return GroupDetail(
      group: Group.fromJson(
        preview,
      ).copyWith(memberCount: _asInt(preview['member_count'])),
      isMember: isMember,
    );
  }

  Future<Group> createGroup(Group group) async {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) {
      throw StateError('No authenticated user is available.');
    }

    final country = await MomoService.instance.resolveCountry(
      countryCode: group.country,
    );
    final routeType = group.type == 'community'
        ? (_parseRecipientType(group.momoRouteType) ??
              _inferRecipientType(country, group.momoNumber ?? ''))
        : null;
    final normalizedRecipient =
        group.type != 'community' || (group.momoNumber?.trim().isEmpty ?? true)
        ? null
        : routeType == MomoRecipientType.code
        ? country.normalizeMerchantCode(group.momoNumber!)
        : country.buildE164Phone(group.momoNumber!);

    final response = await _client.rpc(
      'create_group_atomic',
      params: <String, dynamic>{
        'p_name': group.name,
        'p_visibility': group.visibility,
        'p_type': group.type,
        'p_description': group.description,
        'p_country': country.isoCode,
        'p_target_amount': group.targetAmount,
        'p_monthly_contribution': group.monthlyContribution,
        'p_cycle_days': _cycleDaysForFrequency(group.frequency),
        'p_bank_partner': group.bankPartner,
        'p_momo_number': routeType == MomoRecipientType.phoneNumber
            ? normalizedRecipient
            : null,
        'p_receiving_momo_code': normalizedRecipient,
        'p_receiving_momo_route_type': routeType == null
            ? null
            : _recipientTypeValue(routeType),
      },
    );

    final data = _asMap(response);
    if (data['status']?.toString() != 'success') {
      throw StateError(
        data['message']?.toString() ?? 'Failed to create group.',
      );
    }

    final groupId = data['group_id']?.toString();
    if (groupId == null || groupId.isEmpty) {
      throw StateError('Group creation did not return an id.');
    }

    final detail = await getGroupById(groupId);
    if (detail != null) {
      return detail.group;
    }

    final groupRow = await _client
        .from('groups')
        .select()
        .eq('id', groupId)
        .single();
    return Group.fromJson(_asMap(groupRow));
  }

  Future<void> contribute(String groupId, int amount) async {
    if (amount <= 0) {
      throw StateError('Contribution amount must be greater than zero.');
    }

    final currentUser = _client.auth.currentUser;
    if (currentUser == null) {
      throw StateError('No authenticated user is available.');
    }

    final groupRow = await _client
        .from('groups')
        .select(
          'country, momo_number, receiving_momo_code, '
          'receiving_momo_route_type',
        )
        .eq('id', groupId)
        .maybeSingle();
    if (groupRow == null) {
      throw StateError('Group not found.');
    }

    final membershipRow = await _client
        .from('group_members')
        .select('id')
        .eq('group_id', groupId)
        .eq('user_id', currentUser.id)
        .maybeSingle();
    if (membershipRow == null) {
      throw StateError('You are not a member of this group.');
    }

    final reference =
        'GCT-${DateTime.now().millisecondsSinceEpoch}-${currentUser.id.substring(0, 8)}';
    final country = await MomoService.instance.resolveCountry(
      countryCode: groupRow['country']?.toString(),
    );
    final rawRecipientMomo =
        groupRow['receiving_momo_code']?.toString() ??
        groupRow['momo_number']?.toString();
    final recipientMomo =
        rawRecipientMomo == null || rawRecipientMomo.trim().isEmpty
        ? MomoService.appMomoNumber
        : rawRecipientMomo.trim();
    if (recipientMomo.trim().isEmpty) {
      throw const MomoConfigurationException('recipient_momo');
    }

    final recipientType =
        rawRecipientMomo == null || rawRecipientMomo.trim().isEmpty
        ? MomoRecipientType.phoneNumber
        : _parseRecipientType(
                groupRow['receiving_momo_route_type']?.toString(),
              ) ??
              (groupRow['momo_number']?.toString().trim().isNotEmpty == true
                  ? MomoRecipientType.phoneNumber
                  : _inferRecipientType(country, rawRecipientMomo));

    await _client.from('group_contributions').insert(<String, dynamic>{
      'group_id': groupId,
      'user_id': currentUser.id,
      'amount': amount,
      'status': 'pending',
      'momo_reference': reference,
      'created_at': DateTime.now().toIso8601String(),
    });

    try {
      await MomoService.instance.initiatePayment(
        recipientMomo: recipientMomo,
        amount: amount,
        reference: reference,
        recipientType: recipientType,
        countryCode: country.isoCode,
      );
    } catch (error) {
      await _client
          .from('group_contributions')
          .update(<String, dynamic>{'status': 'failed'})
          .eq('group_id', groupId)
          .eq('user_id', currentUser.id)
          .eq('momo_reference', reference);
      rethrow;
    }
  }

  Future<GroupJoinResult> joinGroupByInviteCode(String inviteCode) async {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) {
      throw StateError('You must be signed in to join a group.');
    }

    final normalizedCode = _normalizeInviteCode(inviteCode);
    if (normalizedCode.isEmpty) {
      throw StateError('Enter a valid invite code.');
    }

    final response = await _client.rpc(
      'join_group_via_invite',
      params: <String, dynamic>{'p_invite_code': normalizedCode},
    );
    final data = _asMap(response);
    final status = data['status']?.toString() ?? '';
    if (status != 'joined' && status != 'already_member') {
      throw StateError(
        data['message']?.toString() ?? 'Unable to join this group.',
      );
    }

    final groupId = data['group_id']?.toString();
    final detail = groupId == null || groupId.isEmpty
        ? await getGroupByInviteCode(normalizedCode)
        : await getGroupById(groupId);
    if (detail == null) {
      throw StateError('Joined group could not be loaded.');
    }

    return GroupJoinResult(detail: detail, status: status);
  }

  Future<List<Group>> getPublicGroups(String country) async {
    var query = _client.from('groups').select().eq('visibility', 'public');
    final normalizedCountry = country.trim();
    if (normalizedCountry.isNotEmpty) {
      query = query.eq(
        'country',
        CoolCountryCatalog.normalizeCountryCode(normalizedCountry),
      );
    }

    final response = await query.order('created_at', ascending: false);
    return _asListOfMaps(
      response,
    ).map((row) => Group.fromJson(row)).toList(growable: false);
  }

  Future<List<Group>> _fetchGroupsByIds(List<String> groupIds) async {
    if (groupIds.isEmpty) {
      return const <Group>[];
    }

    final response = await _client
        .from('groups')
        .select()
        .inFilter('id', groupIds)
        .order('created_at', ascending: false);

    return _asListOfMaps(
      response,
    ).map((row) => Group.fromJson(row)).toList(growable: false);
  }

  int _cycleDaysForFrequency(String? frequency) {
    switch (frequency?.trim().toLowerCase()) {
      case 'daily':
        return 1;
      case 'weekly':
        return 7;
      default:
        return 30;
    }
  }

  String _normalizeInviteCode(String inviteCode) {
    return inviteCode.trim().toUpperCase();
  }

  Future<Map<String, String>> _loadContributorNames(
    List<String> userIds, {
    Map<String, String> seedNames = const <String, String>{},
  }) async {
    if (userIds.isEmpty) {
      return seedNames;
    }

    List<Map<String, dynamic>> userRows = const <Map<String, dynamic>>[];
    try {
      userRows = _asListOfMaps(
        await _client
            .from('users')
            .select('id, official_name, full_name')
            .inFilter('id', userIds),
      );
    } on PostgrestException {
      userRows = _asListOfMaps(
        await _client
            .from('users')
            .select('id, full_name')
            .inFilter('id', userIds),
      );
    }

    final contributorNames = <String, String>{...seedNames};
    for (final row in userRows) {
      final id = row['id']?.toString() ?? '';
      final officialName = row['official_name']?.toString().trim() ?? '';
      final fullName = row['full_name']?.toString().trim() ?? '';
      final preferredName = officialName.isNotEmpty ? officialName : fullName;
      if (id.isNotEmpty && preferredName.isNotEmpty) {
        contributorNames[id] = preferredName;
      }
    }

    return contributorNames;
  }
}

MomoRecipientType? _parseRecipientType(String? value) {
  final normalized = value?.trim().toLowerCase();
  switch (normalized) {
    case 'phone':
    case 'phone_number':
    case 'number':
      return MomoRecipientType.phoneNumber;
    case 'code':
    case 'merchant_code':
      return MomoRecipientType.code;
    default:
      return null;
  }
}

MomoRecipientType _inferRecipientType(CoolCountry country, String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return MomoRecipientType.phoneNumber;
  }

  final isPhoneNumber = country.isValidPhoneNumber(trimmed);
  final isMerchantCode =
      country.supportsMomoCode && country.isValidMerchantCode(trimmed);

  if (isPhoneNumber && !isMerchantCode) {
    return MomoRecipientType.phoneNumber;
  }
  if (isMerchantCode && !isPhoneNumber) {
    return MomoRecipientType.code;
  }
  if (isPhoneNumber) {
    return MomoRecipientType.phoneNumber;
  }
  if (isMerchantCode) {
    return MomoRecipientType.code;
  }

  final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  final dialDigits = country.dialCode.replaceFirst('+', '');

  if (trimmed.startsWith('+') ||
      trimmed.startsWith('0') ||
      digits.startsWith(dialDigits) ||
      digits.length >= 9) {
    return MomoRecipientType.phoneNumber;
  }

  return MomoRecipientType.code;
}

String _recipientTypeValue(MomoRecipientType recipientType) {
  return switch (recipientType) {
    MomoRecipientType.phoneNumber => 'phone_number',
    MomoRecipientType.code => 'code',
  };
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value == null) {
    return const <String, dynamic>{};
  }
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  throw StateError('Expected a JSON object but received ${value.runtimeType}.');
}

List<Map<String, dynamic>> _asListOfMaps(dynamic value) {
  if (value == null) {
    return const <Map<String, dynamic>>[];
  }
  if (value is! List) {
    throw StateError(
      'Expected a JSON array but received ${value.runtimeType}.',
    );
  }

  return value
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList(growable: false);
}

int _asInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

bool _asBool(dynamic value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  final normalized = value?.toString().trim().toLowerCase();
  return normalized == 'true' || normalized == '1';
}
