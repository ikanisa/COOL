part of '../cloudflare_admin_notification_management_api_test.dart';

extension _NotificationHistoryCases on _NotificationManagementApiSuite {
  void _registerNotificationHistoryCases() {
    test(
      'history metadata includes all three kinds without conferring assisted authority',
      () async {
        fixture.permissions = ['admin_users.manage'];
        await fixture.open();
        fixture.handler = (_) async => _json({
          'ok': true,
          'result': _history([
            _historyItem(_other, 'materialization', fixture.now),
            _historyItem(_transaction, 'policy', fixture.now),
            _historyItem(_request, 'access', fixture.now),
          ]),
        });
        final before = fixture.session.authorityFence;
        final page = await fixture.api.getHistory();
        expect(page.items.map((x) => x.kind), [
          NotificationManagementHistoryKind.materialization,
          NotificationManagementHistoryKind.policy,
          NotificationManagementHistoryKind.access,
        ]);
        expect(page.items.first.recordedOutcome, 'plan_recorded');
        expect(
          page.items.first.statusPath,
          '/api/admin/notification-operator/materialize/$_other',
        );
        expect(
          page.items.every((x) => x.recordedStateOnly && !x.maySend),
          isTrue,
        );
        expect(page.nextCursor, isNull);
        expect(page.replayAuthorized, isFalse);
        expect(page.originalSessionOnly, isTrue);
        expect(() => page.items.clear(), throwsUnsupportedError);
        expect(fixture.api.canManagePolicy, isFalse);
        expect(fixture.session.authorityFence, before);
        final request = fixture.requests.single;
        expect(request.method, 'GET');
        expect(request.url.path, '/api/admin/notification-operator/operations');
        expect(request.url.queryParameters, {'limit': '25'});
        expect(request.body, isEmpty);
        expect(request.headers.containsKey('Authorization'), isFalse);
      },
    );

    test(
      'history uses paired seek cursors and rejects foreign API cursors before transport',
      () async {
        final at = fixture.now;
        var calls = 0;
        fixture.handler = (_) async => _json({
          'ok': true,
          'result': ++calls == 1
              ? _history(
                  [_historyItem(_other, 'access', at)],
                  next: {
                    'after_created_at': at.toIso8601String(),
                    'after_request_id': _other,
                  },
                )
              : _history([_historyItem(_request, 'policy', at)]),
        });
        final first = await fixture.api.getHistory(limit: 1);
        final cursor = first.nextCursor!;
        final second = await fixture.api.getHistory(limit: 1, after: cursor);
        expect(second.items.single.requestId, _request);
        expect(fixture.requests.last.url.queryParameters, {
          'limit': '1',
          'after_created_at': at.toIso8601String(),
          'after_request_id': _other,
        });
        final count = fixture.requests.length;
        final otherApi = CloudflareAdminNotificationManagementApi(
          fixture.session,
        );
        await expectLater(
          otherApi.getHistory(after: cursor),
          throwsA(isA<AdminAccountException>()),
        );
        for (final limit in [0, 26]) {
          await expectLater(
            fixture.api.getHistory(limit: limit),
            throwsArgumentError,
          );
        }
        expect(fixture.requests, hasLength(count));
      },
    );

    test(
      'history rejects duplicates, ascending ties, foreign paths and malformed continuation',
      () async {
        final at = fixture.now;
        final a = _historyItem(_other, 'access', at);
        final b = _historyItem(_request, 'policy', at);
        final badRows = <Map<String, dynamic>>[
          _history([a, a]),
          _history([b, a]),
          _history([
            {...a, 'kind': 'cancel'},
          ]),
          _history([
            {...a, 'status_path': 'https://foreign.example/$_other'},
          ]),
          _history([
            {...a, 'status_path': a['status_path'] + '/cancel'},
          ]),
          _history([
            {
              ...a,
              'status_path':
                  '/api/admin/notification-operator/policies/operations/$_other',
            },
          ]),
          _history([
            {...a, 'recorded_outcome': 'plan_recorded'},
          ]),
          _history([
            {...a, 'recorded_at': '2026-02-31T00:00:00.000Z'},
          ]),
          _history([
            {...a, 'current_admin_id': _other},
          ]),
          _history([
            {...a, 'may_send': true},
          ]),
          {
            ..._history([a]),
            'replay_authorized': true,
          },
          {
            ..._history([a]),
            'original_session_only': false,
          },
          _history([a], next: {'after_created_at': at.toIso8601String()}),
          _history(
            [a],
            next: {
              'after_created_at': at.toIso8601String(),
              'after_request_id': _request,
            },
          ),
          _history(
            [a],
            next: {
              'after_created_at': at.toIso8601String(),
              'after_request_id': _other,
              'offset': 1,
            },
          ),
          _history(
            [],
            next: {
              'after_created_at': at.toIso8601String(),
              'after_request_id': _other,
            },
          ),
        ];
        for (final row in badRows) {
          fixture.handler = (_) async => _json({'ok': true, 'result': row});
          await expectLater(
            fixture.api.getHistory(limit: row['next_cursor'] == null ? 25 : 1),
            throwsFormatException,
          );
        }
        fixture.handler = (_) async => _json({
          'ok': true,
          'result': _history([a, b]),
        });
        await expectLater(
          fixture.api.getHistory(limit: 1),
          throwsFormatException,
        );
      },
    );

    test(
      'a subsequent history page cannot repeat or advance beyond its cursor',
      () async {
        final row = _historyItem(_request, 'access', fixture.now);
        fixture.handler = (_) async => _json({
          'ok': true,
          'result': _history(
            [row],
            next: {
              'after_created_at': fixture.now.toIso8601String(),
              'after_request_id': _request,
            },
          ),
        });
        final cursor = (await fixture.api.getHistory(limit: 1)).nextCursor!;
        for (final id in [_request, _other]) {
          fixture.handler = (_) async => _json({
            'ok': true,
            'result': _history([_historyItem(id, 'access', fixture.now)]),
          });
          await expectLater(
            fixture.api.getHistory(limit: 1, after: cursor),
            throwsFormatException,
          );
        }
      },
    );
  }
}
