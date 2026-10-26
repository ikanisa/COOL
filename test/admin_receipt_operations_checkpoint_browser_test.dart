@TestOn('browser')
library;

import 'dart:js_interop';
import 'package:collect_app/admin/core/admin_receipt_operations_checkpoint.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/admin_receipt_operations_fixture.dart';

@JS('window.localStorage')
external _Storage get _storage;

extension type _Storage(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void removeItem(String key);
}

void main() {
  test(
    'actual browser localStorage adapter retains original across instances and isolates owners',
    () {
      final owner = adminReceiptOperationsOwnerDigest(operationsPrincipal);
      final checkpoint = AdminReceiptOperationsCheckpoint.fromIntent(
        owner,
        operationsIntent(),
      );
      final key =
          'collect.admin.receipt-operations.recovery.v3.$owner.${checkpoint.requestId}';
      _storage.removeItem(key);
      _storage.removeItem('$key.resolution');
      addTearDown(() {
        _storage.removeItem(key);
        _storage.removeItem('$key.resolution');
      });
      final first = browserAdminReceiptOperationsCheckpointStore()!;
      first.write(owner, checkpoint.requestId, checkpoint.encode());
      final restarted = browserAdminReceiptOperationsCheckpointStore()!;
      expect(restarted.read(owner), [checkpoint.encode()]);
      expect(
        restarted.read(adminReceiptOperationsOwnerDigest(operationsDevice)),
        isEmpty,
      );
      expect(
        () => restarted.write(owner, checkpoint.requestId, checkpoint.encode()),
        throwsFormatException,
      );
      restarted.resolve(checkpoint, 'recorded');
      expect(restarted.read(owner), isEmpty);
      expect(_storage.getItem(key), checkpoint.encode());
    },
  );
}
