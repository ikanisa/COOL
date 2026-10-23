@TestOn('browser')
library;

import 'dart:convert';
import 'package:collect_app/admin/core/admin_receipt_cancel_models.dart';
import 'package:collect_app/admin/core/admin_receipt_cancel_checkpoint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'actual same-tab storage persists exact original intent across adapter recreation and isolates owners',
    () {
      final owner = adminReceiptCancelOwnerDigest('synthetic-owner'),
          other = adminReceiptCancelOwnerDigest('other');
      final first = browserAdminReceiptCancelCheckpointStore()!;
      first.clear(owner);
      first.clear(other);
      final saved = AdminReceiptCancelCheckpoint(
        owner,
        AdminReceiptCancelIntent(
          requestId: '99710000-0000-4000-8000-000000000002',
          outboxId: '99710000-0000-4000-8000-000000000003',
          revision: 1,
          reason: AdminReceiptCancelReason.recipientReviewRequired,
        ),
      );
      first.write(owner, saved.encode());
      final next = browserAdminReceiptCancelCheckpointStore()!;
      expect(
        AdminReceiptCancelCheckpoint.parse(
          next.read(owner)!,
          owner,
        ).intent.parameters,
        saved.intent.parameters,
      );
      expect(jsonDecode(next.read(owner)!).keys.toSet(), {
        'version',
        'owner_digest',
        'request',
      });
      expect(next.read(other), isNull);
      next.clear(owner);
      expect(first.read(owner), isNull);
    },
  );
}
