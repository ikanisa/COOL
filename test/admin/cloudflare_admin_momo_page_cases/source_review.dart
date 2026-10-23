part of '../cloudflare_admin_momo_page_test.dart';

void _registerMomoSourceReviewCases() {
  testWidgets(
    'source correction records strict reviewed facts with immutable source guards',
    (tester) async {
      final requests = <http.Request>[];
      final result = await pump(
        tester,
        records: page(),
        sourceJobs: [reviewJob()],
        respond: (request) async {
          if (request.url.path.endsWith('/correct-extraction')) {
            requests.add(request);
            return jsonResponse({
              'raw_sms_id': rawSmsId,
              'parse_attempt_id': txId,
              'status': 'review_recorded',
              'financial_effects': 0,
            });
          }
          return http.Response('{}', 404);
        },
      );
      await openReviewSource(tester);
      await tester.tap(find.text('Correct extraction'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save review'),
            )
            .onPressed,
        isNull,
      );
      await selectReview(tester, 'Message type', 'incoming receipt');
      await selectReview(tester, 'Provider outcome', 'successful');
      await enterReview(tester, 'Provider transaction ID', 'SYNTHETIC-007');
      await enterReview(tester, 'Principal amount', '5000');
      await enterReview(tester, 'Currency', 'RWF');
      final excerpts = find.text('Exact supporting excerpts');
      await tester.ensureVisible(excerpts);
      await tester.tap(excerpts);
      await tester.pumpAndSettle();
      await enterReview(
        tester,
        'Success or classification excerpt',
        'Synthetic received RWF 5000',
      );
      await enterReview(tester, 'Principal excerpt', 'RWF 5000');
      await enterReview(tester, 'Transaction ID excerpt', 'SYNTHETIC-007');
      await reasonReview(tester);
      final submit = find.text('Save review');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(requests.length, 1);
      final body = jsonDecode(requests.single.body) as Map;
      expect(body['expected_state'], 'needs_review');
      expect(body['expected_attempt_count'], 2);
      expect(body['expected_body_sha256'], 'a' * 64);
      final extraction = body['extraction'] as Map;
      expect(extraction['schema_version'], 'momo-extraction.v1');
      expect(extraction['event_kind'], 'incoming_receipt');
      expect(extraction['principal_amount_raw'], '5000');
      expect(extraction['payer_name_raw'], isNull);
      expect(extraction['issues'], isEmpty);
      expect(
        find.textContaining('No contribution was credited'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      result.dispose();
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'non-payment review retries exact negative evidence after unknown outcome',
    (tester) async {
      final requests = <http.Request>[];
      final result = await pump(
        tester,
        width: 320,
        textScale: 2,
        records: page(),
        sourceJobs: [reviewJob()],
        respond: (request) async {
          if (request.url.path.endsWith('/classify-non-payment')) {
            requests.add(request);
            if (requests.length == 1) {
              throw http.ClientException('Synthetic review response lost');
            }
            return jsonResponse({
              'raw_sms_id': rawSmsId,
              'parse_attempt_id': txId,
              'status': 'review_recorded',
              'financial_effects': 0,
            });
          }
          return http.Response('{}', 404);
        },
      );
      await openReviewSource(tester);
      final action = find.text('Classify non-payment');
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      await selectReview(tester, 'Message type', 'failed');
      await enterReview(tester, 'Excerpt', 'Synthetic payment failed');
      await reasonReview(tester);
      final submit = find.text('Save review');
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      expect(submit.hitTestable(), findsOneWidget);
      await capture(tester, result.key, 'nonpayment-320-text2');
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.text('Retry original request'), findsOneWidget);
      await tester.ensureVisible(find.text('Retry original request'));
      await tester.tap(find.text('Retry original request'));
      await tester.pumpAndSettle();
      expect(requests.length, 2);
      expect(requests[0].body, requests[1].body);
      expect(
        requests[0].headers['idempotency-key'],
        requests[1].headers['idempotency-key'],
      );
      final body = jsonDecode(requests.last.body) as Map;
      expect(body['classification_evidence'], 'Synthetic payment failed');
      final extraction = body['extraction'] as Map;
      expect(extraction['event_kind'], 'failed');
      expect(extraction['payment_outcome'], 'failed');
      expect(extraction['principal_amount_raw'], isNull);
      expect(extraction['transaction_id_raw'], isNull);
      expect(
        (extraction['evidence'] as Map)['incoming_success'],
        'Synthetic payment failed',
      );
      expect(
        find.textContaining('No contribution was credited'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      result.dispose();
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'accepted source and metadata-only reader have no extraction correction action',
    (tester) async {
      for (final accepted in [true, false]) {
        final result = await pump(
          tester,
          records: page(),
          sourceJobs: [
            reviewJob(outcome: accepted ? 'accepted' : 'validation_failed'),
          ],
          permissions: accepted ? null : ['payments.read', 'sms.read'],
        );
        await openReviewSource(tester);
        expect(find.text('Correct extraction'), findsNothing);
        expect(find.text('Classify non-payment'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        result.dispose();
        await tester.pumpAndSettle();
      }
    },
  );
  testWidgets(
    'unlinked conflict review retains originals and exact complete attempt set',
    (tester) async {
      final requests = <http.Request>[];
      final record = {
        ...transaction(status: 'needs_review'),
        'has_conflict': 1,
      };
      final attempts = [rawSmsId, paymentId];
      final result = await pump(
        tester,
        records: {
          ...page(),
          'rows': [record],
        },
        detailRecord: record,
        conflictingAttempts: attempts,
        respond: (request) async {
          if (request.url.path.endsWith('/review-conflict')) {
            requests.add(request);
            return jsonResponse({
              'transaction_id': txId,
              'version': 2,
              'status': 'needs_allocation',
              'financial_effects': 0,
            });
          }
          return http.Response('{}', 404);
        },
      );
      await tester.ensureVisible(find.text('Synthetic payer · …007'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Synthetic payer · …007'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Review conflict'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review conflict'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Replacing accepted facts is unavailable'),
        findsOneWidget,
      );
      await reasonReview(tester);
      await tester.ensureVisible(find.text('Retain original'));
      await tester.tap(find.text('Retain original'));
      await tester.pumpAndSettle();
      expect(requests.length, 1);
      final body = jsonDecode(requests.single.body) as Map;
      expect(body['decision'], 'retain_original');
      expect(body['expected_version'], 1);
      expect(body['expected_conflicting_attempt_ids'], attempts);
      expect(
        find.textContaining('No contribution was credited'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      result.dispose();
      await tester.pumpAndSettle();
    },
  );
  testWidgets('linked payment conflict never offers retain-original review', (
    tester,
  ) async {
    final record = {
      ...transaction(status: 'credited'),
      'has_conflict': 1,
      'payment_id': paymentId,
      'credited_amount_minor': 5000,
    };
    final result = await pump(
      tester,
      records: {
        ...page(),
        'rows': [record],
      },
      detailRecord: record,
      conflictingAttempts: [rawSmsId],
    );
    await tester.ensureVisible(find.text('Synthetic payer · …007'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Synthetic payer · …007'));
    await tester.pumpAndSettle();
    expect(find.text('Review conflict'), findsNothing);
    expect(find.text('Credited'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    result.dispose();
    await tester.pumpAndSettle();
  });
  Map<String, dynamic> memberChecks({
    Map<String, dynamic> overrides = const {},
  }) => {
    'contract_version': 1,
    'total': 1,
    'offset': 0,
    'limit': 25,
    'next_offset': null,
    'rows': [
      {
        'id': rawSmsId,
        'member_id': memberId,
        'member_public_id': '123456',
        'member_name': 'Synthetic requesting member',
        'group_id': groupId,
        'group_name': 'Synthetic savings group',
        'intent_id': txId,
        'expected_amount_minor': 5000,
        'currency': 'RWF',
        'requested_at': '2026-10-18T08:00:00.000Z',
        'request_status': 'received',
        'provider_reference': 'SYNTHETIC-007',
        'evidence_note': 'Synthetic member-supplied retained evidence',
        'source': 'member_request',
        'provider_reference_verified': false,
        'financial_effects': 0,
        ...overrides,
      },
    ],
  };
  testWidgets(
    'member payment checks stay unverified and seed only existing receipt search',
    (tester) async {
      final searches = <String>[];
      final requests = <http.Request>[];
      final result = await pump(
        tester,
        width: 390,
        transactionRecords: (request) {
          searches.add(request.url.queryParameters['search'] ?? '');
          return page();
        },
        respond: (request) async {
          requests.add(request);
          return request.url.path.endsWith('/transactions/payment-checks')
              ? jsonResponse(memberChecks())
              : http.Response('{}', 404);
        },
      );
      await tester.tap(find.text('Member checks'));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic requesting member'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('5,000'),
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('do not establish a received payment or credit'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('SYNTHETIC-007'));
      await tester.pumpAndSettle();
      expect(find.text('SYNTHETIC-007'), findsOneWidget);
      expect(
        find.text('Synthetic member-supplied retained evidence'),
        findsOneWidget,
      );
      await capture(tester, result.key, 'member-checks-390');
      await tester.ensureVisible(find.text('Search reference'));
      await tester.tap(find.text('Search reference'));
      await tester.pumpAndSettle();
      expect(searches.last, 'SYNTHETIC-007');
      expect(requests.every((request) => request.method == 'GET'), isTrue);
      expect(find.text('Member payment checks'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      result.dispose();
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'compact member check table preserves unverified evidence and search-only action',
    (tester) async {
      final searches = <String>[];
      final requests = <http.Request>[];
      final result = await pump(
        tester,
        width: 320,
        textScale: 2,
        reduceMotion: true,
        transactionRecords: (request) {
          searches.add(request.url.queryParameters['search'] ?? '');
          return page();
        },
        respond: (request) async {
          requests.add(request);
          return request.url.path.endsWith('/transactions/payment-checks')
              ? jsonResponse(memberChecks())
              : http.Response('{}', 404);
        },
      );
      try {
        await tester.ensureVisible(find.text('Member checks'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Member checks'));
        await tester.pumpAndSettle();
        final checks = find.byWidgetPredicate(
          (widget) =>
              widget is AdminDataTable &&
              widget.tableLabel == 'Member payment checks',
        );
        expect(checks, findsOneWidget);
        for (final value in [
          'Member',
          'Member ID',
          'Group',
          'Expected amount · RWF',
          'Requested · Kigali',
          'Status',
          'Unverified reference',
          'Member note',
          'Request ID',
          'Search',
          'Synthetic requesting member',
          '123456',
          '5,000',
          'SYNTHETIC-007',
          'Synthetic member-supplied retained evidence',
          rawSmsId,
        ]) {
          expect(
            find.descendant(of: checks, matching: find.text(value)),
            findsOneWidget,
          );
        }
        expect(
          find.descendant(of: checks, matching: find.byType(ExpansionTile)),
          findsNothing,
        );
        expect(
          find.textContaining('do not establish a received payment or credit'),
          findsOneWidget,
        );
        final search = find.text('Search reference');
        await tester.ensureVisible(search);
        await tester.pumpAndSettle();
        await tester.tap(search);
        await tester.pumpAndSettle();
        expect(searches.last, 'SYNTHETIC-007');
        expect(requests.every((request) => request.method == 'GET'), isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        result.dispose();
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('member check queue requires all three read permissions', (
    tester,
  ) async {
    final result = await pump(
      tester,
      permissions: ['payments.read', 'users.read'],
    );
    expect(find.text('Member checks'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    result.dispose();
    await tester.pumpAndSettle();
  });
  testWidgets(
    'member check queue rejects verified-reference or financial-effect claims',
    (tester) async {
      for (final invalid in [
        {'provider_reference_verified': true},
        {'financial_effects': 1},
      ]) {
        final result = await pump(
          tester,
          respond: (request) async =>
              request.url.path.endsWith('/transactions/payment-checks')
              ? jsonResponse(memberChecks(overrides: invalid))
              : http.Response('{}', 404),
        );
        await tester.tap(find.text('Member checks'));
        await tester.pumpAndSettle();
        expect(find.text('Synthetic requesting member'), findsNothing);
        expect(find.textContaining('could not be verified'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        result.dispose();
        await tester.pumpAndSettle();
      }
    },
  );
  testWidgets(
    'processed non-payment source remains reviewable without editing accepted receipts',
    (tester) async {
      final result = await pump(
        tester,
        records: page(),
        sourceJobs: [
          {...reviewJob(outcome: 'non_payment'), 'state': 'completed'},
        ],
      );
      await tester.tap(find.text('Needs attention'));
      await tester.pumpAndSettle();
      final filter = find.byType(DropdownButtonFormField<String>).last;
      await tester.ensureVisible(filter);
      await tester.pumpAndSettle();
      await tester.tap(filter);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Processed source messages').last);
      await tester.pumpAndSettle();
      final source = find.text('Source message — processing completed');
      await tester.ensureVisible(source);
      await tester.tap(source);
      await tester.pumpAndSettle();
      expect(find.text('Correct extraction'), findsOneWidget);
      expect(find.text('Classify non-payment'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      result.dispose();
      await tester.pumpAndSettle();
    },
  );
}
