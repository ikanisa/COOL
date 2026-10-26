import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import 'admin_account_api.dart';
import 'cloudflare_admin_session.dart';

final _uuid = RegExp(
  r'^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
  caseSensitive: false,
);
final _hash = RegExp(r'^[a-f0-9]{64}$');
const _permissions = ['assisted_sms.read', 'assisted_sms.manage'];
const _template = 'collect.recorded_contribution.v1';
const _marker = {
  'contract_version',
  'scope',
  'legal_release_approved',
  'provider_approved',
  'delivery_confirmed',
};

Never _invalid() => throw const FormatException(
  'The receipt SMS configuration response could not be verified.',
);
String _id(Object? value) =>
    value is String && _uuid.hasMatch(value) ? value.toLowerCase() : _invalid();
String _digest(Object? value) =>
    value is String && _hash.hasMatch(value) ? value : _invalid();
bool _boolean(Object? value) => value is bool ? value : _invalid();
int _revision(Object? value, {int minimum = 0, int maximum = 999999999}) =>
    value is int && value >= minimum && value <= maximum ? value : _invalid();
const _maximumDecisionRevision = 9007199254740991;
int _decisionRevision(Object? value, {int minimum = 0}) =>
    value is int && value >= minimum && value <= _maximumDecisionRevision
    ? value
    : _invalid();
Map<String, dynamic> _map(Object? value) {
  if (value is! Map || !value.keys.every((key) => key is String)) _invalid();
  return Map<String, dynamic>.from(value);
}

void _keys(Map<String, dynamic> row, Set<String> required) {
  if (row.length != required.length || !required.every(row.containsKey)) {
    _invalid();
  }
}

DateTime _timestamp(Object? value) {
  if (value is! String ||
      !RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$').hasMatch(value)) {
    _invalid();
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || parsed.toUtc().toIso8601String() != value) _invalid();
  return parsed;
}

void _markers(Map<String, dynamic> row, String scope, Set<String> fields) {
  _keys(row, {..._marker, ...fields});
  if (row['contract_version'] is! int ||
      row['contract_version'] != 1 ||
      row['scope'] != scope ||
      row['legal_release_approved'] != false ||
      row['provider_approved'] != false ||
      row['delivery_confirmed'] != false) {
    _invalid();
  }
}

void _permissionNames(Object? raw) {
  if (raw is! List ||
      raw.length != _permissions.length ||
      raw[0] != _permissions[0] ||
      raw[1] != _permissions[1]) {
    _invalid();
  }
}

String _stable(Object? value) {
  if (value is Map<String, dynamic>) {
    final keys = value.keys.toList()..sort();
    return '{${keys.map((key) => '${jsonEncode(key)}:${_stable(value[key])}').join(',')}}';
  }
  if (value is List) return '[${value.map(_stable).join(',')}]';
  return jsonEncode(value);
}

void _decision(Map<String, dynamic> row, Set<String> fields, String hashField) {
  final decision = {for (final field in fields) field: row[field]};
  if (sha256.convert(utf8.encode(_stable(decision))).toString() !=
      _digest(row[hashField])) {
    _invalid();
  }
}

class NotificationManagementAccessState {
  NotificationManagementAccessState._(this._owner, Map<String, dynamic> row)
    : adminId = _id(row['current_admin_id']),
      principalId = _id(row['current_principal_id']),
      decisionRevision = _decisionRevision(row['decision_revision']),
      readGranted = _boolean(row['read_granted']),
      manageGranted = _boolean(row['manage_granted']),
      canOperate = _boolean(row['can_operate']) {
    _markers(row, 'owner_receipt_sms_access', {
      'current_admin_id',
      'current_principal_id',
      'decision_revision',
      'read_granted',
      'manage_granted',
      'can_operate',
      'permissions',
    });
    _permissionNames(row['permissions']);
    if (canOperate != (readGranted && manageGranted)) _invalid();
  }
  final Object _owner;
  final String adminId, principalId;
  final int decisionRevision;
  final bool readGranted, manageGranted, canOperate;
}

class NotificationManagementPolicyState {
  NotificationManagementPolicyState._(this._owner, Map<String, dynamic> row)
    : collectionId = _id(row['collection_id']),
      configured = _boolean(row['configured']),
      enabled = _boolean(row['enabled']),
      revision = _revision(row['revision']),
      collectionActive = _boolean(row['collection_active']),
      recordedOwnerDecisionSha256 =
          row['recorded_owner_decision_sha256'] == null
          ? null
          : _digest(row['recorded_owner_decision_sha256']),
      recordedAt = row['recorded_at'] == null
          ? null
          : _timestamp(row['recorded_at']) {
    _markers(row, 'owner_receipt_sms_configuration', {
      'collection_id',
      'configured',
      'enabled',
      'revision',
      'template_key',
      'recorded_owner_decision_sha256',
      'recorded_at',
      'collection_active',
    });
    if (row['template_key'] != _template ||
        (configured
            ? revision < 1 ||
                  recordedOwnerDecisionSha256 == null ||
                  recordedAt == null
            : revision != 0 ||
                  enabled ||
                  recordedOwnerDecisionSha256 != null ||
                  recordedAt != null)) {
      _invalid();
    }
  }
  final Object _owner;
  final String collectionId;
  final bool configured, enabled, collectionActive;
  final int revision;
  String get templateKey => _template;
  final String? recordedOwnerDecisionSha256;
  final DateTime? recordedAt;
}

/// An immutable historical write receipt. It is never current access/policy.
sealed class NotificationManagementReceipt {
  const NotificationManagementReceipt(this.requestId);
  final String requestId;
  String get action;
  bool get recordedStateOnly => true;
}

class NotificationManagementAccessReceipt
    extends NotificationManagementReceipt {
  NotificationManagementAccessReceipt._(Map<String, dynamic> row)
    : adminId = _id(row['current_admin_id']),
      principalId = _id(row['current_principal_id']),
      decisionRevision = _decisionRevision(
        row['decision_revision'],
        minimum: 1,
      ),
      grantTransactionId = _id(row['grant_transaction_id']),
      originatingSessionId = _id(row['originating_session_id']),
      publicSessionId = _id(row['public_session_id']),
      enabled = _boolean(row['enabled']),
      readGranted = _boolean(row['read_granted']),
      manageGranted = _boolean(row['manage_granted']),
      canOperate = _boolean(row['can_operate']),
      recordedAt = _timestamp(row['recorded_at']),
      decisionSha256 = _digest(row['decision_sha256']),
      replay = _boolean(row['replay']),
      super(_id(row['request_id'])) {
    _markers(row, 'owner_receipt_sms_access', {
      'kind',
      'request_id',
      'grant_transaction_id',
      'current_admin_id',
      'current_principal_id',
      'decision_revision',
      'originating_session_id',
      'public_session_id',
      'enabled',
      'permissions',
      'recorded_at',
      'read_granted',
      'manage_granted',
      'can_operate',
      'decision_sha256',
      'recorded_state_only',
      'replay',
    });
    _permissionNames(row['permissions']);
    if (row['kind'] != 'authenticated_owner_receipt_sms_access' ||
        row['recorded_state_only'] != true ||
        readGranted != enabled ||
        manageGranted != enabled ||
        canOperate != enabled) {
      _invalid();
    }
    _decision(row, {
      'kind',
      'request_id',
      'grant_transaction_id',
      'current_admin_id',
      'current_principal_id',
      // The qualified backend contract binds the immutable decision hash to
      // its recorded head; current access is fetched separately.
      'decision_revision',
      'originating_session_id',
      'public_session_id',
      'enabled',
      'permissions',
      'recorded_at',
    }, 'decision_sha256');
  }
  final String adminId,
      principalId,
      grantTransactionId,
      originatingSessionId,
      publicSessionId,
      decisionSha256;
  final bool enabled, readGranted, manageGranted, canOperate, replay;
  final int decisionRevision;
  final DateTime recordedAt;
  @override
  String get action => 'access';
}

class NotificationManagementPolicyReceipt
    extends NotificationManagementReceipt {
  NotificationManagementPolicyReceipt._(Map<String, dynamic> row)
    : collectionId = _id(row['collection_id']),
      revision = _revision(row['revision'], minimum: 1),
      enabled = _boolean(row['enabled']),
      ownerUserId = _id(row['owner_user_id']),
      originatingSessionId = _id(row['originating_session_id']),
      publicSessionId = _id(row['public_session_id']),
      recordedAt = _timestamp(row['recorded_at']),
      recordedOwnerDecisionSha256 = _digest(
        row['recorded_owner_decision_sha256'],
      ),
      super(_id(row['request_id'])) {
    _markers(row, 'owner_receipt_sms_configuration', {
      'kind',
      'request_id',
      'collection_id',
      'revision',
      'enabled',
      'template_key',
      'owner_user_id',
      'originating_session_id',
      'public_session_id',
      'recorded_at',
      'recorded_owner_decision_sha256',
    });
    if (row['kind'] != 'authenticated_owner_receipt_sms_policy' ||
        row['template_key'] != _template) {
      _invalid();
    }
    _decision(row, {
      'kind',
      'request_id',
      'collection_id',
      'revision',
      'enabled',
      'template_key',
      'owner_user_id',
      'originating_session_id',
      'public_session_id',
      'recorded_at',
      'legal_release_approved',
      'provider_approved',
    }, 'recorded_owner_decision_sha256');
  }
  final String collectionId,
      ownerUserId,
      originatingSessionId,
      publicSessionId,
      recordedOwnerDecisionSha256;
  final int revision;
  final bool enabled;
  final DateTime recordedAt;
  String get templateKey => _template;
  @override
  String get action => 'policy';
}

enum NotificationManagementHistoryKind { access, policy, materialization }

enum NotificationManagementRecordedStatus { recorded, notRecorded }

String _statusPrefix(NotificationManagementHistoryKind kind) => switch (kind) {
  NotificationManagementHistoryKind.access =>
    '/api/admin/notification-operator/access/operations/',
  NotificationManagementHistoryKind.policy =>
    '/api/admin/notification-operator/policies/operations/',
  NotificationManagementHistoryKind.materialization =>
    '/api/admin/notification-operator/materialize/',
};

/// An opaque seek boundary from one verified page, owned by this API/fence.
/// It cannot be reconstructed from local metadata or another sign-in.
class NotificationManagementHistoryCursor {
  const NotificationManagementHistoryCursor._(
    this._owner,
    this._fence,
    this.recordedAt,
    this.requestId,
  );
  final Object _owner;
  final ({int epoch, Object? key}) _fence;
  final DateTime recordedAt;
  final String requestId;
}

/// Server-recorded metadata only. A status path supplies no read, replay or send
/// authority; callers choose a dedicated typed method with its current guard.
class NotificationManagementHistoryItem {
  NotificationManagementHistoryItem._(Map<String, dynamic> row)
    : requestId = _id(row['request_id']),
      recordedAt = _timestamp(row['recorded_at']),
      kind = switch (row['kind']) {
        'access' => NotificationManagementHistoryKind.access,
        'policy' => NotificationManagementHistoryKind.policy,
        'materialization' => NotificationManagementHistoryKind.materialization,
        _ => _invalid(),
      } {
    _keys(row, {
      'request_id',
      'kind',
      'recorded_at',
      'recorded_outcome',
      'status_path',
      'recorded_state_only',
      'may_send',
    });
    if (row['request_id'] != requestId ||
        row['recorded_outcome'] != recordedOutcome ||
        row['status_path'] != statusPath ||
        row['recorded_state_only'] != true ||
        row['may_send'] != false) {
      _invalid();
    }
  }
  final String requestId;
  final DateTime recordedAt;
  final NotificationManagementHistoryKind kind;
  String get recordedOutcome =>
      kind == NotificationManagementHistoryKind.materialization
      ? 'plan_recorded'
      : 'decision_recorded';
  String get statusPath => _statusPrefix(kind) + requestId;
  bool get recordedStateOnly => true;
  bool get maySend => false;
}

class NotificationManagementHistoryPage {
  NotificationManagementHistoryPage._(
    List<NotificationManagementHistoryItem> items,
    this.nextCursor,
  ) : items = List.unmodifiable(items);
  final List<NotificationManagementHistoryItem> items;
  final NotificationManagementHistoryCursor? nextCursor;
  bool get originalSessionOnly => true;
  bool get recordedStateOnly => true;
  bool get maySend => false;
  bool get replayAuthorized => false;
}

class NotificationManagementAccessOperationStatus {
  const NotificationManagementAccessOperationStatus._(
    this.requestId,
    this.recordedDecision,
    this.currentAccess,
  );
  final String requestId;
  final NotificationManagementAccessReceipt? recordedDecision;
  final NotificationManagementAccessState currentAccess;
  bool get observed => recordedDecision != null;
  NotificationManagementRecordedStatus get status => observed
      ? NotificationManagementRecordedStatus.recorded
      : NotificationManagementRecordedStatus.notRecorded;
  bool get mayBeInFlight => !observed;
  bool get recordedStateOnly => true;
  bool get maySend => false;
  bool get replayAuthorized => false;
}

class NotificationManagementPolicyOperationStatus {
  const NotificationManagementPolicyOperationStatus._(
    this.requestId,
    this.recordedDecision,
  );
  final String requestId;
  final NotificationManagementPolicyReceipt? recordedDecision;
  bool get observed => recordedDecision != null;
  NotificationManagementRecordedStatus get status => observed
      ? NotificationManagementRecordedStatus.recorded
      : NotificationManagementRecordedStatus.notRecorded;
  bool get mayBeInFlight => !observed;
  bool get recordedStateOnly => true;
  bool get maySend => false;
  bool get replayAuthorized => false;
}

bool _olderHistory(
  DateTime at,
  String id,
  DateTime boundaryAt,
  String boundaryId,
) =>
    at.isBefore(boundaryAt) || at == boundaryAt && id.compareTo(boundaryId) < 0;

/// Exact body and original authority stay in RAM. No reconstruction adapter.
class NotificationManagementOperation {
  NotificationManagementOperation._(
    this._owner,
    this._fence,
    this.action,
    this.requestId,
    this.resourceId,
    this.expectedDecisionRevision,
    this._path,
    Map<String, dynamic> body,
  ) : _body = Map.unmodifiable(body);
  final Object _owner;
  final ({int epoch, Object? key}) _fence;
  final String action, requestId, resourceId, _path;
  final int? expectedDecisionRevision;
  final Map<String, dynamic> _body;
  bool _dispatched = false, _inFlight = false;
  bool get dispatched => _dispatched;
}

class NotificationManagementRequestException
    extends CloudflareAdminRequestException {
  NotificationManagementRequestException({
    required this.operation,
    required this.cause,
  }) : super(
         'The result is unknown. Keep the original request and check its receipt.',
         outcomeUnknown: true,
         statusCode: cause is CloudflareAdminRequestException
             ? cause.statusCode
             : null,
         code: cause is CloudflareAdminRequestException ? cause.code : null,
       );
  final NotificationManagementOperation operation;
  final Object cause;
}

class NotificationManagementResolution {
  NotificationManagementResolution._(
    this.requestId,
    this.observed,
    this.receipt,
  );
  final String requestId;
  final bool observed;
  final NotificationManagementReceipt? receipt;
}

class CloudflareAdminNotificationManagementApi {
  CloudflareAdminNotificationManagementApi(
    this.session, {
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       _fence = session.authorityFence;
  final CloudflareAdminSession session;
  final DateTime Function() _now;
  final ({int epoch, Object? key}) _fence;
  final Object _owner = Object();
  final Set<String> _requestIds = {};
  bool get authorityCurrent =>
      session.mounted && session.authorityFence == _fence;
  bool _allowed(String permission) {
    final user = session.user, now = _now();
    return authorityCurrent &&
        !session.logoutUnconfirmed &&
        user != null &&
        user.role == AdminAccountRole.owner &&
        user.email == 'info@ikanisa.com' &&
        user.principalId != null &&
        _uuid.hasMatch(user.principalId!) &&
        user.permissions.contains(permission) &&
        user.hasRecentSensitiveVerification(now: now);
  }

  bool get canManageAccess => _allowed('admin_users.manage');
  bool get canManagePolicy => _allowed('assisted_sms.manage');
  bool get canResolveOperations => canManagePolicy;
  bool get canReadHistory => canManageAccess;
  bool get canReadAccessOperation => canManageAccess;
  bool get canReadPolicyOperation => canManagePolicy;
  void _guard({bool access = false}) {
    if (!(access ? canManageAccess : canManagePolicy)) {
      throw AdminAccountException(
        session.user?.usesEmailVerification == true
            ? 'Reopen receipt SMS configuration with current owner access and recent email verification.'
            : 'Reopen receipt SMS configuration with current owner access and fresh authenticator verification.',
      );
    }
  }

  void _owned(Object owner, {bool access = false}) {
    _guard(access: access);
    if (!identical(owner, _owner)) {
      throw const AdminAccountException(
        'Reload the current receipt SMS configuration.',
      );
    }
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, dynamic>? body,
    bool access = false,
  }) async {
    _guard(access: access);
    final result = await session.request(
      path,
      body: body,
      authenticated: true,
      method: body == null ? 'GET' : 'POST',
    );
    _guard(access: access);
    _keys(result, {'ok', 'result'});
    if (result['ok'] != true) _invalid();
    return _map(result['result']);
  }

  void _identity(String adminId, String principalId) {
    if (adminId != _id(session.user?.id) ||
        principalId != _id(session.user?.principalId)) {
      _invalid();
    }
  }

  Future<NotificationManagementAccessState> getAccess() async {
    final state = NotificationManagementAccessState._(
      _owner,
      await _request('notification-operator/access', access: true),
    );
    _identity(state.adminId, state.principalId);
    return state;
  }

  Future<NotificationManagementPolicyState> getPolicy(
    String collectionId,
  ) async {
    final normalized = _id(collectionId);
    final state = NotificationManagementPolicyState._(
      _owner,
      await _request('notification-operator/policies/$normalized'),
    );
    if (state.collectionId != normalized) _invalid();
    return state;
  }

  /// Current original-session metadata. A missing row/page is never proof that
  /// an outstanding original request failed or may be submitted with a new UUID.
  Future<NotificationManagementHistoryPage> getHistory({
    int limit = 25,
    NotificationManagementHistoryCursor? after,
  }) async {
    _guard(access: true);
    if (limit < 1 || limit > 25) {
      throw ArgumentError.value(
        limit,
        'limit',
        'Use one to twenty-five records.',
      );
    }
    if (after != null) {
      _owned(after._owner, access: true);
      if (after._fence != _fence) {
        throw ArgumentError('Use the cursor under its original authority.');
      }
    }
    final query = Uri(
      queryParameters: {
        'limit': '$limit',
        if (after != null)
          'after_created_at': after.recordedAt.toUtc().toIso8601String(),
        if (after != null) 'after_request_id': after.requestId,
      },
    ).query;
    final row = await _request(
      'notification-operator/operations?$query',
      access: true,
    );
    _markers(row, 'own_receipt_sms_request_history', {
      'items',
      'next_cursor',
      'original_session_only',
      'recorded_state_only',
      'may_send',
      'replay_authorized',
    });
    if (row['original_session_only'] != true ||
        row['recorded_state_only'] != true ||
        row['may_send'] != false ||
        row['replay_authorized'] != false ||
        row['items'] is! List ||
        (row['items'] as List).length > limit) {
      _invalid();
    }
    final items = <NotificationManagementHistoryItem>[];
    final ids = <String>{};
    DateTime? boundaryAt = after?.recordedAt;
    String? boundaryId = after?.requestId;
    for (final raw in row['items'] as List) {
      final item = NotificationManagementHistoryItem._(_map(raw));
      if (!ids.add(item.requestId) ||
          boundaryAt != null &&
              !_olderHistory(
                item.recordedAt,
                item.requestId,
                boundaryAt,
                boundaryId!,
              )) {
        _invalid();
      }
      items.add(item);
      boundaryAt = item.recordedAt;
      boundaryId = item.requestId;
    }
    NotificationManagementHistoryCursor? next;
    if (row['next_cursor'] != null) {
      final raw = _map(row['next_cursor']);
      _keys(raw, {'after_created_at', 'after_request_id'});
      final at = _timestamp(raw['after_created_at']),
          id = _id(raw['after_request_id']);
      if (items.length != limit ||
          raw['after_request_id'] != id ||
          items.last.recordedAt != at ||
          items.last.requestId != id) {
        _invalid();
      }
      next = NotificationManagementHistoryCursor._(_owner, _fence, at, id);
    }
    return NotificationManagementHistoryPage._(items, next);
  }

  void _statusOriginal(
    NotificationManagementOperation? original,
    String rid,
    String action, {
    required bool access,
  }) {
    if (original == null) return;
    _owned(original._owner, access: access);
    if (original.requestId != rid ||
        original.action != action ||
        original._fence != _fence) {
      throw ArgumentError(
        'Use the exact original operation under its original authority.',
      );
    }
  }

  void _statusEnvelope(
    Map<String, dynamic> row,
    String scope,
    String rid, {
    bool access = false,
  }) {
    _markers(row, scope, {
      'request_id',
      'observed',
      'status',
      'may_be_in_flight',
      'recorded_decision',
      'recorded_state_only',
      'may_send',
      'replay_authorized',
      if (access) 'current_access',
    });
    final observed = _boolean(row['observed']);
    if (row['request_id'] != rid ||
        row['status'] != (observed ? 'recorded' : 'not_recorded') ||
        row['may_be_in_flight'] != !observed ||
        (row['recorded_decision'] != null) != observed ||
        row['recorded_state_only'] != true ||
        row['may_send'] != false ||
        row['replay_authorized'] != false) {
      _invalid();
    }
  }

  /// Readable after assisted self-disable under actual Owner/admin_users.manage.
  /// Historical head/booleans are never substituted for the separately current read.
  Future<NotificationManagementAccessOperationStatus> getAccessOperation(
    String requestId, {
    NotificationManagementOperation? originalOperation,
  }) async {
    final rid = _id(requestId);
    _guard(access: true);
    _statusOriginal(originalOperation, rid, 'access', access: true);
    final row = await _request(
      'notification-operator/access/operations/$rid',
      access: true,
    );
    _statusEnvelope(
      row,
      'owner_receipt_sms_access_operation',
      rid,
      access: true,
    );
    final current = NotificationManagementAccessState._(
      _owner,
      _map(row['current_access']),
    );
    _identity(current.adminId, current.principalId);
    NotificationManagementAccessReceipt? receipt;
    if (row['recorded_decision'] != null) {
      receipt = NotificationManagementAccessReceipt._(
        _map(row['recorded_decision']),
      );
      _identity(receipt.adminId, receipt.principalId);
      if (receipt.requestId != rid ||
          receipt.replay ||
          receipt.publicSessionId != _id(session.user?.sessionId) ||
          current.decisionRevision < receipt.decisionRevision) {
        _invalid();
      }
      if (originalOperation != null) _match(originalOperation, receipt);
    }
    return NotificationManagementAccessOperationStatus._(rid, receipt, current);
  }

  /// This endpoint returns no current policy. Use getPolicy separately with the
  /// verified collection ID; absence remains an uncertain original outcome.
  Future<NotificationManagementPolicyOperationStatus> getPolicyOperation(
    String requestId, {
    NotificationManagementOperation? originalOperation,
  }) async {
    final rid = _id(requestId);
    _guard();
    _statusOriginal(originalOperation, rid, 'policy', access: false);
    final row = await _request(
      'notification-operator/policies/operations/$rid',
    );
    _statusEnvelope(row, 'owner_receipt_sms_policy_operation', rid);
    NotificationManagementPolicyReceipt? receipt;
    if (row['recorded_decision'] != null) {
      receipt = NotificationManagementPolicyReceipt._(
        _map(row['recorded_decision']),
      );
      if (receipt.requestId != rid ||
          receipt.ownerUserId != _id(session.user?.principalId) ||
          receipt.publicSessionId != _id(session.user?.sessionId)) {
        _invalid();
      }
      if (originalOperation != null) _match(originalOperation, receipt);
    }
    return NotificationManagementPolicyOperationStatus._(rid, receipt);
  }

  NotificationManagementOperation _prepare(
    String action,
    String resourceId,
    String path,
    Map<String, dynamic> body,
    String? requestId, {
    int? expectedDecisionRevision,
  }) {
    final rid = _id(requestId ?? const Uuid().v4());
    if (!_requestIds.add(rid)) {
      throw StateError(
        'Keep the original request object for explicit reconciliation.',
      );
    }
    return NotificationManagementOperation._(
      _owner,
      _fence,
      action,
      rid,
      resourceId,
      expectedDecisionRevision,
      path,
      {'request_id': rid, ...body},
    );
  }

  NotificationManagementOperation prepareAccess({
    required NotificationManagementAccessState expected,
    required bool enabled,
    required bool ownerConfirmation,
    String? requestId,
  }) {
    _owned(expected._owner, access: true);
    _identity(expected.adminId, expected.principalId);
    if (expected.decisionRevision >= _maximumDecisionRevision) {
      throw StateError('The receipt SMS decision revision cannot advance.');
    }
    if (enabled && !ownerConfirmation) {
      throw ArgumentError(
        'Explicit owner confirmation is required before enabling access.',
      );
    }
    return _prepare(
      'access',
      expected.principalId,
      'notification-operator/access',
      {
        'expected_read': expected.readGranted,
        'expected_manage': expected.manageGranted,
        'expected_decision_revision': expected.decisionRevision,
        'enabled': enabled,
        'owner_confirmation': ownerConfirmation,
      },
      requestId,
      expectedDecisionRevision: expected.decisionRevision,
    );
  }

  NotificationManagementOperation preparePolicy({
    required NotificationManagementPolicyState expected,
    required bool enabled,
    required bool ownerConfirmation,
    String? requestId,
  }) {
    _owned(expected._owner);
    if (expected.revision > 999999998 ||
        enabled && (!ownerConfirmation || !expected.collectionActive)) {
      throw ArgumentError(
        'A current active group and explicit owner confirmation are required.',
      );
    }
    return _prepare(
      'policy',
      expected.collectionId,
      'notification-operator/policies/${expected.collectionId}',
      {
        'expected_revision': expected.revision,
        'enabled': enabled,
        'owner_confirmation': ownerConfirmation,
      },
      requestId,
    );
  }

  Future<T> _dispatch<T>(
    NotificationManagementOperation operation,
    String action,
    T Function(Map<String, dynamic>) parse, {
    bool replay = false,
  }) async {
    _owned(operation._owner, access: action == 'access');
    if (operation.action != action || operation._fence != _fence) {
      throw ArgumentError('Use the exact original receipt SMS operation.');
    }
    if (operation._inFlight || operation.dispatched != replay) {
      throw StateError(
        'Only an explicit replay of the original dispatched request is supported.',
      );
    }
    operation._dispatched = true;
    operation._inFlight = true;
    try {
      return parse(
        await _request(
          operation._path,
          body: operation._body,
          access: action == 'access',
        ),
      );
    } catch (error) {
      throw NotificationManagementRequestException(
        operation: operation,
        cause: error,
      );
    } finally {
      operation._inFlight = false;
    }
  }

  void _match(
    NotificationManagementOperation operation,
    NotificationManagementReceipt receipt,
  ) {
    if (receipt.requestId != operation.requestId ||
        receipt.action != operation.action) {
      _invalid();
    }
    switch (receipt) {
      case NotificationManagementAccessReceipt():
        _identity(receipt.adminId, receipt.principalId);
        final expectedRevision = operation.expectedDecisionRevision;
        if (receipt.principalId != operation.resourceId ||
            receipt.enabled != operation._body['enabled'] ||
            expectedRevision == null ||
            receipt.decisionRevision != expectedRevision + 1 ||
            receipt.publicSessionId != _id(session.user?.sessionId)) {
          _invalid();
        }
      case NotificationManagementPolicyReceipt():
        if (receipt.collectionId != operation.resourceId ||
            receipt.revision !=
                (operation._body['expected_revision'] as int) + 1 ||
            receipt.enabled != operation._body['enabled'] ||
            receipt.ownerUserId != _id(session.user?.principalId) ||
            receipt.publicSessionId != _id(session.user?.sessionId)) {
          _invalid();
        }
    }
  }

  Future<NotificationManagementAccessReceipt> _access(
    NotificationManagementOperation operation, {
    bool replay = false,
  }) => _dispatch(operation, 'access', (row) {
    final receipt = NotificationManagementAccessReceipt._(row);
    _match(operation, receipt);
    return receipt;
  }, replay: replay);
  Future<NotificationManagementAccessReceipt> setAccess(
    NotificationManagementOperation operation,
  ) => _access(operation);
  Future<NotificationManagementAccessReceipt> replayAccess(
    NotificationManagementOperation original,
  ) => _access(original, replay: true);
  Future<NotificationManagementPolicyReceipt> _policy(
    NotificationManagementOperation operation, {
    bool replay = false,
  }) => _dispatch(operation, 'policy', (row) {
    final receipt = NotificationManagementPolicyReceipt._(row);
    _match(operation, receipt);
    return receipt;
  }, replay: replay);
  Future<NotificationManagementPolicyReceipt> setPolicy(
    NotificationManagementOperation operation,
  ) => _policy(operation);
  Future<NotificationManagementPolicyReceipt> replayPolicy(
    NotificationManagementOperation original,
  ) => _policy(original, replay: true);

  /// Receipt-only lookup uses the existing operator contract. It requires the
  /// actual assisted_sms.manage grant, including after a self-access change.
  Future<NotificationManagementResolution> getOperation(
    String requestId, {
    NotificationManagementOperation? originalOperation,
  }) async {
    final rid = _id(requestId);
    if (originalOperation != null) {
      _owned(originalOperation._owner);
      if (originalOperation.requestId != rid ||
          originalOperation._fence != _fence) {
        throw ArgumentError(
          'Use the original request under its original authority.',
        );
      }
    }
    final row = await _request(
      'notification-operator',
      body: {'action': 'get_operation', 'request_id': rid},
    );
    _keys(row, {
      'contract_version',
      'scope',
      'delivery_confirmed',
      'provider_confirmation',
      'settlement_status',
      'request_id',
      'observed',
      'receipt',
      'may_send',
    });
    if (row['contract_version'] is! int ||
        row['contract_version'] != 1 ||
        row['scope'] != 'assisted_sms_internal_record' ||
        row['delivery_confirmed'] != false ||
        row['provider_confirmation'] != false ||
        row['settlement_status'] != 'not_asserted' ||
        _id(row['request_id']) != rid ||
        row['observed'] is! bool ||
        row['may_send'] != false ||
        (row['observed'] == false) != (row['receipt'] == null)) {
      _invalid();
    }
    NotificationManagementReceipt? receipt;
    if (row['receipt'] != null) {
      final raw = _map(row['receipt']);
      receipt = switch (raw['kind']) {
        'authenticated_owner_receipt_sms_access' =>
          NotificationManagementAccessReceipt._(raw),
        'authenticated_owner_receipt_sms_policy' =>
          NotificationManagementPolicyReceipt._(raw),
        _ => _invalid(),
      };
      if (receipt.requestId != rid) _invalid();
      if (receipt is NotificationManagementAccessReceipt) {
        _identity(receipt.adminId, receipt.principalId);
        if (receipt.publicSessionId != _id(session.user?.sessionId)) _invalid();
      } else if (receipt is NotificationManagementPolicyReceipt) {
        if (receipt.ownerUserId != _id(session.user?.principalId) ||
            receipt.publicSessionId != _id(session.user?.sessionId)) {
          _invalid();
        }
      }
      if (originalOperation != null) _match(originalOperation, receipt);
    }
    return NotificationManagementResolution._(
      rid,
      row['observed'] as bool,
      receipt,
    );
  }
}
