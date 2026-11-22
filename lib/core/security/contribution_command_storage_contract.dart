import 'dart:convert';

import '../data/exact_json_values.dart';
import '../payments/contribution_command.dart';

final class ContributionStoreSnapshot {
  ContributionStoreSnapshot({
    required this.partitionId,
    required this.revision,
    required this.payload,
  });
  final String partitionId;
  final int revision;
  final String? payload;
  factory ContributionStoreSnapshot.fromWire(
    Object? value,
    String partitionId, {
    bool cas = false,
  }) {
    final row = contributionObject(value, {
      'schema_version',
      'partition_id',
      'revision',
      'payload',
      if (cas) 'committed',
    });
    final revision = exactJsonInteger(
      row['revision'],
      field: 'contribution.store_revision',
      minimum: 0,
    );
    final payload = row['payload'];
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(partitionId) ||
        row['schema_version'] != 1 ||
        row['partition_id'] != partitionId ||
        (revision == 0
            ? payload != null
            : payload is! String || payload.isEmpty) ||
        (payload is String &&
            utf8.encode(payload).length > contributionCommandMaxPayloadBytes) ||
        (cas && row['committed'] is! bool)) {
      throw StateError('Protected contribution recovery is unreadable.');
    }
    return ContributionStoreSnapshot(
      partitionId: partitionId,
      revision: revision,
      payload: payload as String?,
    );
  }
}

final class ContributionStoreCasResult {
  ContributionStoreCasResult({required this.committed, required this.snapshot});
  final bool committed;
  final ContributionStoreSnapshot snapshot;
}

abstract interface class ContributionCommandProtectedStorage {
  Future<ContributionStoreSnapshot> read(String partitionId);
  Future<ContributionStoreCasResult> compareAndSet(
    String partitionId,
    int expectedRevision,
    String payload,
  );
}
