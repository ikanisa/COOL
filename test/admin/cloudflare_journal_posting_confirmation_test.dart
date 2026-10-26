import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_pending_attempt_store.dart';
import 'package:collect_app/admin/core/cloudflare_admin_operating_pages.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/shared/components/admin_data_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'cloudflare_core_fixtures.dart';
import 'cloudflare_operating_pages_test.dart'
    show
        clean,
        draftJournalForPosting,
        journalPostingResponse,
        pumpOperating,
        reasonAndReview;
import 'cloudflare_operating_repository_test.dart'
    show operatingReceipt, operatingRepository, operatingResponse, otherId;

const postingForm = CloudflareOperatingForm(
  operation: CloudflareOperation.postJournal,
  detail: draftJournalForPosting,
);
const postingPath = '/api/admin/operations/journals/$coreId';

List<Map<String, dynamic>> rows(Map<String, dynamic> data) =>
    ((data['related'] as Map)['entries'] as List).cast<Map<String, dynamic>>();

void main() {
  for (final count in [2, 100]) {
    testWidgets('posting confirms all $count fresh lines with exact payload', (
      tester,
    ) async {
      var reads = 0, writes = 0;
      final repo = await operatingRepository((request) async {
        if (request.method == 'GET') {
          reads++;
          expect(request.url.path, postingPath);
          expect(request.url.queryParameters, {
            'relation': 'entries',
            'limit': '100',
            'offset': '0',
          });
          return operatingResponse(journalPostingResponse(count: count));
        }
        writes++;
        expect(request.method, 'POST');
        expect(request.url.path, '$postingPath/post');
        expect(jsonDecode(request.body), {
          'reason': 'Checked against the supporting evidence',
          'expected_version': 1,
        });
        expect(request.headers['Idempotency-Key'], isNotEmpty);
        return operatingResponse(
          operatingReceipt(type: 'journals', version: 2),
        );
      });
      await pumpOperating(tester, repo, postingForm);
      await reasonAndReview(tester);
      expect(reads, 1);
      expect(writes, 0);
      final tables = tester.widgetList<AdminDataTable>(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(AdminDataTable),
        ),
      );
      final lines = tables.singleWhere(
        (t) => t.tableLabel == 'Journal entries to post',
      );
      expect(lines.rows.length, count);
      expect(lines.rows.last.extra['line_number'], count);
      expect(
        tables.any((t) => t.tableLabel == 'Journal posting context'),
        isTrue,
      );
      expect(
        lines.columns!
            .where((c) => ['Debit Rwf', 'Credit Rwf'].contains(c.label))
            .every((c) => c.numeric),
        isTrue,
      );
      await tester.tap(find.text('Confirm permanent posting'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(find.text('Change saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await clean(tester, repo);
    });
  }

  final invalid = <String, void Function(Map<String, dynamic>)>{
    'changed version': (d) => (d['resource'] as Map)['version'] = 2,
    'wrong actor': (d) => d['current_actor_id'] = otherId,
    'wrong record': (d) => (d['resource'] as Map)['id'] = otherId,
    'wrong group': (d) => (d['resource'] as Map)['group_id'] = coreId,
    'posted record': (d) => (d['resource'] as Map)['status'] = 'posted',
    'no management': (d) => d['can_manage'] = false,
    'creator is reviewer': (d) =>
        (d['resource'] as Map)['created_by_admin_id'] = coreId,
    'editor is reviewer': (d) =>
        (d['resource'] as Map)['edited_by_admin_id'] = coreId,
    'missing pagination': (d) => d.remove('related_pages'),
    'wrong page size': (d) =>
        ((d['related_pages'] as Map)['entries'] as Map)['limit'] = 2,
    'wrong page offset': (d) {
      ((d['related_pages'] as Map)['entries'] as Map).addAll(<String, dynamic>{
        'total': 3,
        'offset': 1,
      });
    },
    'partial first window': (d) {
      ((d['related_pages'] as Map)['entries'] as Map).addAll(<String, dynamic>{
        'total': 100,
        'limit': 2,
        'next_offset': 2,
      });
      d['related_truncated'] = true;
    },
    'one line': (d) {
      rows(d).removeLast();
      ((d['related_pages'] as Map)['entries'] as Map)['total'] = 1;
    },
    'wrong journal parent': (d) => rows(d)[0]['journal_id'] = otherId,
    'wrong group parent': (d) => rows(d)[0]['group_id'] = coreId,
    'wrong line ordinal': (d) => rows(d)[1]['line_number'] = 1,
    'duplicate entry': (d) => rows(d)[1]['id'] = rows(d)[0]['id'],
    'invalid account identity': (d) =>
        rows(d)[0]['account_id'] = 'not-an-account',
    'missing account name': (d) => rows(d)[0].remove('account_name'),
    'unbalanced journal': (d) => rows(d)[1]['credit_rwf'] = 2,
    'two positive sides': (d) => rows(d)[0]['credit_rwf'] = 1,
    'missing exact amount': (d) => rows(d)[0]['debit_rwf'] = null,
    'incomplete payment relationship': (d) =>
        (d['resource'] as Map)['allocation_id'] = otherId,
  };
  for (final entry in invalid.entries) {
    testWidgets(
      'posting rejects ${entry.key} before confirmation or mutation',
      (tester) async {
        var writes = 0;
        final response = journalPostingResponse();
        entry.value(response);
        final storage = MemoryAdminPendingAttemptStorage();
        final repo = await operatingRepository((request) async {
          if (request.method != 'GET') writes++;
          return operatingResponse(response);
        });
        await pumpOperating(tester, repo, postingForm, storage: storage);
        await reasonAndReview(tester);
        expect(find.byType(AlertDialog), findsNothing);
        expect(
          find.textContaining('response could not be verified'),
          findsOneWidget,
        );
        expect(writes, 0);
        expect(storage.values, isEmpty);
        expect(tester.takeException(), isNull);
        await clean(tester, repo);
      },
    );
  }

  for (final mode in ['more than100', 'exact total overflow']) {
    testWidgets('posting rejects $mode without partial review', (tester) async {
      final response = journalPostingResponse(count: 100);
      if (mode == 'more than100') {
        ((response['related_pages'] as Map)['entries'] as Map).addAll(
          <String, dynamic>{'total': 101, 'next_offset': 100},
        );
        response['related_truncated'] = true;
      } else {
        for (final row in rows(response)) {
          row[row['debit_rwf'] == 0 ? 'credit_rwf' : 'debit_rwf'] =
              9007199254740991;
        }
      }
      var writes = 0;
      final repo = await operatingRepository((request) async {
        if (request.method != 'GET') writes++;
        return operatingResponse(response);
      });
      await pumpOperating(tester, repo, postingForm);
      await reasonAndReview(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(writes, 0);
      await clean(tester, repo);
    });
  }

  testWidgets(
    'session change during context GET cannot open or submit review',
    (tester) async {
      final response = Completer<http.Response>();
      var reads = 0, writes = 0;
      final repo = await operatingRepository((request) async {
        if (request.method != 'GET') writes++;
        reads++;
        return response.future;
      });
      await pumpOperating(tester, repo, postingForm);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Reason for this change'),
        'Independent evidence review',
      );
      await tester.tap(find.text('Review change'));
      await tester.pump();
      expect(reads, 1);
      repo.session.clear();
      response.complete(operatingResponse(journalPostingResponse()));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(writes, 0);
      await clean(tester, repo);
    },
  );

  testWidgets(
    'retained posting confirmation rejects revoked session authority',
    (tester) async {
      var writes = 0;
      final repo = await operatingRepository((request) async {
        if (request.method != 'GET') writes++;
        return operatingResponse(journalPostingResponse());
      });
      await pumpOperating(tester, repo, postingForm);
      await reasonAndReview(tester);
      final confirm = find.widgetWithText(
        FilledButton,
        'Confirm permanent posting',
      );
      final retained = tester.widget<FilledButton>(confirm).onPressed!;
      repo.session.clear();
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      retained();
      await tester.pumpAndSettle();
      expect(writes, 0);
      await clean(tester, repo);
    },
  );

  for (final stale in [false, true]) {
    testWidgets('original-key retry uses fresh context; stale=$stale', (
      tester,
    ) async {
      var writes = 0, contextReads = 0, checks = 0;
      String? originalKey, originalBody;
      final storage = MemoryAdminPendingAttemptStorage();
      final repo = await operatingRepository((request) async {
        if (request.method == 'POST') {
          writes++;
          if (writes == 1) {
            originalKey = request.headers['Idempotency-Key'];
            originalBody = request.body;
            throw http.ClientException('lost posting response');
          }
          expect(request.headers['Idempotency-Key'], originalKey);
          expect(request.body, originalBody);
          return operatingResponse(
            operatingReceipt(type: 'journals', version: 2),
          );
        }
        if (request.url.path == postingPath) {
          contextReads++;
          final data = journalPostingResponse();
          if (stale && contextReads > 1) {
            (data['resource'] as Map)['version'] = 2;
          }
          return operatingResponse(data);
        }
        expect(request.url.path, '/api/admin/operations/requests/$originalKey');
        checks++;
        return operatingResponse(
          checks == 1
              ? {'status': 'not_found'}
              : {
                  'status': 'succeeded',
                  'request_id': otherId,
                  'receipt': operatingReceipt(type: 'journals', version: 2),
                },
        );
      });
      await pumpOperating(tester, repo, postingForm, storage: storage);
      await reasonAndReview(tester);
      await tester.tap(find.text('Confirm permanent posting'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      await tester.ensureVisible(find.text('Check request status'));
      await tester.tap(find.text('Check request status'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Retry identical request'));
      await tester.tap(find.text('Retry identical request'));
      await tester.pumpAndSettle();
      expect(contextReads, 2);
      expect(writes, 1);
      if (stale) {
        expect(find.byType(AlertDialog), findsNothing);
        expect(storage.values, isNotEmpty);
        // Original receipt GET remains available despite unusable live context.
        await tester.ensureVisible(find.text('Check request status'));
        await tester.tap(find.text('Check request status'));
        await tester.pumpAndSettle();
        expect(checks, 2);
        expect(writes, 1);
      } else {
        expect(find.text('Confirm identical retry'), findsOneWidget);
        await tester.tap(find.text('Confirm identical retry'));
        await tester.pumpAndSettle();
        expect(writes, 2);
      }
      expect(find.text('Change saved'), findsOneWidget);
      expect(storage.values, isEmpty);
      expect(tester.takeException(), isNull);
      await clean(tester, repo);
    });
  }
}
