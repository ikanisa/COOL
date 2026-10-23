import 'admin_receipt_operational_history_models.dart';

typedef AdminReceiptHistoryRpc =
    Future<Map<String, dynamic>> Function(
      String name,
      Map<String, dynamic> parameters,
    );

/// Closed read-only RPC surface. Pagination cannot dispatch an operation.
class AdminReceiptOperationalHistoryApi {
  const AdminReceiptOperationalHistoryApi({required this.rpc});
  final AdminReceiptHistoryRpc rpc;
  Future<AdminReceiptHistoryPage> page(AdminReceiptHistoryQuery query) async {
    query.validate();
    final raw = await rpc(
      query.starts
          ? 'admin_list_receipt_operation_starts_v1'
          : 'admin_list_receipt_operation_evidence_v1',
      query.parameters,
    ).timeout(const Duration(seconds: 15));
    return AdminReceiptHistoryPage.parse(raw, query: query);
  }

  Future<AdminReceiptOperationalRun> run(String runId) async {
    historyUuid(runId);
    final raw = await rpc('admin_get_receipt_operation_run_v1', {
      'p_run_id': runId,
    }).timeout(const Duration(seconds: 15));
    return AdminReceiptOperationalRun.parse(raw, runId: runId);
  }
}
