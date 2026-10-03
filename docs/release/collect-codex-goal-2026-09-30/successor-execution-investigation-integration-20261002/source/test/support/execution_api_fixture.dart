import 'dart:async';
import 'package:collect_app/admin/core/admin_receipt_successor_execution_sdk.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_execution_models.dart';
import 'execution_fixture.dart';

class ExecutionApiFixture implements AdminReceiptSuccessorExecutionApi {
  ExecutionApiFixture({this.raw = knownSentRaw});
  final String raw;
  bool current = true;
  Completer<AdminReceiptSuccessorExecutionSnapshot>? inspectPending;
  Completer<AdminReceiptSuccessorObservationPage>? pagePending;
  final calls = <(String, int?, int)>[];
  AdminReceiptSuccessorExecutionSnapshot get currentSnapshot => snapshot(raw);
  @override
  Future<AdminReceiptSuccessorExecutionSnapshot> inspect(
    String approval,
    String root,
  ) async {
    calls.add((approval, null, 0));
    if (inspectPending != null) return inspectPending!.future;
    return currentSnapshot;
  }

  AdminReceiptSuccessorObservationPage fixturePage(
    AdminReceiptSuccessorExecutionSnapshot s,
    int? after,
    int limit,
  ) {
    final f = ExecutionFixture();
    final all = s.attemptId == f.original.attemptId
        ? f.pages
              .expand((p) => (p['items'] as List).cast<Map<String, dynamic>>())
              .where((r) => (r['lineage_after'] as int) > (after ?? 0))
              .toList()
        : <Map<String, dynamic>>[];
    final items = all.take(limit).toList();
    // Preserve actual producer rows; adapt only the explicitly requested page
    // size/cursor for controller unit scheduling. Exact real pages are tested separately.
    final r = <String, dynamic>{
      ...f.pages.first,
      'approval_id': s.approvalId,
      'primary_receipt_id': s.primaryReceiptId,
      'cutoff_revision': s.cutoff,
      'after_revision': after,
      'limit': limit,
      'items': items,
      'next_after_revision': all.length > limit
          ? items.last['lineage_after']
          : null,
    };
    return AdminReceiptSuccessorObservationPage.parse(r, s, after, limit);
  }

  @override
  Future<AdminReceiptSuccessorObservationPage> observations(
    AdminReceiptSuccessorExecutionSnapshot s, {
    int? after,
    int limit = 20,
  }) async {
    calls.add((s.approvalId, after, limit));
    if (pagePending != null) return pagePending!.future;
    return fixturePage(s, after, limit);
  }
}
