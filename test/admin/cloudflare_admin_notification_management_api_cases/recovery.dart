part of '../cloudflare_admin_notification_management_api_test.dart';

extension _NotificationRecoveryCases on _NotificationManagementApiSuite {
  void _registerNotificationRecoveryCases() {
    test(
      'policy GET, disable CAS and exact original replay do not add replay fields',
      () async {
        final operation = await fixture.policyOperation();
        expect(operation.expectedDecisionRevision, isNull);
        final first = await fixture.api.setPolicy(operation);
        final originalBody = fixture.requests.last.body;
        expect(first.revision, 4);
        expect(first.enabled, isFalse);
        expect(first.recordedStateOnly, isTrue);
        expect(jsonDecode(originalBody), {
          'request_id': _request,
          'expected_revision': 3,
          'enabled': false,
          'owner_confirmation': false,
        });
        await expectLater(fixture.api.setPolicy(operation), throwsStateError);
        final replay = await fixture.api.replayPolicy(operation);
        expect(
          replay.recordedOwnerDecisionSha256,
          first.recordedOwnerDecisionSha256,
        );
        expect(fixture.requests.last.body, originalBody);
        expect(
          fixture.requests.last.url.path,
          '/api/admin/notification-operator/policies/$_collection',
        );
        expect((await fixture.api.getPolicy(_collection)).revision, 3);
      },
    );

    test(
      'enable requires explicit assent and current active policy source',
      () async {
        final access = await fixture.api.getAccess();
        expect(
          () => fixture.api.prepareAccess(
            expected: access,
            enabled: true,
            ownerConfirmation: false,
          ),
          throwsArgumentError,
        );
        fixture.collectionActive = false;
        var state = await fixture.api.getPolicy(_collection);
        expect(
          () => fixture.api.preparePolicy(
            expected: state,
            enabled: true,
            ownerConfirmation: true,
          ),
          throwsArgumentError,
        );
        fixture.collectionActive = true;
        state = await fixture.api.getPolicy(_collection);
        expect(
          () => fixture.api.preparePolicy(
            expected: state,
            enabled: true,
            ownerConfirmation: false,
          ),
          throwsArgumentError,
        );
        fixture.policyRevision = 999999999;
        final maximum = await fixture.api.getPolicy(_collection);
        expect(
          () => fixture.api.preparePolicy(
            expected: maximum,
            enabled: false,
            ownerConfirmation: false,
          ),
          throwsArgumentError,
        );
      },
    );

    test(
      'only explicit access replay uses the exact frozen body and original UUID',
      () async {
        final operation = await fixture.accessOperation();
        await expectLater(
          fixture.api.replayAccess(operation),
          throwsStateError,
        );
        final receipt = await fixture.api.setAccess(operation);
        final original = fixture.requests.last.body;
        await expectLater(fixture.api.setAccess(operation), throwsStateError);
        final current = await fixture.api.getAccess();
        expect(
          () => fixture.api.prepareAccess(
            expected: current,
            enabled: false,
            ownerConfirmation: false,
            requestId: _request,
          ),
          throwsStateError,
        );
        final replay = await fixture.api.replayAccess(operation);
        expect(replay.replay, isTrue);
        expect(replay.decisionSha256, receipt.decisionSha256);
        expect(fixture.requests.last.body, original);
      },
    );

    test(
      'all dispatched errors retain original operation and require explicit recovery',
      () async {
        for (final status in [403, 409, 503]) {
          final fresh = _Fixture();
          await fresh.open();
          try {
            final operation = await fresh.accessOperation();
            fresh.handler = (_) async =>
                _json({'error': 'sms_access_changed'}, status);
            await expectLater(
              fresh.api.setAccess(operation),
              throwsA(
                isA<NotificationManagementRequestException>()
                    .having((e) => e.outcomeUnknown, 'unknown', isTrue)
                    .having(
                      (e) => identical(e.operation, operation),
                      'original',
                      isTrue,
                    )
                    .having((e) => e.operation.requestId, 'UUID', _request),
              ),
            );
            expect(
              fresh.requests.where((r) => r.method == 'POST'),
              hasLength(1),
            );
            await expectLater(fresh.api.setAccess(operation), throwsStateError);
          } finally {
            fresh.dispose();
          }
        }
      },
    );

    test(
      'lost transport may be reconciled only by deliberate original-body replay',
      () async {
        final operation = await fixture.accessOperation();
        fixture.handler = (request) async {
          fixture.result(
            request,
          ); // The server committed before losing its response.
          throw http.ClientException('lost reply');
        };
        await expectLater(
          fixture.api.setAccess(operation),
          throwsA(
            isA<NotificationManagementRequestException>().having(
              (e) => e.outcomeUnknown,
              'unknown',
              isTrue,
            ),
          ),
        );
        final original = fixture.requests.last.body;
        fixture.handler = null;
        final replay = await fixture.api.replayAccess(operation);
        expect(replay.replay, isTrue);
        expect(fixture.requests.last.body, original);
        expect(fixture.requests.where((r) => r.method == 'POST'), hasLength(2));
      },
    );

    test(
      'authority loss during an access mutation never adopts or confirms newer access',
      () async {
        final operation = await fixture.accessOperation();
        final reply = Completer<http.Response>();
        fixture.handler = (_) => reply.future;
        final pending = fixture.api.setAccess(operation);
        await Future<void>.delayed(Duration.zero);
        fixture.session.clear();
        reply.complete(
          _json({
            'ok': true,
            'result': fixture.accessReceipt({
              'request_id': _request,
              'enabled': true,
            }),
          }),
        );
        await expectLater(
          pending,
          throwsA(
            isA<NotificationManagementRequestException>()
                .having((e) => e.outcomeUnknown, 'unknown', isTrue)
                .having(
                  (e) => e.operation.requestId,
                  'retained UUID',
                  _request,
                ),
          ),
        );
        await fixture.session.refresh();
        expect(fixture.api.authorityCurrent, isFalse);
        await expectLater(
          fixture.api.replayAccess(operation),
          throwsA(isA<AdminAccountException>()),
        );
      },
    );

    test(
      'wrong action, foreign state and concurrent replay are blocked before transport',
      () async {
        final operation = await fixture.accessOperation();
        await expectLater(
          fixture.api.setPolicy(operation),
          throwsArgumentError,
        );
        final freshApi = CloudflareAdminNotificationManagementApi(
          fixture.session,
        );
        await expectLater(
          freshApi.setAccess(operation),
          throwsA(isA<AdminAccountException>()),
        );
        final reply = Completer<http.Response>();
        fixture.handler = (_) => reply.future;
        final pending = fixture.api.setAccess(operation);
        await Future<void>.delayed(Duration.zero);
        await expectLater(
          fixture.api.replayAccess(operation),
          throwsStateError,
        );
        reply.complete(
          _json({
            'ok': true,
            'result': fixture.accessReceipt({
              'request_id': _request,
              'enabled': true,
            }),
          }),
        );
        await pending;
        expect(fixture.requests.where((r) => r.method == 'POST'), hasLength(1));
      },
    );

    test(
      'actual reads reject malformed capability/state identities and field sets',
      () async {
        for (final patch in <Map<String, dynamic>>[
          {'can_operate': true},
          {'current_principal_id': _other},
          {
            'permissions': ['assisted_sms.read', 'users.manage'],
          },
          {'read_granted': 1},
          {'legal_release_approved': true},
          {'unexpected': true},
        ]) {
          fixture.handler = (_) async => _json({
            'ok': true,
            'result': {...fixture.access(), ...patch},
          });
          await expectLater(fixture.api.getAccess(), throwsFormatException);
        }
        fixture.policyRevision = 0;
        fixture.handler = (_) async => _json({
          'ok': true,
          'result': {
            ...fixture.policy(),
            'recorded_owner_decision_sha256': 'b' * 64,
          },
        });
        await expectLater(
          fixture.api.getPolicy(_collection),
          throwsFormatException,
        );
      },
    );

    test('malformed write receipts cannot become confirmed outcomes', () async {
      for (final patch in <Map<String, dynamic>>[
        {'grant_transaction_id': '00000000-0000-0000-0000-000000000000'},
        {'decision_sha256': 'c' * 64},
        {'recorded_state_only': false},
        {'read_granted': false},
        {'public_session_id': _other},
        {'provider_approved': true},
        {'replay': 'false'},
      ]) {
        final fresh = _Fixture();
        await fresh.open();
        try {
          final operation = await fresh.accessOperation();
          fresh.handler = (request) async => _json({
            'ok': true,
            'result': {
              ...fresh.accessReceipt(
                Map<String, dynamic>.from(jsonDecode(request.body) as Map),
              ),
              ...patch,
            },
          });
          await expectLater(
            fresh.api.setAccess(operation),
            throwsA(
              isA<NotificationManagementRequestException>().having(
                (e) => e.outcomeUnknown,
                'unknown',
                isTrue,
              ),
            ),
          );
        } finally {
          fresh.dispose();
        }
      }
      final operation = await fixture.policyOperation();
      fixture.handler = (request) async => _json({
        'ok': true,
        'result': {
          ...fixture.policyReceipt(
            Map<String, dynamic>.from(jsonDecode(request.body) as Map),
          ),
          'replay':
              true, // The actual policy receipt contract has no replay field.
        },
      });
      await expectLater(
        fixture.api.setPolicy(operation),
        throwsA(isA<NotificationManagementRequestException>()),
      );
    });

    test(
      'typed operation lookup returns historical receipts and never current grants',
      () async {
        final operation = await fixture.accessOperation();
        await fixture.api.setAccess(operation);
        final resolved = await fixture.api.getOperation(
          _request,
          originalOperation: operation,
        );
        expect(resolved.observed, isTrue);
        expect(resolved.receipt, isA<NotificationManagementAccessReceipt>());
        expect(resolved.receipt!.recordedStateOnly, isTrue);
        expect((await fixture.api.getAccess()).canOperate, isFalse);
        final count = fixture.requests.length;
        await expectLater(
          fixture.api.getOperation(_other, originalOperation: operation),
          throwsArgumentError,
        );
        expect(fixture.requests, hasLength(count));
        final freshApi = CloudflareAdminNotificationManagementApi(
          fixture.session,
        );
        await expectLater(
          freshApi.getOperation(_request, originalOperation: operation),
          throwsA(isA<AdminAccountException>()),
        );
      },
    );

    test(
      'policy lookup and not-found remain receipt-only; malformed recovery fails closed',
      () async {
        final operation = await fixture.policyOperation();
        await fixture.api.setPolicy(operation);
        final resolved = await fixture.api.getOperation(
          _request,
          originalOperation: operation,
        );
        expect(resolved.receipt, isA<NotificationManagementPolicyReceipt>());
        expect((await fixture.api.getPolicy(_collection)).revision, 3);
        final absent = await fixture.api.getOperation(_other);
        expect(absent.observed, isFalse);
        expect(absent.receipt, isNull);
        for (final patch in <Map<String, dynamic>>[
          {'may_send': true},
          {'observed': false},
          {'request_id': _other},
        ]) {
          fixture.handler = (_) async => _json({
            'ok': true,
            'result': {
              ...fixture.lookup(_request, fixture.retained[_request]),
              ...patch,
            },
          });
          await expectLater(
            fixture.api.getOperation(_request),
            throwsFormatException,
          );
        }
      },
    );

    test(
      'UUID version/variant validation and normalization match the backend',
      () async {
        for (final value in [
          '00000000-0000-0000-0000-000000000000',
          '30000000-0000-9000-8000-000000000006',
          '30000000-0000-4000-7000-000000000006',
        ]) {
          await expectLater(
            fixture.api.getPolicy(value),
            throwsFormatException,
          );
          await expectLater(
            fixture.api.getOperation(value),
            throwsFormatException,
          );
        }
        final state = await fixture.api.getAccess();
        final operation = fixture.api.prepareAccess(
          expected: state,
          enabled: false,
          ownerConfirmation: false,
          requestId: 'A0000000-DEAD-4ABC-8DEF-000000000006',
        );
        expect(operation.requestId, 'a0000000-dead-4abc-8def-000000000006');
      },
    );
  }
}
