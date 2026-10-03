import 'package:flutter_test/flutter_test.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_models.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_checkpoint.dart';
import 'support/successor_fixture.dart';

void main() {
  test(
    'actual closure and masked current preview DTOs parse without send authority',
    () {
      final f = SuccessorFixture();
      final c = AdminReceiptClosureInspection.parse(
        observed('closure_inspection'),
        f.outbox,
      );
      final p = AdminReceiptSuccessorInspection.parse(
        observed('retry_preview'),
        f.outbox,
        f.source,
      );
      expect(c.canClose, isTrue);
      expect(p.canApprove, isTrue);
      expect(p.preview!.recipient, matches(r'^\+250\*\*\*\d{3}$'));
      expect(p.preview!.row.containsKey('destination_e164'), isFalse);
    },
  );
  test('extra authority fields and modified exact body are refused', () {
    final f = SuccessorFixture();
    final p = observed('retry_preview');
    p['send_authority'] = true;
    expect(
      () => AdminReceiptSuccessorInspection.parse(p, f.outbox, f.source),
      throwsFormatException,
    );
    final changed = observed('retry_preview');
    (changed['preview'] as Map)['body'] = 'Unapproved copy';
    expect(
      () => AdminReceiptSuccessorInspection.parse(changed, f.outbox, f.source),
      throwsFormatException,
    );
  });
  test(
    'stale sample, numeric coercion and leaked contact do not become eligible',
    () {
      final f = SuccessorFixture();
      final p = f.previewRow();
      p['sample_valid_until'] = stamp(f.now.add(const Duration(seconds: 61)));
      expect(
        () => AdminReceiptSuccessorInspection.parse(p, f.outbox, f.source),
        throwsFormatException,
      );
      final n = f.previewRow();
      (n['preview'] as Map)['amount_rwf'] = '100';
      expect(
        () => AdminReceiptSuccessorInspection.parse(n, f.outbox, f.source),
        throwsFormatException,
      );
      final leak = f.previewRow();
      (leak['preview'] as Map)['destination_e164'] = '+250788971001';
      expect(
        () => AdminReceiptSuccessorInspection.parse(leak, f.outbox, f.source),
        throwsFormatException,
      );
    },
  );
  test(
    'actual retained approval and keyset lineage reject duplicate or forged progression',
    () {
      final f = SuccessorFixture();
      final r = observed('lineage_pages');
      final page = AdminReceiptSuccessorHistory.parse(
        r['first'],
        f.outbox,
        limit: 1,
      );
      expect(page.items.single.status, 'revoked');
      final duplicate = Map<String, dynamic>.from(r['first'] as Map);
      duplicate['items'] = [
        ...duplicate['items'] as List,
        ...duplicate['items'] as List,
      ];
      expect(
        () => AdminReceiptSuccessorHistory.parse(duplicate, f.outbox, limit: 2),
        throwsFormatException,
      );
    },
  );
  test(
    'recovery checkpoint has exact binding and no receipt text or reason',
    () async {
      final f = SuccessorFixture();
      final i = await f.sdk.inspect(f.outbox, f.source);
      final intent = f.sdk.prepareApproval(
        request,
        i,
        'A reviewed reason with personal details',
      );
      final encoded = AdminReceiptSuccessorCheckpoint(
        f.owner,
        intent.binding,
      ).encode();
      expect(encoded, contains(request));
      expect(encoded, isNot(contains(i.preview!.body)));
      expect(encoded, isNot(contains('personal details')));
      expect(encoded, isNot(contains('destination')));
      expect(
        AdminReceiptSuccessorCheckpoint.parse(
          encoded,
          f.owner,
        ).binding.requestId,
        request,
      );
      expect(
        () => AdminReceiptSuccessorCheckpoint.parse(encoded, 'a' * 64),
        throwsFormatException,
      );
    },
  );
}
