part of 'admin_runtime.dart';

mixin _AdminExceptionRepository on AdminRepositoryBase {
  Future<Map<String, dynamic>> rpcMap(
    String rpcName, {
    Map<String, dynamic>? params,
    bool automaticRetry = true,
  });

  @override
  Future<Map<String, dynamic>> exceptionInbox({
    bool active = true,
    int limit = 20,
    AdminExceptionSource? source,
    DateTime? beforeChangedAt,
    String? beforeId,
  }) async {
    if (limit < 1 ||
        limit > 50 ||
        (beforeChangedAt == null) != (beforeId == null) ||
        beforeChangedAt != null &&
            (beforeChangedAt.year < 1 || beforeChangedAt.year > 9999)) {
      throw const FormatException('Invalid exception cursor.');
    }
    if (beforeId != null) exceptionUuid(beforeId);
    final raw = await rpcMap(
      'admin_list_operational_exceptions_v2',
      params: {
        'p_active': active,
        'p_limit': limit,
        'p_source_kind': source?.wire,
        'p_before_changed_at': beforeChangedAt?.toUtc().toIso8601String(),
        'p_before_id': beforeId,
      },
    );
    AdminExceptionSnapshot.parse(
      raw,
      active: active,
      limit: limit,
      source: source,
      beforeChangedAt: beforeChangedAt,
      beforeId: beforeId,
    );
    return raw;
  }

  @override
  Future<Map<String, dynamic>> receiptDeferralEvidence(
    String exceptionId,
  ) async {
    exceptionUuid(exceptionId);
    final raw = await rpcMap(
      'admin_get_receipt_deferral_exception_v1',
      params: {'p_exception_id': exceptionId},
      automaticRetry: false,
    ).timeout(const Duration(seconds: 15));
    AdminReceiptDeferralEvidence.parse(raw, exceptionId);
    return raw;
  }

  @override
  Future<Map<String, dynamic>> exceptionWorkflow(String exceptionId) async {
    exceptionUuid(exceptionId);
    final raw = await rpcMap(
      'admin_get_exception_workflow_v1',
      params: {'p_exception_id': exceptionId},
    );
    AdminExceptionWorkflow.parse(raw, exceptionId);
    return raw;
  }

  @override
  Future<Map<String, dynamic>> exceptionWorkflowAction(
    AdminExceptionWorkflowIntent intent,
  ) async {
    AdminExceptionWorkflowIntent.parse(intent.parameters);
    final raw = await rpcMap(
      'admin_act_exception_workflow_v1',
      params: intent.parameters,
      automaticRetry: false,
    );
    AdminExceptionWorkflowReceipt.parse(raw, intent);
    return raw;
  }

  @override
  Future<Map<String, dynamic>> exceptionWorkflowRequest(
    String requestId,
  ) async {
    exceptionUuid(requestId);
    return rpcMap(
      'admin_get_exception_workflow_request_v1',
      params: {'p_request_id': requestId},
      automaticRetry: false,
    );
  }

  @override
  Future<Map<String, dynamic>> exceptionFollowupOperators(
    AdminExceptionFollowupDirectoryQuery query,
  ) async {
    final raw = await rpcMap(
      'admin_list_exception_followup_operators_v2',
      params: query.parameters,
      automaticRetry: false,
    ).timeout(const Duration(seconds: 15));
    AdminExceptionFollowupDirectory.parse(raw, query: query);
    return raw;
  }

  @override
  Future<Map<String, dynamic>> exceptionFollowupAction(
    AdminExceptionWorkflowIntent intent,
  ) async {
    final original = AdminExceptionFollowupReference.fromIntent(intent);
    final raw = await rpcMap(
      'admin_act_exception_workflow_v2',
      params: intent.parameters,
      automaticRetry: false,
    ).timeout(const Duration(seconds: 15));
    AdminExceptionFollowupReceipt.parse(raw, original);
    return raw;
  }

  @override
  Future<Map<String, dynamic>> exceptionFollowupRequest(
    AdminExceptionFollowupReference original,
  ) async {
    final raw = await rpcMap(
      'admin_get_exception_workflow_request_v2',
      params: original.lookupParameters,
      automaticRetry: false,
    ).timeout(const Duration(seconds: 15));
    AdminExceptionFollowupLookup.parse(raw, original);
    return raw;
  }

  @override
  Future<Map<String, dynamic>> exceptionEscalationInbox() => rpcMap(
    'admin_list_exception_escalation_inbox_v1',
    params: {'p_limit': 20},
  );
  @override
  Future<Map<String, dynamic>> readExceptionEscalation(String escalationId) {
    exceptionUuid(escalationId);
    return rpcMap(
      'admin_read_exception_escalation_v1',
      params: {'p_escalation_id': escalationId},
      automaticRetry: false,
    );
  }

  @override
  Future<Map<String, dynamic>> exceptionActionLookup(String requestId) async {
    exceptionUuid(requestId);
    final raw = await rpcMap(
      'admin_get_operational_exception_action_v2',
      params: {'p_request_id': requestId},
      automaticRetry: false,
    );
    AdminExceptionLookup.parse(raw, requestId: requestId);
    return raw;
  }

  @override
  Future<AdminExceptionReceipt> exceptionAction(
    AdminExceptionIntent intent,
  ) async {
    final raw = await rpcMap(
      'admin_act_operational_exception_v1',
      params: intent.parameters,
      automaticRetry: false,
    );
    return AdminExceptionReceipt.parse(raw, intent: intent);
  }
}
