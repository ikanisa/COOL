part of '../cloudflare_admin_momo_page_test.dart';

void _registerMomoGatewayCases() {
  testWidgets(
    'generic gateway creates receiving account with explicit provider code name and reason',
    (tester) async {
      final requests = <http.Request>[];
      final accounts = <Map<String, dynamic>>[];
      final result = await pump(
        tester,
        receivingAccounts: accounts,
        respond: (request) async {
          requests.add(request);
          if (request.method == 'POST' &&
              request.url.path.endsWith('/momo/accounts')) {
            accounts.add({
              'id': accountId,
              'provider': 'airtel_money',
              'public_code': '0788000123',
              'recipient_name': 'Synthetic Airtel receiver',
              'profile_status': 'unverified',
              'status': 'active',
            });
            return jsonResponse({
              'id': accountId,
              'profile_status': 'unverified',
            });
          }
          return http.Response('{}', 404);
        },
      );
      await openGatewayTools(tester);
      await tester.pumpAndSettle();
      await fillGatewayAccount(tester);
      await tester.ensureVisible(find.text('Create receiving account'));
      await tester.tap(find.text('Create receiving account'));
      await tester.pumpAndSettle();
      expect(requests, hasLength(1));
      expect(jsonDecode(requests.single.body), {
        'provider': 'airtel_money',
        'public_code': '0788000123',
        'recipient_name': 'Synthetic Airtel receiver',
        'reason': 'Synthetic owner verified against receiving account evidence',
      });
      expect(
        requests.single.headers['idempotency-key'],
        matches(RegExp(r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$')),
      );
      expect(
        find.text('Synthetic Airtel receiver · 0788000123 · unverified'),
        findsOneWidget,
      );
      expect(
        find.textContaining('No sample profile is enabled'),
        findsOneWidget,
      );
      expect(find.text('Retry original request'), findsNothing);
      expect(find.text('Copy pairing code'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      result.dispose();
      await tester.pumpAndSettle();
    },
  );

  for (final kind in ['account', 'pair']) {
    testWidgets(
      'generic gateway unknown $kind reply reopens durable exact body and request key',
      (tester) async {
        final requests = <http.Request>[];
        final storage = MemoryAdminPendingAttemptStorage();
        Future<http.Response> respond(http.Request request) async {
          if (request.method == 'POST' &&
              request.url.path.endsWith(
                kind == 'account' ? '/momo/accounts' : '/momo/bindings',
              )) {
            requests.add(request);
            if (requests.length == 1) {
              throw http.ClientException('Synthetic gateway reply lost');
            }
            return jsonResponse(
              kind == 'account'
                  ? {'id': accountId, 'profile_status': 'unverified'}
                  : {
                      'binding_id': txId,
                      'pairing_code': 'SYNTHETIC-RESTORED-PAIRING-CODE',
                      'expires_in_seconds': 600,
                    },
            );
          }
          return http.Response('{}', 404);
        }

        final first = await pump(
          tester,
          pendingStorage: storage,
          respond: respond,
        );
        await openGatewayTools(tester);
        await tester.pumpAndSettle();
        if (kind == 'account') {
          await fillGatewayAccount(tester);
        } else {
          await fillGatewayPair(tester);
        }
        final submit = find.text(
          kind == 'account'
              ? 'Create receiving account'
              : 'Create phone pairing code',
        );
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(requests, hasLength(1));
        expect(
          jsonDecode(requests.single.body),
          kind == 'account'
              ? {
                  'provider': 'airtel_money',
                  'public_code': '0788000123',
                  'recipient_name': 'Synthetic Airtel receiver',
                  'reason':
                      'Synthetic owner verified against receiving account evidence',
                }
              : {
                  'receiving_account_id': accountId,
                  'subscription_id': 7,
                  'reason':
                      'Synthetic dedicated phone and receiving account verified',
                },
        );
        expect(find.text('Retry original request'), findsOneWidget);
        expect(storage.values, hasLength(1));
        final retained = jsonDecode(storage.values.values.single) as Map;
        final checkpoint = (retained['entries'] as List).single as Map;
        expect(checkpoint['family'], 'momo-gateway-$kind');
        expect(checkpoint['intent'], jsonDecode(requests.single.body));
        expect(
          checkpoint['request_key'],
          requests.single.headers['idempotency-key'],
        );
        expect(
          storage.values.values.single,
          isNot(contains('SYNTHETIC-RESTORED-PAIRING-CODE')),
        );
        await tester.ensureVisible(find.text('Close').last);
        await tester.tap(find.text('Close').last);
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        first.dispose();
        await tester.pumpAndSettle();

        final reopened = await pump(
          tester,
          pendingStorage: storage,
          respond: respond,
        );
        await openGatewayTools(tester);
        await tester.pumpAndSettle();
        expect(requests, hasLength(1), reason: 'Restoration must not send.');
        expect(find.text('Retry original request'), findsOneWidget);
        expect(
          find.textContaining(requests.single.headers['idempotency-key']!),
          findsOneWidget,
        );
        expect(find.text('Create receiving account'), findsNothing);
        expect(find.text('Create phone pairing code'), findsNothing);
        await tester.tap(find.text('Retry original request'));
        await tester.pumpAndSettle();
        expect(requests, hasLength(2));
        expect(requests[1].body, requests[0].body);
        expect(
          requests[1].headers['idempotency-key'],
          requests[0].headers['idempotency-key'],
        );
        expect(
          storage.values,
          isEmpty,
          reason: 'Only verified success clears recovery.',
        );
        expect(find.text('Retry original request'), findsNothing);
        if (kind == 'pair') {
          expect(find.text('SYNTHETIC-RESTORED-PAIRING-CODE'), findsOneWidget);
          expect(find.textContaining('expires in 10 minutes'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        reopened.dispose();
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'generic gateway blocks failed recovery write and retries same key after storage returns',
    (tester) async {
      final requests = <http.Request>[];
      final storage = _FailingGatewayStorage();
      final result = await pump(
        tester,
        pendingStorage: storage,
        respond: (request) async {
          if (request.url.path.endsWith('/momo/bindings')) {
            expect(storage.values, hasLength(1));
            final saved = jsonDecode(storage.values.values.single) as Map;
            final retained = (saved['entries'] as List).single as Map;
            expect(retained['intent'], jsonDecode(request.body));
            expect(retained['request_key'], request.headers['idempotency-key']);
            requests.add(request);
            return jsonResponse({
              'binding_id': txId,
              'pairing_code': 'SYNTHETIC-STORAGE-RECOVERY-PAIRING-CODE',
              'expires_in_seconds': 600,
            });
          }
          return http.Response('{}', 404);
        },
      );
      await openGatewayTools(tester);
      await tester.pumpAndSettle();
      await fillGatewayPair(tester);
      await tester.tap(find.text('Create phone pairing code'));
      await tester.pumpAndSettle();
      expect(requests, isEmpty, reason: 'Transport requires durable recovery.');
      expect(storage.values, isEmpty);
      expect(find.text('Retry original request'), findsOneWidget);
      final unresolved = tester
          .widget<SelectableText>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is SelectableText &&
                  widget.data?.startsWith('Unresolved original request') ==
                      true,
            ),
          )
          .data!;
      final originalKey = RegExp(
        r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}',
      ).firstMatch(unresolved)!.group(0)!;
      expect(
        find.textContaining('Recovery storage is unavailable'),
        findsOneWidget,
      );
      storage.failWrites = false;
      await tester.tap(find.text('Retry original request'));
      await tester.pumpAndSettle();
      expect(requests, hasLength(1));
      expect(requests.single.headers['idempotency-key'], originalKey);
      expect(jsonDecode(requests.single.body), {
        'receiving_account_id': accountId,
        'subscription_id': 7,
        'reason': 'Synthetic dedicated phone and receiving account verified',
      });
      expect(
        storage.values,
        isEmpty,
        reason: 'Verified success clears recovery.',
      );
      expect(find.text('Retry original request'), findsNothing);
      expect(
        find.text('SYNTHETIC-STORAGE-RECOVERY-PAIRING-CODE'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      result.dispose();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'generic gateway pending pairing rejects stale retry after session replacement',
    (tester) async {
      final requests = <http.Request>[];
      final storage = MemoryAdminPendingAttemptStorage();
      final result = await pump(
        tester,
        pendingStorage: storage,
        respond: (request) async {
          if (request.url.path.endsWith('/momo/bindings')) {
            requests.add(request);
            throw http.ClientException('Synthetic gateway reply lost');
          }
          return http.Response('{}', 404);
        },
      );
      await openGatewayTools(tester);
      await tester.pumpAndSettle();
      await fillGatewayPair(tester);
      await tester.tap(find.text('Create phone pairing code'));
      await tester.pumpAndSettle();
      expect(requests, hasLength(1));
      expect(find.text('Retry original request'), findsOneWidget);
      final departedRetry = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Retry original request'),
          )
          .onPressed!;
      result.session.clear();
      await result.session.refresh();
      await tester.pumpAndSettle();
      expect(find.text('Account changed'), findsOneWidget);
      expect(find.text('Retry original request'), findsNothing);
      expect(find.text('Create phone pairing code'), findsNothing);
      expect(storage.values, isEmpty);
      departedRetry();
      await tester.pumpAndSettle();
      expect(
        storage.values,
        isEmpty,
        reason: 'A stale dialog cannot claim a new checkpoint.',
      );
      expect(requests, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      result.dispose();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'historical source requires explicit account, evidence and reason before queuing',
    (tester) async {
      final requests = <http.Request>[];
      final result = await pump(
        tester,
        width: 390,
        records: page(),
        sourceJobs: [sourceJob()],
        respond: (request) async {
          if (request.url.path.endsWith('/sources/$rawSmsId/resolve')) {
            requests.add(request);
            return jsonResponse(sourceResolution());
          }
          return http.Response('{}', 404);
        },
      );
      await openUnresolvedSource(tester);
      expect(find.text('Request reparse'), findsNothing);
      expect(find.text('Reveal original SMS'), findsOneWidget);
      expect(find.textContaining('synthetic raw source'), findsNothing);
      await tester.tap(find.text('Resolve historical source'));
      await tester.pumpAndSettle();
      final submit = find.widgetWithText(FilledButton, 'Queue source');
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>).last,
            )
            .initialValue,
        isNull,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Reason'),
        'Verified historical receiver using retained evidence',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Evidence'),
        'synthetic-archive/source-001',
      );
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      await fillSourceResolution(tester);
      expect(
        find.text('MTN MoMo · Collect synthetic receiver'),
        findsOneWidget,
      );
      await tester.enterText(find.widgetWithText(TextField, 'Reason'), 'short');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      await tester.enterText(
        find.widgetWithText(TextField, 'Reason'),
        'Verified historical receiver using the retained account evidence',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Evidence'),
        'short',
      );
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      await tester.enterText(
        find.widgetWithText(TextField, 'Evidence'),
        'synthetic-archive/source-001',
      );
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      await capture(tester, result.key, 'dialog-390');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(requests.length, 1);
      expect(jsonDecode(requests.single.body), {
        'receiving_account_id': accountId,
        'evidence_reference': 'synthetic-archive/source-001',
        'reason':
            'Verified historical receiver using the retained account evidence',
      });
      expect(
        find.text(
          'Historical source queued for processing. No contribution was credited.',
        ),
        findsOneWidget,
      );
      expect(find.text('Retry original request'), findsNothing);
      await tester.tap(find.text('Close').last);
      await tester.pumpAndSettle();
      expect(find.text('Resolve historical source'), findsNothing);
      expect(find.text('Request reparse'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      result.dispose();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'historical source keeps selected code and identity readable at 320',
    (tester) async {
      final result = await pump(
        tester,
        width: 320,
        records: page(),
        sourceJobs: [sourceJob()],
      );
      await openUnresolvedSource(tester);
      await tester.tap(find.text('Resolve historical source'));
      await tester.pumpAndSettle();
      await fillSourceResolution(tester);
      final identity = find.text('MTN MoMo · Collect synthetic receiver');
      await tester.ensureVisible(identity);
      await tester.pumpAndSettle();
      final paragraph = tester.renderObject<RenderParagraph>(identity);
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(paragraph.size.width, lessThanOrEqualTo(320));
      expect(tester.widget<Text>(identity).maxLines, isNull);
      expect(find.text('123456'), findsWidgets);
      expect(tester.takeException(), isNull);
      await capture(tester, result.key, 'dialog-320');
      await tester.pumpWidget(const SizedBox.shrink());
      result.dispose();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('historical source remains usable at 320 with 200 percent text', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final result = await pump(
      tester,
      width: 320,
      textScale: 2,
      records: page(),
      sourceJobs: [sourceJob()],
      respond: (request) async {
        if (request.url.path.endsWith('/sources/$rawSmsId/resolve')) {
          requests.add(request);
          return jsonResponse(sourceResolution());
        }
        return http.Response('{}', 404);
      },
    );
    await openUnresolvedSource(tester);
    final resolve = find.text('Resolve historical source');
    await tester.ensureVisible(resolve);
    await tester.pumpAndSettle();
    await tester.tap(resolve);
    await tester.pumpAndSettle();
    final account = find.byType(DropdownButtonFormField<String>).last;
    await tester.ensureVisible(account);
    await tester.pumpAndSettle();
    await fillSourceResolution(tester);
    final identity = find.text('MTN MoMo · Collect synthetic receiver');
    await tester.ensureVisible(identity);
    await tester.pumpAndSettle();
    final paragraph = tester.renderObject<RenderParagraph>(identity);
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(tester.widget<Text>(identity).maxLines, isNull);
    expect(find.text('123456'), findsWidgets);
    expect(tester.takeException(), isNull);
    await capture(tester, result.key, 'identity-320-text2');
    final submit = find.widgetWithText(FilledButton, 'Queue source');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
    expect(submit.hitTestable(), findsOneWidget);
    await capture(tester, result.key, 'action-320-text2');
    final label = find.text('Queue source');
    final renderedLabel = tester.renderObject<RenderParagraph>(label);
    final buttonBounds = tester.getRect(submit);
    for (final box in renderedLabel.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: 'Queue source'.length),
    )) {
      final bounds = box.toRect().shift(
        renderedLabel.localToGlobal(Offset.zero),
      );
      expect(bounds.left, greaterThanOrEqualTo(buttonBounds.left));
      expect(bounds.right, lessThanOrEqualTo(buttonBounds.right));
      expect(bounds.top, greaterThanOrEqualTo(buttonBounds.top));
      expect(bounds.bottom, lessThanOrEqualTo(buttonBounds.bottom));
    }
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(requests.length, 1);
    expect(
      find.text(
        'Historical source queued for processing. No contribution was credited.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    result.dispose();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'historical source resolution is hidden without either permission',
    (tester) async {
      for (final permissions in [
        ['payments.read', 'sms.read', 'sms.extract'],
        ['payments.read', 'sms.read', 'receivers.read'],
      ]) {
        final result = await pump(
          tester,
          records: page(),
          permissions: permissions,
          sourceJobs: [sourceJob()],
        );
        await openUnresolvedSource(tester);
        expect(find.text('Resolve historical source'), findsNothing);
        expect(find.text('Request reparse'), findsNothing);
        expect(find.text('Reveal original SMS'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        result.dispose();
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('an already-bound source never offers historical rebinding', (
    tester,
  ) async {
    final result = await pump(
      tester,
      records: page(),
      sourceJobs: [sourceJob(binding: txId, account: accountId)],
    );
    await openUnresolvedSource(tester);
    expect(find.text('Resolve historical source'), findsNothing);
    expect(find.text('Request reparse'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    result.dispose();
    await tester.pumpAndSettle();
  });

  testWidgets('transaction source without job state never offers resolution', (
    tester,
  ) async {
    final result = await pump(
      tester,
      transactionSources: [
        {
          'raw_sms_id': rawSmsId,
          'relation': 'accepted',
          'outcome': 'accepted',
          'parser_version': 'synthetic-v1',
          'created_at': '2026-10-18T08:01:00.000Z',
        },
      ],
    );
    await tester.ensureVisible(find.text('Synthetic payer · …007'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Synthetic payer · …007'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Original SMS'));
    await tester.tap(find.text('Original SMS'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Review original source'));
    await tester.tap(find.text('Review original source'));
    await tester.pumpAndSettle();
    expect(find.text('Resolve historical source'), findsNothing);
    expect(find.text('Request reparse'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    result.dispose();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'lost historical resolution response restores exact original retry',
    (tester) async {
      final requests = <http.Request>[];
      final result = await pump(
        tester,
        records: page(),
        sourceJobs: [sourceJob()],
        respond: (request) async {
          if (request.url.path.endsWith('/sources/$rawSmsId/resolve')) {
            requests.add(request);
            if (requests.length == 1) {
              throw http.ClientException('Synthetic historical response lost');
            }
            return jsonResponse(sourceResolution());
          }
          return http.Response('{}', 404);
        },
      );
      await openUnresolvedSource(tester);
      await tester.tap(find.text('Resolve historical source'));
      await tester.pumpAndSettle();
      await fillSourceResolution(tester);
      await tester.tap(find.text('Queue source'));
      await tester.pumpAndSettle();
      expect(find.text('Retry original request'), findsOneWidget);
      await tester.tap(find.text('Close').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resolve historical source'));
      await tester.pumpAndSettle();
      expect(requests.length, 1);
      expect(find.text('Retry original request'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Reason'), findsNothing);
      await tester.tap(find.text('Retry original request'));
      await tester.pumpAndSettle();
      expect(requests.length, 2);
      expect(requests[0].body, requests[1].body);
      expect(
        requests[0].headers['idempotency-key'],
        requests[1].headers['idempotency-key'],
      );
      expect(
        find.text(
          'Historical source queued for processing. No contribution was credited.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      result.dispose();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'historical source rejects responses outside original scope or effect',
    (tester) async {
      for (final incorrect in [
        {'raw_sms_id': txId},
        {'receiving_account_id': groupId},
        {'mode': 'live'},
        {'status': 'completed'},
        {'financial_effects': 1},
      ]) {
        final result = await pump(
          tester,
          records: page(),
          sourceJobs: [sourceJob()],
          respond: (request) async =>
              request.url.path.endsWith('/sources/$rawSmsId/resolve')
              ? jsonResponse({...sourceResolution(), ...incorrect})
              : http.Response('{}', 404),
        );
        await openUnresolvedSource(tester);
        await tester.tap(find.text('Resolve historical source'));
        await tester.pumpAndSettle();
        await fillSourceResolution(tester);
        await tester.tap(find.text('Queue source'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Historical source queued for processing. No contribution was credited.',
          ),
          findsNothing,
        );
        expect(find.text('Retry original request'), findsOneWidget);
        expect(find.textContaining('could not be verified'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        result.dispose();
        await tester.pumpAndSettle();
      }
    },
  );
}
