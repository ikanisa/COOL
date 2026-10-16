import '../../core/data/exact_json_values.dart';
import '../../core/security/phone_normalizer.dart';

final _allocationUuid = RegExp(
  r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$',
);

String _allocationId(Object? value) {
  if (value is! String || !_allocationUuid.hasMatch(value)) {
    throw const FormatException('Invalid member allocation reference.');
  }
  return value;
}

String _allocationText(Object? value) {
  if (value is! String || value.trim().isEmpty || value.length > 500) {
    throw const FormatException('Member allocation details are incomplete.');
  }
  return value;
}

class AdminAllocationMember {
  AdminAllocationMember._(Map<String, dynamic> json)
    : memberId = _allocationId(json['member_id']),
      displayName = _allocationText(json['display_name']),
      collectId = _allocationText(json['collect_id']),
      momoNumber = _allocationText(json['momo_number']),
      momoRegisteredName = json['momo_registered_name'] == null
          ? null
          : _allocationText(json['momo_registered_name']),
      collectionId = _allocationId(json['collection_id']),
      collectionName = _allocationText(json['collection_name']),
      paymentIntentId = json['payment_intent_id'] == null
          ? null
          : _allocationId(json['payment_intent_id']),
      directAssignmentId = json['direct_assignment_id'] == null
          ? null
          : _allocationId(json['direct_assignment_id']),
      eligible = json['eligible'] == true,
      unavailableReason = json['unavailable_reason'] == null
          ? null
          : _allocationText(json['unavailable_reason']);

  final String memberId, displayName, collectId, momoNumber;
  final String? momoRegisteredName;
  final String collectionId, collectionName;
  final String? paymentIntentId, directAssignmentId, unavailableReason;
  final bool eligible;
  String get key =>
      '$memberId/$collectionId/$paymentIntentId/$directAssignmentId';

  factory AdminAllocationMember.parse(Map<String, dynamic> json) {
    const keys = {
      'member_id',
      'display_name',
      'collect_id',
      'momo_number',
      'momo_registered_name',
      'collection_id',
      'collection_name',
      'payment_intent_id',
      'direct_assignment_id',
      'eligible',
      'unavailable_reason',
    };
    if (json.length != keys.length ||
        !json.keys.every(keys.contains) ||
        json['eligible'] is! bool) {
      throw const FormatException('Invalid member search result.');
    }
    final member = AdminAllocationMember._(json);
    final candidateCount =
        (member.paymentIntentId == null ? 0 : 1) +
        (member.directAssignmentId == null ? 0 : 1);
    if (!RegExp(r'^[0-9]{6}$').hasMatch(member.collectId) ||
        PhoneNormalizer.normalizeRwanda(member.momoNumber) !=
            member.momoNumber ||
        (member.eligible
            ? candidateCount != 1 || member.unavailableReason != null
            : candidateCount != 0 || member.unavailableReason == null)) {
      throw const FormatException('Member search result is not verifiable.');
    }
    return member;
  }
}

class AdminAllocationMemberPage {
  const AdminAllocationMemberPage._(this.rows, this.total);
  final List<AdminAllocationMember> rows;
  final int total;

  factory AdminAllocationMemberPage.parse(
    Map<String, dynamic> json, {
    required int limit,
    required int offset,
  }) {
    final raw = json['rows'];
    final total = json['total'];
    if (json.length != 2 ||
        raw is! List ||
        total is! int ||
        total < 0 ||
        total > maxExactJsonInteger) {
      throw const FormatException('Invalid member search response.');
    }
    final remaining = total - offset;
    final expected = remaining <= 0 ? 0 : remaining.clamp(0, limit);
    if (raw.length != expected || raw.any((item) => item is! Map)) {
      throw const FormatException('Member search page is incomplete.');
    }
    final rows = [
      for (final item in raw)
        AdminAllocationMember.parse(Map<String, dynamic>.from(item as Map)),
    ];
    if (rows.map((row) => row.key).toSet().length != rows.length) {
      throw const FormatException('Member search has duplicate candidates.');
    }
    return AdminAllocationMemberPage._(List.unmodifiable(rows), total);
  }
}

class AdminMemberAllocationReceipt {
  const AdminMemberAllocationReceipt._(this.paymentId);
  final String paymentId;
  String get message =>
      'Member allocation recorded. Independent provider confirmation is still required.';

  factory AdminMemberAllocationReceipt.parse(
    Map<String, dynamic> json, {
    required String eventId,
    required AdminAllocationMember member,
  }) {
    const keys = {
      'status',
      'payment_id',
      'event_id',
      'member_id',
      'collection_id',
      'momo_number',
      'display_name',
      'momo_registered_name',
      'ledger_posted',
    };
    if (json.length != keys.length ||
        !json.keys.every(keys.contains) ||
        json['status'] != 'awaiting_provider_confirmation' ||
        json['ledger_posted'] != false ||
        json['event_id'] != eventId ||
        json['member_id'] != member.memberId ||
        json['collection_id'] != member.collectionId ||
        json['momo_number'] != member.momoNumber ||
        json['display_name'] != member.displayName ||
        json['momo_registered_name'] != member.momoRegisteredName) {
      throw const FormatException('Member allocation was not confirmed.');
    }
    return AdminMemberAllocationReceipt._(_allocationId(json['payment_id']));
  }
}

abstract class AdminExistingMemberAllocationApi {
  Future<AdminAllocationMemberPage> search({
    required String eventId,
    required String query,
    int limit = 10,
    int offset = 0,
  });
  Future<AdminMemberAllocationReceipt> allocate({
    required String eventId,
    required AdminAllocationMember member,
    required String reason,
  });
}

typedef AdminMemberAllocationRpc =
    Future<Map<String, dynamic>> Function(
      String name,
      Map<String, dynamic> parameters,
    );

class AdminExistingMemberAllocationSdk
    implements AdminExistingMemberAllocationApi {
  const AdminExistingMemberAllocationSdk({required this.rpc});
  final AdminMemberAllocationRpc rpc;

  @override
  Future<AdminAllocationMemberPage> search({
    required String eventId,
    required String query,
    int limit = 10,
    int offset = 0,
  }) async {
    _allocationId(eventId);
    final search = query.trim();
    if (search.length < 3 ||
        search.length > 80 ||
        limit < 1 ||
        limit > 25 ||
        offset < 0 ||
        offset > 10000) {
      throw const FormatException('Enter at least 3 characters to search.');
    }
    return AdminAllocationMemberPage.parse(
      await rpc('admin_search_allocation_members_v1', {
        'p_event_id': eventId,
        'p_search': search,
        'p_limit': limit,
        'p_offset': offset,
      }),
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<AdminMemberAllocationReceipt> allocate({
    required String eventId,
    required AdminAllocationMember member,
    required String reason,
  }) async {
    _allocationId(eventId);
    final cleanReason = reason.trim();
    if (!member.eligible ||
        cleanReason.length < 8 ||
        cleanReason.length > 500) {
      throw const FormatException(
        'Confirm an eligible member and allocation reason.',
      );
    }
    final result = await rpc('admin_allocate_existing_member_v1', {
      'p_event_id': eventId,
      'p_member_id': member.memberId,
      'p_momo_number': member.momoNumber,
      'p_display_name': member.displayName,
      'p_momo_registered_name': member.momoRegisteredName,
      'p_collection_id': member.collectionId,
      'p_payment_intent_id': member.paymentIntentId,
      'p_direct_assignment_id': member.directAssignmentId,
      'p_reason': cleanReason,
    });
    return AdminMemberAllocationReceipt.parse(
      result,
      eventId: eventId,
      member: member,
    );
  }
}
