part of '../cloudflare_admin_notification_management_page_test.dart';

void _registerNotificationCommandPageCases() {
  testWidgets(
    'Owner bootstrap persists its expected decision head before HTTP and requires explicit two-grant confirmation',
    (tester) async {
      final storage = MemoryAdminPendingAttemptStorage();
      var observedBeforeHttp = false;
      final fixture = _Fixture(
        decisionRevision: 6,
        handler: (request) async {
          if (request.url.path == _accessPath && request.method == 'POST') {
            final body = _body(request), retained = _retainedReference(storage);
            expect(retained['request_key'], body['request_id']);
            expect(retained['intent'], {
              'action': 'access',
              'resource_id': _principal,
              'expected_decision_revision': 6,
            });
            observedBeforeHttp = true;
          }
          return null;
        },
      );
      final container = await _mount(tester, fixture, storage);
      expect(fixture.requests.single.method, 'GET');
      expect(fixture.requests.single.url.path, _accessPath);
      expect(find.text('Not granted'), findsNWidgets(2));
      expect(fixture.writes, isEmpty);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Enable access'),
            )
            .onPressed,
        isNull,
      );
      await _checkBox(tester, _accessCheckbox);
      await _tap(tester, 'Enable access');
      expect(fixture.writes, hasLength(1));
      final body = _body(fixture.writes.single);
      expect(body, containsPair('expected_read', false));
      expect(body, containsPair('expected_manage', false));
      expect(body, containsPair('expected_decision_revision', 6));
      expect(body, containsPair('enabled', true));
      expect(body, containsPair('owner_confirmation', true));
      expect(
        fixture.requests.where(
          (r) => r.url.path == _accessPath && r.method == 'GET',
        ),
        hasLength(2),
      );
      expect(fixture.sessionReads, 2);
      expect(
        fixture.session.user!.permissions,
        containsAll(['assisted_sms.read', 'assisted_sms.manage']),
      );
      expect(
        find.textContaining('Reopen controls with the actual Owner account'),
        findsOneWidget,
      );
      expect(find.text('Yes; not current authority'), findsNothing);
      final beforeDisclosure = fixture.requests.length;
      await _toggleDetails(
        tester,
        ValueKey('management-original-details:${body['request_id']}'),
      );
      expect(find.text('Yes; not current authority'), findsOneWidget);
      expect(fixture.requests, hasLength(beforeDisclosure));
      expect(observedBeforeHttp, isTrue);
      final historical = find.byWidgetPredicate(
        (widget) =>
            widget is AdminRecordFactsTable &&
            widget.semanticLabel ==
                'Recorded historical decision ${body['request_id']}',
      );
      expect(
        find.descendant(of: historical, matching: find.text('7')),
        findsOneWidget,
      );
      expect(storage.values, isEmpty);
      await _close(tester, container);
    },
  );

  for (final mode in ['not-owner', 'missing-existing-grant', 'AAL1']) {
    testWidgets('management admission refuses $mode before transport', (
      tester,
    ) async {
      final fixture = _Fixture(
        role: mode == 'not-owner' ? 'admin' : 'owner',
        adminManage: mode != 'missing-existing-grant',
        assurance: mode == 'AAL1' ? 1 : 2,
        readGranted: true,
        manageGranted: true,
      );
      final container = await _mount(
        tester,
        fixture,
        MemoryAdminPendingAttemptStorage(),
      );
      expect(fixture.requests, isEmpty);
      expect(
        find.textContaining('Reopen controls with the actual Owner account'),
        findsOneWidget,
      );
      await _close(tester, container);
    });
  }

  testWidgets(
    'policy lookup shows current facts and disable sends exact revision CAS; enable and materializer remain unavailable',
    (tester) async {
      final fixture = _Fixture(readGranted: true, manageGranted: true);
      final container = await _mount(
        tester,
        fixture,
        MemoryAdminPendingAttemptStorage(),
      );
      await _lookupPolicy(tester);
      final facts = find.byWidgetPredicate(
        (widget) =>
            widget is AdminRecordFactsTable &&
            widget.semanticLabel ==
                'Actual current collection receipt SMS policy',
      );
      expect(
        find.descendant(of: facts, matching: find.text(_collection)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: facts, matching: find.text('Current revision')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: facts, matching: find.text('3')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Enable receipt SMS policy'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(
                OutlinedButton,
                'Prepare bounded receipt SMS jobs',
              ),
            )
            .onPressed,
        isNull,
      );
      await _checkBox(tester, _policyCheckbox);
      await _tap(tester, 'Disable current collection policy');
      final body = _body(fixture.writes.single);
      expect(body['expected_revision'], 3);
      expect(body['enabled'], false);
      expect(body['owner_confirmation'], false);
      expect(
        fixture.requests.where(
          (r) => r.url.path == _policyPath && r.method == 'GET',
        ),
        hasLength(2),
      );
      expect(
        find.descendant(of: facts, matching: find.text('4')),
        findsOneWidget,
      );
      expect(find.text(_policyCheckbox), findsNothing);
      expect(
        fixture.requests.any((r) => r.url.path.endsWith('/materialize')),
        isFalse,
      );
      await _close(tester, container);
    },
  );

  testWidgets(
    'history filter popup after two policy decisions retains the Owner review and usable controls',
    (tester) async {
      const secondPath =
          '/api/admin/notification-operator/policies/$_secondCollection';
      late _Fixture fixture;
      fixture = _Fixture(
        readGranted: true,
        manageGranted: true,
        handler: (request) async {
          if (request.url.path == secondPath && request.method == 'GET') {
            return _result(fixture.policy(collectionId: _secondCollection));
          }
          if (request.url.path == secondPath && request.method == 'POST') {
            final body = _body(request);
            fixture.policyEnabled = body['enabled'] as bool;
            fixture.policyRevision = (body['expected_revision'] as int) + 1;
            return _result(
              fixture.policyReceipt(body, collectionId: _secondCollection),
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
      await _lookupPolicy(tester);
      await _checkBox(tester, _policyCheckbox);
      await _tap(tester, 'Disable current collection policy');
      // A second collection has its own already-recorded enabled policy;
      // this page still issues only explicit disabling decisions.
      fixture.policyEnabled = true;
      fixture.policyRevision = 7;
      await _lookupPolicy(tester, collectionId: _secondCollection);
      await _checkBox(tester, _policyCheckbox);
      await _tap(tester, 'Disable current collection policy');
      expect(fixture.writes, hasLength(2));
      expect(fixture.writes.map((request) => _body(request)['enabled']), [
        false,
        false,
      ]);
      final history = find.byWidgetPredicate(
        (widget) =>
            widget is AdminDataTable &&
            widget.tableLabel == 'Original assisted SMS management operations',
      );
      expect(tester.widget<AdminDataTable>(history).rows, hasLength(2));
      final filter = find.descendant(
        of: history,
        matching: find.byTooltip('Filter loaded rows'),
      );
      await _reveal(tester, filter);
      await tester.tap(filter);
      await tester.pumpAndSettle();
      final dropdown = find.descendant(
        of: history,
        matching: find.byType(DropdownButtonFormField<String>),
      );
      expect(dropdown, findsOneWidget);
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(dropdown)
            .decoration
            .labelText,
        'Filter column',
      );
      await _reveal(tester, dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Reopen controls with the actual Owner account'),
        findsNothing,
      );
      expect(tester.widget<AdminDataTable>(history).rows, hasLength(2));
      final outerPage = find.byKey(const Key('admin-page-scroll-view'));
      expect(tester.widget(outerPage), isA<ListView>());
      expect(find.ancestor(of: history, matching: outerPage), findsOneWidget);
      // The header is a lazy ListView child. The history widget's nearest
      // vertical ancestor is the outer AdminPage scrollable; its table/cell
      // scrollables are descendants and cannot be selected here.
      final outerPosition = Scrollable.of(
        tester.element(history),
        axis: Axis.vertical,
      ).position;
      outerPosition.jumpTo(0);
      await tester.pumpAndSettle();
      expect(outerPosition.pixels, 0);
      final refresh = find.byWidgetPredicate(
        (widget) =>
            widget is IconButton &&
            widget.tooltip == 'Refresh current assisted SMS access',
      );
      expect(refresh, findsOneWidget);
      expect(tester.widget<IconButton>(refresh).onPressed, isNotNull);
      await _reveal(tester, refresh);
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      expect(
        fixture.requests.where(
          (request) =>
              request.url.path == _accessPath && request.method == 'GET',
        ),
        hasLength(2),
      );
      expect(tester.widget<AdminDataTable>(history).rows, hasLength(2));
      expect(tester.takeException(), isNull);
      await _close(tester, container);
    },
  );
}
