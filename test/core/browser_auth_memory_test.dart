import 'dart:convert';

import 'package:collect_app/core/supabase/browser_auth_memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotrue/src/collect_browser_invalidation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const actor = '99890000-0000-4000-8000-000000000001';
const sidA = '99890000-0000-4000-8000-000000000011';
const sidB = '99890000-0000-4000-8000-000000000012';
Session session(String sid, {String user = actor}) => Session(
  accessToken:
      'e30.${base64Url.encode(utf8.encode(jsonEncode({'sub': user, 'session_id': sid, 'exp': 4000000000}))).replaceAll('=', '')}.synthetic',
  refreshToken: 'synthetic-refresh-never-channel',
  tokenType: 'bearer',
  user: User(
    id: user,
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-09-30T00:00:00Z',
  ),
);

void main() {
  final clock = DateTime.utc(2026, 9, 30, 12);
  const project = 'https://synthetic.example/auth/v1';
  test(
    'web memory and native durable options are explicitly distinct',
    () async {
      final web = collectAuthOptions(browser: true);
      final native = collectAuthOptions(browser: false);
      expect(web.persistSession, isFalse);
      expect(web.localStorage, isA<EmptyLocalStorage>());
      expect(web.pkceAsyncStorage, isA<CollectMemoryPkceStorage>());
      await web.pkceAsyncStorage!.setItem(key: 'verifier', value: 'synthetic');
      expect(await web.pkceAsyncStorage!.getItem(key: 'verifier'), 'synthetic');
      expect(
        await collectAuthOptions(
          browser: true,
        ).pkceAsyncStorage!.getItem(key: 'verifier'),
        isNull,
      );
      await web.pkceAsyncStorage!.removeItem(key: 'verifier');
      expect(await web.pkceAsyncStorage!.getItem(key: 'verifier'), isNull);
      expect(native.persistSession, isTrue);
      expect(native.pkceAsyncStorage, isNull);
      expect(native.autoRefreshToken, isTrue);
    },
  );
  test('departed session shape contains references only', () {
    final message = CollectBrowserInvalidation.departed(
      session(sidA),
      project,
      now: clock,
    )!;
    expect(message.keys.toSet(), {
      'protocol',
      'version',
      'event',
      'project',
      'actor',
      'session',
      'issued',
      'expires',
    });
    expect(jsonEncode(message), isNot(contains('synthetic-refresh')));
    expect(jsonEncode(message), isNot(contains('access_token')));
    expect(
      CollectBrowserInvalidation.accepts(
        message,
        session(sidA),
        project,
        now: clock,
      ),
      isTrue,
    );
    expect(
      CollectBrowserInvalidation.accepts(
        message,
        session(sidB),
        project,
        now: clock,
      ),
      isFalse,
    );
    expect(
      CollectBrowserInvalidation.accepts(message, null, project, now: clock),
      isFalse,
    );
  });
  test(
    'same-session refresh matches departure without sharing new credentials',
    () {
      final message = CollectBrowserInvalidation.departed(
        session(sidA),
        project,
        now: clock,
      )!;
      expect(
        CollectBrowserInvalidation.matchesOwner(message, session(sidA)),
        isTrue,
      );
    },
  );
  test(
    'untrusted foreign malformed or expired input cannot clear a session',
    () {
      final base = CollectBrowserInvalidation.departed(
        session(sidA),
        project,
        now: clock,
      )!;
      final changes = <Map<String, dynamic>>[
        {...base, 'project': 'https://foreign.example/auth/v1'},
        {...base, 'version': 2},
        {...base, 'session': 'not-a-session'},
        {...base, 'actor': '99890000-0000-4000-8000-000000000002'},
        {...base, 'event': 'TOKEN_REFRESHED'},
        {...base, 'session_payload': session(sidA).toJson()},
        {...base, 'issued': base['issued'] + 1, 'expires': base['expires'] + 1},
        {...base, 'expires': base['expires'] + 1},
        {...base, 'issued': 'invalid'},
      ];
      for (final message in changes) {
        expect(
          CollectBrowserInvalidation.accepts(
            message,
            session(sidA),
            project,
            now: clock,
          ),
          isFalse,
        );
      }
      expect(
        CollectBrowserInvalidation.accepts(
          base,
          session(sidA),
          project,
          now: clock.add(const Duration(seconds: 30)),
        ),
        isFalse,
      );
      expect(CollectBrowserInvalidation.owner(session('invalid')), isNull);
    },
  );
}
