import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/cloudflare_admin_observation_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/legacy_backend_fixture.dart';

const _group = 'group-1';
const _source = '11111111-1111-4111-8111-111111111111';
const _request = '22222222-2222-4222-8222-222222222222';
const _time = '2026-11-11T09:30:00.000Z';
const _body = 'Synthetic message for a source review';
final _hash = sha256.convert(utf8.encode(_body)).toString();

Map<String, dynamic> _admission({String state = 'retained'}) => {
  'requestId': _request,
  'sourceId': _source,
  'admittedAt': _time,
  'retentionState': state,
  'bodySha256': state == 'retained' ? _hash : null,
};
Map<String, dynamic> _page({String group = _group, List<Object?>? items}) => {
  'contractVersion': 1,
  'collectionId': group,
  'items': items ?? [_admission()],
  'nextCursor': null,
  'asOf': _time,
};
Map<String, dynamic> _content() => {
  'contractVersion': 1,
  'collectionId': _group,
  'sourceId': _source,
  'sourceKind': 'observation',
  'retentionState': 'retained',
  'rawSender': 'Synthetic',
  'rawBody': _body,
  'bodySha256': _hash,
};
Map<String, dynamic> _hints() => {
  'schemaVersion': 1,
  'kind': 'partial_inbox_display_only',
  'profileVersion': 'synthetic-profile',
  'profileSha256': List.filled(64, 'a').join(),
  'bodySha256': _hash,
  'hints': [
    {
      'kind': 'quoted_incoming_amount',
      'text': 'Synthetic',
      'start': 0,
      'end': 9,
    },
    {'kind': 'quoted_reference', 'text': 'message', 'start': 10, 'end': 17},
  ],
};
http.Response _json(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json'},
);

class _TestSession extends CloudflareAdminSession {
  _TestSession(super.client)
    : super(
        origin: Uri.parse('https://admin.example.test/'),
        environment: legacyBackendFixtureEnvironment,
      );
  void emailProof(DateTime? at) =>
      state = AsyncData(user!.withEmailVerification(at));
}

void main() {
  test('observation integration is disabled unless explicitly configured', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(burimunsiObservationEnabledProvider), isFalse);
    expect(container.read(burimunsiObservationHintsEnabledProvider), isFalse);
  });

  test('collections and pages enforce exact metadata scope and state', () {
    final collections = {
      'contractVersion': 1,
      'items': [
        {'collectionId': _group, 'label': 'Example group'},
      ],
      'asOf': _time,
    };
    expect(ObservationCollections.parse(collections).items.single.id, _group);
    expect(
      () => ObservationCollections.parse({
        ...collections,
        'items': [
          {'collectionId': _group, 'label': 'One'},
          {'collectionId': _group, 'label': 'Two'},
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => ObservationCollections.parse({
        ...collections,
        'unexpected': 'raw text',
      }),
      throwsFormatException,
    );
    final valid = ObservationAdmissionPage.parse(_page(), _group, 25);
    expect(valid.items.single.retained, isTrue);
    expect(
      () => ObservationAdmissionPage.parse(_page(group: 'other'), _group, 25),
      throwsFormatException,
    );
    expect(
      () => ObservationAdmissionPage.parse(
        _page(items: [_admission(), _admission()]),
        _group,
        25,
      ),
      throwsFormatException,
    );
    expect(
      () => ObservationAdmissionPage.parse(
        {..._page(), 'nextCursor': List.filled(2049, 'x').join()},
        _group,
        25,
      ),
      throwsFormatException,
    );
    expect(
      () => ObservationAdmissionPage.parse(
        _page(
          items: [
            {..._admission(state: 'unresolved'), 'bodySha256': _hash},
          ],
        ),
        _group,
        25,
      ),
      throwsFormatException,
    );
    expect(
      () => ObservationAdmissionPage.parse(
        _page(
          items: [
            {..._admission(), 'rawBody': _body},
          ],
        ),
        _group,
        25,
      ),
      throwsFormatException,
    );
  });

  test('revealed bytes are bound to the selected group, source and digest', () {
    final retained = ObservationAdmission.parse(_admission());
    expect(ObservationContent.parse(_content(), _group, retained).body, _body);
    for (final altered in [
      {..._content(), 'collectionId': 'other'},
      {..._content(), 'sourceId': '33333333-3333-4333-8333-333333333333'},
      {..._content(), 'rawBody': 'different'},
      {..._content(), 'bodySha256': List.filled(64, '0').join()},
      {..._content(), 'sourceKind': 'capture'},
    ]) {
      expect(
        () => ObservationContent.parse(altered, _group, retained),
        throwsFormatException,
      );
    }
    expect(
      () => ObservationContent.parse(
        _content(),
        _group,
        ObservationAdmission.parse(_admission(state: 'unresolved')),
      ),
      throwsFormatException,
    );
  });

  test('optional display hints require exact bounded body-backed evidence', () {
    final retained = ObservationAdmission.parse(_admission());
    final withHints = {..._content(), 'displayHints': _hints()};
    final parsed = ObservationContent.parse(
      withHints,
      _group,
      retained,
      displayHintsRequested: true,
    );
    expect(parsed.displayHints!.hints.map((h) => h.text), [
      'Synthetic',
      'message',
    ]);
    expect(
      ObservationContent.parse(
        {..._content(), 'displayHints': null},
        _group,
        retained,
        displayHintsRequested: true,
      ).displayHints,
      isNull,
    );
    expect(
      () => ObservationContent.parse(withHints, _group, retained),
      throwsFormatException,
    );
    expect(
      () => ObservationContent.parse(
        _content(),
        _group,
        retained,
        displayHintsRequested: true,
      ),
      throwsFormatException,
    );
    final invalidHints = [
      {..._hints(), 'schemaVersion': 2},
      {..._hints(), 'kind': 'canonical_extraction'},
      {..._hints(), 'profileVersion': ''},
      {..._hints(), 'profileSha256': 'bad'},
      {..._hints(), 'bodySha256': List.filled(64, '0').join()},
      {..._hints(), 'hints': []},
      {
        ..._hints(),
        'hints': [
          {
            'kind': 'quoted_reference',
            'text': 'Synthetic',
            'start': 0,
            'end': 9,
          },
          {
            'kind': 'quoted_reference',
            'text': 'message',
            'start': 10,
            'end': 17,
          },
        ],
      },
      {
        ..._hints(),
        'hints': [
          {'kind': 'recipient', 'text': 'Synthetic', 'start': 0, 'end': 9},
        ],
      },
      {
        ..._hints(),
        'hints': [
          {
            'kind': 'quoted_reference',
            'text': 'Invented',
            'start': 0,
            'end': 9,
          },
        ],
      },
      {
        ..._hints(),
        'hints': [
          {
            'kind': 'quoted_reference',
            'text': 'Synthetic',
            'start': -1,
            'end': 9,
          },
        ],
      },
      {
        ..._hints(),
        'hints': [
          {
            'kind': 'quoted_reference',
            'text': 'Synthetic',
            'start': 0,
            'end': 900,
          },
        ],
      },
    ];
    for (final hints in invalidHints) {
      expect(
        () => ObservationContent.parse(
          {..._content(), 'displayHints': hints},
          _group,
          retained,
          displayHintsRequested: true,
        ),
        throwsFormatException,
      );
    }
  });

  test(
    'display spans use UTF-16 offsets without splitting surrogate pairs',
    () {
      const body = '💜 amount';
      final hash = sha256.convert(utf8.encode(body)).toString();
      final retained = ObservationAdmission.parse({
        ..._admission(),
        'bodySha256': hash,
      });
      final content = {..._content(), 'rawBody': body, 'bodySha256': hash};
      final hints = {
        ..._hints(),
        'bodySha256': hash,
        'hints': [
          {
            'kind': 'quoted_incoming_amount',
            'text': 'amount',
            'start': 3,
            'end': 9,
          },
        ],
      };
      expect(
        ObservationContent.parse(
          {...content, 'displayHints': hints},
          _group,
          retained,
          displayHintsRequested: true,
        ).displayHints!.hints.single.text,
        'amount',
      );
      final split = {
        ...hints,
        'hints': [
          {
            'kind': 'quoted_reference',
            'text': body.substring(0, 1),
            'start': 0,
            'end': 1,
          },
        ],
      };
      expect(
        () => ObservationContent.parse(
          {...content, 'displayHints': split},
          _group,
          retained,
          displayHintsRequested: true,
        ),
        throwsFormatException,
      );
    },
  );

  for (final enabled in [false, true]) {
    test('audited reveal requests hints only when enabled: $enabled', () async {
      final saved = Map<String, dynamic>.from(
        jsonDecode(
              File(
                'test/fixtures/admin-sms-capture-dto-examples.json',
              ).readAsStringSync(),
            )['session']
            as Map,
      );
      final expiry = DateTime.now()
          .add(const Duration(hours: 1))
          .toUtc()
          .toIso8601String();
      var reads = 0;
      final session = _TestSession(
        MockClient((request) async {
          if (request.url.path == '/api/admin/auth/session') {
            return _json({
              ...saved,
              'user': {
                ...Map<String, dynamic>.from(saved['user'] as Map),
                'role': 'admin',
                'permissions': ['sms.read', 'sms.reveal'],
                'expiresAt': expiry,
              },
              'expiresAt': expiry,
            });
          }
          expect(request.url.queryParameters, {
            'collectionId': _group,
            if (enabled) 'displayHintsVersion': '1',
          });
          expect(
            request.headers['X-Collect-Review-Reason'],
            'Review the source',
          );
          reads++;
          return _json({..._content(), if (enabled) 'displayHints': _hints()});
        }),
      );
      addTearDown(session.dispose);
      await session.refresh();
      session.emailProof(DateTime.now().toUtc());
      final content =
          await CloudflareAdminObservationApi(
            session,
            displayHints: enabled,
          ).reveal(
            _group,
            ObservationAdmission.parse(_admission()),
            'Review the source',
          );
      expect(content.displayHints != null, enabled);
      expect(reads, 1);
    });
  }

  test('a failed opt-in reveal is never silently retried', () async {
    final saved = Map<String, dynamic>.from(
      jsonDecode(
            File(
              'test/fixtures/admin-sms-capture-dto-examples.json',
            ).readAsStringSync(),
          )['session']
          as Map,
    );
    final expiry = DateTime.now()
        .add(const Duration(hours: 1))
        .toUtc()
        .toIso8601String();
    var reads = 0;
    final session = _TestSession(
      MockClient((request) async {
        if (request.url.path == '/api/admin/auth/session') {
          return _json({
            ...saved,
            'user': {
              ...Map<String, dynamic>.from(saved['user'] as Map),
              'role': 'admin',
              'permissions': ['sms.read', 'sms.reveal'],
              'expiresAt': expiry,
            },
            'expiresAt': expiry,
          });
        }
        reads++;
        return http.Response('{}', 404);
      }),
    );
    addTearDown(session.dispose);
    await session.refresh();
    session.emailProof(DateTime.now().toUtc());
    await expectLater(
      CloudflareAdminObservationApi(session, displayHints: true).reveal(
        _group,
        ObservationAdmission.parse(_admission()),
        'Review the source',
      ),
      throwsA(isA<Exception>()),
    );
    expect(reads, 1);
  });

  test(
    'a late page cannot survive logout and a new session generation',
    () async {
      final saved = Map<String, dynamic>.from(
        jsonDecode(
              File(
                'test/fixtures/admin-sms-capture-dto-examples.json',
              ).readAsStringSync(),
            )['session']
            as Map,
      );
      final response = Completer<http.Response>();
      final dispatched = Completer<void>();
      final expiry = DateTime.now()
          .add(const Duration(hours: 1))
          .toUtc()
          .toIso8601String();
      final session = _TestSession(
        MockClient((request) async {
          if (request.url.path == '/api/admin/auth/session') {
            return _json({
              ...saved,
              'user': {
                ...Map<String, dynamic>.from(saved['user'] as Map),
                'role': 'admin',
                'permissions': ['sms.read'],
                'expiresAt': expiry,
              },
              'expiresAt': expiry,
            });
          }
          if (request.url.path == '/api/admin/momo/observations') {
            expect(request.url.queryParameters['collectionId'], _group);
            dispatched.complete();
            return response.future;
          }
          return http.Response('{}', 404);
        }),
      );
      addTearDown(session.dispose);
      await session.refresh();
      final pending = CloudflareAdminObservationApi(session).admissions(_group);
      await dispatched.future;
      session.clear();
      response.complete(_json(_page()));
      await expectLater(pending, throwsA(isA<Exception>()));
    },
  );

  test('a late original message cannot survive logout', () async {
    final saved = Map<String, dynamic>.from(
      jsonDecode(
            File(
              'test/fixtures/admin-sms-capture-dto-examples.json',
            ).readAsStringSync(),
          )['session']
          as Map,
    );
    final response = Completer<http.Response>();
    final dispatched = Completer<void>();
    final expiry = DateTime.now()
        .add(const Duration(hours: 1))
        .toUtc()
        .toIso8601String();
    final session = _TestSession(
      MockClient((request) async {
        if (request.url.path == '/api/admin/auth/session') {
          return _json({
            ...saved,
            'user': {
              ...Map<String, dynamic>.from(saved['user'] as Map),
              'role': 'admin',
              'permissions': ['sms.read', 'sms.reveal'],
              'expiresAt': expiry,
            },
            'expiresAt': expiry,
          });
        }
        if (request.url.path ==
            '/api/admin/momo/observations/$_source/content') {
          expect(
            request.headers['X-Collect-Review-Reason'],
            'Review the source',
          );
          dispatched.complete();
          return response.future;
        }
        return http.Response('{}', 404);
      }),
    );
    addTearDown(session.dispose);
    await session.refresh();
    session.emailProof(DateTime.now().toUtc());
    final pending = CloudflareAdminObservationApi(session).reveal(
      _group,
      ObservationAdmission.parse(_admission()),
      'Review the source',
    );
    await dispatched.future;
    session.clear();
    response.complete(_json(_content()));
    await expectLater(pending, throwsA(isA<Exception>()));
  });

  test(
    'reveal is rejected when the same-session email proof disappears in flight',
    () async {
      final saved = Map<String, dynamic>.from(
        jsonDecode(
              File(
                'test/fixtures/admin-sms-capture-dto-examples.json',
              ).readAsStringSync(),
            )['session']
            as Map,
      );
      final response = Completer<http.Response>();
      final dispatched = Completer<void>();
      final expiry = DateTime.now()
          .add(const Duration(hours: 1))
          .toUtc()
          .toIso8601String();
      final session = _TestSession(
        MockClient((request) async {
          if (request.url.path == '/api/admin/auth/session') {
            return _json({
              ...saved,
              'user': {
                ...Map<String, dynamic>.from(saved['user'] as Map),
                'role': 'admin',
                'permissions': ['sms.read', 'sms.reveal'],
                'expiresAt': expiry,
              },
              'expiresAt': expiry,
            });
          }
          if (request.url.path ==
              '/api/admin/momo/observations/$_source/content') {
            dispatched.complete();
            return response.future;
          }
          return http.Response('{}', 404);
        }),
      );
      addTearDown(session.dispose);
      await session.refresh();
      session.emailProof(DateTime.now().toUtc());
      final fence = session.authorityFence;
      final pending = CloudflareAdminObservationApi(session).reveal(
        _group,
        ObservationAdmission.parse(_admission()),
        'Review the source',
      );
      await dispatched.future;
      session.emailProof(null);
      expect(session.authorityFence, fence);
      response.complete(_json(_content()));
      await expectLater(pending, throwsA(isA<Exception>()));
    },
  );

  test(
    'staff cannot reveal even when a response claims a reveal grant',
    () async {
      final saved = Map<String, dynamic>.from(
        jsonDecode(
              File(
                'test/fixtures/admin-sms-capture-dto-examples.json',
              ).readAsStringSync(),
            )['session']
            as Map,
      );
      final expiry = DateTime.now()
          .add(const Duration(hours: 1))
          .toUtc()
          .toIso8601String();
      var contentRequests = 0;
      final session = CloudflareAdminSession(
        MockClient((request) async {
          if (request.url.path == '/api/admin/auth/session') {
            return _json({
              ...saved,
              'user': {
                ...Map<String, dynamic>.from(saved['user'] as Map),
                'role': 'staff',
                'permissions': ['sms.read', 'sms.reveal'],
                'expiresAt': expiry,
              },
              'expiresAt': expiry,
            });
          }
          contentRequests++;
          return _json(_content());
        }),
        origin: Uri.parse('https://admin.example.test/'),
        environment: legacyBackendFixtureEnvironment,
      );
      addTearDown(session.dispose);
      await session.refresh();
      await expectLater(
        CloudflareAdminObservationApi(session).reveal(
          _group,
          ObservationAdmission.parse(_admission()),
          'Review the source',
        ),
        throwsA(isA<Exception>()),
      );
      expect(contentRequests, 0);
    },
  );
}
