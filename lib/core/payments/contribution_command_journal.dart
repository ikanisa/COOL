import 'dart:convert';

import '../../shared/models/collect_models.dart';
import '../security/contribution_command_storage.dart';
import 'contribution_command.dart';

/// Encrypted custody with platform-wide CAS. This is not a payment ledger.
/// No deletion, eviction, retry-send or session-rebinding operation exists.
final class ContributionCommandJournal {
  ContributionCommandJournal({ContributionCommandProtectedStorage? storage})
    : _storage = storage ?? createContributionCommandStorage();
  final ContributionCommandProtectedStorage _storage;

  List<ContributionCommandCheckpoint> _decode(
    ContributionStoreSnapshot snapshot,
    ContributionCommandOwner owner,
  ) {
    final payload = snapshot.payload;
    if (payload == null) {
      if (snapshot.revision != 0) {
        throw StateError('Contribution recovery is unreadable.');
      }
      return const [];
    }
    final value = jsonDecode(payload);
    if (contributionCanonicalJson(value) != payload) {
      throw const FormatException('Contribution recovery is not canonical.');
    }
    final row = contributionObject(value, const {
      'schema_version',
      'owner',
      'records',
    });
    if (row['schema_version'] != 1 ||
        contributionCanonicalJson(row['owner']) !=
            contributionCanonicalJson(owner.toJson()) ||
        row['records'] is! List ||
        (row['records'] as List).length > contributionCommandMaxRecords) {
      throw const FormatException('Contribution recovery is unreadable.');
    }
    final records = (row['records'] as List)
        .map(ContributionCommandCheckpoint.fromJson)
        .toList(growable: false);
    if (records.map((r) => r.body.requestId).toSet().length != records.length) {
      throw const FormatException('Contribution recovery identities conflict.');
    }
    return records;
  }

  String _encode(
    ContributionCommandOwner owner,
    List<ContributionCommandCheckpoint> records,
  ) {
    final payload = contributionCanonicalJson({
      'schema_version': 1,
      'owner': owner.toJson(),
      'records': records.map((r) => r.toJson()).toList(growable: false),
    });
    if (utf8.encode(payload).length > contributionCommandMaxPayloadBytes) {
      throw StateError('Contribution recovery is full.');
    }
    return payload;
  }

  void _current(ContributionSessionWitness witness, bool Function() isCurrent) {
    if (!isCurrent() || !witness.usableAt(DateTime.now())) {
      throw StateError('Account changed. Sign in again to check this request.');
    }
  }

  Future<List<ContributionCommandCheckpoint>> read(
    ContributionCommandOwner owner,
  ) async =>
      List.unmodifiable(_decode(await _storage.read(owner.partitionId), owner));
  Future<ContributionCommandCheckpoint?> latestUnresolved(
    ContributionCommandOwner owner,
    String collectionId,
  ) async {
    final records = await read(owner);
    return records.reversed
        .where(
          (r) =>
              r.body.collectionId == collectionId &&
              !r.committedContributionObserved,
        )
        .firstOrNull;
  }

  Future<ContributionCommandCheckpoint> find(
    ContributionCommandOwner owner,
    String requestId,
  ) async {
    final records = await read(owner);
    final matches = records.where((r) => r.body.requestId == requestId);
    if (matches.length != 1) {
      throw StateError(
        'The original contribution recovery record is unavailable.',
      );
    }
    return matches.single;
  }

  Future<ContributionCommandCheckpoint> prepare(
    ContributionSessionWitness witness,
    ContributionCommandBody body, {
    required bool Function() isCurrent,
  }) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      _current(witness, isCurrent);
      final snapshot = await _storage.read(witness.owner.partitionId);
      _current(witness, isCurrent);
      final records = _decode(snapshot, witness.owner);
      final pending = records.reversed
          .where(
            (r) =>
                r.body.collectionId == body.collectionId &&
                !r.committedContributionObserved,
          )
          .firstOrNull;
      if (pending != null) throw ContributionRecoveryRequired(pending);
      if (records.length >= contributionCommandMaxRecords ||
          records.any((r) => r.body.requestId == body.requestId)) {
        throw StateError(
          'Contribution recovery is full. Check the retained requests.',
        );
      }
      final checkpoint = ContributionCommandCheckpoint.prepared(body, witness);
      final payload = _encode(witness.owner, [...records, checkpoint]);
      final result = await _storage.compareAndSet(
        witness.owner.partitionId,
        snapshot.revision,
        payload,
      );
      _current(witness, isCurrent);
      if (result.committed) {
        _ack(result, snapshot.revision, payload);
        return checkpoint;
      }
      _decode(result.snapshot, witness.owner);
    }
    throw StateError(
      'Another contribution action is in progress. Check the original request.',
    );
  }

  Future<ContributionCommandCheckpoint> _mutate(
    ContributionSessionWitness witness,
    String requestId,
    ContributionCommandCheckpoint Function(ContributionCommandCheckpoint)
    update, {
    required bool Function() isCurrent,
  }) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      _current(witness, isCurrent);
      final snapshot = await _storage.read(witness.owner.partitionId);
      _current(witness, isCurrent);
      final records = _decode(snapshot, witness.owner);
      final index = records.indexWhere((r) => r.body.requestId == requestId);
      if (index < 0) {
        throw StateError('The original contribution record is unavailable.');
      }
      final updated = update(records[index]);
      // A caller cannot replace original custody identities while recording an observation.
      if (updated.body.canonical != records[index].body.canonical ||
          updated.originalSessionId != records[index].originalSessionId ||
          (records[index].providerHandoffPossible &&
              !updated.providerHandoffPossible)) {
        throw StateError('Contribution recovery identity changed.');
      }
      final next = [...records];
      next[index] = updated;
      final payload = _encode(witness.owner, next);
      final result = await _storage.compareAndSet(
        witness.owner.partitionId,
        snapshot.revision,
        payload,
      );
      _current(witness, isCurrent);
      if (result.committed) {
        _ack(result, snapshot.revision, payload);
        return updated;
      }
      _decode(result.snapshot, witness.owner);
    }
    throw StateError(
      'Another contribution action is in progress. Check the original request.',
    );
  }

  void _ack(
    ContributionStoreCasResult result,
    int expectedRevision,
    String payload,
  ) {
    if (result.snapshot.revision != expectedRevision + 1 ||
        result.snapshot.payload != payload) {
      throw StateError('Contribution recovery commit was not acknowledged.');
    }
  }

  Future<ContributionCommandCheckpoint> claimDispatch(
    ContributionSessionWitness witness,
    String requestId, {
    required bool Function() isCurrent,
  }) => _mutate(witness, requestId, (record) {
    if (record.originalSessionId != witness.sessionId) {
      throw ContributionRecoveryRequired(record);
    }
    return record.dispatched();
  }, isCurrent: isCurrent);
  Future<ContributionCommandCheckpoint> retainReceipt(
    ContributionSessionWitness witness,
    String requestId,
    String intentId, {
    required bool Function() isCurrent,
  }) => _mutate(witness, requestId, (record) {
    if (record.originalSessionId != witness.sessionId) {
      throw ContributionRecoveryRequired(record);
    }
    return record.received(intentId);
  }, isCurrent: isCurrent);
  Future<ContributionCommandCheckpoint> retainObservation(
    ContributionSessionWitness witness,
    String requestId,
    ContributionCommandObservation observation, {
    required bool Function() isCurrent,
  }) => _mutate(
    witness,
    requestId,
    (record) => record.observed(observation),
    isCurrent: isCurrent,
  );
  Future<ContributionCommandCheckpoint> claimProviderHandoff(
    ContributionSessionWitness witness,
    String requestId,
    String intentId, {
    required bool Function() isCurrent,
  }) => _mutate(witness, requestId, (record) {
    if (record.originalSessionId != witness.sessionId ||
        record.intentId != intentId) {
      throw ContributionRecoveryRequired(record);
    }
    return record.handedOff();
  }, isCurrent: isCurrent);
  Future<ContributionCommandCheckpoint> retainCommittedContribution(
    ContributionSessionWitness witness,
    String requestId,
    PaymentIntentModel intent, {
    required bool Function() isCurrent,
  }) => _mutate(
    witness,
    requestId,
    (record) => record.committed(intent),
    isCurrent: isCurrent,
  );
}
