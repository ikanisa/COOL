import 'package:flutter/services.dart';

import '../data/exact_json_values.dart';
import 'contribution_command_storage_contract.dart';

ContributionCommandProtectedStorage createStore() =>
    const NativeContributionCommandStorage();

final class NativeContributionCommandStorage
    implements ContributionCommandProtectedStorage {
  const NativeContributionCommandStorage({
    MethodChannel channel = const MethodChannel(
      'collect/contribution_commands_v1',
    ),
    // Keep the injectable channel public while retaining the field as private.
    // ignore: prefer_initializing_formals
  }) : _channel = channel;
  final MethodChannel _channel;
  @override
  Future<ContributionStoreSnapshot> read(String partitionId) async {
    try {
      return ContributionStoreSnapshot.fromWire(
        await _channel.invokeMethod<Object?>('read', {
          'partition_id': partitionId,
        }),
        partitionId,
      );
    } catch (_) {
      throw StateError('Protected contribution recovery is unavailable.');
    }
  }

  @override
  Future<ContributionStoreCasResult> compareAndSet(
    String partitionId,
    int expectedRevision,
    String payload,
  ) async {
    try {
      exactJsonInteger(
        expectedRevision,
        field: 'contribution.store_revision',
        minimum: 0,
        maximum: maxExactJsonInteger - 1,
      );
      final raw = await _channel.invokeMethod<Object?>('compareAndSet', {
        'partition_id': partitionId,
        'expected_revision': expectedRevision,
        'payload': payload,
      });
      final snapshot = ContributionStoreSnapshot.fromWire(
        raw,
        partitionId,
        cas: true,
      );
      final committed = (raw as Map)['committed'] == true;
      if (committed &&
          (snapshot.revision != expectedRevision + 1 ||
              snapshot.payload != payload)) {
        throw StateError('Contribution recovery commit was not acknowledged.');
      }
      return ContributionStoreCasResult(
        committed: committed,
        snapshot: snapshot,
      );
    } catch (_) {
      // A missing/lost reply can follow a durable commit. Never turn it into a
      // dispatch permit, an empty partition, or a fresh request key.
      throw StateError(
        'Contribution recovery commit could not be confirmed. Check the original request.',
      );
    }
  }
}
