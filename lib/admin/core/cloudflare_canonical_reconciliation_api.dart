import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../core/data/exact_json_values.dart';
import 'admin_account_api.dart';
import 'admin_pending_attempt_store.dart';
import 'cloudflare_admin_reconciliation_api.dart'
    show
        ReconciliationMember,
        ReconciliationPage,
        ReconciliationPaymentIdentity,
        ReconciliationReceipt;
import 'cloudflare_admin_repository.dart';
import 'cloudflare_admin_session.dart';
import 'cloudflare_admin_request_identity.dart';

part 'cloudflare_canonical_reconciliation_models.dart';
part 'cloudflare_canonical_reconciliation_attempts.dart';

Never _invalid() => throw const FormatException(
  'The retained evidence response could not be verified.',
);
final _uuid = RegExp(r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$');
bool _id(Object? value) => value is String && _uuid.hasMatch(value);
bool _int(Object? value, {int minimum = 0}) =>
    value is int && value >= minimum && value <= 9007199254740991;
void _keys(Map<dynamic, dynamic> data, Set<String> keys) {
  if (data.length != keys.length || !data.keys.every(keys.contains)) _invalid();
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : _invalid();
void _marker(Map<String, dynamic> data) {
  if (data['contract_version'] != 2 ||
      data['model'] != 'canonical_evidence_ledger') {
    _invalid();
  }
}

DateTime _date(Object? value) =>
    exactJsonTimestamp(value, field: 'Evidence timestamp');
void _reason(String reason) {
  if (reason.trim().length < 8 ||
      reason.trim().length > 500 ||
      RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]').hasMatch(reason)) {
    throw const FormatException('Record a reason of 8 to 500 characters.');
  }
}

class CanonicalReconciliationApi {
  CanonicalReconciliationApi(this.session, {this.pendingStore})
    : _fence = session.authorityFence;
  final CloudflareAdminSession session;
  final AdminPendingAttemptStore? pendingStore;
  final Object _fence;

  CloudflareAdminUser _user(String permission, {bool fresh = false}) {
    final user = session.user;
    if (user == null ||
        _fence != session.authorityFence ||
        !user.usesCanonicalEvidence ||
        user.principalId == null ||
        !user.expiresAt.isAfter(DateTime.now()) ||
        !user.permissions.contains(permission)) {
      throw const AdminAccountException(
        'Reopen this view with the current authorized account.',
      );
    }
    if (fresh && !user.hasRecentSensitiveVerification()) {
      throw AdminAccountException(
        user.usesEmailVerification
            ? 'Verify your email before saving.'
            : 'Complete a current authenticator check before saving.',
      );
    }
    return user;
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    String permission = 'reconciliations.read',
  }) async {
    _user(permission);
    final result = await session.request(path, authenticated: true);
    _user(permission);
    _marker(result);
    return result;
  }

  void _paging(int limit, int offset, String search) {
    if (limit < 1 ||
        limit > 100 ||
        offset < 0 ||
        offset > 2147483647 ||
        search.length > 200 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(search)) {
      throw const FormatException('Choose a valid evidence page or search.');
    }
  }

  ReconciliationPage<T> _page<T>(
    Map<String, dynamic> data,
    T Function(Map<String, dynamic>) parse,
  ) => ReconciliationPage.parse({
    for (final key in const ['rows', 'total', 'limit', 'offset', 'next_offset'])
      key: data[key],
  }, parse);

  Future<ReconciliationPage<Map<String, dynamic>>> queue({
    String search = '',
    String status = '',
    int limit = 25,
    int offset = 0,
  }) async {
    _paging(limit, offset, search);
    if (!const {
      '',
      'recorded',
      'ambiguous',
      'reconciled',
      'confirmed',
      'corrected',
      'reversed',
    }.contains(status)) {
      throw const FormatException('Choose a valid evidence status.');
    }
    final query = Uri(
      queryParameters: {
        'search': search.trim(),
        'status': status,
        'limit': '$limit',
        'offset': '$offset',
      },
    ).query;
    final data = await _get('reconciliations?$query');
    _keys(data, const {
      'contract_version',
      'model',
      'rows',
      'total',
      'limit',
      'offset',
      'next_offset',
    });
    final page = _page(
      data,
      (row) =>
          parseCanonicalEvidenceRecord(CloudflareCoreArea.transactions, row),
    );
    if (page.offset != offset ||
        page.limit != limit ||
        page.rows.map((row) => row['id']).toSet().length != page.rows.length ||
        status.isNotEmpty && page.rows.any((row) => row['status'] != status)) {
      _invalid();
    }
    return page;
  }

  Future<CanonicalReconciliationDetail> detail(
    String id, {
    String? relation,
    int limit = 25,
    int offset = 0,
  }) async {
    _paging(limit, offset, '');
    if (!_id(id) ||
        relation != null &&
            !const {
              'evidence',
              'proposals',
              'ledger_entries',
            }.contains(relation)) {
      throw const FormatException('Choose a valid retained payment.');
    }
    final query = Uri(
      queryParameters: {
        'relation': ?relation,
        'limit': '$limit',
        'offset': '$offset',
      },
    ).query;
    final data = await _get('reconciliations/$id?$query'),
        user = _user('reconciliations.read');
    _keys(data, const {
      'contract_version',
      'model',
      'resource_type',
      'resource',
      'current_actor_id',
      'current_principal_id',
      'can_propose',
      'can_review',
      'group_state',
      'related',
    });
    if (data['resource_type'] != 'reconciliations' ||
        data['current_actor_id'] != user.id ||
        data['current_principal_id'] != user.principalId ||
        data['can_propose'] is! bool ||
        data['can_review'] is! bool) {
      _invalid();
    }
    final record = parseCanonicalEvidenceRecord(
      CloudflareCoreArea.transactions,
      _map(data['resource']),
    );
    if (record['id'] != id) _invalid();
    final group = _map(data['group_state']);
    _keys(group, const {'id', 'status', 'version', 'receiver'});
    if (group['id'] != record['group_id'] ||
        !_int(group['version'], minimum: 1) ||
        !const {'active', 'suspended', 'archived'}.contains(group['status'])) {
      _invalid();
    }
    final receiver = _map(group['receiver']);
    _receiver(receiver);
    group['receiver'] = Map.unmodifiable(receiver);
    final eligible =
        group['status'] == 'active' &&
        const {'recorded', 'ambiguous'}.contains(record['status']) &&
        record['member_user_id'] == null &&
        record['allocated_amount_rwf'] == 0;
    if (data['can_propose'] == true &&
            (!eligible ||
                !user.permissions.contains('reconciliations.propose')) ||
        data['can_review'] == true &&
            (user.role == AdminAccountRole.staff ||
                !user.permissions.contains('reconciliations.review'))) {
      _invalid();
    }
    final raw = _map(data['related']);
    final expected = relation == null
        ? {
            'evidence',
            'proposals',
            if (user.permissions.contains('ledger.read')) 'ledger_entries',
          }
        : {relation};
    _keys(raw, expected);
    final related = <String, ReconciliationPage<Map<String, dynamic>>>{};
    for (final name in expected) {
      final page = ReconciliationPage.parse(
        _map(raw[name]),
        (row) => switch (name) {
          'evidence' => parseCanonicalRetainedEvidence(
            row,
            record['evidence_id'] as String,
          ),
          'proposals' => CanonicalReconciliationProposal.parse(
            row,
            transactionId: id,
            evidenceId: record['evidence_id'] as String,
          ).values,
          'ledger_entries' => _ledger(row, id, record['evidence_id'] as String),
          _ => _invalid(),
        },
      );
      if (page.limit != limit ||
          page.offset != offset ||
          page.rows.map((row) => row['id']).toSet().length !=
              page.rows.length) {
        _invalid();
      }
      related[name] = page;
    }
    return CanonicalReconciliationDetail(
      record,
      Map.unmodifiable(group),
      user.id,
      user.principalId!,
      data['can_propose'] as bool,
      data['can_review'] as bool,
      Map.unmodifiable(related),
    );
  }

  Future<ReconciliationPage<ReconciliationMember>> members(
    CanonicalReconciliationDetail detail, {
    String search = '',
    int limit = 25,
    int offset = 0,
  }) async {
    _paging(limit, offset, search);
    final query = Uri(
      queryParameters: {
        'transaction_id': detail.id,
        'search': search.trim(),
        'limit': '$limit',
        'offset': '$offset',
      },
    ).query;
    final data = await _get(
      'reconciliations/members?$query',
      permission: 'users.read',
    );
    _keys(data, const {
      'contract_version',
      'model',
      'transaction_id',
      'rows',
      'total',
      'limit',
      'offset',
      'next_offset',
    });
    if (data['transaction_id'] != detail.id) _invalid();
    final page = _page(data, ReconciliationMember.parse);
    if (page.offset != offset ||
        page.limit != limit ||
        page.rows.any(
          (member) => member.groupId != detail.transaction['group_id'],
        ) ||
        page.rows.map((member) => member.id).toSet().length !=
            page.rows.length) {
      _invalid();
    }
    return page;
  }

  CanonicalFinancialAttempt propose(
    CanonicalReconciliationDetail detail,
    ReconciliationMember member,
    String reason,
  ) {
    _user('reconciliations.propose', fresh: true);
    _reason(reason);
    if (!detail.canPropose ||
        member.groupId != detail.transaction['group_id'] ||
        !member.identity.eligible ||
        member.values['group_version'] != detail.group['version']) {
      throw const FormatException(
        'Review the current group member and recorded payment identity.',
      );
    }
    return CanonicalFinancialAttempt._(
      const Uuid().v4(),
      detail.id,
      null,
      'propose',
      'reconciliations.propose',
      '/${detail.id}/proposals',
      {
        'member_user_id': member.id,
        'amount_rwf': detail.transaction['amount_rwf'],
        'expected_transaction_version': detail.transaction['version'],
        'expected_member_version': member.memberVersion,
        'expected_membership_version': member.membershipVersion,
        'expected_payment_identity': member.identity.json,
        'reason': reason.trim(),
      },
      _fence,
    );
  }

  CanonicalFinancialAttempt review(
    CanonicalReconciliationDetail detail,
    CanonicalReconciliationProposal proposal,
    String outcome,
    String reason, {
    ReconciliationMember? member,
  }) {
    final user = _user('reconciliations.review', fresh: true);
    _reason(reason);
    if (user.role == AdminAccountRole.staff ||
        !detail.canReview ||
        proposal.values['status'] != 'proposed' ||
        !proposal.snapshotAvailable ||
        proposal.values['payment_id'] != detail.id ||
        proposal.values['proposed_by_principal_id'] == user.principalId ||
        !const {'approved', 'rejected'}.contains(outcome) ||
        outcome == 'approved' && !proposal.currentFor(detail, member)) {
      throw const FormatException(
        'An independent reviewer must confirm the current retained evidence and member identity.',
      );
    }
    final reference = detail.transaction['provider_reference'];
    if (outcome == 'approved' &&
        (reference is! String || reference.trim().isEmpty)) {
      throw const FormatException(
        'Approval needs an independently reviewed event-specific evidence reference. Recording and rejection remain available.',
      );
    }
    return CanonicalFinancialAttempt._(
      const Uuid().v4(),
      detail.id,
      proposal.id,
      'review',
      'reconciliations.review',
      '/proposals/${proposal.id}/reviews',
      {
        'outcome': outcome,
        'expected_proposal_version': proposal.values['version'],
        'expected_transaction_version': detail.transaction['version'],
        'reason': reason.trim(),
      },
      _fence,
    );
  }
}

void _receiver(Map<String, dynamic> value) {
  _keys(value, const {'momo_number_or_code', 'network', 'label'});
  if (value['momo_number_or_code'] is! String ||
      !RegExp(
        r'^(?:07[2389][0-9]{7}|\+?2507[2389][0-9]{7})$',
      ).hasMatch(value['momo_number_or_code'] as String) ||
      !const {'mtn_momo', 'airtel_money'}.contains(value['network']) ||
      value['label'] is! String ||
      (value['label'] as String).trim().isEmpty) {
    _invalid();
  }
}

Map<String, dynamic> _ledger(
  Map<String, dynamic> row,
  String paymentId,
  String evidenceId,
) {
  final result = parseCanonicalEvidenceRecord(CloudflareCoreArea.ledgers, row);
  if (result['payment_id'] != paymentId ||
      result['evidence_id'] != evidenceId) {
    _invalid();
  }
  return result;
}
