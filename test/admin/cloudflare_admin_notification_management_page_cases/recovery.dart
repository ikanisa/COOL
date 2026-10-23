part of '../cloudflare_admin_notification_management_page_test.dart';

void _registerNotificationRecoveryPageCases() {
  testWidgets(
    'unknown self-access retains only metadata and reload never reconstructs or resends the command',
    (tester) async {
      final storage = MemoryAdminPendingAttemptStorage();
      final first = _Fixture(
        handler: (request) async {
          if (request.url.path == _accessPath && request.method == 'POST') {
            throw http.ClientException('Lost acknowledgement');
          }
          return null;
        },
      );
      var container = await _mount(tester, first, storage);
      await _checkBox(tester, _accessCheckbox);
      await _tap(tester, 'Enable access');
      final id = _body(first.writes.single)['request_id'];
      final saved = storage.values.values.join();
      expect(saved, contains(id));
      expect(
        _retainedReference(storage)['intent'],
        containsPair('expected_decision_revision', 0),
      );
      for (final field in [
        'expected_read',
        'expected_manage',
        'owner_confirmation',
        'claim_token',
      ]) {
        expect(saved, isNot(contains(field)));
      }
      expect(
        find.text('Check or resume exact original request'),
        findsOneWidget,
      );
      await _close(tester, container);
      final next = _Fixture(decisionRevision: 11);
      container = await _mount(tester, next, storage);
      expect(next.writes, isEmpty);
      expect(
        find.descendant(
          of: _facts('Unresolved original request $id'),
          matching: find.text(id as String),
        ),
        findsOneWidget,
      );
      expect(find.text('Check or resume exact original request'), findsNothing);
      expect(find.text('Not granted'), findsNWidgets(2));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Enable access'),
            )
            .onPressed,
        isNull,
      );
      expect(storage.values.values.join(), contains(id));
      expect(
        _retainedReference(storage)['intent'],
        containsPair('expected_decision_revision', 0),
      );
      await _close(tester, container);
    },
  );

  testWidgets(
    'legacy unresolved access UUID without a decision head remains held after reload',
    (tester) async {
      final storage = MemoryAdminPendingAttemptStorage();
      final first = _Fixture(
        handler: (request) async {
          if (request.url.path == _accessPath && request.method == 'POST') {
            throw http.ClientException('Lost acknowledgement');
          }
          return null;
        },
      );
      var container = await _mount(tester, first, storage);
      await _checkBox(tester, _accessCheckbox);
      await _tap(tester, 'Enable access');
      final originalId = _body(first.writes.single)['request_id'] as String;
      await _close(tester, container);

      // The predecessor schema retained these exact identity fields but no
      // decision head. It must remain a hold, not become a new confirmation.
      final storageKey = storage.values.keys.single;
      final envelope = Map<String, dynamic>.from(
        jsonDecode(storage.values[storageKey]!) as Map,
      );
      final reference = _retainedReference(storage);
      final intent = Map<String, dynamic>.from(reference['intent'] as Map)
        ..remove('expected_decision_revision');
      reference['intent'] = intent;
      envelope['entries'] = [reference];
      storage.write(storageKey, jsonEncode(envelope));

      final next = _Fixture(decisionRevision: 12);
      container = await _mount(tester, next, storage);
      expect(next.writes, isEmpty);
      expect(
        find.descendant(
          of: _facts('Unresolved original request $originalId'),
          matching: find.text(originalId),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _facts('Unresolved original request $originalId'),
          matching: find.textContaining(
            'Expected access decision revision was not retained',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('No live original command'), findsOneWidget);
      expect(find.text('Check or resume exact original request'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Enable access'),
            )
            .onPressed,
        isNull,
      );
      expect(storage.values.values.join(), contains(originalId));
      expect(
        _retainedReference(storage)['intent'],
        isNot(contains('expected_decision_revision')),
      );
      final currentFacts = find.byWidgetPredicate(
        (widget) =>
            widget is AdminRecordFactsTable &&
            widget.semanticLabel == 'Actual current assisted SMS grants',
      );
      expect(
        find.descendant(of: currentFacts, matching: find.text('12')),
        findsOneWidget,
      );
      await _close(tester, container);
    },
  );

  for (final malformed in <({String label, Object? value})>[
    (label: 'null', value: null),
    (label: 'numeric-string', value: '4'),
    (label: 'negative', value: -1),
    (label: 'exhausted', value: 9007199254740991),
  ]) {
    testWidgets(
      'malformed retained expected head ${malformed.label} keeps a visible UUID and fails closed',
      (tester) async {
        final storage = MemoryAdminPendingAttemptStorage();
        final first = _Fixture(
          decisionRevision: 4,
          handler: (request) async {
            if (request.url.path == _accessPath && request.method == 'POST') {
              throw http.ClientException('Lost acknowledgement');
            }
            return null;
          },
        );
        var container = await _mount(tester, first, storage);
        await _checkBox(tester, _accessCheckbox);
        await _tap(tester, 'Enable access');
        final originalId = _body(first.writes.single)['request_id'] as String;
        await _close(tester, container);

        final storageKey = storage.values.keys.single;
        final envelope = Map<String, dynamic>.from(
          jsonDecode(storage.values[storageKey]!) as Map,
        );
        final reference = _retainedReference(storage);
        final intent = Map<String, dynamic>.from(reference['intent'] as Map);
        intent['expected_decision_revision'] = malformed.value;
        reference['intent'] = intent;
        envelope['entries'] = [reference];
        storage.write(storageKey, jsonEncode(envelope));

        final next = _Fixture(decisionRevision: 8);
        container = await _mount(tester, next, storage);
        expect(
          find.descendant(
            of: _facts('Unresolved original request $originalId'),
            matching: find.text(originalId),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: _facts('Unresolved original request $originalId'),
            matching: find.textContaining(
              'The retained access decision revision could not be verified',
            ),
          ),
          findsOneWidget,
        );
        expect(find.text('No live original command'), findsOneWidget);
        expect(
          find.text('Check or resume exact original request'),
          findsNothing,
        );
        expect(find.text('Not submitted'), findsNothing);
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Check recorded operation'),
              )
              .onPressed,
          isNull,
        );
        expect(next.requests, isEmpty);
        expect(storage.values.values.join(), contains(originalId));
        expect(
          _retainedReference(storage)['intent'],
          containsPair('expected_decision_revision', malformed.value),
        );
        expect(tester.takeException(), isNull);
        await _close(tester, container);
      },
    );
  }

  testWidgets(
    'deliberate original replay preserves the exact body and UUID instead of generating a newer command',
    (tester) async {
      late _Fixture fixture;
      var posts = 0;
      fixture = _Fixture(
        handler: (request) async {
          if (request.url.path == _accessPath &&
              request.method == 'POST' &&
              ++posts == 1) {
            throw http.ClientException('Lost acknowledgement');
          }
          return null;
        },
      );
      final container = await _mount(
        tester,
        fixture,
        MemoryAdminPendingAttemptStorage(),
      );
      await _checkBox(tester, _accessCheckbox);
      await _tap(tester, 'Enable access');
      final original = _body(fixture.writes.single);
      expect(fixture.writes, hasLength(1));
      expect(original['expected_decision_revision'], 0);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(
                OutlinedButton,
                'Check or resume exact original request',
              ),
            )
            .onPressed,
        isNotNull,
      );
      await _tap(tester, 'Check or resume exact original request');
      expect(fixture.writes, hasLength(2));
      expect(_body(fixture.writes.last), original);
      expect(fixture.decisionRevision, 1);
      expect(fixture.sessionReads, 2);
      await _close(tester, container);
    },
  );

  testWidgets(
    'restored expected head refuses a different recorded head without clearing its UUID hold',
    (tester) async {
      final storage = MemoryAdminPendingAttemptStorage();
      final first = _Fixture(
        decisionRevision: 4,
        handler: (request) async {
          if (request.url.path == _accessPath && request.method == 'POST') {
            throw http.ClientException('Lost acknowledgement');
          }
          return null;
        },
      );
      var container = await _mount(tester, first, storage);
      await _checkBox(tester, _accessCheckbox);
      await _tap(tester, 'Enable access');
      final original = _body(first.writes.single);
      await _close(tester, container);

      late _Fixture next;
      next = _Fixture(
        readGranted: true,
        manageGranted: true,
        decisionRevision: 12,
        handler: (request) async {
          if (request.url.path ==
              '$_accessPath/operations/${original['request_id']}') {
            return _result(
              next.accessOperation(
                original['request_id'] as String,
                recorded: next.accessReceipt({
                  ...original,
                  'expected_decision_revision': 8,
                }),
              ),
            );
          }
          return null;
        },
      );
      container = await _mount(tester, next, storage);
      expect(find.text('Check or resume exact original request'), findsNothing);
      await _tap(tester, 'Check recorded operation');
      expect(
        find.descendant(
          of: _facts('Unresolved original request ${original['request_id']}'),
          matching: find.text(original['request_id'] as String),
        ),
        findsOneWidget,
      );
      expect(
        _retainedReference(storage)['intent'],
        containsPair('expected_decision_revision', 4),
      );
      expect(
        find.textContaining('The response could not be verified'),
        findsOneWidget,
      );
      expect(find.text('Yes; not current authority'), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Remove access'),
            )
            .onPressed,
        isNull,
      );
      expect(next.writes, isEmpty);
      expect(next.requests.every((request) => request.method == 'GET'), isTrue);
      expect(
        next.requests.last.url.path,
        '$_accessPath/operations/${original['request_id']}',
      );
      await _close(tester, container);
    },
  );

  testWidgets(
    'unknown disable replay retains its original head after regrant under unchanged permissions',
    (tester) async {
      final storage = MemoryAdminPendingAttemptStorage();
      late _Fixture fixture;
      var posts = 0;
      fixture = _Fixture(
        readGranted: true,
        manageGranted: true,
        decisionRevision: 8,
        handler: (request) async {
          if (request.url.path == _accessPath && request.method == 'POST') {
            final body = _body(request);
            if (++posts == 1) {
              fixture.readGranted = false;
              fixture.manageGranted = false;
              fixture.decisionRevision =
                  (body['expected_decision_revision'] as int) + 1;
              throw http.ClientException('Committed disable lost its response');
            }
            // The immutable old result is returned without applying it again
            // to current grants or advancing the newer decision head.
            return _result(fixture.accessReceipt(body, replay: true));
          }
          return null;
        },
      );
      var container = await _mount(tester, fixture, storage);
      final originalFence = fixture.session.authorityFence;
      await _tap(tester, 'Remove access');
      final original = _body(fixture.writes.single);
      expect(original['enabled'], isFalse);
      expect(original['expected_decision_revision'], 8);
      expect(
        _retainedReference(storage)['intent'],
        containsPair('expected_decision_revision', 8),
      );

      // A later explicit regrant returns to the same grant booleans. Session
      // permissions alone cannot distinguish this newer Owner decision.
      fixture.readGranted = true;
      fixture.manageGranted = true;
      fixture.decisionRevision = 10;
      await tester.runAsync(fixture.session.refresh);
      await tester.pumpAndSettle();
      expect(fixture.session.authorityFence, originalFence);
      final history = find.byWidgetPredicate(
        (widget) =>
            widget is AdminDataTable &&
            widget.tableLabel == 'Original assisted SMS management operations',
      );
      Scrollable.of(
        tester.element(history),
        axis: Axis.vertical,
      ).position.jumpTo(0);
      await tester.pumpAndSettle();
      final refresh = find.byTooltip('Refresh current assisted SMS access');
      await _reveal(tester, refresh);
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      final currentFacts = find.byWidgetPredicate(
        (widget) =>
            widget is AdminRecordFactsTable &&
            widget.semanticLabel == 'Actual current assisted SMS grants',
      );
      expect(
        find.descendant(of: currentFacts, matching: find.text('10')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: currentFacts, matching: find.text('Granted')),
        findsNWidgets(2),
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Remove access'),
            )
            .onPressed,
        isNull,
      );
      expect(fixture.writes, hasLength(1));
      expect(
        _retainedReference(storage)['intent'],
        containsPair('expected_decision_revision', 8),
      );
      await _tap(tester, 'Check or resume exact original request');
      expect(fixture.writes, hasLength(2));
      expect(_body(fixture.writes.last), original);
      expect(fixture.decisionRevision, 10);
      expect(fixture.readGranted && fixture.manageGranted, isTrue);
      final recordedFacts = find.byWidgetPredicate(
        (widget) =>
            widget is AdminRecordFactsTable &&
            widget.semanticLabel ==
                'Recorded historical decision ${original['request_id']}',
      );
      expect(
        find.descendant(of: recordedFacts, matching: find.text('9')),
        findsOneWidget,
      );
      expect(storage.values, isEmpty);
      expect(
        find.textContaining('Reopen controls with the actual Owner account'),
        findsOneWidget,
      );
      await _close(tester, container);

      final next = _Fixture(
        readGranted: true,
        manageGranted: true,
        decisionRevision: 10,
      );
      container = await _mount(tester, next, storage);
      expect(
        find.descendant(of: currentFacts, matching: find.text('10')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: currentFacts, matching: find.text('Granted')),
        findsNWidgets(2),
      );
      expect(next.writes, isEmpty);
      await _close(tester, container);
    },
  );

  testWidgets(
    'grant refresh before POST acknowledgement preserves unknown UUID across reopen but drops original replay authority',
    (tester) async {
      final reply = Completer<http.Response>();
      late _Fixture fixture;
      fixture = _Fixture(
        handler: (request) async {
          if (request.url.path == _accessPath && request.method == 'POST') {
            fixture.readGranted = true;
            fixture.manageGranted = true;
            fixture.decisionRevision =
                (_body(request)['expected_decision_revision'] as int) + 1;
            return reply.future;
          }
          return null;
        },
      );
      final storage = MemoryAdminPendingAttemptStorage();
      var container = await _mount(tester, fixture, storage);
      await _checkBox(tester, _accessCheckbox);
      final enable = find.widgetWithText(FilledButton, 'Enable access');
      final retainedCallback = tester.widget<FilledButton>(enable).onPressed!;
      await _reveal(tester, enable);
      await tester.tap(enable);
      await tester.pump();
      final original = _body(fixture.writes.single);
      expect(
        _retainedReference(storage)['intent'],
        containsPair('expected_decision_revision', 0),
      );
      await tester.runAsync(fixture.session.refresh);
      await tester.pump();
      expect(storage.values.values.join(), contains(original['request_id']));
      retainedCallback();
      reply.complete(_result(fixture.accessReceipt(original)));
      await tester.pumpAndSettle();
      expect(fixture.writes, hasLength(1));
      expect(find.text('Check or resume exact original request'), findsNothing);
      expect(storage.values.values.join(), contains(original['request_id']));
      await _close(tester, container);
      final next = _Fixture(
        readGranted: true,
        manageGranted: true,
        decisionRevision: 1,
      );
      container = await _mount(tester, next, storage);
      expect(
        find.descendant(
          of: _facts('Unresolved original request ${original['request_id']}'),
          matching: find.text(original['request_id'] as String),
        ),
        findsOneWidget,
      );
      expect(find.text('Check or resume exact original request'), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Remove access'),
            )
            .onPressed,
        isNull,
      );
      expect(next.writes, isEmpty);
      expect(storage.values.values.join(), contains(original['request_id']));
      expect(
        _retainedReference(storage)['intent'],
        containsPair('expected_decision_revision', 0),
      );
      await _close(tester, container);
    },
  );
}
