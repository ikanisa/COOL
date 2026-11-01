part of 'cloudflare_admin_notification_management_api.dart';

/// Bounded server observations. Neither a prepared job nor this readback
/// authorizes a transport action or asserts that a message was delivered.
class NotificationManagementMaterializationItem {
  NotificationManagementMaterializationItem._(Map<String, dynamic> row)
    : entryId = _id(row['entry_id']),
      paymentId = _id(row['payment_id']),
      status = row['status'] is String ? row['status'] as String : _invalid(),
      code = row['code'] as String?,
      resumeSafe = row['resume_safe'] == true,
      jobId = row['status'] == 'committed'
          ? _id(_map(row['receipt'])['job_id'])
          : null {
    switch (status) {
      case 'committed':
        _keys(row, {'entry_id', 'payment_id', 'status', 'receipt'});
        final receipt = _map(row['receipt']);
        _keys(receipt, {
          'contract_version',
          'scope',
          'delivery_confirmed',
          'provider_confirmation',
          'settlement_status',
          'job_id',
          'payment_id',
          'state',
          'body_sha256',
        });
        if (receipt['contract_version'] != 1 ||
            receipt['scope'] != 'assisted_sms_internal_record' ||
            receipt['delivery_confirmed'] != false ||
            receipt['provider_confirmation'] != false ||
            receipt['settlement_status'] != 'not_asserted' ||
            receipt['state'] != 'queued' ||
            _id(receipt['payment_id']) != paymentId) {
          _invalid();
        }
        _digest(receipt['body_sha256']);
      case 'blocked':
        _keys(row, {'entry_id', 'payment_id', 'status', 'code'});
        if (code == null) {
          _invalid();
        }
      case 'planned':
      case 'unknown':
        _keys(row, {'entry_id', 'payment_id', 'status', 'code', 'resume_safe'});
        _boolean(row['resume_safe']);
        if (status == 'planned' && (code != null || !resumeSafe)) _invalid();
        if (status == 'unknown' && code == null) _invalid();
      default:
        {
          _invalid();
        }
    }
    if (code != null && !RegExp(r'^[a-z][a-z0-9_]{0,79}$').hasMatch(code!)) {
      {
        _invalid();
      }
    }
  }
  final String entryId, paymentId, status;
  final String? code, jobId;
  final bool resumeSafe;
}

class NotificationManagementMaterializationReceipt
    extends NotificationManagementReceipt {
  NotificationManagementMaterializationReceipt._(Map<String, dynamic> row)
    : observed = _boolean(row['observed']),
      status = row['status'] is String ? row['status'] as String : _invalid(),
      collectionId = row['collection_id'] == null
          ? null
          : _id(row['collection_id']),
      publicSessionId = row['public_session_id'] == null
          ? null
          : _id(row['public_session_id']),
      plannedCount = row['planned_count'] == null
          ? null
          : _revision(row['planned_count'], maximum: 10),
      materializedCount = _revision(row['materialized_count'], maximum: 10),
      mayBeInFlight = _boolean(row['may_be_in_flight']),
      hasMoreObserved = row['has_more_observed'] == null
          ? null
          : _boolean(row['has_more_observed']),
      items = row['items'] is List
          ? List.unmodifiable(
              (row['items'] as List).map(
                (item) =>
                    NotificationManagementMaterializationItem._(_map(item)),
              ),
            )
          : _invalid(),
      super(_id(row['request_id'])) {
    _markers(row, 'bounded_receipt_sms_materialization', {
      'request_id',
      'observed',
      'status',
      'may_be_in_flight',
      'planned_count',
      'items',
      'materialized_jobs',
      'materialized_count',
      'blocked',
      'recorded_state_only',
      'may_send',
      'transport_started',
      'all_source_events_complete',
      if (observed) ...{
        'collection_id',
        'source_identity',
        'originating_session_id',
        'public_session_id',
        'recorded_at',
        'has_more_observed',
      },
    });
    if (row['recorded_state_only'] != true ||
        row['may_send'] != false ||
        row['transport_started'] != false ||
        row['all_source_events_complete'] != false ||
        row['materialized_jobs'] is! List ||
        items.length > 10 ||
        items.map((item) => item.entryId).toSet().length != items.length) {
      _invalid();
    }
    if (!observed) {
      if (status != 'not_recorded' ||
          !mayBeInFlight ||
          plannedCount != null ||
          items.isNotEmpty ||
          materializedCount != 0 ||
          row['blocked'] != null ||
          (row['materialized_jobs'] as List).isNotEmpty) {
        _invalid();
      }
      return;
    }
    _id(row['originating_session_id']);
    _timestamp(row['recorded_at']);
    if (collectionId == null ||
        publicSessionId == null ||
        hasMoreObserved == null ||
        row['source_identity'] != 'immutable_contribution_entry_id' ||
        plannedCount != items.length ||
        !{
          'bounded_pass',
          'partial_blocked',
          'unknown',
          'planned',
        }.contains(status)) {
      _invalid();
    }
    final committed = items
        .where((item) => item.status == 'committed')
        .toList();
    final blocked = items.where((item) => item.status == 'blocked').toList();
    final unknown = items.any((item) => item.status == 'unknown');
    final expectedStatus = blocked.isNotEmpty
        ? 'partial_blocked'
        : unknown
        ? 'unknown'
        : committed.length == items.length
        ? 'bounded_pass'
        : 'planned';
    if (status != expectedStatus ||
        mayBeInFlight != unknown ||
        materializedCount != committed.length ||
        (row['materialized_jobs'] as List).length != committed.length) {
      _invalid();
    }
    for (var i = 0; i < committed.length; i++) {
      final job = _map((row['materialized_jobs'] as List)[i]);
      final source = _map(
        (row['items'] as List).firstWhere(
          (item) => _map(item)['entry_id'] == committed[i].entryId,
        ),
      );
      if (_stable(job) != _stable(source['receipt'])) {
        _invalid();
      }
    }
    if (blocked.isEmpty) {
      if (row['blocked'] != null) {
        _invalid();
      }
    } else {
      final first = _map(row['blocked']);
      _keys(first, {'source_entry_id', 'code'});
      if (_id(first['source_entry_id']) != blocked.first.entryId ||
          first['code'] != blocked.first.code) {
        _invalid();
      }
    }
  }
  final bool observed, mayBeInFlight;
  final bool? hasMoreObserved;
  final String status;
  final String? collectionId, publicSessionId;
  final int? plannedCount;
  final int materializedCount;
  final List<NotificationManagementMaterializationItem> items;
  bool get resolved =>
      observed &&
      !mayBeInFlight &&
      {'bounded_pass', 'partial_blocked'}.contains(status);
  @override
  String get action => 'materialization';
}

extension NotificationManagementMaterializationApi
    on CloudflareAdminNotificationManagementApi {
  NotificationManagementOperation prepareMaterialization({
    required NotificationManagementPolicyState expected,
    required bool ownerConfirmation,
    int limit = 5,
    String? requestId,
  }) {
    _owned(expected._owner);
    if (!ownerConfirmation ||
        !expected.enabled ||
        !expected.collectionActive ||
        limit < 1 ||
        limit > 10) {
      throw ArgumentError(
        'Confirm the current enabled collection and a batch of one to ten jobs.',
      );
    }
    return _prepare(
      'materialization',
      expected.collectionId,
      'notification-operator/materialize',
      {'collection_id': expected.collectionId, 'limit': limit},
      requestId,
    );
  }

  Future<NotificationManagementMaterializationReceipt> _materialize(
    NotificationManagementOperation operation, {
    bool replay = false,
  }) => _dispatch(operation, 'materialization', (row) {
    final receipt = NotificationManagementMaterializationReceipt._(row);
    _match(operation, receipt);
    return receipt;
  }, replay: replay);

  Future<NotificationManagementMaterializationReceipt> materialize(
    NotificationManagementOperation operation,
  ) => _materialize(operation);

  Future<NotificationManagementMaterializationReceipt> resumeMaterialization(
    NotificationManagementOperation original,
  ) => _materialize(original, replay: true);

  Future<NotificationManagementMaterializationReceipt> getMaterialization(
    String requestId, {
    NotificationManagementOperation? originalOperation,
  }) async {
    final rid = _id(requestId);
    if (originalOperation != null) {
      _owned(originalOperation._owner);
      if (originalOperation.action != 'materialization' ||
          originalOperation.requestId != rid ||
          originalOperation._fence != _fence) {
        throw ArgumentError(
          'Use the original batch under its original authority.',
        );
      }
    }
    final receipt = NotificationManagementMaterializationReceipt._(
      await _request('notification-operator/materialize/$rid'),
    );
    if (receipt.requestId != rid ||
        receipt.observed &&
            receipt.publicSessionId != _id(session.user?.sessionId)) {
      _invalid();
    }
    if (originalOperation != null) _match(originalOperation, receipt);
    return receipt;
  }
}
