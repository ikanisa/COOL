import 'dart:convert';

import '../../shared/models/collect_models.dart';
import '../data/exact_json_values.dart';
import '../security/hash_utils.dart';

const contributionCommandPurpose = 'collect.contribution-commands.v1';
const contributionCommandMaxPayloadBytes = 1048576;
const contributionCommandMaxRecords = 64;

String contributionCanonicalJson(Object? value) {
  Object? canonical(Object? item) {
    if (item is Map<String, dynamic>) {
      final keys = item.keys.toList()..sort();
      return {for (final key in keys) key: canonical(item[key])};
    }
    if (item is List) return item.map(canonical).toList(growable: false);
    if (item == null || item is String || item is bool || item is int) {
      return item;
    }
    throw const FormatException('Invalid contribution recovery value.');
  }

  return jsonEncode(canonical(value));
}

Map<String, dynamic> contributionObject(Object? value, Set<String> keys) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Invalid contribution recovery record.');
  }
  final result = Map<String, dynamic>.from(value);
  if (result.length != keys.length || !result.keys.toSet().containsAll(keys)) {
    throw const FormatException('Unsupported contribution recovery record.');
  }
  return result;
}

String contributionUuid(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$',
      ).hasMatch(value)) {
    throw const FormatException('Invalid contribution identity.');
  }
  return value;
}

DateTime _observationTime(Object? value) {
  final result = exactJsonTimestamp(value, field: 'contribution.observed_at');
  if (value is! String || value != result.toIso8601String()) {
    throw const FormatException('Invalid contribution observation.');
  }
  return result;
}

final class ContributionCommandOwner {
  ContributionCommandOwner({
    required this.projectOrigin,
    required String principalId,
    required String authSubject,
  }) : principalId = contributionUuid(principalId),
       authSubject = contributionUuid(authSubject) {
    final origin = Uri.tryParse(projectOrigin);
    if (origin == null ||
        origin.origin != projectOrigin ||
        (origin.scheme != 'https' &&
            !(origin.scheme == 'http' &&
                const {
                  'localhost',
                  '127.0.0.1',
                  '::1',
                }.contains(origin.host)))) {
      throw const FormatException('Invalid contribution project.');
    }
  }

  final String projectOrigin, principalId, authSubject;
  Map<String, dynamic> toJson() => {
    'purpose': contributionCommandPurpose,
    'project_origin': projectOrigin,
    'principal_id': principalId,
    'auth_subject': authSubject,
  };
  String get partitionId =>
      HashUtils.sha256Hex(contributionCanonicalJson(toJson()));
  bool sameOwner(ContributionCommandOwner other) =>
      partitionId == other.partitionId;
}

/// A fresh server observation, never reusable payment authorization or JWT data.
final class ContributionSessionWitness {
  ContributionSessionWitness._(
    this.owner,
    this.sessionId,
    this.expiresAt,
    this.observedAt,
  );
  final ContributionCommandOwner owner;
  final String sessionId;
  final int expiresAt;
  final DateTime observedAt;
  bool usableAt(DateTime now) =>
      expiresAt > now.toUtc().millisecondsSinceEpoch ~/ 1000;

  factory ContributionSessionWitness.fromWire(
    Object? value, {
    required ContributionCommandOwner expectedOwner,
    required DateTime now,
  }) {
    final row = contributionObject(value, const {
      'contract_version',
      'binding_kind',
      'issuer',
      'owner_id',
      'auth_subject',
      'session_id',
      'expires_at',
      'observed_at',
      'retry_authorized',
      'launch_authorized',
    });
    if (row['contract_version'] != 1 ||
        row['binding_kind'] != 'current_contribution_session' ||
        row['issuer'] != '${expectedOwner.projectOrigin}/auth/v1' ||
        row['owner_id'] != expectedOwner.principalId ||
        row['auth_subject'] != expectedOwner.authSubject ||
        row['retry_authorized'] != false ||
        row['launch_authorized'] != false) {
      throw const FormatException(
        'Contribution session could not be verified.',
      );
    }
    final witness = ContributionSessionWitness._(
      expectedOwner,
      contributionUuid(row['session_id']),
      exactJsonInteger(
        row['expires_at'],
        field: 'contribution.expires_at',
        minimum: 1,
      ),
      _observationTime(row['observed_at']),
    );
    if (!witness.usableAt(now)) throw StateError('Sign in again to continue.');
    return witness;
  }
}

final class ContributionCommandBody {
  ContributionCommandBody({
    required String collectionId,
    required int amountRwf,
    required this.senderPhoneHash,
    required String requestId,
  }) : collectionId = contributionUuid(collectionId),
       amountRwf = exactJsonInteger(
         amountRwf,
         field: 'contribution.amount',
         minimum: 1,
       ),
       requestId = contributionUuid(requestId) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(senderPhoneHash)) {
      throw const FormatException('Invalid contribution profile binding.');
    }
  }
  final String collectionId, senderPhoneHash, requestId;
  final int amountRwf;
  Map<String, dynamic> toJson() => {
    'collection': collectionId,
    'p_expected_amount_rwf': amountRwf,
    'p_sender_phone_hash': senderPhoneHash,
    'p_request_id': requestId,
  };
  String get canonical => contributionCanonicalJson(toJson());
  String get sha256 => HashUtils.sha256Hex(canonical);
  factory ContributionCommandBody.fromJson(Object? value) {
    final row = contributionObject(value, const {
      'collection',
      'p_expected_amount_rwf',
      'p_sender_phone_hash',
      'p_request_id',
    });
    if (row['p_sender_phone_hash'] is! String) {
      throw const FormatException('Invalid contribution body.');
    }
    return ContributionCommandBody(
      collectionId: contributionUuid(row['collection']),
      amountRwf: exactJsonInteger(
        row['p_expected_amount_rwf'],
        field: 'contribution.amount',
        minimum: 1,
      ),
      senderPhoneHash: row['p_sender_phone_hash'] as String,
      requestId: contributionUuid(row['p_request_id']),
    );
  }
}

enum ContributionCommandPhase { prepared, dispatchPossible, receiptRetained }

/// Immutable original command. Uncertainty survives logout, renewal and restart.
final class ContributionCommandCheckpoint {
  ContributionCommandCheckpoint._({
    required this.body,
    required this.originalSessionId,
    required this.phase,
    this.intentId,
    this.observedStatus,
    this.providerHandoffPossible = false,
    this.committedContributionObserved = false,
  });
  factory ContributionCommandCheckpoint.prepared(
    ContributionCommandBody body,
    ContributionSessionWitness witness,
  ) => ContributionCommandCheckpoint._(
    body: body,
    originalSessionId: witness.sessionId,
    phase: ContributionCommandPhase.prepared,
  );
  final ContributionCommandBody body;
  final String originalSessionId;
  final ContributionCommandPhase phase;
  final String? intentId, observedStatus;
  final bool providerHandoffPossible, committedContributionObserved;

  ContributionCommandCheckpoint dispatched() {
    if (phase != ContributionCommandPhase.prepared) {
      throw ContributionRecoveryRequired(this);
    }
    return _copy(phase: ContributionCommandPhase.dispatchPossible);
  }

  ContributionCommandCheckpoint received(String id) {
    if (phase != ContributionCommandPhase.dispatchPossible ||
        intentId != null) {
      throw ContributionRecoveryRequired(this);
    }
    return _copy(
      phase: ContributionCommandPhase.receiptRetained,
      intentId: contributionUuid(id),
    );
  }

  ContributionCommandCheckpoint observed(
    ContributionCommandObservation observation,
  ) {
    if (observation.requestId != body.requestId) {
      throw const FormatException('Invalid contribution observation.');
    }
    if (intentId != null &&
        observation.intentId != null &&
        intentId != observation.intentId) {
      throw const FormatException('Contribution intent changed.');
    }
    return _copy(
      intentId: observation.intentId,
      observedStatus: observation.status,
    );
  }

  ContributionCommandCheckpoint handedOff() {
    if (phase != ContributionCommandPhase.receiptRetained ||
        intentId == null ||
        providerHandoffPossible) {
      throw ContributionRecoveryRequired(this);
    }
    return _copy(providerHandoffPossible: true);
  }

  ContributionCommandCheckpoint committed(PaymentIntentModel intent) {
    if (intent.id != intentId ||
        intent.collectionId != body.collectionId ||
        intent.expectedAmountRwf != body.amountRwf ||
        !intent.hasCommittedContribution) {
      throw const FormatException(
        'Contribution posting could not be verified.',
      );
    }
    return _copy(committedContributionObserved: true);
  }

  ContributionCommandCheckpoint _copy({
    ContributionCommandPhase? phase,
    String? intentId,
    String? observedStatus,
    bool providerHandoffPossible = false,
    bool committedContributionObserved = false,
  }) => ContributionCommandCheckpoint._(
    body: body,
    originalSessionId: originalSessionId,
    phase: phase ?? this.phase,
    intentId: intentId ?? this.intentId,
    observedStatus: observedStatus ?? this.observedStatus,
    providerHandoffPossible:
        this.providerHandoffPossible || providerHandoffPossible,
    committedContributionObserved:
        this.committedContributionObserved || committedContributionObserved,
  );
  Map<String, dynamic> toJson() => {
    'body': body.toJson(),
    'body_sha256': body.sha256,
    'original_session_id': originalSessionId,
    'phase': phase.name,
    'intent_id': intentId,
    'observed_status': observedStatus,
    'provider_handoff_possible': providerHandoffPossible,
    'committed_contribution_observed': committedContributionObserved,
  };
  factory ContributionCommandCheckpoint.fromJson(Object? value) {
    final row = contributionObject(value, const {
      'body',
      'body_sha256',
      'original_session_id',
      'phase',
      'intent_id',
      'observed_status',
      'provider_handoff_possible',
      'committed_contribution_observed',
    });
    final body = ContributionCommandBody.fromJson(row['body']);
    final phases = ContributionCommandPhase.values.where(
      (p) => p.name == row['phase'],
    );
    final status = row['observed_status'];
    if (row['body_sha256'] != body.sha256 ||
        phases.length != 1 ||
        row['provider_handoff_possible'] is! bool ||
        row['committed_contribution_observed'] is! bool ||
        (status != null &&
            !const {
              'pending',
              'expired',
              'cancelled',
              'matched',
              'ambiguous',
            }.contains(status))) {
      throw const FormatException('Contribution recovery is unreadable.');
    }
    final id = row['intent_id'] == null
        ? null
        : contributionUuid(row['intent_id']);
    final phase = phases.single;
    if ((phase == ContributionCommandPhase.receiptRetained && id == null) ||
        (phase == ContributionCommandPhase.prepared &&
            (id != null || row['provider_handoff_possible'] == true)) ||
        (row['provider_handoff_possible'] == true &&
            (phase != ContributionCommandPhase.receiptRetained ||
                id == null)) ||
        (row['committed_contribution_observed'] == true && id == null)) {
      throw const FormatException('Invalid contribution recovery phase.');
    }
    return ContributionCommandCheckpoint._(
      body: body,
      originalSessionId: contributionUuid(row['original_session_id']),
      phase: phase,
      intentId: id,
      observedStatus: status as String?,
      providerHandoffPossible: row['provider_handoff_possible'] as bool,
      committedContributionObserved:
          row['committed_contribution_observed'] as bool,
    );
  }
}

final class ContributionCommandObservation {
  ContributionCommandObservation._(
    this.requestId,
    this.intentId,
    this.status,
    this.observedAt,
  );
  final String requestId;
  final String? intentId, status;
  final DateTime observedAt;
  factory ContributionCommandObservation.fromWire(
    Object? value,
    ContributionCommandCheckpoint original,
  ) {
    final row = contributionObject(value, const {
      'contract_version',
      'request_id',
      'original_session_id',
      'collection_id',
      'body_sha256',
      'command_status',
      'observed_at',
      'external_payment',
      'retry_authorized',
      'launch_authorized',
      'observed_intent',
    });
    if (row['contract_version'] != 1 ||
        row['request_id'] != original.body.requestId ||
        row['original_session_id'] != original.originalSessionId ||
        row['collection_id'] != original.body.collectionId ||
        row['body_sha256'] != original.body.sha256 ||
        row['external_payment'] != 'unknown' ||
        row['retry_authorized'] != false ||
        row['launch_authorized'] != false) {
      throw const FormatException('Contribution request could not be checked.');
    }
    String? id, status;
    if (row['command_status'] == 'receipt_retained') {
      final intent = contributionObject(row['observed_intent'], const {
        'id',
        'status',
      });
      id = contributionUuid(intent['id']);
      if (!const {
        'pending',
        'expired',
        'cancelled',
        'matched',
        'ambiguous',
      }.contains(intent['status'])) {
        throw const FormatException('Invalid contribution status.');
      }
      status = intent['status'] as String;
    } else if (row['command_status'] != 'unknown' ||
        row['observed_intent'] != null) {
      throw const FormatException('Invalid contribution status.');
    }
    return ContributionCommandObservation._(
      original.body.requestId,
      id,
      status,
      _observationTime(row['observed_at']),
    );
  }
}

/// Constructible only from the distinct current-review RPC contract.
final class ContributionIntentReview {
  ContributionIntentReview._(
    this.intent,
    this.sessionId,
    this.collectionRevision,
    this.observedAt,
  );
  final PaymentIntentModel intent;
  final String sessionId;
  final int collectionRevision;
  final DateTime observedAt;
  factory ContributionIntentReview.fromWire(
    Object? value, {
    required String collectionId,
    required String intentId,
    required String sessionId,
  }) {
    final row = contributionObject(value, const {
      'contract_version',
      'review_status',
      'collection_id',
      'intent_id',
      'reviewed_session_id',
      'collection_revision',
      'observed_at',
      'external_payment',
      'retry_authorized',
      'launch_authorized',
      'intent',
    });
    if (row['contract_version'] != 1 ||
        row['review_status'] != 'current' ||
        row['collection_id'] != contributionUuid(collectionId) ||
        row['intent_id'] != contributionUuid(intentId) ||
        row['reviewed_session_id'] != contributionUuid(sessionId) ||
        row['external_payment'] != 'unknown' ||
        row['retry_authorized'] != false ||
        row['launch_authorized'] != true) {
      throw const FormatException(
        'Current contribution details could not be verified.',
      );
    }
    final projection = contributionObject(row['intent'], const {
      'id',
      'collection_id',
      'amount_minor',
      'currency',
      'rail',
      'status',
      'receiver_momo_number',
      'network',
      'receiver_label',
      'receiver_momo_number_hash',
      'sender_phone_hash',
      'originating_session_id',
      'created_at',
      'expires_at',
    });
    final intent = PaymentIntentModel.fromJson(projection);
    if (intent.id != intentId ||
        intent.collectionId != collectionId ||
        projection['originating_session_id'] != sessionId) {
      throw const FormatException('Current contribution identity changed.');
    }
    return ContributionIntentReview._(
      intent,
      sessionId,
      exactJsonInteger(
        row['collection_revision'],
        field: 'contribution.collection_revision',
        minimum: 1,
      ),
      _observationTime(row['observed_at']),
    );
  }
}

final class ContributionRecoveryRequired implements Exception {
  const ContributionRecoveryRequired(this.checkpoint);
  final ContributionCommandCheckpoint checkpoint;
  @override
  String toString() =>
      'Check the original contribution request before another payment.';
}

final class ContributionReviewChanged implements Exception {
  const ContributionReviewChanged();
}

/// Acknowledged durable handoff claim plus a final synchronous lifecycle fence.
/// Consumed at most once immediately before the native launcher.
final class ContributionLaunchPermit {
  ContributionLaunchPermit({
    required this.review,
    required bool Function() isCurrent,
    // Keep the injected callback public while retaining the field as private.
    // ignore: prefer_initializing_formals
  }) : _isCurrent = isCurrent;
  final ContributionIntentReview review;
  final bool Function() _isCurrent;
  bool _consumed = false;
  bool consume() {
    if (_consumed || !_isCurrent()) return false;
    _consumed = true;
    return true;
  }
}
