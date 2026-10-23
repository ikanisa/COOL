@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:collect_app/admin/core/admin_governed_settings_checkpoint.dart';
import 'package:collect_app/admin/core/admin_governed_settings_models.dart';
import 'package:flutter_test/flutter_test.dart';

@JS('window.localStorage')
external _Storage get _storage;

extension type _Storage(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}

@JS('navigator.locks')
external _Locks get _locks;

extension type _Locks(JSObject _) implements JSObject {
  external JSPromise<JSAny?> request(
    String name,
    _Options options,
    JSFunction callback,
  );
}

extension type _Options._(JSObject _) implements JSObject {
  external factory _Options({String mode});
}

const rawControl =
    r''' {"ok":true,"scope":"runtime_controls","value":{"key":"qa_runtime_current","label":"Synthetic reason","locale":"en","enabled":true,"metadata":{},"description":null,"request_type":"account_deletion","display_order":100},"exists":true,"family":"account_request_reason_options","identity":{"key":"qa_runtime_current","locale":"en","request_type":"account_deletion"},"redacted":false,"revision":1,"can_manage":true,"checked_at":"2026-10-01T17:17:35.150588Z","content_sha256":"3d07cba95d3c4bc9812bb84143586cc98d362ee08c6e7360b566d21a25b9a213","contract_version":2,"sample_valid_until":"2026-10-01T17:18:35.150588Z"} ''';
const actor = '99850000-0000-4000-8000-000000001111';
const scope = (
  key: (userId: actor, sessionId: '99850000-0000-4000-8000-000000001112'),
  generation: 1,
);
String request(int n) =>
    '99850000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
final owner = adminSettingsOwnerDigest(actor);
String key(AdminSettingsBookmark b) =>
    'collect.admin.settings.recovery.v3.$owner.${b.requestId}';
AdminSettingsBookmark original(int n) {
  final f = AdminSettingsFamily.parse('account_request_reason_options'),
      v = jsonDecode(rawControl) as Map;
  final c = AdminSettingsControl.parse(v, f, f.identity(v['identity']));
  return AdminSettingsBookmark.fromPrepared(
    owner,
    AdminSettingsPreparedUpdate.prepare(
      requestId: request(n),
      control: c,
      patch: {'label': 'Approved browser fixture'},
      reason: 'Reviewed browser admission fixture',
      now: settingsInstant(v['checked_at']),
      scope: scope,
    ),
  );
}

void clean(int n) {
  final k = key(original(n));
  _storage.removeItem(k);
  _storage.removeItem('$k.resolution');
}

void main() {
  setUp(() {
    for (var n = 1; n <= 8; n++) {
      clean(n);
    }
  });
  tearDown(() {
    for (var n = 1; n <= 8; n++) {
      clean(n);
    }
  });
  test(
    'actual browser store retains immutable metadata across instances and resolves separately',
    () async {
      final first = browserAdminSettingsCheckpointStore()!,
          second = browserAdminSettingsCheckpointStore()!,
          b = original(1);
      await first.write(b);
      expect(second.read(owner), [b.encode()]);
      expect(_storage.getItem(key(b)), isNot(contains('patch_json')));
      expect(_storage.getItem(key(b)), isNot(contains('"reason"')));
      await second.resolve(b, 'recorded');
      expect(first.read(owner), isEmpty);
      expect(_storage.getItem(key(b)), b.encode());
      await expectLater(first.write(b), throwsFormatException);
    },
  );
  test(
    'actual per-actor Web Lock serializes concurrent original admissions across store instances',
    () async {
      final a = browserAdminSettingsCheckpointStore()!,
          b = browserAdminSettingsCheckpointStore()!;
      var accepted = 0, denied = 0;
      Future<void> send(AdminSettingsCheckpointStore store, int id) async {
        try {
          await store.write(original(id));
          accepted++;
        } on AdminSettingsPendingOriginal {
          denied++;
        }
      }

      await Future.wait([send(a, 1), send(b, 2)]);
      expect(accepted, 1);
      expect(denied, 1);
      expect(a.read(owner).length, 1);
      expect(b.read(owner).length, 1);
    },
  );
  test(
    'actor pending unknown blocks later instance and foreign owner is isolated',
    () async {
      final a = browserAdminSettingsCheckpointStore()!,
          b = browserAdminSettingsCheckpointStore()!;
      await a.write(original(3));
      await expectLater(
        b.write(original(4)),
        throwsA(isA<AdminSettingsPendingOriginal>()),
      );
      expect(
        b.read(
          adminSettingsOwnerDigest('99850000-0000-4000-8000-000000002222'),
        ),
        isEmpty,
      );
    },
  );
  test(
    'corrupt and orphaned resolution evidence refuse admission without overwriting originals',
    () async {
      final a = browserAdminSettingsCheckpointStore()!, b = original(5);
      _storage.setItem('${key(b)}.resolution', '{}');
      expect(() => a.read(owner), throwsFormatException);
      await expectLater(a.write(original(6)), throwsFormatException);
      expect(_storage.getItem(key(original(6))), isNull);
      _storage.removeItem('${key(b)}.resolution');
      await a.write(b);
      _storage.setItem(
        '${key(b)}.resolution',
        jsonEncode({
          'version': 2,
          'original_sha256': 'a' * 64,
          'status': 'recorded',
        }),
      );
      expect(() => a.read(owner), throwsFormatException);
      expect(_storage.getItem(key(b)), b.encode());
    },
  );
  test(
    'immutable resolution cannot change from recorded to absence and retained original cannot replay',
    () async {
      final a = browserAdminSettingsCheckpointStore()!, b = original(7);
      await a.write(b);
      await a.resolve(b, 'recorded');
      await expectLater(
        a.resolve(b, 'not_recorded_after_deadline'),
        throwsFormatException,
      );
      await expectLater(a.write(b), throwsFormatException);
      expect(_storage.getItem(key(b)), b.encode());
    },
  );
  test(
    'queued admission times out at five seconds and cannot publish late after release',
    () async {
      final store = browserAdminSettingsCheckpointStore()!,
          b = original(8),
          entered = Completer<void>(),
          release = Completer<void>();
      final held = _locks
          .request(
            'collect.admin.settings.recovery.v3.$owner.exclusive',
            _Options(mode: 'exclusive'),
            ((JSAny? lock) {
              entered.complete();
              return release.future.then<JSAny?>((_) => null).toJS;
            }).toJS,
          )
          .toDart;
      await entered.future;
      Object? error;
      final watch = Stopwatch()..start();
      try {
        await store.write(b);
      } catch (e) {
        error = e;
      }
      expect(error, isNotNull);
      expect(watch.elapsed.inMilliseconds, inInclusiveRange(4900, 6500));
      release.complete();
      await held;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(_storage.getItem(key(b)), isNull);
      expect(store.read(owner), isEmpty);
    },
  );
}
