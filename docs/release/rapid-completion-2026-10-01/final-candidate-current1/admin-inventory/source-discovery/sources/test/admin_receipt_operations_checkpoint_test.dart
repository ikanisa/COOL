import 'dart:convert';
import 'package:collect_app/admin/core/admin_receipt_operations_checkpoint.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/admin_receipt_operations_fixture.dart';

class MemoryOperationsStore implements AdminReceiptOperationsCheckpointStore {
  final originals = <String, String>{}, resolutions = <String, String>{};
  bool failWrite = false,
      failRead = false,
      failResolve = false,
      tamperRead = false;
  void Function()? onWrite;
  String key(String owner, String request) => '$owner:$request';
  @override
  List<String> read(String ownerDigest) {
    if (failRead) throw StateError('PRIVATE_STORAGE_CANARY');
    return originals.entries
        .where(
          (e) =>
              e.key.startsWith('$ownerDigest:') &&
              !resolutions.containsKey(e.key),
        )
        .map((e) => tamperRead ? '{}' : e.value)
        .toList();
  }

  @override
  void write(String ownerDigest, String requestId, String encoded) {
    if (failWrite) throw StateError('PRIVATE_STORAGE_CANARY');
    final k = key(ownerDigest, requestId);
    if (originals.containsKey(k)) {
      throw StateError('Original UUID already reserved.');
    }
    originals[k] = encoded;
    onWrite?.call();
  }

  @override
  void resolve(AdminReceiptOperationsCheckpoint checkpoint, String status) {
    if (failResolve ||
        originals[key(checkpoint.ownerDigest, checkpoint.requestId)] !=
            checkpoint.encode()) {
      throw StateError('PRIVATE_STORAGE_CANARY');
    }
    resolutions[key(checkpoint.ownerDigest, checkpoint.requestId)] = status;
  }
}

void main() {
  final owner = adminReceiptOperationsOwnerDigest(operationsPrincipal);
  AdminReceiptOperationsCheckpoint original() =>
      AdminReceiptOperationsCheckpoint.fromIntent(owner, operationsIntent());
  test(
    'bookmark preserves original action/deadline but omits reason and mutation parameters',
    () {
      final value = original(), encoded = value.encode();
      expect(
        AdminReceiptOperationsCheckpoint.parse(encoded, owner).encode(),
        encoded,
      );
      expect(encoded, isNot(contains(operationsIntent().reason)));
      expect(encoded, isNot(contains('p_caps')));
      expect(encoded, isNot(contains('p_principal_ids')));
      expect(encoded, isNot(contains('p_reason')));
      expect(encoded.length, lessThan(2048));
    },
  );
  test('owner-purpose digest isolates another current account', () {
    final another = adminReceiptOperationsOwnerDigest(operationsDevice);
    expect(another, isNot(owner));
    expect(
      () =>
          AdminReceiptOperationsCheckpoint.parse(original().encode(), another),
      throwsFormatException,
    );
  });
  for (final key in [
    'version',
    'owner_digest',
    'request_id',
    'action',
    'expected_revision',
    'mode',
    'emergency_stop',
    'created_at',
    'expires_at',
  ]) {
    test('checkpoint refuses altered $key', () {
      final row = jsonDecode(original().encode()) as Map<String, dynamic>;
      row[key] = key == 'version' ? true : 'invalid';
      expect(
        () => AdminReceiptOperationsCheckpoint.parse(jsonEncode(row), owner),
        throwsFormatException,
      );
    });
  }
  test(
    'noncanonical/duplicate/extra JSON and oversized bookmarks are refused',
    () {
      final raw = original().encode();
      for (final value in [
        '$raw ',
        '{"version":2,${raw.substring(1)}',
        '${raw.substring(0, raw.length - 1)},"token":"PRIVATE"}',
        'x' * 2049,
      ]) {
        expect(
          () => AdminReceiptOperationsCheckpoint.parse(value, owner),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'immutable per-request originals coexist rather than overwrite another unknown action',
    () {
      final store = MemoryOperationsStore(), first = original();
      final stop = AdminReceiptOperationsCheckpoint.fromIntent(
        owner,
        operationsIntent(stop: true),
      );
      store.write(owner, first.requestId, first.encode());
      store.write(owner, stop.requestId, stop.encode());
      expect(store.read(owner).length, 2);
      expect(
        () => store.write(owner, first.requestId, first.encode()),
        throwsStateError,
      );
      store.resolve(first, 'recorded');
      expect(store.read(owner), [stop.encode()]);
      expect(
        store.originals[store.key(owner, first.requestId)],
        first.encode(),
      );
    },
  );
}
