import '../../core/data/exact_json_values.dart';

const receiptSmsPurpose = 'contribution_receipt_sms';

String receiptSmsUuid(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(value)) {
    throw const FormatException('Receipt SMS identity is invalid.');
  }
  return value;
}

int receiptSmsDecisionRevision(Object? value, {bool expected = false}) {
  if (value is! int ||
      value < 0 ||
      value > (expected ? 9007199254740990 : 9007199254740991)) {
    throw const FormatException('Receipt SMS decision revision is invalid.');
  }
  return value;
}

int _revision(Object? value, {int minimum = 0}) {
  if (value is! int || value < minimum || value > 999999999) {
    throw const FormatException('Receipt SMS revision is invalid.');
  }
  return value;
}

bool _boolean(Object? value) {
  if (value is! bool) {
    throw const FormatException('Receipt SMS state is invalid.');
  }
  return value;
}

Map<String, dynamic> _object(Object? value, Set<String> keys) {
  if (value is! Map<String, dynamic> ||
      value.length != keys.length ||
      !value.keys.every(keys.contains)) {
    throw const FormatException('Receipt SMS response is invalid.');
  }
  if (value['contract_version'] is! int ||
      value['contract_version'] != 1 ||
      value['scope'] != 'own_receipt_sms_consent' ||
      value['purpose'] != receiptSmsPurpose ||
      value['delivery_confirmed'] != false ||
      value['provider_confirmation'] != false) {
    throw const FormatException('Receipt SMS contract is unavailable.');
  }
  return value;
}

String? _hash(Object? value, {bool optional = false}) {
  if (optional && value == null) return null;
  if (value is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw const FormatException('Receipt SMS receipt is invalid.');
  }
  return value;
}

enum ReceiptSmsAuthorization {
  disabled('disabled'),
  active('active'),
  blockedPhone('blocked_phone_binding'),
  blockedMembership('blocked_membership'),
  directPending('direct_verification_pending');

  const ReceiptSmsAuthorization(this.value);
  final String value;
}

final class ReceiptSmsConsent {
  const ReceiptSmsConsent({
    required this.collectionId,
    required this.optIn,
    required this.revision,
    required this.decisionRevision,
    required this.destinationRevision,
    required this.authorization,
    required this.effective,
    required this.phoneBinding,
    required this.phoneVerificationAvailable,
    required this.optInAvailable,
    required this.unavailableReason,
  });
  final String collectionId;
  final bool optIn,
      effective,
      phoneBinding,
      phoneVerificationAvailable,
      optInAvailable;
  final int revision, decisionRevision;
  final int? destinationRevision;
  final ReceiptSmsAuthorization authorization;
  final String? unavailableReason;

  factory ReceiptSmsConsent.decode(Object? response, String collectionId) {
    final row = _object(response, const {
      'contract_version',
      'scope',
      'purpose',
      'collection_id',
      'opt_in',
      'revision',
      'decision_revision',
      'destination_revision',
      'current_verified_phone_binding',
      'phone_verification_available',
      'opt_in_available',
      'unavailable_reason',
      'delivery_confirmed',
      'provider_confirmation',
      'authorization_status',
      'consent_effective',
    });
    if (receiptSmsUuid(row['collection_id']) != receiptSmsUuid(collectionId)) {
      throw const FormatException(
        'Receipt SMS response belongs to another group.',
      );
    }
    final authorization = ReceiptSmsAuthorization.values
        .where((s) => s.value == row['authorization_status'])
        .singleOrNull;
    final optIn = _boolean(row['opt_in']),
        effective = _boolean(row['consent_effective']);
    final binding = _boolean(row['current_verified_phone_binding']);
    final phoneAvailable = _boolean(row['phone_verification_available']);
    final available = _boolean(row['opt_in_available']);
    final reason = row['unavailable_reason'];
    if (authorization == null ||
        (reason != null &&
            !const {
              'direct_recipient_verification_required',
              'current_phone_verification_required',
              'active_membership_required',
            }.contains(reason)) ||
        (available && (!phoneAvailable || reason != null)) ||
        effective != (authorization == ReceiptSmsAuthorization.active) ||
        optIn != (authorization != ReceiptSmsAuthorization.disabled) ||
        (effective && !binding) ||
        (authorization == ReceiptSmsAuthorization.blockedPhone && binding)) {
      throw const FormatException('Receipt SMS status is inconsistent.');
    }
    final revision = _revision(row['revision']);
    final destinationRevision = row['destination_revision'] == null
        ? null
        : _revision(row['destination_revision'], minimum: 1);
    if (optIn && (revision == 0 || destinationRevision == null)) {
      throw const FormatException(
        'Receipt SMS authorization revision is missing.',
      );
    }
    return ReceiptSmsConsent(
      collectionId: collectionId,
      optIn: optIn,
      revision: revision,
      decisionRevision: receiptSmsDecisionRevision(row['decision_revision']),
      destinationRevision: destinationRevision,
      authorization: authorization,
      effective: effective,
      phoneBinding: binding,
      phoneVerificationAvailable: phoneAvailable,
      optInAvailable: available,
      unavailableReason: reason as String?,
    );
  }
}

/// Minimum recovery metadata. No phone, bearer, request body, or destination proof.
final class PendingReceiptSmsRequest {
  const PendingReceiptSmsRequest({
    required this.userId,
    required this.sessionId,
    required this.collectionId,
    required this.requestId,
    required this.expectedRevision,
    required this.expectedDecisionRevision,
    required this.optIn,
  });
  final String userId, sessionId, collectionId, requestId;
  final int expectedRevision, expectedDecisionRevision;
  final bool optIn;
  Map<String, dynamic> toJson() => {
    'schema_version': 2,
    'user_id': userId,
    'session_id': sessionId,
    'collection_id': collectionId,
    'request_id': requestId,
    'expected_revision': expectedRevision,
    'expected_decision_revision': expectedDecisionRevision,
    'opt_in': optIn,
  };
  factory PendingReceiptSmsRequest.decode(Object? value) {
    const keys = {
      'schema_version',
      'user_id',
      'session_id',
      'collection_id',
      'request_id',
      'expected_revision',
      'expected_decision_revision',
      'opt_in',
    };
    if (value is! Map<String, dynamic> ||
        value.length != keys.length ||
        !value.keys.every(keys.contains) ||
        value['schema_version'] is! int ||
        value['schema_version'] != 2) {
      throw const FormatException(
        'Pending receipt SMS recovery is unavailable.',
      );
    }
    final revision = _revision(value['expected_revision']);
    if (revision > 999999998) {
      throw const FormatException('Receipt SMS revision is exhausted.');
    }
    return PendingReceiptSmsRequest(
      userId: receiptSmsUuid(value['user_id']),
      sessionId: receiptSmsUuid(value['session_id']),
      collectionId: receiptSmsUuid(value['collection_id']),
      requestId: receiptSmsUuid(value['request_id']),
      expectedRevision: revision,
      expectedDecisionRevision: receiptSmsDecisionRevision(
        value['expected_decision_revision'],
        expected: true,
      ),
      optIn: _boolean(value['opt_in']),
    );
  }
  Map<String, dynamic> get rpcParameters => {
    'p_collection_id': collectionId,
    'p_expected_revision': expectedRevision,
    'p_expected_decision_revision': expectedDecisionRevision,
    'p_opt_in': optIn,
    'p_request_id': requestId,
  };
  bool sameRequest(PendingReceiptSmsRequest other) =>
      userId == other.userId &&
      sessionId == other.sessionId &&
      collectionId == other.collectionId &&
      requestId == other.requestId &&
      expectedRevision == other.expectedRevision &&
      expectedDecisionRevision == other.expectedDecisionRevision &&
      optIn == other.optIn;
}

final class ReceiptSmsDecision {
  const ReceiptSmsDecision(this.revision, this.decisionRevision, this.replay);
  final int revision, decisionRevision;
  final bool replay;
  factory ReceiptSmsDecision.decode(
    Object? response,
    PendingReceiptSmsRequest request,
  ) {
    final row = _object(response, const {
      'contract_version',
      'scope',
      'delivery_confirmed',
      'provider_confirmation',
      'kind',
      'purpose',
      'request_id',
      'collection_id',
      'recipient_user_id',
      'originating_session_id',
      'opt_in',
      'consent_revision',
      'decision_revision',
      'destination_revision',
      'destination_sha256',
      'phone_verification_challenge_id',
      'recorded_at',
      'decision_sha256',
      'authorization_receipt_sha256',
      'recorded_state_only',
      'replay',
    });
    if (row['kind'] != 'authenticated_member_receipt_sms_consent' ||
        row['recorded_state_only'] != true ||
        receiptSmsUuid(row['request_id']) != request.requestId ||
        receiptSmsUuid(row['collection_id']) != request.collectionId ||
        receiptSmsUuid(row['recipient_user_id']) != request.userId ||
        receiptSmsUuid(row['originating_session_id']) != request.sessionId ||
        _boolean(row['opt_in']) != request.optIn) {
      throw const FormatException(
        'Receipt SMS acknowledgement does not match this request.',
      );
    }
    final revision = _revision(row['consent_revision']);
    if (revision < request.expectedRevision ||
        revision > request.expectedRevision + 1 ||
        request.optIn && request.expectedRevision == 0 && revision != 1) {
      throw const FormatException(
        'Receipt SMS acknowledgement revision is invalid.',
      );
    }
    if (row['destination_revision'] != null) {
      _revision(row['destination_revision'], minimum: 1);
    }
    _hash(row['destination_sha256'], optional: true);
    _hash(row['decision_sha256']);
    _hash(row['authorization_receipt_sha256'], optional: true);
    if (row['phone_verification_challenge_id'] != null) {
      receiptSmsUuid(row['phone_verification_challenge_id']);
    }
    if (request.optIn &&
        (row['destination_revision'] == null ||
            row['destination_sha256'] == null ||
            row['phone_verification_challenge_id'] == null ||
            row['authorization_receipt_sha256'] == null)) {
      throw const FormatException(
        'Receipt SMS acknowledgement proof is incomplete.',
      );
    }
    exactJsonTimestamp(row['recorded_at'], field: 'consent.recorded_at');
    final decisionRevision = receiptSmsDecisionRevision(
      row['decision_revision'],
    );
    if (decisionRevision != request.expectedDecisionRevision + 1) {
      throw const FormatException(
        'Receipt SMS acknowledgement decision order is invalid.',
      );
    }
    return ReceiptSmsDecision(
      revision,
      decisionRevision,
      _boolean(row['replay']),
    );
  }
}

final class ReceiptSmsSuperseded {
  const ReceiptSmsSuperseded(this.request, this.observedDecisionRevision);
  final PendingReceiptSmsRequest request;
  final int observedDecisionRevision;
  Map<String, dynamic> toJson() => {
    ...request.toJson(),
    'superseded_by_decision_revision': observedDecisionRevision,
  };
  factory ReceiptSmsSuperseded.decode(Object? value) {
    if (value is! Map ||
        value.length != 9 ||
        !value.containsKey('superseded_by_decision_revision')) {
      throw const FormatException('Superseded receipt SMS custody is invalid.');
    }
    final row = Map<String, dynamic>.from(value),
        head = receiptSmsDecisionRevision(
          value['superseded_by_decision_revision'],
        );
    row.remove('superseded_by_decision_revision');
    final request = PendingReceiptSmsRequest.decode(row);
    if (head <= request.expectedDecisionRevision) {
      throw const FormatException('An earlier request has not been fenced.');
    }
    return ReceiptSmsSuperseded(request, head);
  }
}

final class ReceiptSmsRecoveryState {
  const ReceiptSmsRecoveryState({
    this.pending = const [],
    this.superseded = const [],
  });
  final List<PendingReceiptSmsRequest> pending;
  final List<ReceiptSmsSuperseded> superseded;
  Map<String, dynamic> toJson() => {
    'schema_version': 2,
    'pending': pending.map((r) => r.toJson()).toList(),
    'superseded': superseded.map((r) => r.toJson()).toList(),
  };
  factory ReceiptSmsRecoveryState.decode(
    Object? value,
    String user,
    String group,
  ) {
    if (value is! Map ||
        value.length != 3 ||
        value['schema_version'] is! int ||
        value['schema_version'] != 2 ||
        value['pending'] is! List ||
        value['superseded'] is! List) {
      throw const FormatException('Secure receipt SMS journal is unavailable.');
    }
    final pending = (value['pending'] as List)
        .map(
          (r) => PendingReceiptSmsRequest.decode(
            Map<String, dynamic>.from(r as Map),
          ),
        )
        .toList(growable: false);
    final history = (value['superseded'] as List)
        .map(ReceiptSmsSuperseded.decode)
        .toList(growable: false);
    final all = [...pending, ...history.map((r) => r.request)];
    if (pending.length > 32 ||
        history.length > 32 ||
        all.any((r) => r.userId != user || r.collectionId != group) ||
        all.map((r) => r.requestId).toSet().length != all.length ||
        pending.map((r) => r.sessionId).toSet().length != pending.length ||
        pending.where((r) => r.optIn).length > 1 ||
        (pending.length > 1 && history.length + pending.length > 32)) {
      throw const FormatException(
        'Receipt SMS recovery scope or capacity is invalid.',
      );
    }
    return ReceiptSmsRecoveryState(
      pending: List.unmodifiable(pending),
      superseded: List.unmodifiable(history),
    );
  }
  bool retains(String requestId) =>
      pending.any((r) => r.requestId == requestId) ||
      superseded.any((r) => r.request.requestId == requestId);
}

final class ReceiptSmsConsentView {
  const ReceiptSmsConsentView({
    this.consent,
    this.recovery = const ReceiptSmsRecoveryState(),
    this.busy = false,
    this.needsRefresh = true,
    this.supportUnavailable = false,
    this.storageAvailable = false,
    this.refreshedPending = false,
    this.recordedRevision,
    this.recordedDecisionRevision,
    this.acknowledgedRequest,
    this.error,
    this.unpersistedRequestIds = const {},
  });
  final ReceiptSmsConsent? consent;
  final ReceiptSmsRecoveryState recovery;
  PendingReceiptSmsRequest? get pending => recovery.pending.firstOrNull;
  final bool busy,
      needsRefresh,
      supportUnavailable,
      storageAvailable,
      refreshedPending;
  final int? recordedRevision, recordedDecisionRevision;
  final PendingReceiptSmsRequest? acknowledgedRequest;
  final Set<String> unpersistedRequestIds;
  final String? error;
}
