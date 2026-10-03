@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_checkpoint.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_models.dart';

void main() {
  test(
    'actual Chrome same-tab successor checkpoint survives store recreation',
    () {
      const id = '99780000-0000-4000-8000-000000080001';
      final owner = successorOwnerDigest(id),
          store = browserReceiptSuccessorCheckpointStore()!;
      addTearDown(() => store.clear(owner));
      final binding = AdminReceiptSuccessorBinding(
        requestId: id,
        action: 'close_unarmed',
        expected: {
          'outbox_id': id,
          'expected_root_revision': 1,
          'expected_lineage_revision': 1,
        },
      );
      final encoded = AdminReceiptSuccessorCheckpoint(owner, binding).encode();
      store.write(owner, encoded);
      final next = browserReceiptSuccessorCheckpointStore()!;
      expect(
        AdminReceiptSuccessorCheckpoint.parse(
          next.read(owner)!,
          owner,
        ).binding.requestId,
        id,
      );
      expect(encoded, isNot(contains('body')));
      next.clear(owner);
      expect(next.read(owner), isNull);
    },
  );
  test(
    'actual Chrome separates owner recovery and refuses corrupted checkpoint',
    () {
      const id = '99780000-0000-4000-8000-000000080002';
      final owner = successorOwnerDigest(id),
          other = successorOwnerDigest('another-owner'),
          store = browserReceiptSuccessorCheckpointStore()!;
      addTearDown(() => store.clear(owner));
      store.write(owner, '{"version":1,"owner_digest":"$owner","binding":{}}');
      expect(store.read(other), isNull);
      expect(
        () => AdminReceiptSuccessorCheckpoint.parse(store.read(owner)!, owner),
        throwsFormatException,
      );
    },
  );
}
