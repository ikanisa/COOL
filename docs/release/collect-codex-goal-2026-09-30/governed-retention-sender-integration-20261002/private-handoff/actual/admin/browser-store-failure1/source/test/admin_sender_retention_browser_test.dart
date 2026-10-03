import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:collect_app/admin/core/admin_sender_retention_checkpoint.dart';
import 'package:collect_app/admin/core/admin_sender_retention_models.dart';
import 'support/retention_fixture.dart';

void main() {
  final key = 'collect.retention-control.v1.$actor.$session';
  setUp(() {
    final keys = <String>[];
    for (var i = 0; i < web.window.localStorage.length; i++) {
      final k = web.window.localStorage.key(i);
      if (k?.startsWith(key) == true) keys.add(k!);
    }
    for (final k in keys) {
      web.window.localStorage.removeItem(k);
    }
  });
  test(
    'actual Chrome durable write/readback retains original on resolution',
    () async {
      final s = browserAdminRetentionStore()!, i = originalIntent();
      await s.write(i);
      expect((await s.read(actor, session))!.fingerprint, i.fingerprint);
      await s.clear(i);
      expect(await s.read(actor, session), isNull);
      expect(
        web.window.localStorage.getItem('$key.resolved.${i.requestId}'),
        isNotNull,
      );
    },
  );
  test(
    'real Web Locks serialize competing checkpoints without replacing the first',
    () async {
      final s = browserAdminRetentionStore()!,
          i = originalIntent(),
          j = AdminRetentionIntent.parse({
            ...i.row,
            'reason': 'Different concurrent original reason',
          });
      final replies = await Future.wait([
        s.write(i).then((_) => true).catchError((_) => false),
        s.write(j).then((_) => true).catchError((_) => false),
      ]);
      expect(replies.where((v) => v), hasLength(1));
      expect((await s.read(actor, session))!.fingerprint, i.fingerprint);
    },
  );
  test('wrong original cannot resolve or overwrite retained request', () async {
    final s = browserAdminRetentionStore()!,
        i = originalIntent(),
        j = AdminRetentionIntent.parse({
          ...i.row,
          'request_id': '33333333-3333-4333-8333-333333333333',
        });
    await s.write(i);
    await expectLater(s.clear(j), throwsFormatException);
    await expectLater(s.write(j), throwsFormatException);
    expect((await s.read(actor, session))!.fingerprint, i.fingerprint);
  });
  test(
    'malformed or foreign session local evidence refuses instead of submitting',
    () async {
      final s = browserAdminRetentionStore()!;
      web.window.localStorage.setItem(key, '{}');
      await expectLater(s.read(actor, session), throwsFormatException);
      expect(
        await s.read(actor, '44444444-4444-4444-8444-444444444444'),
        isNull,
      );
    },
  );
  test('resolved original cannot be resurrected by a stale writer', () async {
    final s = browserAdminRetentionStore()!, i = originalIntent();
    await s.write(i);
    await s.clear(i);
    final retained = web.window.localStorage.getItem('$key.resolved.${i.requestId}');
    await expectLater(s.write(i), throwsFormatException);
    expect(await s.read(actor, session), isNull);
    expect(web.window.localStorage.getItem('$key.resolved.${i.requestId}'), retained);
  });
  test('stale resolved writer cannot erase or block a newer pending original', () async {
    final s = browserAdminRetentionStore()!, i = originalIntent();
    final j = AdminRetentionIntent.parse({
      ...i.row,
      'request_id': '33333333-3333-4333-8333-333333333333',
    });
    await s.write(i);
    await s.clear(i);
    final retained = web.window.localStorage.getItem('$key.resolved.${i.requestId}');
    final outcomes = await Future.wait([
      s.write(i).then((_) => true).catchError((_) => false),
      s.write(j).then((_) => true).catchError((_) => false),
    ]);
    expect(outcomes, [false, true]);
    expect((await s.read(actor, session))!.fingerprint, j.fingerprint);
    await expectLater(s.write(i), throwsFormatException);
    expect((await s.read(actor, session))!.fingerprint, j.fingerprint);
    expect(web.window.localStorage.getItem('$key.resolved.${i.requestId}'), retained);
  });
}
