@TestOn('browser')
library;

import 'dart:convert';
import 'package:collect_app/admin/core/admin_exception_models.dart';
import 'package:collect_app/admin/core/admin_exception_checkpoint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'real browser sessionStorage retains only session-bound reviewed references across adapter recreation',
    () {
      final owner = adminExceptionOwnerDigest(
        'synthetic-actor',
        'synthetic-session',
      );
      final other = adminExceptionOwnerDigest(
        'other-actor',
        'synthetic-session',
      );
      final first = browserAdminExceptionCheckpointStore()!;
      first.clear(owner);
      first.clear(other);
      final checkpoint = AdminExceptionCheckpoint(
        owner,
        AdminExceptionIntent(
          requestId: '99770000-0000-4000-8000-000000000111',
          exceptionId: '99770000-0000-4000-8000-000000000222',
          revision: 3,
          action: AdminExceptionAction.escalate,
          reason: AdminExceptionReviewReason.uncertainSendReview,
        ),
      );
      first.write(owner, checkpoint.encode());
      final next = browserAdminExceptionCheckpointStore()!;
      expect(
        AdminExceptionCheckpoint.parse(
          next.read(owner)!,
          owner,
        ).intent.parameters,
        checkpoint.intent.parameters,
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
