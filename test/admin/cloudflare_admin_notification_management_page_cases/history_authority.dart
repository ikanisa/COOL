part of '../cloudflare_admin_notification_management_page_test.dart';

void _registerNotificationHistoryAuthorityPageCases() {
  testWidgets(
    'canonical principal change clears the old namespace and cannot restore another link history',
    (tester) async {
      final fixture = _Fixture(
        handler: (request) async {
          if (request.method == 'POST') {
            throw http.ClientException('Lost acknowledgement');
          }
          return null;
        },
      );
      final storage = MemoryAdminPendingAttemptStorage();
      final container = await _mount(tester, fixture, storage);
      await _checkBox(tester, _accessCheckbox);
      await _tap(tester, 'Enable access');
      expect(storage.values, isNotEmpty);
      fixture.principal = _otherPrincipal;
      await tester.runAsync(fixture.session.refresh);
      await tester.pumpAndSettle();
      expect(storage.values, isEmpty);
      expect(find.text('Check or resume exact original request'), findsNothing);
      expect(fixture.writes, hasLength(1));
      await _close(tester, container);
    },
  );

  testWidgets(
    'unavailable per-tab storage prevents access mutation before dispatch',
    (tester) async {
      final fixture = _Fixture();
      final container = await _mount(tester, fixture, _RejectedStorage());
      await _checkBox(tester, _accessCheckbox);
      await _tap(tester, 'Enable access');
      expect(fixture.writes, isEmpty);
      expect(find.textContaining('No request was submitted'), findsOneWidget);
      await _close(tester, container);
    },
  );

  testWidgets(
    'backgrounding drops confirmations and foreground refresh never restores confirmation',
    (tester) async {
      final fixture = _Fixture();
      final container = await _mount(
        tester,
        fixture,
        MemoryAdminPendingAttemptStorage(),
      );
      await _checkBox(tester, _accessCheckbox);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text(_accessCheckbox), findsNothing);
      await _refreshCurrentAccess(tester);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, _accessCheckbox),
            )
            .value,
        isFalse,
      );
      expect(fixture.writes, isEmpty);
      await _close(tester, container);
    },
  );

  testWidgets(
    'Owner without assisted grants discovers same-session history and separates recorded access from current head',
    (tester) async {
      late _Fixture fixture;
      fixture = _Fixture(
        decisionRevision: 3,
        handler: (request) async {
          if (request.url.path == _historyPath) {
            return _result(
              _historyResponse(
                items: [
                  _historyItem(
                    _historyAccessId,
                    recordedAt: fixture.now.toIso8601String(),
                  ),
                  _historyItem(
                    _historyPolicyId,
                    kind: 'policy',
                    recordedAt: fixture.now.toIso8601String(),
                  ),
                  _historyItem(
                    _historyPlanId,
                    kind: 'materialization',
                    recordedAt: fixture.now.toIso8601String(),
                  ),
                ],
              ),
            );
          }
          if (request.url.path == '$_accessPath/operations/$_historyAccessId') {
            fixture.decisionRevision = 5;
            return _result(
              fixture.accessOperation(
                _historyAccessId,
                recorded: fixture.accessReceipt({
                  'request_id': _historyAccessId,
                  'expected_decision_revision': 0,
                  'enabled': true,
                }),
              ),
            );
          }
          return null;
        },
      );
      final container = await _mount(
        tester,
        fixture,
        MemoryAdminPendingAttemptStorage(),
      );
      expect(fixture.requests, hasLength(1));
      await _loadHistory(tester);
      final history = _serverHistory();
      expect(tester.widget<AdminDataTable>(history).rows, hasLength(3));
      for (final id in [_historyPolicyId, _historyPlanId]) {
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(ValueKey('management-history-status:$id')),
              )
              .onPressed,
          isNull,
        );
      }
      await _tapKey(
        tester,
        const ValueKey('management-history-status:$_historyAccessId'),
      );
      final recorded = _facts(
        'Server recorded historical decision $_historyAccessId',
      );
      final current = _facts(
        'Current access observed with recorded request $_historyAccessId',
      );
      expect(
        find.descendant(of: recorded, matching: find.text('1')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: recorded,
          matching: find.text('Recorded access enabled'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: current, matching: find.text('5')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: current, matching: find.text('Not granted')),
        findsNWidgets(2),
      );
      expect(_facts('Actual current assisted SMS grants'), findsNothing);
      expect(find.text('Check or resume exact original request'), findsNothing);
      expect(find.text('Original management operations'), findsNothing);
      expect(
        fixture.requests.every((request) => request.method == 'GET'),
        isTrue,
      );
      expect(
        fixture.requests.any(
          (request) => request.url.path == '/api/admin/notification-operator',
        ),
        isFalse,
      );
      expect(
        fixture.requests.any(
          (request) => request.url.path.contains('/materialize/'),
        ),
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await _close(tester, container);
    },
  );

  testWidgets(
    'empty history and absent Owner access result preserve a self-disable UUID after grants disappear',
    (tester) async {
      final storage = MemoryAdminPendingAttemptStorage();
      final first = _Fixture(
        readGranted: true,
        manageGranted: true,
        decisionRevision: 4,
        handler: (request) async {
          if (request.url.path == _accessPath && request.method == 'POST') {
            throw http.ClientException('Committed disable response lost');
          }
          return null;
        },
      );
      var container = await _mount(tester, first, storage);
      await _tap(tester, 'Remove access');
      final original = _body(first.writes.single);
      await _close(tester, container);
      final next = _Fixture(decisionRevision: 5);
      container = await _mount(tester, next, storage);
      await _loadHistory(tester);
      expect(
        find.textContaining('No recorded requests on this page'),
        findsOneWidget,
      );
      expect(storage.values.values.join(), contains(original['request_id']));
      final check = find.widgetWithText(
        OutlinedButton,
        'Check recorded operation',
      );
      expect(tester.widget<OutlinedButton>(check).onPressed, isNotNull);
      await _tap(tester, 'Check recorded operation');
      expect(
        find.descendant(
          of: _facts('Unresolved original request ${original['request_id']}'),
          matching: find.textContaining('No recorded result observed'),
        ),
        findsOneWidget,
      );
      expect(storage.values.values.join(), contains(original['request_id']));
      expect(
        _retainedReference(storage)['intent'],
        containsPair('expected_decision_revision', 4),
      );
      expect(find.text('Check or resume exact original request'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Enable access'),
            )
            .onPressed,
        isNull,
      );
      expect(
        next.requests.last.url.path,
        '$_accessPath/operations/${original['request_id']}',
      );
      expect(next.requests.every((request) => request.method == 'GET'), isTrue);
      expect(next.writes, isEmpty);
      await _close(tester, container);
    },
  );

  testWidgets(
    'dedicated Owner Check resolves a recorded self-disable without assisted manage and keeps historical and current heads distinct',
    (tester) async {
      final storage = MemoryAdminPendingAttemptStorage();
      final first = _Fixture(
        readGranted: true,
        manageGranted: true,
        decisionRevision: 4,
        handler: (request) async {
          if (request.url.path == _accessPath && request.method == 'POST') {
            throw http.ClientException('Lost committed response');
          }
          return null;
        },
      );
      var container = await _mount(tester, first, storage);
      await _tap(tester, 'Remove access');
      final original = _body(first.writes.single),
          id = original['request_id'] as String;
      await _close(tester, container);
      late _Fixture next;
      next = _Fixture(
        decisionRevision: 7,
        handler: (request) async {
          if (request.url.path == '$_accessPath/operations/$id') {
            return _result(
              next.accessOperation(id, recorded: first.accessReceipt(original)),
            );
          }
          if (request.url.path == _historyPath) {
            return _result(
              _historyResponse(
                items: [
                  _historyItem(id, recordedAt: first.now.toIso8601String()),
                ],
              ),
            );
          }
          return null;
        },
      );
      container = await _mount(tester, next, storage);
      await _tap(tester, 'Check recorded operation');
      expect(storage.values, isEmpty);
      expect(
        find.descendant(
          of: _facts('Recorded historical decision $id'),
          matching: find.text('5'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _facts('Actual current assisted SMS grants'),
          matching: find.text('7'),
        ),
        findsOneWidget,
      );
      expect(find.text('Check or resume exact original request'), findsNothing);
      await _loadHistory(tester);
      expect(
        tester.widget<AdminDataTable>(_serverHistory()).rows.single.id,
        id,
      );
      expect(next.requests.every((request) => request.method == 'GET'), isTrue);
      expect(
        next.requests.any(
          (request) => request.url.path == '/api/admin/notification-operator',
        ),
        isFalse,
      );
      expect(next.writes, isEmpty);
      await _close(tester, container);
    },
  );

  testWidgets(
    'discovered recorded receipt never resolves a matching local unknown or reconstructs its command',
    (tester) async {
      final storage = MemoryAdminPendingAttemptStorage();
      final first = _Fixture(
        handler: (request) async {
          if (request.url.path == _accessPath && request.method == 'POST') {
            throw http.ClientException('Lost response');
          }
          return null;
        },
      );
      var container = await _mount(tester, first, storage);
      await _checkBox(tester, _accessCheckbox);
      await _tap(tester, 'Enable access');
      final original = _body(first.writes.single),
          id = original['request_id'] as String;
      await _close(tester, container);
      late _Fixture next;
      next = _Fixture(
        decisionRevision: 2,
        handler: (request) async {
          if (request.url.path == _historyPath) {
            return _result(
              _historyResponse(
                items: [
                  _historyItem(id, recordedAt: first.now.toIso8601String()),
                ],
              ),
            );
          }
          if (request.url.path == '$_accessPath/operations/$id') {
            return _result(
              next.accessOperation(id, recorded: first.accessReceipt(original)),
            );
          }
          return null;
        },
      );
      container = await _mount(tester, next, storage);
      await _loadHistory(tester);
      await _tapKey(tester, ValueKey('management-history-status:$id'));
      expect(_facts('Server recorded historical decision $id'), findsOneWidget);
      expect(storage.values.values.join(), contains(id));
      expect(
        _retainedReference(storage)['intent'],
        containsPair('expected_decision_revision', 0),
      );
      expect(find.text('Check or resume exact original request'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Enable access'),
            )
            .onPressed,
        isNull,
      );
      expect(next.writes, isEmpty);
      expect(next.requests.every((request) => request.method == 'GET'), isTrue);
      await _close(tester, container);
    },
  );

  testWidgets(
    'policy history reads immutable result and current policy independently without preparing a mutation draft',
    (tester) async {
      late _Fixture fixture;
      fixture = _Fixture(
        readGranted: true,
        manageGranted: true,
        handler: (request) async {
          if (request.url.path == _historyPath) {
            return _result(
              _historyResponse(
                items: [
                  _historyItem(
                    _historyPolicyId,
                    kind: 'policy',
                    recordedAt: fixture.now.toIso8601String(),
                  ),
                ],
              ),
            );
          }
          if (request.url.path ==
              '/api/admin/notification-operator/policies/operations/$_historyPolicyId') {
            return _result(
              fixture.policyOperation(
                _historyPolicyId,
                recorded: fixture.policyReceipt({
                  'request_id': _historyPolicyId,
                  'expected_revision': 3,
                  'enabled': false,
                }),
              ),
            );
          }
          return null;
        },
      );
      fixture.policyRevision = 9;
      final container = await _mount(
        tester,
        fixture,
        MemoryAdminPendingAttemptStorage(),
      );
      await _loadHistory(tester);
      await _tapKey(
        tester,
        const ValueKey('management-history-status:$_historyPolicyId'),
      );
      expect(
        find.descendant(
          of: _facts('Server recorded historical decision $_historyPolicyId'),
          matching: find.text('4'),
        ),
        findsOneWidget,
      );
      expect(
        fixture.requests.where((request) => request.url.path == _policyPath),
        isEmpty,
      );
      await _tap(tester, 'Check current policy for recorded collection');
      expect(
        find.descendant(
          of: _facts(
            'Current policy observed with recorded request $_historyPolicyId',
          ),
          matching: find.text('9'),
        ),
        findsOneWidget,
      );
      expect(
        _facts('Actual current collection receipt SMS policy'),
        findsNothing,
      );
      expect(find.text(_policyCheckbox), findsNothing);
      expect(fixture.writes, isEmpty);
      expect(
        fixture.requests.every((request) => request.method == 'GET'),
        isTrue,
      );
      await _close(tester, container);
    },
  );
}
