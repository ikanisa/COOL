part of 'admin_runtime.dart';

class AdminRepository extends AdminRepositoryBase
    with _AdminReceiptRepository, _AdminExceptionRepository {
  const AdminRepository(this._supabase, {this.isCurrent});

  final SupabaseClient? _supabase;
  final bool Function()? isCurrent;

  @override
  AdminExistingMemberAllocationApi get existingMemberAllocation =>
      AdminExistingMemberAllocationSdk(
        rpc: (name, parameters) =>
            rpcMap(name, params: parameters, automaticRetry: false),
      );

  @override
  Future<AdminUserGroupsPage> userGroups(
    String userId, {
    int limit = 25,
    int offset = 0,
  }) async {
    _requireReconciliationUuid(userId);
    if (limit < 1 || limit > 100 || offset < 0 || offset > 2147483647) {
      throw const FormatException('Invalid user group page request.');
    }
    final result = await rpcMap(
      'admin_list_user_groups_v1',
      params: {'p_user_id': userId, 'p_limit': limit, 'p_offset': offset},
    );
    return AdminUserGroupsPage.parse(
      result,
      userId: userId,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<AdminPayerGroupsPage> transactionPayerGroups(
    String transactionId, {
    int limit = 10,
    int offset = 0,
  }) async {
    validateAdminDetailRequest('admin_get_collect_transaction', transactionId);
    if (limit < 1 || limit > 100 || offset < 0 || offset > 2147483647) {
      throw const FormatException('Invalid payer groups request.');
    }
    final result = await rpcMap(
      'admin_list_collect_transaction_payer_groups_v1',
      params: {'p_id': transactionId, 'p_limit': limit, 'p_offset': offset},
    );
    return AdminPayerGroupsPage.parse(result, limit: limit, offset: offset);
  }

  @override
  AdminGovernedSettingsApi get governedSettings => AdminGovernedSettingsSdk(
    rpc: (name, parameters) =>
        rpcMap(name, params: parameters, automaticRetry: false),
    isCurrent: () => isCurrent?.call() != false,
    now: DateTime.now,
    currentSession: () => adminSessionKey(_requireClient().auth.currentSession),
  );

  Future<T> _withSession<T>(
    Future<T> Function(AdminRequestSession) operation, {
    bool reconciliation = false,
  }) async {
    Never changed() => throw reconciliation
        ? const AdminReconciliationStepUpException(
            'session_changed',
            'Your sign-in changed. Reopen reconciliation and try again.',
          )
        : const AdminSessionChanged();
    if (isCurrent?.call() == false) changed();
    final session = AdminRequestSession(_requireClient());
    void check() {
      try {
        session.checkCurrent();
      } on AdminSessionChanged {
        changed();
      }
      if (isCurrent?.call() == false) changed();
    }

    try {
      final result = await operation(session);
      check();
      return result;
    } catch (_) {
      check();
      rethrow;
    } finally {
      await session.dispose();
      check();
    }
  }

  @override
  Future<void> sendOtp({required String phone}) async {
    final normalizedPhone = _normalizeAdminPhone(phone);
    await _requireClient().auth.signInWithOtp(
      phone: normalizedPhone,
      channel: OtpChannel.whatsapp,
      shouldCreateUser: false,
    );
  }

  @override
  Future<void> sendEmailOtp({required String email}) async {
    final normalized = normalizeAdminEmail(email);
    await _requireClient().auth.signInWithOtp(
      email: normalized,
      shouldCreateUser: false,
    );
  }

  @override
  Future<AdminIdentity?> verifyEmailOtp({
    required String email,
    required String otp,
  }) async {
    final normalized = normalizeAdminEmail(email);
    final token = normalizeAdminEmailOtp(otp);
    final client = _requireClient();
    final response = await client.auth.verifyOTP(
      email: normalized,
      token: token,
      type: OtpType.email,
    );
    if (response.session == null) {
      throw const AuthException(
        'Admin email verification did not create a session.',
      );
    }
    return AdminRepository(client).currentIdentity();
  }

  @override
  Future<AdminIdentity?> verifyOtp({
    required String phone,
    required String otp,
  }) async {
    final client = _requireClient();
    final normalizedPhone = _normalizeAdminPhone(phone);
    final response = await client.auth.verifyOTP(
      phone: normalizedPhone,
      token: otp.trim(),
      type: OtpType.sms,
    );
    if (response.session == null) {
      throw const AuthException(
        'Admin OTP verification did not create a session.',
      );
    }
    // A successful OTP creates a new provider generation. Read that new
    // identity without reusing the signed-out repository's lifetime fence.
    return AdminRepository(client).currentIdentity();
  }

  @override
  Future<void> signOut() async => _supabase?.auth.signOut();

  @override
  Future<AdminIdentity?> currentIdentity() async {
    final client = _supabase;
    if (client == null) return null;
    if (client.auth.currentSession == null) return null;
    return _withSession((session) async {
      final row = await client
          .rpc<dynamic>('admin_current_user')
          .setHeader('Authorization', 'Bearer ${session.token}');
      return parseAdminIdentity(row, actorId: session.key!.userId);
    });
  }

  @override
  Future<List<AdminMetric>> overviewMetrics() async {
    return parseAdminOverview(await rpcMap('admin_overview'));
  }

  @override
  Future<AdminListResult> list(
    String rpcName, {
    String? search,
    String? status,
    int? limit,
    int? offset,
    String? sortBy,
    String? countryCode,
  }) async {
    final pageSize = limit ?? 25;
    final pageOffset = offset ?? 0;
    if (pageSize < 1 || pageSize > 100) {
      throw RangeError.range(pageSize, 1, 100, 'limit');
    }
    if (pageOffset < 0 || pageOffset > maxExactJsonInteger) {
      throw RangeError.range(pageOffset, 0, maxExactJsonInteger, 'offset');
    }
    final trimmedSearch = search?.trim();
    final trimmedStatus = status?.trim();
    final trimmedSort = sortBy?.trim();
    final normalizedCountry = countryCode?.trim().toUpperCase();
    final scoped =
        normalizedCountry?.isNotEmpty == true &&
        adminRpcUsesCountryScope(rpcName);
    // Every list request is a server window. A missing paged RPC must fail;
    // fetching an unpaged legacy batch and slicing it can conceal records.
    final row = await rpcMap(
      scoped ? 'admin_list_country_scoped' : rpcName,
      params: {
        if (scoped) 'p_rpc_name': rpcName,
        if (scoped) 'p_country': normalizedCountry,
        'p_search': trimmedSearch?.isEmpty == true ? null : trimmedSearch,
        'p_status': trimmedStatus?.isEmpty == true ? null : trimmedStatus,
        'p_limit': pageSize,
        'p_offset': pageOffset,
        'p_sort': trimmedSort == null || trimmedSort.isEmpty
            ? 'created_at_desc'
            : trimmedSort,
      },
    );
    final result = AdminListResult.fromJson(
      row,
    ).validateWindow(limit: pageSize, offset: pageOffset);
    // The scoped RPC promises an explicit country on every row. Verify the
    // server result here as well as in the page widget so overview and other
    // repository callers cannot accidentally publish an unscoped row.
    if (scoped &&
        normalizedCountry == 'RW' &&
        result.rows.any(
          (item) =>
              '${item.extra['country_code'] ?? ''}'.trim().toUpperCase() !=
              'RW',
        )) {
      throw const FormatException(
        'Admin list returned rows outside the requested country.',
      );
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>> detail(String rpcName, String id) async {
    validateAdminDetailRequest(rpcName, id);
    return validateAdminDetail(
      rpcName,
      id,
      await rpcMap(rpcName, params: {'p_id': id}),
    );
  }

  @override
  Future<Map<String, dynamic>> smsQueueHealth() => _withSession((
    session,
  ) async {
    final response = await _requireClient().functions.invoke(
      'collect-notification-operator',
      body: const {'action': 'health'},
      headers: {'Authorization': 'Bearer ${session.token}'},
    );
    final raw = response.data is String
        ? jsonDecode(response.data as String)
        : response.data;
    if (response.status != 200 ||
        raw is! Map ||
        raw.length != 3 ||
        raw['ok'] != true ||
        raw['action'] != 'health' ||
        raw['result'] is! Map) {
      throw const FormatException('SMS queue health could not be validated.');
    }
    final data = Map<String, dynamic>.from(raw['result'] as Map);
    AdminSmsQueueHealth.parse(data);
    return data;
  });

  @override
  Future<Map<String, dynamic>> shadowRuns({
    int limit = 20,
    DateTime? beforeStartedAt,
    String? beforeRunId,
  }) async {
    if (limit < 1 || limit > 50) {
      throw RangeError.range(limit, 1, 50, 'limit');
    }
    if ((beforeStartedAt == null) != (beforeRunId == null) ||
        (beforeRunId != null &&
            !RegExp(
              r'^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$',
            ).hasMatch(beforeRunId))) {
      throw const FormatException(
        'A complete shadow history cursor is required.',
      );
    }
    final cursorId = beforeRunId?.toLowerCase();
    final data = await rpcMap(
      'list_collect_shadow_runs_v1',
      params: {
        'p_limit': limit,
        'p_before_started_at': beforeStartedAt?.toUtc().toIso8601String(),
        'p_before_run_id': cursorId,
      },
    );
    AdminShadowRunsSnapshot.parse(
      data,
      limit: limit,
      beforeStartedAt: beforeStartedAt,
      beforeRunId: cursorId,
    );
    return data;
  }

  @override
  Future<Map<String, dynamic>> operatorEntityAudit(
    AdminEntityAuditQuery query,
  ) async {
    query.validate();
    final data = await rpcMap(
      'admin_get_operator_entity_audit_v1',
      params: {
        'p_entity_kind': query.kind.wire,
        'p_entity_id': query.id,
        'p_limit': query.limit,
        'p_before_at': query.before?.recordedAt.toUtc().toIso8601String(),
        'p_before_event_id': query.before?.eventId,
      },
      automaticRetry: false,
    ).timeout(const Duration(seconds: 15));
    AdminEntityAuditSnapshot.parse(data, query: query);
    return data;
  }

  @override
  Future<Map<String, dynamic>> exceptionEntityAudit(
    AdminEntityAuditQuery query,
  ) async {
    final parameters = adminExceptionHistoryParameters(query);
    final data = await rpcMap(
      'admin_get_exception_entity_audit_v2',
      params: parameters,
      automaticRetry: false,
    ).timeout(const Duration(seconds: 15));
    AdminExceptionHistorySnapshot.parse(data, query: query);
    return data;
  }

  @override
  Future<Map<String, dynamic>> exceptionEscalationInboxPage(
    AdminExceptionEscalationInboxQuery query,
  ) async {
    final parameters = query.parameters;
    final recipient = _requireClient().auth.currentUser?.id;
    if (recipient == null) throw const AdminSessionChanged();
    final data = await rpcMap(
      'admin_list_exception_escalation_inbox_v2',
      params: parameters,
      automaticRetry: false,
    ).timeout(const Duration(seconds: 15));
    AdminExceptionEscalationInboxSnapshot.parse(
      data,
      query: query,
      recipientId: recipient,
    );
    return data;
  }

  @override
  Future<Map<String, dynamic>> readExceptionEscalationCurrent(String id) async {
    exceptionUuid(id);
    final data = await rpcMap(
      'admin_read_exception_escalation_v2',
      params: {'p_escalation_id': id},
      automaticRetry: false,
    ).timeout(const Duration(seconds: 15));
    AdminExceptionEscalationReadReceipt.parse(data, escalationId: id);
    return data;
  }

  @override
  Future<AdminQueueSla?> queueSla(String queueKey) async {
    if (_supabase == null) return null;
    final normalized = validateAdminQueueSlaRequest(queueKey);
    try {
      return await _withSession(
        (session) async => parseAdminQueueSla(
          await _requireClient()
              .rpc<dynamic>(
                'admin_get_queue_sla',
                params: {'p_queue_key': normalized},
              )
              .setHeader('Authorization', 'Bearer ${session.token}'),
          queueKey: normalized,
        ),
      );
    } on PostgrestException catch (error) {
      if (!_isLegacySlaSignatureError(error)) rethrow;
      return null;
    }
  }

  @override
  Future<AdminRuntimeConfig?> runtimeConfig() async {
    if (_supabase == null) return null;
    try {
      final row = await rpcMap('admin_runtime_config');
      return parseAdminRuntimeConfig(row);
    } on PostgrestException catch (error) {
      if (!_isMissingRuntimeConfigError(error)) rethrow;
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>> action(
    String rpcName,
    Map<String, dynamic> params,
  ) async {
    final frozen = Map<String, dynamic>.unmodifiable(params);
    final result = await rpcMap(rpcName, params: frozen, automaticRetry: false);
    validateAdminActionReceipt(rpcName, frozen, result);
    return result;
  }

  @override
  Future<void> assignOperatorDraftOwner({
    required String collectionId,
    required String ownerCollectId,
    required String reason,
  }) async {
    validateAdminDetailRequest('admin_get_collection', collectionId);
    if (!RegExp(r'^[0-9]{6}$').hasMatch(ownerCollectId) ||
        reason.trim().length < 8 ||
        reason.trim().length > 500) {
      throw const FormatException('Invalid group owner assignment request.');
    }
    final response = await _withSession(
      (session) => _requireClient()
          .rpc<dynamic>(
            'admin_assign_operator_draft_owner_v1',
            params: {
              'p_collection': collectionId,
              'p_new_owner_public_id': ownerCollectId,
              'p_reason': reason.trim(),
            },
          )
          .setHeader('Authorization', 'Bearer ${session.token}'),
    );
    if (response != null) {
      throw const FormatException(
        'Unexpected group owner assignment response.',
      );
    }
  }

  @override
  Future<AdminGatewayActionReceipt> gatewayOwnerAction(
    AdminGatewayOwnerIntent intent,
  ) async {
    final result = await rpcMap(
      intent.action.rpc,
      params: intent.parameters,
      automaticRetry: false,
    );
    return AdminGatewayActionReceipt.parse(
      result,
      requestId: intent.requestId,
      action: intent.action,
      deviceId: intent.deviceId,
    );
  }

  @override
  Future<Map<String, dynamic>> gatewayDevices({
    int limit = 20,
    DateTime? beforeEnrolledAt,
    String? beforeDeviceId,
  }) async {
    if (limit < 1 || limit > 50) {
      throw RangeError.range(limit, 1, 50, 'limit');
    }
    if ((beforeEnrolledAt == null) != (beforeDeviceId == null) ||
        beforeEnrolledAt != null &&
            (beforeEnrolledAt.year < 1 || beforeEnrolledAt.year > 9999)) {
      throw const FormatException(
        'A complete gateway device cursor is required.',
      );
    }
    if (beforeDeviceId != null) gatewayUuid(beforeDeviceId);
    final result = await rpcMap(
      'admin_list_gateway_devices_v1',
      params: {
        'p_limit': limit,
        'p_before_enrolled_at': beforeEnrolledAt?.toUtc().toIso8601String(),
        'p_before_device_id': beforeDeviceId,
      },
    );
    AdminGatewaySnapshot.parse(
      result,
      limit: limit,
      beforeEnrolledAt: beforeEnrolledAt,
      beforeDeviceId: beforeDeviceId,
    );
    return result;
  }

  @override
  Future<Map<String, dynamic>> gatewayOwnerRequest(String requestId) async {
    gatewayUuid(requestId);
    final result = await rpcMap(
      'admin_get_gateway_owner_request_v1',
      params: {'p_request_id': requestId},
    );
    AdminGatewayRequestSnapshot.parse(result, requestId: requestId);
    return result;
  }

  @override
  Future<Map<String, dynamic>> automaticReceiptEvidence(
    String receiptId, {
    int limit = 20,
    AdminAutomaticHistoryCursor? before,
  }) async {
    _automaticGatewayInput(
      receiptId,
      limit,
      before?.recordedAt,
      before?.requestId,
    );
    final result = await rpcMap(
      'admin_get_gateway_receipt_investigation_v3',
      params: {
        'p_receipt_id': receiptId,
        'p_limit': limit,
        'p_before_at': before?.recordedAt.toUtc().toIso8601String(),
        'p_before_request_id': before?.requestId,
      },
    );
    AdminAutomaticReceiptEvidence.parse(
      result,
      receiptId: receiptId,
      limit: limit,
      before: before,
    );
    return result;
  }

  @override
  Future<Map<String, dynamic>> automaticDeviceAttempts(
    String deviceId, {
    int limit = 20,
    AdminAutomaticDeviceCursor? before,
  }) async {
    _automaticGatewayInput(
      deviceId,
      limit,
      before?.issuedAt,
      before?.attemptId,
    );
    final result = await rpcMap(
      'admin_list_gateway_device_attempts_v3',
      params: {
        'p_device_id': deviceId,
        'p_limit': limit,
        'p_before_at': before?.issuedAt.toUtc().toIso8601String(),
        'p_before_attempt_id': before?.attemptId,
      },
    );
    AdminAutomaticDeviceEvidence.parse(
      result,
      deviceId: deviceId,
      limit: limit,
      before: before,
    );
    return result;
  }

  @override
  AdminRosterGateway openRosterImport() =>
      SupabaseAdminRosterGateway(_requireClient());

  @override
  Future<Map<String, dynamic>> prepareRosterImport(
    Map<String, dynamic> body,
  ) async {
    final response = await _withSession(
      (session) => _requireClient().functions.invoke(
        'prepare-roster-import',
        body: body,
        headers: {'Authorization': 'Bearer ${session.token}'},
      ),
    );
    final data = response.data;
    final decoded = data is String ? jsonDecode(data) : data;
    if (decoded is! Map) {
      throw StateError(
        'prepare-roster-import returned ${decoded.runtimeType}, expected map',
      );
    }
    final result = Map<String, dynamic>.from(decoded);
    final error = '${result['error'] ?? ''}'.trim();
    if (error.isNotEmpty) throw StateError(error);
    return result;
  }

  @override
  Future<AdminListResult> paymentReconciliationReviews(
    String? paymentId, {
    int limit = 25,
    int offset = 0,
  }) async {
    if (paymentId != null) _requireReconciliationUuid(paymentId);
    if (limit < 1 || limit > 100 || offset < 0 || offset > 100000) {
      throw const FormatException('Invalid reconciliation page.');
    }
    final scope = _captureReconciliationSession();
    final result = await rpcMap(
      'list_payment_reconciliations_v2',
      params: {'p_payment_id': paymentId, 'p_limit': limit, 'p_offset': offset},
    );
    _checkReconciliationSession(scope);
    final rows = result['rows'];
    if (result['total'] is! int || rows is! List) {
      throw const FormatException('Invalid evidence review response.');
    }
    for (final raw in rows) {
      if (raw is! Map || !_validReconciliationReview(raw, paymentId)) {
        throw const FormatException('Invalid evidence review response.');
      }
    }
    return AdminListResult.fromJson(
      result,
    ).validateWindow(limit: limit, offset: offset);
  }

  @override
  Future<Map<String, dynamic>> paymentReconciliationDetail(
    String reviewId, {
    required String paymentId,
  }) async {
    _requireReconciliationUuid(reviewId);
    _requireReconciliationUuid(paymentId);
    final scope = _captureReconciliationSession();
    final result = await rpcMap(
      'get_payment_reconciliation_v2',
      params: {'p_review_id': reviewId},
    );
    _checkReconciliationSession(scope);
    if (result['id'] != reviewId ||
        result['payment_id'] != paymentId ||
        result.containsKey('proposed_session_id') ||
        result.containsKey('approved_session_id') ||
        ['audit', 'journals', 'receiver_routes'].any(
          (key) =>
              result[key] is! List ||
              (result[key] as List).any((row) => row is! Map),
        )) {
      throw const FormatException('Invalid evidence lineage response.');
    }
    return result;
  }

  String _captureReconciliationSession() {
    final key = _reconciliationSessionKey(_requireClient().auth.currentSession);
    if (key == null) {
      throw const AdminReconciliationStepUpException(
        'session_changed',
        'Your sign-in changed. Reopen reconciliation and try again.',
      );
    }
    return key;
  }

  void _checkReconciliationSession(String expected) {
    if (_reconciliationSessionKey(_requireClient().auth.currentSession) !=
        expected) {
      throw const AdminReconciliationStepUpException(
        'session_changed',
        'Your sign-in changed. Reopen reconciliation and try again.',
      );
    }
  }

  @override
  Future<String> proposePaymentReconciliation(
    Map<String, dynamic> evidence,
  ) async {
    final scope = _captureReconciliationSession();
    final result = await _withSession(
      (session) => _requireClient()
          .rpc<dynamic>('propose_payment_reconciliation_v2', params: evidence)
          .retry(enabled: false)
          .setHeader('Authorization', 'Bearer ${session.token}'),
      reconciliation: true,
    );
    _checkReconciliationSession(scope);
    if (result is! String || !_reconciliationUuid.hasMatch(result)) {
      throw const FormatException(
        'Reconciliation proposal was not acknowledged.',
      );
    }
    return result;
  }

  @override
  Future<void> approvePaymentReconciliation(
    String reviewId,
    String reason,
  ) async {
    _requireReconciliationUuid(reviewId);
    if (reason.trim().length < 10 || reason.trim().length > 500) {
      throw const FormatException('Use a reason of 10 to 500 characters.');
    }
    final scope = _captureReconciliationSession();
    final result = await _withSession(
      (session) => _requireClient()
          .rpc<dynamic>(
            'approve_payment_reconciliation_v2',
            params: {'p_review_id': reviewId, 'p_reason': reason},
          )
          .retry(enabled: false)
          .setHeader('Authorization', 'Bearer ${session.token}'),
      reconciliation: true,
    );
    _checkReconciliationSession(scope);
    if (result != true) {
      throw const FormatException(
        'Reconciliation approval was not acknowledged.',
      );
    }
  }

  @override
  Future<AdminReconciliationFinalization> finalizePaymentReconciliation(
    String reviewId, {
    required String paymentId,
  }) async {
    _requireReconciliationUuid(reviewId);
    _requireReconciliationUuid(paymentId);
    final scope = _captureReconciliationSession();
    final response = await _withSession(
      (session) => _requireClient().functions.invoke(
        'reconciliation-finalize',
        body: {'review_id': reviewId},
        headers: {'Authorization': 'Bearer ${session.token}'},
      ),
      reconciliation: true,
    );
    _checkReconciliationSession(scope);
    final value = response.data;
    final decoded = value is String ? jsonDecode(value) : value;
    if (response.status != 200 || decoded is! Map) {
      throw StateError(
        'Reconciliation finalization could not be acknowledged.',
      );
    }
    return AdminReconciliationFinalization.fromJson(
      Map<String, dynamic>.from(decoded),
      reviewId: reviewId,
      paymentId: paymentId,
    );
  }

  @override
  Future<Map<String, dynamic>> rpcMap(
    String rpcName, {
    Map<String, dynamic>? params,
    bool automaticRetry = true,
  }) async {
    final response = await _withSession(
      (session) => _requireClient()
          .rpc<dynamic>(rpcName, params: params)
          // An uncertain reply requires an explicit operator decision. A
          // transport retry must never repeat a write or an audited reveal.
          .retry(enabled: automaticRetry)
          .setHeader('Authorization', 'Bearer ${session.token}'),
      reconciliation: const {
        'list_payment_reconciliations_v2',
        'get_payment_reconciliation_v2',
      }.contains(rpcName),
    );
    if (response == null) return const {};
    if (response is Map) return Map<String, dynamic>.from(response);
    throw StateError('$rpcName returned ${response.runtimeType}, expected map');
  }

  SupabaseClient _requireClient() {
    final client = _supabase;
    if (client == null) {
      throw StateError('Supabase is not configured for the admin app.');
    }
    return client;
  }

  String _normalizeAdminPhone(String phone) {
    return PhoneNormalizer.normalizeRwanda(phone);
  }

  bool _isLegacySlaSignatureError(PostgrestException error) {
    return error.code == 'PGRST202' ||
        error.code == '42883' ||
        (error.code == 'P0001' &&
            error.message.toLowerCase().startsWith(
              'unsupported admin queue sla key:',
            ));
  }

  bool _isMissingRuntimeConfigError(PostgrestException error) {
    return error.code == '42883' || error.code == 'PGRST202';
  }
}
