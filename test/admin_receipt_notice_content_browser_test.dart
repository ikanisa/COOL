@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:collect_app/admin/core/admin_receipt_notice_content_checkpoint.dart';
import 'support/receipt_notice_content_browser_fixture.dart';

void main() {
  const key =
      'collect.notice-content.v1.$noticeBrowserActor.$noticeBrowserSession';
  void clean() {
    final keys = <String>[];
    for (var i = 0; i < web.window.localStorage.length; i++) {
      final k = web.window.localStorage.key(i);
      if (k?.startsWith(key) == true) {
        keys.add(k!);
      }
    }
    for (final k in keys) {
      web.window.localStorage.removeItem(k);
    }
  }

  setUp(clean);
  tearDown(clean);
  test(
    'actual Chrome retains durable original and resolution tombstone',
    () async {
      final s = browserReceiptNoticeContentStore()!, i = noticeBrowserIntent();
      await s.write(i);
      expect(
        (await s.read(noticeBrowserActor, noticeBrowserSession))!.fingerprint,
        i.fingerprint,
      );
      await s.clear(i);
      expect(await s.read(noticeBrowserActor, noticeBrowserSession), isNull);
      expect(
        web.window.localStorage.getItem('$key.resolved.${i.requestId}'),
        isNotNull,
      );
    },
  );
  test(
    'real Web Locks serialize competing originals with no replacement',
    () async {
      final s = browserReceiptNoticeContentStore()!,
          i = noticeBrowserIntent(),
          j = noticeBrowserIntent('99780000-0000-4000-8000-000000009002');
      final outcomes = await Future.wait([
        s.write(i).then((_) => true).catchError((_) => false),
        s.write(j).then((_) => true).catchError((_) => false),
      ]);
      expect(outcomes.where((v) => v), hasLength(1));
      final actual = await s.read(noticeBrowserActor, noticeBrowserSession);
      expect(actual!.fingerprint, anyOf(i.fingerprint, j.fingerprint));
    },
  );
  test('wrong original cannot clear or overwrite a pending request', () async {
    final s = browserReceiptNoticeContentStore()!,
        i = noticeBrowserIntent(),
        j = noticeBrowserIntent('99780000-0000-4000-8000-000000009002');
    await s.write(i);
    await expectLater(s.clear(j), throwsFormatException);
    await expectLater(s.write(j), throwsFormatException);
    expect(
      (await s.read(noticeBrowserActor, noticeBrowserSession))!.fingerprint,
      i.fingerprint,
    );
  });
  test(
    'malformed and foreign-session evidence refuses before mutation',
    () async {
      final s = browserReceiptNoticeContentStore()!;
      web.window.localStorage.setItem(key, '{}');
      await expectLater(
        s.read(noticeBrowserActor, noticeBrowserSession),
        throwsFormatException,
      );
      expect(
        await s.read(
          noticeBrowserActor,
          '99780000-0000-4000-8000-000000019999',
        ),
        isNull,
      );
    },
  );
  test('resolved UUID cannot be resurrected by a recreated store', () async {
    final i = noticeBrowserIntent(), s = browserReceiptNoticeContentStore()!;
    await s.write(i);
    await s.clear(i);
    final retained = web.window.localStorage.getItem(
      '$key.resolved.${i.requestId}',
    );
    final restarted = browserReceiptNoticeContentStore()!;
    await expectLater(restarted.write(i), throwsFormatException);
    expect(
      await restarted.read(noticeBrowserActor, noticeBrowserSession),
      isNull,
    );
    expect(
      web.window.localStorage.getItem('$key.resolved.${i.requestId}'),
      retained,
    );
  });
  test(
    'old resolved writer cannot erase a concurrent newer original',
    () async {
      final s = browserReceiptNoticeContentStore()!,
          i = noticeBrowserIntent(),
          j = noticeBrowserIntent('99780000-0000-4000-8000-000000009002');
      await s.write(i);
      await s.clear(i);
      final retained = web.window.localStorage.getItem(
        '$key.resolved.${i.requestId}',
      );
      final outcomes = await Future.wait([
        s.write(i).then((_) => true).catchError((_) => false),
        s.write(j).then((_) => true).catchError((_) => false),
      ]);
      expect(outcomes, [false, true]);
      expect(
        (await s.read(noticeBrowserActor, noticeBrowserSession))!.fingerprint,
        j.fingerprint,
      );
      await expectLater(s.write(i), throwsFormatException);
      expect(
        (await s.read(noticeBrowserActor, noticeBrowserSession))!.fingerprint,
        j.fingerprint,
      );
      expect(
        web.window.localStorage.getItem('$key.resolved.${i.requestId}'),
        retained,
      );
    },
  );
}
