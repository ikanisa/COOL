import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import 'admin_account_api.dart';
import 'cloudflare_admin_session.dart';

final _uuid = RegExp(
  r'^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
  caseSensitive: false,
);
final _hash = RegExp(r'^[a-f0-9]{64}$');
const _marker = {
  'contract_version',
  'scope',
  'delivery_confirmed',
  'provider_confirmation',
  'settlement_status',
};
Never _invalid() => throw const FormatException(
  'The assisted SMS response could not be verified.',
);
String _id(Object? value) =>
    value is String && _uuid.hasMatch(value) ? value.toLowerCase() : _invalid();
String _digest(Object? value) =>
    value is String && _hash.hasMatch(value) ? value : _invalid();
int _integer(
  Object? value, {
  int minimum = 0,
  int maximum = 9007199254740991,
}) => value is int && value >= minimum && value <= maximum ? value : _invalid();
String _text(Object? value, {int maximum = 4096}) =>
    value is String && value.isNotEmpty && value.length <= maximum
    ? value
    : _invalid();
Map<String, dynamic> _map(Object? value) {
  if (value is! Map || !value.keys.every((key) => key is String)) _invalid();
  return Map<String, dynamic>.from(value);
}

void _keys(
  Map<String, dynamic> row,
  Set<String> required, [
  Set<String> optional = const {},
]) {
  if (!required.every(row.containsKey) ||
      row.keys.any(
        (key) => !required.contains(key) && !optional.contains(key),
      )) {
    _invalid();
  }
}

DateTime _timestamp(Object? value) {
  if (value is! String ||
      !RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$').hasMatch(value)) {
    _invalid();
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || parsed.toUtc().toIso8601String() != value) _invalid();
  return parsed;
}

void _receiptKeys(
  Map<String, dynamic> row,
  Set<String> fields, [
  Set<String> optional = const {},
]) {
  _keys(row, {..._marker, ...fields}, optional);
  if (row['contract_version'] is! int ||
      row['contract_version'] != 1 ||
      row['scope'] != 'assisted_sms_internal_record' ||
      row['delivery_confirmed'] != false ||
      row['provider_confirmation'] != false ||
      row['settlement_status'] != 'not_asserted' ||
      (row.containsKey('replay') && row['replay'] is! bool)) {
    _invalid();
  }
}

enum NotificationOperatorJobState {
  queued('queued'),
  claimed('claimed'),
  sendStarted('send_started'),
  uncertain('uncertain');

  const NotificationOperatorJobState(this.wireValue);
  final String wireValue;
  static NotificationOperatorJobState _parse(Object? value) =>
      values.firstWhere((state) => state.wireValue == value, orElse: _invalid);
}

enum NotificationOperatorObservation {
  observedSent('observed_sent'),
  failedNoSend('failed_no_send'),
  uncertain('uncertain');

  const NotificationOperatorObservation(this.wireValue);
  final String wireValue;
  static NotificationOperatorObservation _parse(Object? value) =>
      values.firstWhere((state) => state.wireValue == value, orElse: _invalid);
}

class NotificationOperatorCursor {
  NotificationOperatorCursor._(this.afterCreatedAt, this.afterJobId);
  final DateTime afterCreatedAt;
  final String afterJobId;
  static NotificationOperatorCursor _parse(Object? raw) {
    final row = _map(raw);
    _keys(row, {'after_created_at', 'after_job_id'});
    return NotificationOperatorCursor._(
      _timestamp(row['after_created_at']),
      _id(row['after_job_id']),
    );
  }
}

class NotificationOperatorPendingJob {
  NotificationOperatorPendingJob._(this._owner, Map<String, dynamic> row)
    : id = _id(row['id']),
      paymentId = _id(row['payment_id']),
      state = NotificationOperatorJobState._parse(row['state']),
      createdAt = _timestamp(row['created_at']),
      fence = _integer(row['fence'], maximum: 999999999),
      attemptId = row['attempt_id'] == null ? null : _id(row['attempt_id']) {
    _keys(row, {
      'id',
      'payment_id',
      'state',
      'created_at',
      'fence',
      'attempt_id',
    });
    if ((state == NotificationOperatorJobState.sendStarted ||
            state == NotificationOperatorJobState.uncertain) !=
        (attemptId != null)) {
      _invalid();
    }
    if (state != NotificationOperatorJobState.queued && fence < 1) _invalid();
  }
  final Object _owner;
  final String id, paymentId;
  final NotificationOperatorJobState state;
  final DateTime createdAt;
  final int fence;
  final String? attemptId;
}

class NotificationOperatorPendingPage {
  NotificationOperatorPendingPage._(this.items, this.nextCursor);
  final List<NotificationOperatorPendingJob> items;
  final NotificationOperatorCursor? nextCursor;
}

/// Exact original command held in memory. It has no persistence/Map adapter.
/// A dispatched object cannot be executed again; reconcile its requestId first.
class NotificationOperatorOperation {
  NotificationOperatorOperation._(
    this._owner,
    this._fence,
    this.action,
    this.requestId,
    this.resourceId,
    Map<String, dynamic> body,
    this._claim,
    this._content,
    this._confirmation,
  ) : _body = Map.unmodifiable(body);
  final Object _owner;
  final ({int epoch, Object? key}) _fence;
  final String action, requestId, resourceId;
  final Map<String, dynamic> _body;
  final NotificationOperatorClaim? _claim;
  final NotificationOperatorContent? _content;
  final NotificationOperatorConfirmation? _confirmation;
  bool _dispatched = false;
  bool get dispatched => _dispatched;
}

class NotificationOperatorRequestException
    extends CloudflareAdminRequestException {
  NotificationOperatorRequestException({
    required this.operation,
    required this.cause,
    required super.outcomeUnknown,
  }) : super(
         outcomeUnknown
             ? 'The result is unknown. Check the original operation before continuing.'
             : 'The assisted SMS request was not confirmed. Refresh its status.',
         statusCode: cause is CloudflareAdminRequestException
             ? cause.statusCode
             : null,
         code: cause is CloudflareAdminRequestException ? cause.code : null,
       );
  final NotificationOperatorOperation operation;
  final Object cause;
}

sealed class NotificationOperatorReceipt {
  const NotificationOperatorReceipt(this.jobId);
  final String? jobId;
  String get action;
}

class NotificationOperatorClaim extends NotificationOperatorReceipt {
  NotificationOperatorClaim._(this._owner, Map<String, dynamic> row)
    : claimToken = _id(row['claim_token']),
      fenceVersion = _integer(
        row['fence_version'],
        minimum: 1,
        maximum: 999999998,
      ),
      workerId = _text(row['worker_id'], maximum: 80),
      claimExpiresAt = _timestamp(row['claim_expires_at']),
      originatingSessionId = _id(row['originating_session_id']),
      publicSessionId = _id(row['public_session_id']),
      super(_id(row['job_id'])) {
    _receiptKeys(
      row,
      {
        'job_id',
        'claim_token',
        'fence_version',
        'worker_id',
        'claim_expires_at',
        'originating_session_id',
        'public_session_id',
      },
      {'replay'},
    );
    if (!RegExp(r'^[A-Za-z0-9._:-]{3,80}$').hasMatch(workerId)) _invalid();
  }
  final Object _owner;
  final String claimToken, workerId, originatingSessionId, publicSessionId;
  final int fenceVersion;
  final DateTime claimExpiresAt;
  @override
  String get action => 'claim';
}

class NotificationOperatorContent {
  NotificationOperatorContent._(
    this._owner,
    this._claim,
    Map<String, dynamic> row,
  ) : jobId = _id(row['job_id']),
      claimToken = _id(row['claim_token']),
      fenceVersion = _integer(
        row['fence_version'],
        minimum: 1,
        maximum: 999999998,
      ),
      destinationE164 = _text(row['destination_e164'], maximum: 13),
      destinationSha256 = _digest(row['destination_sha256']),
      destinationRevision = _integer(row['destination_revision'], minimum: 1),
      messageBody = _text(row['message_body']),
      bodySha256 = _digest(row['body_sha256']),
      paymentId = _id(row['payment_id']),
      templateKey = _text(row['template_key'], maximum: 100),
      claimExpiresAt = _timestamp(row['claim_expires_at']) {
    _receiptKeys(row, {
      'job_id',
      'claim_token',
      'fence_version',
      'destination_e164',
      'destination_sha256',
      'destination_revision',
      'message_body',
      'body_sha256',
      'payment_id',
      'template_key',
      'claim_expires_at',
    });
    if (templateKey != 'collect.recorded_contribution.v1' ||
        !RegExp(r'^\+2507[2389][0-9]{7}$').hasMatch(destinationE164) ||
        sha256.convert(utf8.encode(messageBody)).toString() != bodySha256 ||
        sha256.convert(utf8.encode(destinationE164)).toString() !=
            destinationSha256) {
      _invalid();
    }
  }
  final Object _owner;
  final NotificationOperatorClaim _claim;
  final String jobId,
      claimToken,
      destinationE164,
      destinationSha256,
      messageBody,
      bodySha256,
      paymentId,
      templateKey;
  final int fenceVersion, destinationRevision;
  final DateTime claimExpiresAt;
}

class NotificationOperatorConfirmation extends NotificationOperatorReceipt {
  NotificationOperatorConfirmation._(this._owner, Map<String, dynamic> row)
    : confirmationId = _id(row['confirmation_id']),
      claimToken = _id(row['claim_token']),
      fenceVersion = _integer(
        row['fence_version'],
        minimum: 1,
        maximum: 999999998,
      ),
      bodySha256 = _digest(row['body_sha256']),
      destinationSha256 = _digest(row['destination_sha256']),
      destinationRevision = _integer(row['destination_revision'], minimum: 1),
      expiresAt = _timestamp(row['expires_at']),
      originatingSessionId = _id(row['originating_session_id']),
      publicSessionId = _id(row['public_session_id']),
      super(_id(row['job_id'])) {
    _receiptKeys(
      row,
      {
        'job_id',
        'confirmation_id',
        'claim_token',
        'fence_version',
        'body_sha256',
        'destination_sha256',
        'destination_revision',
        'expires_at',
        'originating_session_id',
        'public_session_id',
      },
      {'replay'},
    );
  }
  final Object _owner;
  final String confirmationId,
      claimToken,
      bodySha256,
      destinationSha256,
      originatingSessionId,
      publicSessionId;
  final int fenceVersion, destinationRevision;
  final DateTime expiresAt;
  @override
  String get action => 'confirm';
}

/// An acknowledged first response is usable at most once under the same
/// authority. This object cannot be reconstructed from a recovered receipt.
class NotificationOperatorSendPermit {
  NotificationOperatorSendPermit._(
    this._api,
    this.attemptId,
    this.jobId,
    this._expiresAt,
  );
  final CloudflareAdminNotificationOperatorApi _api;
  final String attemptId, jobId;
  final DateTime _expiresAt;
  bool _consumed = false;
  bool get isUsable =>
      !_consumed && _api.canManage && _expiresAt.isAfter(_api._now());
  bool consume() {
    final allowed = isUsable;
    _consumed = true;
    return allowed;
  }
}

class NotificationOperatorSendStart extends NotificationOperatorReceipt {
  NotificationOperatorSendStart._(Map<String, dynamic> row, {this.permit})
    : attemptId = _id(row['attempt_id']),
      confirmationId = _id(row['confirmation_id']),
      claimToken = _id(row['claim_token']),
      fenceVersion = _integer(
        row['fence_version'],
        minimum: 1,
        maximum: 999999998,
      ),
      originatingSessionId = _id(row['originating_session_id']),
      publicSessionId = _id(row['public_session_id']),
      replay = row['replay'] as bool?,
      acknowledgement = row['acknowledgement'] as String?,
      super(_id(row['job_id'])) {
    _receiptKeys(
      row,
      {
        'attempt_id',
        'job_id',
        'confirmation_id',
        'claim_token',
        'fence_version',
        'state',
        'originating_session_id',
        'public_session_id',
      },
      {'replay', 'may_send', 'acknowledgement'},
    );
    if (row['state'] != 'send_started' ||
        (row.containsKey('may_send') && row['may_send'] is! bool) ||
        (row.containsKey('acknowledgement') && acknowledgement == null)) {
      _invalid();
    }
  }
  final String attemptId,
      confirmationId,
      claimToken,
      originatingSessionId,
      publicSessionId;
  final int fenceVersion;
  final bool? replay;
  final String? acknowledgement;
  final NotificationOperatorSendPermit? permit;
  @override
  String get action => 'record_send_start';
}

class NotificationOperatorRelease extends NotificationOperatorReceipt {
  NotificationOperatorRelease._(Map<String, dynamic> row)
    : fenceVersion = _integer(
        row['fence_version'],
        minimum: 2,
        maximum: 999999999,
      ),
      super(_id(row['job_id'])) {
    _receiptKeys(row, {'job_id', 'state', 'fence_version'});
    if (row['state'] != 'queued') _invalid();
  }
  final int fenceVersion;
  @override
  String get action => 'release_claim';
}

class NotificationOperatorOutcome extends NotificationOperatorReceipt {
  NotificationOperatorOutcome._(Map<String, dynamic> row)
    : attemptId = _id(row['attempt_id']),
      observation = NotificationOperatorObservation._parse(row['observation']),
      evidenceReferenceSha256 = _digest(row['evidence_reference_sha256']),
      super(null) {
    _receiptKeys(row, {
      'attempt_id',
      'observation',
      'evidence_reference_sha256',
      'may_send',
    });
    if (row['may_send'] != false) _invalid();
  }
  final String attemptId, evidenceReferenceSha256;
  final NotificationOperatorObservation observation;
  @override
  String get action => 'record_outcome';
}

/// The internal producer can leave a queued receipt visible to get_operation.
/// There is deliberately no corresponding client enqueue command.
class NotificationOperatorQueuedReceipt extends NotificationOperatorReceipt {
  NotificationOperatorQueuedReceipt._(Map<String, dynamic> row)
    : paymentId = _id(row['payment_id']),
      bodySha256 = _digest(row['body_sha256']),
      super(_id(row['job_id'])) {
    _receiptKeys(row, {'job_id', 'payment_id', 'state', 'body_sha256'});
    if (row['state'] != 'queued') _invalid();
  }
  final String paymentId, bodySha256;
  @override
  String get action => 'enqueue';
}

class NotificationOperatorResolution {
  NotificationOperatorResolution._(this.requestId, this.observed, this.receipt);
  final String requestId;
  final bool observed;
  final NotificationOperatorReceipt? receipt;
}

/// Private client for the proposed Cloudflare contract v1. The service remains
/// authoritative for current role, principal, original session and verification.
class CloudflareAdminNotificationOperatorApi {
  CloudflareAdminNotificationOperatorApi(
    this.session, {
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       _fence = session.authorityFence;
  final CloudflareAdminSession session;
  final DateTime Function() _now;
  final ({int epoch, Object? key}) _fence;
  final Object _owner = Object();
  final Set<String> _preparedRequestIds = {};
  final Set<String> _attemptedConfirmationIds = {};
  bool get authorityCurrent =>
      session.mounted && session.authorityFence == _fence;
  bool _allowed(String capability) {
    final user = session.user, now = _now();
    return authorityCurrent &&
        !session.logoutUnconfirmed &&
        user != null &&
        user.expiresAt.isAfter(now) &&
        user.permissions.contains(capability) &&
        user.principalId != null &&
        user.hasRecentSensitiveVerification(now: now);
  }

  bool get canRead => _allowed('assisted_sms.read');
  bool get canManage => _allowed('assisted_sms.manage');
  void _guard({bool read = false}) {
    if (!(read ? canRead : canManage)) {
      throw AdminAccountException(
        session.user?.usesEmailVerification == true
            ? 'Reopen assisted SMS with current access and recent email verification.'
            : 'Reopen assisted SMS with current access and fresh authenticator verification.',
      );
    }
  }

  void _owned(Object owner) {
    _guard();
    if (!identical(_owner, owner)) {
      throw const AdminAccountException(
        'Reload the current assisted SMS claim.',
      );
    }
  }

  void _live(DateTime expiry) {
    if (!expiry.isAfter(_now())) {
      throw const AdminAccountException(
        'This assisted SMS claim expired. Refresh its status.',
      );
    }
  }

  String _requestId(String? value) => _id(value ?? const Uuid().v4());
  Map<String, dynamic> _claimBody(NotificationOperatorClaim claim) => {
    'job_id': claim.jobId,
    'claim_token': claim.claimToken,
    'fence_version': claim.fenceVersion,
  };
  NotificationOperatorOperation _prepare(
    String action,
    String requestId,
    String resourceId,
    Map<String, dynamic> body, {
    NotificationOperatorClaim? claim,
    NotificationOperatorContent? content,
    NotificationOperatorConfirmation? confirmation,
  }) {
    _guard();
    if (!_preparedRequestIds.add(requestId)) {
      throw StateError(
        'Keep the original operation object and check its status.',
      );
    }
    return NotificationOperatorOperation._(
      _owner,
      _fence,
      action,
      requestId,
      resourceId,
      {'action': action, ...body, 'request_id': requestId},
      claim,
      content,
      confirmation,
    );
  }

  Future<Map<String, dynamic>> _request(
    Map<String, dynamic> body, {
    bool read = false,
  }) async {
    _guard(read: read);
    final result = await session.request(
      'notification-operator',
      body: body,
      authenticated: true,
    );
    _guard(read: read);
    _keys(result, {'ok', 'result'});
    if (result['ok'] != true) _invalid();
    return _map(result['result']);
  }

  Future<T> _mutate<T>(
    NotificationOperatorOperation operation,
    String action,
    T Function(Map<String, dynamic>) parse,
  ) async {
    _owned(operation._owner);
    if (operation.action != action || operation._fence != _fence) {
      throw ArgumentError(
        'The original assisted SMS operation does not match this action.',
      );
    }
    if (operation._dispatched) {
      throw StateError(
        'Check the original operation before any deliberate resume.',
      );
    }
    if (operation._claim case final claim?) _live(claim.claimExpiresAt);
    if (operation._content case final content?) _live(content.claimExpiresAt);
    if (operation._confirmation case final confirmation?) {
      _live(confirmation.expiresAt);
    }
    if (action == 'record_send_start' &&
        !_attemptedConfirmationIds.add(
          operation._confirmation!.confirmationId,
        )) {
      throw StateError(
        'This confirmation already has a send-start attempt. Check its original operation.',
      );
    }
    operation._dispatched = true;
    try {
      return parse(await _request(operation._body));
    } catch (error) {
      throw NotificationOperatorRequestException(
        operation: operation,
        cause: error,
        // The server can commit a receipt and then lose authority before its
        // response. Even a 403 cannot establish that no mutation committed.
        outcomeUnknown: true,
      );
    }
  }

  Future<NotificationOperatorPendingPage> listPending({
    int limit = 20,
    NotificationOperatorCursor? cursor,
  }) async {
    _integer(limit, minimum: 1, maximum: 50);
    final row = await _request({
      'action': 'list_pending',
      'limit': limit,
      if (cursor != null) ...{
        'after_created_at': cursor.afterCreatedAt.toUtc().toIso8601String(),
        'after_job_id': cursor.afterJobId,
      },
    }, read: true);
    _receiptKeys(row, {'items', 'next_cursor'});
    if (row['items'] is! List || (row['items'] as List).length > limit) {
      _invalid();
    }
    final items = (row['items'] as List)
        .map((item) => NotificationOperatorPendingJob._(_owner, _map(item)))
        .toList();
    final ids = <String>{};
    NotificationOperatorPendingJob? previous;
    for (final item in items) {
      if (!ids.add(item.id)) _invalid();
      final previousTime = previous?.createdAt ?? cursor?.afterCreatedAt;
      final previousId = previous?.id ?? cursor?.afterJobId;
      if (previousTime != null &&
          (item.createdAt.isBefore(previousTime) ||
              item.createdAt == previousTime &&
                  item.id.compareTo(previousId!) <= 0)) {
        _invalid();
      }
      previous = item;
    }
    final next = row['next_cursor'] == null
        ? null
        : NotificationOperatorCursor._parse(row['next_cursor']);
    if (next != null &&
        (items.length != limit ||
            next.afterJobId != items.last.id ||
            next.afterCreatedAt != items.last.createdAt)) {
      _invalid();
    }
    return NotificationOperatorPendingPage._(List.unmodifiable(items), next);
  }

  NotificationOperatorOperation prepareClaim(
    NotificationOperatorPendingJob job, {
    required String workerId,
    String? requestId,
  }) {
    _owned(job._owner);
    if (!RegExp(r'^[A-Za-z0-9._:-]{3,80}$').hasMatch(workerId) ||
        job.fence > 999999997 ||
        (job.state != NotificationOperatorJobState.queued &&
            job.state != NotificationOperatorJobState.claimed)) {
      throw ArgumentError('This job or worker cannot be claimed.');
    }
    return _prepare('claim', _requestId(requestId), job.id, {
      'job_id': job.id,
      'worker_id': workerId,
      'expected_fence': job.fence,
    });
  }

  Future<NotificationOperatorClaim> claim(
    NotificationOperatorOperation operation,
  ) => _mutate(operation, 'claim', (row) {
    final claim = NotificationOperatorClaim._(_owner, row);
    if (claim.jobId != operation.resourceId ||
        claim.workerId != operation._body['worker_id'] ||
        claim.fenceVersion != (operation._body['expected_fence'] as int) + 1 ||
        claim.publicSessionId != session.user?.sessionId) {
      _invalid();
    }
    _live(claim.claimExpiresAt);
    return claim;
  });

  Future<NotificationOperatorContent> getClaimed(
    NotificationOperatorClaim claim,
  ) async {
    _owned(claim._owner);
    _live(claim.claimExpiresAt);
    final content = NotificationOperatorContent._(
      _owner,
      claim,
      await _request({'action': 'get_claimed', ..._claimBody(claim)}),
    );
    if (content.jobId != claim.jobId ||
        content.claimToken != claim.claimToken ||
        content.fenceVersion != claim.fenceVersion ||
        content.claimExpiresAt != claim.claimExpiresAt) {
      _invalid();
    }
    _live(content.claimExpiresAt);
    return content;
  }

  NotificationOperatorOperation prepareConfirm(
    NotificationOperatorContent content, {
    required bool userConfirmation,
    String? requestId,
    String? confirmationId,
  }) {
    _owned(content._owner);
    _live(content.claimExpiresAt);
    if (!userConfirmation) {
      throw ArgumentError('Explicit exact-content confirmation is required.');
    }
    return _prepare('confirm', _requestId(requestId), content.jobId, {
      'job_id': content.jobId,
      'claim_token': content.claimToken,
      'fence_version': content.fenceVersion,
      'confirmation_id': _requestId(confirmationId),
      'body_sha256': content.bodySha256,
      'destination_sha256': content.destinationSha256,
      'destination_revision': content.destinationRevision,
      'user_confirmation': true,
    }, content: content);
  }

  Future<NotificationOperatorConfirmation> confirm(
    NotificationOperatorOperation operation,
  ) => _mutate(operation, 'confirm', (row) {
    final confirmation = NotificationOperatorConfirmation._(_owner, row);
    _matches(operation, confirmation);
    if (confirmation.publicSessionId != session.user?.sessionId ||
        confirmation.originatingSessionId !=
            operation._content!._claim.originatingSessionId ||
        confirmation.expiresAt.isAfter(operation._content.claimExpiresAt)) {
      _invalid();
    }
    _live(confirmation.expiresAt);
    return confirmation;
  });

  NotificationOperatorOperation prepareSendStart(
    NotificationOperatorConfirmation confirmation, {
    String? requestId,
  }) {
    _owned(confirmation._owner);
    _live(confirmation.expiresAt);
    return _prepare(
      'record_send_start',
      _requestId(requestId),
      confirmation.jobId!,
      {
        'job_id': confirmation.jobId,
        'claim_token': confirmation.claimToken,
        'fence_version': confirmation.fenceVersion,
        'confirmation_id': confirmation.confirmationId,
      },
      confirmation: confirmation,
    );
  }

  Future<NotificationOperatorSendStart> recordSendStart(
    NotificationOperatorOperation operation,
  ) => _mutate(operation, 'record_send_start', (row) {
    final start = NotificationOperatorSendStart._(row);
    _matches(operation, start);
    final confirmation = operation._confirmation!;
    if (start.originatingSessionId != confirmation.originatingSessionId ||
        start.publicSessionId != confirmation.publicSessionId) {
      _invalid();
    }
    if (row['may_send'] == true) {
      if (start.replay != false ||
          start.acknowledgement != 'first_committed_response_only') {
        _invalid();
      }
      _guard();
      _live(confirmation.expiresAt);
      return NotificationOperatorSendStart._(
        row,
        permit: NotificationOperatorSendPermit._(
          this,
          start.attemptId,
          start.jobId!,
          confirmation.expiresAt,
        ),
      );
    }
    if (row['may_send'] != false ||
        start.replay != true ||
        !const {
          'recorded_start_permit_not_reissued',
          'concurrent_start_observed_permit_not_reissued',
          'start_observed_after_unknown_reply_permit_not_reissued',
        }.contains(start.acknowledgement)) {
      _invalid();
    }
    return start;
  });

  NotificationOperatorOperation prepareRelease(
    NotificationOperatorClaim claim, {
    String? requestId,
  }) {
    _owned(claim._owner);
    _live(claim.claimExpiresAt);
    return _prepare(
      'release_claim',
      _requestId(requestId),
      claim.jobId!,
      _claimBody(claim),
      claim: claim,
    );
  }

  Future<NotificationOperatorRelease> releaseClaim(
    NotificationOperatorOperation operation,
  ) => _mutate(operation, 'release_claim', (row) {
    final release = NotificationOperatorRelease._(row);
    _matches(operation, release);
    return release;
  });
  NotificationOperatorOperation prepareOutcome({
    required String attemptId,
    required NotificationOperatorObservation observation,
    required String evidenceReferenceSha256,
    String? requestId,
  }) => _prepare('record_outcome', _requestId(requestId), _id(attemptId), {
    'attempt_id': _id(attemptId),
    'observation': observation.wireValue,
    'evidence_reference_sha256': _digest(evidenceReferenceSha256),
  });
  Future<NotificationOperatorOutcome> recordOutcome(
    NotificationOperatorOperation operation,
  ) => _mutate(operation, 'record_outcome', (row) {
    final outcome = NotificationOperatorOutcome._(row);
    _matches(operation, outcome);
    return outcome;
  });

  Future<NotificationOperatorResolution> getOperation(
    String requestId, {
    NotificationOperatorOperation? originalOperation,
  }) async {
    final normalizedRequestId = _id(requestId);
    if (originalOperation != null &&
        originalOperation.requestId != normalizedRequestId) {
      throw ArgumentError('Use the exact original operation reference.');
    }
    final row = await _request({
      'action': 'get_operation',
      'request_id': normalizedRequestId,
    });
    _receiptKeys(row, {'request_id', 'observed', 'receipt', 'may_send'});
    if (_id(row['request_id']) != normalizedRequestId ||
        row['observed'] is! bool ||
        row['may_send'] != false ||
        (row['observed'] == false) != (row['receipt'] == null)) {
      _invalid();
    }
    final receipt = row['receipt'] == null
        ? null
        : _recovered(_map(row['receipt']));
    if (receipt != null && originalOperation != null) {
      _matches(originalOperation, receipt);
    }
    return NotificationOperatorResolution._(
      normalizedRequestId,
      row['observed'] as bool,
      receipt,
    );
  }

  NotificationOperatorReceipt _recovered(Map<String, dynamic> row) {
    // Stored receipts must never contain transient acknowledgement/permit data.
    if (row.containsKey('may_send') && row['may_send'] != false ||
        row.containsKey('replay') ||
        row.containsKey('acknowledgement')) {
      _invalid();
    }
    if (row.containsKey('worker_id')) {
      return NotificationOperatorClaim._(Object(), row);
    }
    if (row.containsKey('expires_at')) {
      return NotificationOperatorConfirmation._(Object(), row);
    }
    if (row['state'] == 'send_started') {
      return NotificationOperatorSendStart._(row);
    }
    if (row.containsKey('observation')) {
      return NotificationOperatorOutcome._(row);
    }
    if (row.containsKey('payment_id')) {
      return NotificationOperatorQueuedReceipt._(row);
    }
    return NotificationOperatorRelease._(row);
  }

  void _matches(
    NotificationOperatorOperation operation,
    NotificationOperatorReceipt receipt,
  ) {
    final body = operation._body;
    if (receipt.action != operation.action ||
        receipt is! NotificationOperatorOutcome &&
            receipt.jobId != operation.resourceId) {
      _invalid();
    }
    switch (receipt) {
      case NotificationOperatorClaim():
        if (receipt.workerId != body['worker_id'] ||
            receipt.fenceVersion != (body['expected_fence'] as int) + 1) {
          _invalid();
        }
      case NotificationOperatorConfirmation():
        if (receipt.confirmationId != body['confirmation_id'] ||
            receipt.claimToken != body['claim_token'] ||
            receipt.fenceVersion != body['fence_version'] ||
            receipt.bodySha256 != body['body_sha256'] ||
            receipt.destinationSha256 != body['destination_sha256'] ||
            receipt.destinationRevision != body['destination_revision']) {
          _invalid();
        }
      case NotificationOperatorSendStart():
        if (receipt.confirmationId != body['confirmation_id'] ||
            receipt.claimToken != body['claim_token'] ||
            receipt.fenceVersion != body['fence_version']) {
          _invalid();
        }
      case NotificationOperatorRelease():
        if (receipt.fenceVersion != (body['fence_version'] as int) + 1) {
          _invalid();
        }
      case NotificationOperatorOutcome():
        if (receipt.attemptId != body['attempt_id'] ||
            receipt.observation.wireValue != body['observation'] ||
            receipt.evidenceReferenceSha256 !=
                body['evidence_reference_sha256']) {
          _invalid();
        }
      case NotificationOperatorQueuedReceipt():
        _invalid();
    }
  }
}
