import 'dart:convert';

import 'package:collect_app/admin/cloudflare_admin_app.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/admin/shared/components/admin_data_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'cloudflare_reconciliation_fixtures.dart';
import 'cloudflare_reconciliation_pages_test.dart' as helpers;

void main() {
  for (final lostResponse in [false, true]) {
    testWidgets(
      'reconciliation ${lostResponse ? 'GET recovery' : 'approval'} refreshes mounted queue without replaying the write',
      (tester) async {
        var saved = false, queueReads = 0;
        final writes = <http.Request>[], queueQueries = <Map<String, String>>[];
        final container = await helpers.pumpReconciliation(tester, (
          request,
        ) async {
          if (request.method != 'GET') {
            writes.add(request);
            saved = true;
            if (lostResponse) throw http.ClientException('Lost response');
            return helpers.response(reconReceipt(status: 'approved'));
          }
          if (request.url.path.contains('/requests/')) {
            expect(
              request.url.path.split('/').last,
              writes.single.headers['Idempotency-Key'],
            );
            return helpers.response({
              'status': 'succeeded',
              'request_id': reconRequestId,
              'receipt': reconReceipt(status: 'approved'),
            });
          }
          if (request.url.path.endsWith('/members')) {
            return helpers.response(reconPage([reconMember()]));
          }
          if (request.url.path.endsWith(reconTransactionId)) {
            return helpers.response(
              reconDetail(
                review: !saved,
                propose: false,
                proposals: saved ? [] : [reconProposal()],
                transaction: {
                  ...reconTransaction(),
                  if (saved) ...{
                    'allocated_amount_rwf': 400,
                    'unallocated_amount_rwf': 600,
                    'allocation_status': 'partially_allocated',
                    'pending_proposals': 0,
                    'version': 3,
                  },
                },
              ),
            );
          }
          queueReads++;
          queueQueries.add(request.url.queryParameters);
          return helpers.response(reconPage(saved ? [] : [reconTransaction()]));
        }, role: 'admin');
        final router = container.read(cloudflareAdminRouterProvider);
        router.go('/admin/reconciliations?search=MOMO&allocation=unallocated');
        await tester.pumpAndSettle();
        expect(queueReads, 1);
        await helpers.visibleTap(tester, find.text('456258123456789012'));
        await helpers.visibleTap(tester, find.text('Review'));
        await helpers.visibleTap(
          tester,
          find.text(
            'I independently reviewed this proposal and its recorded payment evidence',
          ),
        );
        await helpers.fill(
          tester,
          'Review reason',
          'Independently confirmed recorded identity.',
        );
        await helpers.visibleTap(tester, find.text('Approve allocation'));
        expect(writes, hasLength(1));
        expect(jsonDecode(writes.single.body)['outcome'], 'approved');
        if (lostResponse) {
          expect(
            queueReads,
            1,
            reason: 'An unknown result cannot imply success',
          );
          await helpers.visibleTap(tester, find.text('Check original request'));
        }
        expect(writes, hasLength(1));
        expect(queueReads, 2);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is AdminDataTable &&
                widget.tableLabel == 'Confirmed operation receipt',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'Approval and allocation recorded. Settlement is not asserted.',
          ),
          findsOneWidget,
        );
        await helpers.visibleTap(
          tester,
          find.byTooltip('Back to reconciliations'),
        );
        expect(router.routeInformationProvider.value.uri.queryParameters, {
          'search': 'MOMO',
          'allocation': 'unallocated',
        });
        expect(
          find.text('No remaining payments match these filters.'),
          findsOneWidget,
        );
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is AdminDataTable &&
                widget.tableLabel == 'Reconciliation queue',
          ),
          findsNothing,
        );
        expect(queueQueries, hasLength(2));
        expect(queueQueries.last, queueQueries.first);
        expect(writes, hasLength(1));
        expect(tester.takeException(), isNull);
        container.read(cloudflareAdminSessionProvider.notifier).clear();
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
