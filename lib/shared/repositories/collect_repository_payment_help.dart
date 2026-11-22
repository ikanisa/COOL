part of 'collect_repository.dart';

/// Owns payment-help persistence and the original request's readback. A support
/// receipt carries no authority to update the displayed payment or balance.
mixin _CollectPaymentHelp on StateNotifier<CollectState>
    implements MemberPaymentRepository {
  CollectCloudflareClient? get _backend;
  PaymentHelpPendingStore get _paymentHelpPendingStore;
  Uuid get _uuid;
  CollectProfile _requireProfile();
  PaymentIntentModel intentById(String id);
  _CollectSessionFence _captureSession();
  void _requireCurrentMemberSession(
    _CollectSessionFence session,
    String profileId,
  );

  final _inFlightPaymentHelp =
      <(String, int, String, String), Future<PaymentHelpCheckpoint>>{};

  @override
  Future<PaymentHelpCheckpoint?> paymentHelpForIntent(String intentId) async {
    final profile = _requireProfile();
    final session = _captureSession();
    void current() => _requireCurrentMemberSession(session, profile.id);
    current();
    final intent = intentById(intentId);
    _paymentHelpPendingStore.bindOwner(profile.id);
    final record = await _paymentHelpPendingStore.read(
      ownerId: profile.id,
      collectionId: intent.collectionId,
      intentId: intentId,
    );
    current();
    return record;
  }

  /// Save first, then send the exact first command. A replacement sign-in reads
  /// the actor-scoped status before retrying; an absent snapshot never grants a
  /// fresh key or body. The old session may still commit after that read.
  @override
  Future<PaymentHelpCheckpoint> requestPaymentHelp({
    required String intentId,
    String? providerReference,
    String? note,
  }) async {
    final profile = _requireProfile();
    final session = _captureSession();
    _requireCurrentMemberSession(session, profile.id);
    final intent = intentById(intentId);
    final reference = providerReference?.trim();
    final evidence = note?.trim();
    final candidate = PaymentHelpCheckpoint(
      ownerId: profile.id,
      collectionId: intent.collectionId,
      intentId: intentId,
      requestId: _uuid.v5(
        Namespace.url.value,
        'collect.payment-help.v1:${profile.id}:$intentId',
      ),
      reference: reference?.isEmpty == true ? null : reference,
      note: evidence?.isEmpty == true ? null : evidence,
    );
    final key = (profile.id, session.generation, intent.collectionId, intentId);
    return _inFlightPaymentHelp.putIfAbsent(key, () async {
      try {
        return await _sendOriginalPaymentHelp(candidate, session);
      } finally {
        _inFlightPaymentHelp.remove(key);
      }
    });
  }

  Future<PaymentHelpCheckpoint> _sendOriginalPaymentHelp(
    PaymentHelpCheckpoint candidate,
    _CollectSessionFence session,
  ) async {
    void current() => _requireCurrentMemberSession(session, candidate.ownerId);
    current();
    _paymentHelpPendingStore.bindOwner(candidate.ownerId);
    final (:record, :created) = await _paymentHelpPendingStore.retainOriginal(
      candidate,
    );
    current();
    if (record.received) return record;
    Future<PaymentHelpCheckpoint> acknowledge() async {
      current();
      final result = await _paymentHelpPendingStore.acknowledge(record);
      current();
      return result;
    }

    if (!created) {
      if (await paymentHelpRequestReceived(record)) return acknowledge();
      current();
    }
    try {
      await createPaymentSupportReview(
        collectionId: record.collectionId,
        intentId: record.intentId,
        requestId: record.requestId,
        providerReference: record.reference,
        note: record.note,
      );
    } catch (_) {
      current();
      // Includes a late old-session commit racing the new-session retry. A
      // failed/unknown status read is never interpreted as absence or receipt.
      try {
        if (await paymentHelpRequestReceived(record)) return acknowledge();
      } catch (_) {
        current();
      }
      rethrow;
    }
    return acknowledge();
  }

  Future<bool> paymentHelpRequestReceived(PaymentHelpCheckpoint record) async {
    final profile = _requireProfile();
    final session = _captureSession();
    void current() => _requireCurrentMemberSession(session, profile.id);
    current();
    final backend = _backend;
    if (backend == null ||
        profile.id != record.ownerId ||
        intentById(record.intentId).collectionId != record.collectionId) {
      throw StateError('Connect to Collect to check this request.');
    }
    final result = await backend
        .rpc<dynamic>(
          'get_current_member_payment_review_request_v1',
          params: {
            'p_request_id': record.requestId,
            'p_collection_id': record.collectionId,
            'p_intent_id': record.intentId,
          },
        )
        .setHeader('Authorization', 'Bearer ${session.accessToken}')
        .retry(enabled: false);
    current();
    return _verifiedPaymentHelpReceipt(
      result,
      requestId: record.requestId,
      collectionId: record.collectionId,
      intentId: record.intentId,
      allowAbsent: true,
    );
  }

  Future<String> createPaymentSupportReview({
    required String collectionId,
    required String intentId,
    required String requestId,
    String? providerReference,
    String? note,
  }) async {
    final profile = _requireProfile();
    final backend = _backend;
    if (backend == null || backend.auth.currentUser == null) {
      throw StateError('Connect to Collect to request a payment check.');
    }
    final session = _captureSession();
    void current() => _requireCurrentMemberSession(session, profile.id);
    current();
    final intent = intentById(intentId);
    if (intent.collectionId != collectionId) {
      throw const FormatException('Payment request group is invalid.');
    }
    final reference = providerReference?.trim();
    final evidence = note?.trim();
    if (!RegExp(
          r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$',
          caseSensitive: false,
        ).hasMatch(requestId) ||
        (reference?.length ?? 0) > 160 ||
        (evidence?.length ?? 0) > 2000) {
      throw const FormatException('Payment check details are invalid.');
    }
    final result = await backend
        .rpc<dynamic>(
          'create_mobile_support_request',
          params: {
            'p_kind': 'payment_review',
            'p_collection_id': collectionId,
            'p_intent_id': intentId,
            'p_request_id': requestId,
            'p_provider_reference': reference?.isEmpty == true
                ? null
                : reference,
            'p_note': evidence?.isEmpty == true ? null : evidence,
          },
        )
        .setHeader('Authorization', 'Bearer ${session.accessToken}')
        .retry(enabled: false);
    current();
    _verifiedPaymentHelpReceipt(
      result,
      requestId: requestId,
      collectionId: collectionId,
      intentId: intentId,
      allowAbsent: false,
    );
    return requestId;
  }

  bool _verifiedPaymentHelpReceipt(
    Object? result, {
    required String requestId,
    required String collectionId,
    required String intentId,
    required bool allowAbsent,
  }) {
    if (result is! Map ||
        result['id'] != requestId ||
        (result['status'] != 'received' &&
            !(allowAbsent && result['status'] == 'absent')) ||
        result['collection_id'] != collectionId ||
        result['intent_id'] != intentId ||
        exactJsonInteger(
              result['financial_effects'],
              field: 'Payment check financial effects',
              minimum: 0,
            ) !=
            0) {
      throw const FormatException('Payment check could not be verified.');
    }
    return result['status'] == 'received';
  }
}
