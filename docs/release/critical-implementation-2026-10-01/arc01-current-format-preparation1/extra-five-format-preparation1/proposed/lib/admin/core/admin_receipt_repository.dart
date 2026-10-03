part of 'admin_runtime.dart';

mixin _AdminReceiptRepository on AdminRepositoryBase {
  Future<Map<String, dynamic>> rpcMap(
    String rpcName, {
    Map<String, dynamic>? params,
    bool automaticRetry = true,
  });

  @override
  AdminReceiptOperationalHistoryApi get receiptOperationalHistory =>
      AdminReceiptOperationalHistoryApi(
        rpc: (name, parameters) =>
            rpcMap(name, params: parameters, automaticRetry: false),
      );

  @override
  Future<Map<String, dynamic>> receiptOverview({String? countryCode}) async {
    if (countryCode != null && countryCode != 'RW') {
      throw const FormatException('Overview country is unsupported.');
    }
    final result = await rpcMap(
      'admin_receipt_overview_v1',
      params: {'p_country': countryCode ?? 'RW'},
    );
    AdminReceiptOverview.parse(result);
    return result;
  }

  @override
  Future<Map<String, dynamic>> investigation({
    required String kind,
    required String id,
  }) async {
    if (!{'transaction', 'receipt'}.contains(kind) ||
        !RegExp(
          r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$',
        ).hasMatch(id)) {
      throw const FormatException('Investigation target is invalid.');
    }
    final result = await rpcMap(
      'admin_get_collect_investigation_v1',
      params: {'p_kind': kind, 'p_id': id},
    );
    final snapshot = AdminInvestigationSnapshot.parse(result);
    if (snapshot.kind != kind || snapshot.targetId != id) {
      throw const FormatException('Investigation target did not match.');
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>> inspectUnstartedReceipt(String outboxId) async {
    cancelUuid(outboxId);
    final raw = await rpcMap(
      'admin_inspect_unstarted_receipt_v1',
      params: {'p_outbox_id': outboxId},
      automaticRetry: false,
    );
    AdminReceiptCancelInspection.parse(raw, outboxId: outboxId);
    return raw;
  }

  @override
  Future<Map<String, dynamic>> operatingPolicy() async {
    final raw = await rpcMap(
      'admin_get_unattended_operating_policy_v1',
      params: const {},
      automaticRetry: false,
    ).timeout(const Duration(seconds: 15));
    AdminOperatingPolicySnapshot.parse(raw);
    return raw;
  }

  @override
  Future<Map<String, dynamic>> receiptOperationsPolicy() async {
    final raw = await rpcMap(
      'admin_get_receipt_operations_policy_v2',
      automaticRetry: false,
    ).timeout(const Duration(seconds: 15));
    AdminReceiptOperationsPolicy.parse(raw);
    return raw;
  }

  @override
  Future<Map<String, dynamic>> receiptOperationalTelemetry() async {
    final raw = await rpcMap(
      'admin_get_receipt_operational_telemetry_v1',
      params: const {},
      automaticRetry: false,
    ).timeout(const Duration(seconds: 15));
    AdminReceiptOperationalTelemetry.parse(raw);
    return raw;
  }

  @override
  Future<Map<String, dynamic>> receiptExceptionWorkerHealth() async {
    final raw = await rpcMap(
      'admin_get_receipt_exception_worker_health_v1',
      params: const {},
      automaticRetry: false,
    ).timeout(const Duration(seconds: 15));
    AdminReceiptWorkerHealth.parse(raw);
    return raw;
  }

  @override
  Future<Map<String, dynamic>> receiptWorkerTransport(
    String requestId, {
    required DateTime expectedExpiresAt,
  }) async {
    exceptionUuid(requestId);
    final raw = await rpcMap(
      'admin_get_receipt_worker_transport_v1',
      params: {'p_request_id': requestId},
      automaticRetry: false,
    ).timeout(const Duration(seconds: 15));
    AdminReceiptWorkerTransport.parse(
      raw,
      requestId: requestId,
      expectedExpiresAt: expectedExpiresAt,
    );
    return raw;
  }

  @override
  Future<Map<String, dynamic>> receiptPrincipals(
    AdminReceiptPrincipalDirectoryQuery query,
  ) async {
    final raw = await rpcMap(
      'admin_list_receipt_operations_identities_v3',
      params: query.parameters,
      automaticRetry: false,
    ).timeout(const Duration(seconds: 15));
    AdminReceiptPrincipalDirectory.parse(raw, query: query);
    return raw;
  }

  @override
  Future<Map<String, dynamic>> receiptPrincipal(String principalId) async {
    exceptionUuid(principalId);
    final raw = await rpcMap(
      'admin_get_receipt_operations_identity_v3',
      params: {'p_principal_id': principalId},
      automaticRetry: false,
    ).timeout(const Duration(seconds: 15));
    AdminReceiptPrincipalObservation.parse(raw, principalId: principalId);
    return raw;
  }

  @override
  Future<Map<String, dynamic>> receiptPrincipalAction(
    AdminReceiptPrincipalIntent intent,
  ) async {
    final raw = await rpcMap(
      intent.rpcName,
      params: intent.parameters,
      automaticRetry: false,
    ).timeout(const Duration(seconds: 15));
    AdminReceiptPrincipalReceipt.parse(raw, binding: intent);
    return raw;
  }

  @override
  Future<Map<String, dynamic>> receiptPrincipalOwnerRequest(
    AdminReceiptPrincipalBinding original,
  ) async {
    final raw = await rpcMap(
      'admin_get_receipt_operations_enrollment_request_v3',
      params: {'p_request_id': original.requestId},
      automaticRetry: false,
    ).timeout(const Duration(seconds: 15));
    AdminReceiptPrincipalLookup.parse(raw, binding: original);
    return raw;
  }

  @override
  Future<Map<String, dynamic>> configureReceiptOperations(
    AdminReceiptOperationsIntent intent,
  ) async {
    final rpcName = switch (intent.action) {
      'configure' => 'admin_configure_receipt_operations_v2',
      'stop' => 'admin_stop_receipt_operations_v2',
      _ => operationsInvalid(),
    };
    final raw = await rpcMap(
      rpcName,
      params: intent.parameters,
      automaticRetry: false,
    ).timeout(const Duration(seconds: 15));
    AdminReceiptOperationsReceipt.parse(raw).validateIntent(intent);
    return raw;
  }

  @override
  Future<Map<String, dynamic>> receiptOperationsOwnerRequest(
    String requestId,
  ) async {
    operationsUuid(requestId);
    final raw = await rpcMap(
      'admin_get_receipt_operations_owner_request_v2',
      params: {'p_request_id': requestId},
      automaticRetry: false,
    ).timeout(const Duration(seconds: 15));
    AdminReceiptOperationsLookup.parse(raw, requestId: requestId);
    return raw;
  }

  @override
  Future<AdminReceiptCancelReceipt> cancelUnstartedReceipt(
    AdminReceiptCancelIntent intent,
  ) async {
    final raw = await rpcMap(
      'admin_cancel_unstarted_receipt_v1',
      params: intent.parameters,
      automaticRetry: false,
    );
    return AdminReceiptCancelReceipt.parse(raw, intent: intent);
  }

  @override
  Future<Map<String, dynamic>> unstartedReceiptAction(String requestId) async {
    cancelUuid(requestId);
    final raw = await rpcMap(
      'admin_get_unstarted_receipt_action_v1',
      params: {'p_request_id': requestId},
      automaticRetry: false,
    );
    AdminReceiptCancelLookup.parse(raw, requestId: requestId);
    return raw;
  }
}
