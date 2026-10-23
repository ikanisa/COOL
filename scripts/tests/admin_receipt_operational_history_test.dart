import 'dart:convert';
import 'dart:io';
import 'package:collect_app/admin/core/admin_receipt_operational_history_models.dart';
import 'package:collect_app/admin/core/admin_receipt_operational_history_sdk.dart';
import 'package:collect_app/admin/core/admin_entity_audit.dart';

Map<String, dynamic> copy(Map<String, dynamic> d) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(d)) as Map);
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    throw ArgumentError('Provide a retained actual SQL fixture directory.');
  }
  final dir = Directory(args.single);
  var n = 0;
  Map<String, dynamic> read(String name) => Map<String, dynamic>.from(
    jsonDecode(File('${dir.path}/$name.json').readAsStringSync()) as Map,
  );
  void check(String name, bool ok) {
    if (!ok) throw StateError(name);
    n++;
    stdout.writeln('PASS $name');
  }

  void reject(String name, void Function() fn) {
    var caught = false;
    try {
      fn();
    } on FormatException {
      caught = true;
    }
    check(name, caught);
  }

  final starts = read('starts-refused');
  const startQuery = AdminReceiptHistoryQuery();
  final startPage = AdminReceiptHistoryPage.parse(starts, query: startQuery);
  check(
    'actual retained begin refusals have no run',
    startPage.rows.any(
      (r) => r.data['run_state'] == 'no_run' && r.runId == null,
    ),
  );
  final closed = read('run-closed'), rid = closed['run_id'] as String;
  for (final name in [
    'run-closed',
    'run-quota-closed',
    'run-short',
    'run-config-unavailable',
    'run-unavailable',
  ]) {
    final raw = read(name);
    final parsed = AdminReceiptOperationalRun.parse(
      raw,
      runId: raw['run_id'] as String,
    );
    check(
      'actual producer/API fixture $name parses',
      parsed.id == raw['run_id'],
    );
  }
  final run = AdminReceiptOperationalRun.parse(closed, runId: rid);
  check(
    'exact lease accepts shorter principal expiry',
    AdminReceiptOperationalRun.parse(
      read('run-short'),
      runId: read('run-short')['run_id'] as String,
    ).available,
  );
  check(
    'historical configuration remains nullable',
    AdminReceiptOperationalRun.parse(
          read('run-config-unavailable'),
          runId: rid,
        ).historicalConfig ==
        null,
  );
  for (final section in AdminReceiptHistorySection.values) {
    final raw = read('evidence-${section.wire}');
    final query = AdminReceiptHistoryQuery(runId: rid, section: section);
    final page = AdminReceiptHistoryPage.parse(raw, query: query);
    check('actual section ${section.wire} parses', page.query == query);
  }
  final events = read('evidence-events'),
      eventQuery = AdminReceiptHistoryQuery(
        runId: rid,
        section: AdminReceiptHistorySection.events,
      );
  final page = AdminReceiptHistoryPage.parse(events, query: eventQuery);
  check(
    'assignment and immutable outcome are distinct',
    page.rows.any(
          (r) => r.data['assigned_at'] != null && r.data['outcome'] == null,
        ) &&
        page.rows.any((r) => r.data['outcome'] != null),
  );
  check(
    'first durable handling is separate proof',
    page.rows.any((r) => r.data['first_handled'] != null),
  );
  for (final kind in [
    AdminAuditEntityKind.receiptOperationRun,
    AdminAuditEntityKind.receiptOperationsPolicy,
    AdminAuditEntityKind.supervisorIdentity,
  ]) {
    final raw = read('audit-${kind.wire}');
    final parsed = AdminEntityAuditSnapshot.parse(
      raw,
      query: AdminEntityAuditQuery(kind: kind, id: raw['entity_id'] as String),
    );
    check(
      'actual joined audit lineage ${kind.wire} parses',
      parsed.rows.isNotEmpty,
    );
  }
  final qraw = read('quota-first');
  final qq = AdminReceiptHistoryQuery(
    runId: qraw['run_id'] as String,
    section: AdminReceiptHistorySection.budgetRefusals,
    limit: 1,
  );
  final qp = AdminReceiptHistoryPage.parse(qraw, query: qq);
  check(
    'immutable budget refusals retain composite identity',
    qp.rows.single.cursor.evidenceId.split(':').length == 2,
  );
  final qnext = read('quota-last');
  AdminReceiptHistoryPage.parse(
    qnext,
    query: AdminReceiptHistoryQuery(
      runId: qq.runId,
      section: qq.section,
      limit: 1,
      before: qp.nextCursor,
    ),
  );
  check(
    'actual composite next page does not overlap',
    qnext['rows'][0]['evidence_id'] != qraw['rows'][0]['evidence_id'],
  );

  final quotaEvents = read('evidence-quota-events');
  final quotaPage = AdminReceiptHistoryPage.parse(
    quotaEvents,
    query: AdminReceiptHistoryQuery(
      runId: quotaEvents['run_id'] as String,
      section: AdminReceiptHistorySection.events,
    ),
  );
  check(
    'actual mutable deferral is retained alongside immutable run evidence',
    quotaPage.rows.any((r) => r.data['current_deferral'] != null),
  );
  final withExceptions = read('evidence-budget-refusals-with-exceptions');
  final refusedPage = AdminReceiptHistoryPage.parse(
    withExceptions,
    query: AdminReceiptHistoryQuery(
      runId: withExceptions['run_id'] as String,
      section: AdminReceiptHistorySection.budgetRefusals,
    ),
  );
  check(
    'actual immutable quota refusal retains supported exception source links',
    refusedPage.rows.any((r) => (r.data['exception_ids'] as List).isNotEmpty),
  );
  final reservations = AdminReceiptHistoryPage.parse(
    read('evidence-reservations'),
    query: AdminReceiptHistoryQuery(
      runId: rid,
      section: AdminReceiptHistorySection.reservations,
    ),
  );
  check(
    'original global backlog snapshot reservation remains linked to original run',
    reservations.rows.any((r) => r.data['snapshot_id'] == r.cursor.evidenceId),
  );
  final tiedFirst = read('quota-first-tied');
  final tiedQuery = AdminReceiptHistoryQuery(
    runId: tiedFirst['run_id'] as String,
    section: AdminReceiptHistorySection.budgetRefusals,
    limit: 1,
  );
  final tiedPage = AdminReceiptHistoryPage.parse(tiedFirst, query: tiedQuery);
  final tiedLast = AdminReceiptHistoryPage.parse(
    read('quota-last-tied'),
    query: AdminReceiptHistoryQuery(
      runId: tiedQuery.runId,
      section: tiedQuery.section,
      limit: 1,
      before: tiedPage.nextCursor,
    ),
  );
  check(
    'actual composite tied cursor continues by complete canonical request snapshot identity',
    tiedPage.rows.single.cursor.recordedAt ==
            tiedLast.rows.single.cursor.recordedAt &&
        tiedPage.rows.single.cursor.evidenceId.compareTo(
              tiedLast.rows.single.cursor.evidenceId,
            ) >
            0,
  );
  var immutable = false;
  try {
    (run.historicalConfig!['caps'] as Map)['global_actions'] = 999;
  } on UnsupportedError {
    immutable = true;
  }
  check(
    'nested actual DTO historical caps cannot be changed after validation',
    immutable,
  );
  reject(
    'wrong run identity',
    () => AdminReceiptHistoryPage.parse(
      events,
      query: const AdminReceiptHistoryQuery(
        runId: '00000000-0000-4000-8000-000000000001',
        section: AdminReceiptHistorySection.events,
      ),
    ),
  );
  reject(
    'wrong section identity',
    () => AdminReceiptHistoryPage.parse(
      events,
      query: AdminReceiptHistoryQuery(
        runId: rid,
        section: AdminReceiptHistorySection.reservations,
      ),
    ),
  );
  final private = copy(events)..['signing_payload'] = 'withheld';
  reject(
    'unexpected private top field',
    () => AdminReceiptHistoryPage.parse(private, query: eventQuery),
  );
  final raw = copy(events);
  raw['rows'][0]['raw_body'] = 'withheld';
  reject(
    'unexpected raw source field',
    () => AdminReceiptHistoryPage.parse(raw, query: eventQuery),
  );
  final reordered = copy(events);
  reordered['rows'] = (reordered['rows'] as List).reversed.toList();
  reject(
    'ascending history',
    () => AdminReceiptHistoryPage.parse(reordered, query: eventQuery),
  );
  final duplicate = copy(events);
  duplicate['rows'][1] = duplicate['rows'][0];
  reject(
    'duplicate source identity',
    () => AdminReceiptHistoryPage.parse(duplicate, query: eventQuery),
  );
  final tie = copy(events);
  final rows = tie['rows'] as List;
  final time = rows.first['recorded_at'];
  for (final row in rows) {
    row['recorded_at'] = time;
  }
  rows.sort(
    (a, b) =>
        (b['evidence_id'] as String).compareTo(a['evidence_id'] as String),
  );
  check(
    'canonical ASCII UUID tie ordering accepted',
    AdminReceiptHistoryPage.parse(tie, query: eventQuery).rows.length ==
        rows.length,
  );
  final long = copy(closed);
  long['run']['expires_at'] = historyUtc(
    historyInstant(long['run']['started_at']).add(const Duration(seconds: 121)),
  );
  reject(
    'lease cannot exceed120seconds',
    () => AdminReceiptOperationalRun.parse(long, runId: rid),
  );
  final missing = copy(closed);
  missing['historical_config']['revision'] =
      (missing['run']['policy_revision'] as int) + 1;
  reject(
    'historical config revision must match run',
    () => AdminReceiptOperationalRun.parse(missing, runId: rid),
  );
  final zero = copy(closed);
  zero['historical_config']['caps']['global_actions'] = 0;
  reject(
    'configured caps retain positive actual producer bounds',
    () => AdminReceiptOperationalRun.parse(zero, runId: rid),
  );
  final complete = copy(closed);
  complete['completion']['business_handled'] = true;
  complete['completion']['deferred_count'] = 1;
  reject(
    'deferred summary never becomes completed work',
    () => AdminReceiptOperationalRun.parse(complete, runId: rid),
  );
  final leaked = copy(events);
  leaked['rows'][0]['source_status'] = 'unavailable';
  leaked['rows'][0]['payment_id'] = rid;
  reject(
    'unavailable source cannot expose joined IDs',
    () => AdminReceiptHistoryPage.parse(leaked, query: eventQuery),
  );
  check(
    'freshness expires exactly at sample boundary',
    run.isFresh(run.checkedAt) &&
        !run.isFresh(run.validUntil) &&
        !run.isFresh(run.checkedAt.subtract(const Duration(microseconds: 1))),
  );
  final calls = <String>[];
  final api = AdminReceiptOperationalHistoryApi(
    rpc: (name, params) async {
      calls.add(name);
      if (name == 'admin_get_receipt_operation_run_v1') {
        check(
          'SDK exact run parameter',
          params.length == 1 && params['p_run_id'] == rid,
        );
        return closed;
      }
      check(
        'SDK complete exact paging parameters',
        params.keys.toSet().containsAll({
          'p_run_id',
          'p_section',
          'p_limit',
          'p_before_at',
          'p_before_id',
        }),
      );
      return events;
    },
  );
  await api.run(rid);
  await api.page(eventQuery);
  check(
    'SDK invokes only read readers',
    calls.join(',') ==
        'admin_get_receipt_operation_run_v1,admin_list_receipt_operation_evidence_v1',
  );
  stdout.writeln('PASS $n actual-fixture and strict boundary checks');
}
