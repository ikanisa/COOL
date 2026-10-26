import 'dart:convert';
import 'dart:math';

import 'package:uuid/uuid.dart';

import '../../core/cloudflare/collect_cloudflare_client.dart';
import 'privacy_contract.dart';
import 'privacy_session.dart';

const privacyEmailPurpose = 'account_deletion_request';

/// Raw HTTP envelope is short-lived memory. Never log or checkpoint its body.
final class PrivacyEmailWireResponse {
  const PrivacyEmailWireResponse(this.status, this.body);
  final int status;
  final Map<String, dynamic> body;
  @override
  String toString() => 'PrivacyEmailWireResponse';
}

/// Optional Supabase seam; phone/intake/status transports keep their contracts.
abstract interface class PrivacyEmailWireTransport {
  bool get privacyEmailAvailable;
  String get privacyEmailIssuer;
  void cancelPrivacyEmailChallenge();
  Future<PrivacyEmailWireResponse> privacyEmailRequest(
    PrivacySessionSnapshot original,
    String operation,
    Map<String, dynamic> body, {
    required bool Function() dispatchCurrent,
  });
}

int _seconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
Never _unconfirmed() =>
    throw const PrivacyRequestException(PrivacyFailure.outcomeUnknown);
bool _integer(Object? n) => n is int && n > 0 && n <= 9007199254740991;
bool _keys(Map<String, dynamic> value, Set<String> keys) =>
    value.length == keys.length && value.keys.every(keys.contains);
String _newPrivacyEmailContext() {
  final secure = Random.secure();
  return base64UrlEncode(
    List<int>.generate(32, (_) => secure.nextInt(256)),
  ).replaceAll('=', '');
}

void _contextCheck(String value) {
  try {
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value)) _unconfirmed();
    final bytes = base64Url.decode(base64Url.normalize(value));
    if (bytes.length != 32 ||
        base64UrlEncode(bytes).replaceAll('=', '') != value) {
      _unconfirmed();
    }
  } catch (_) {
    _unconfirmed();
  }
}

final class PrivacyEmailDescriptor {
  PrivacyEmailDescriptor._(
    this.destinationHint,
    this.createdAt,
    this.expiresAt,
    this.deliveryStatus,
    this.verificationState,
    this.operationId,
    this.cancelled,
    this.candidateCleanup,
  );
  final String destinationHint,
      deliveryStatus,
      verificationState,
      candidateCleanup;
  final int createdAt, expiresAt;
  final String? operationId;
  final bool cancelled;
  @override
  String toString() => 'PrivacyEmailDescriptor';
}

final class _EmailAttempt {
  _EmailAttempt(
    this.original,
    this.challengeId,
    this.context,
    this.epoch,
    this.startedAt,
  );
  final PrivacySessionSnapshot original;
  final String challengeId, context;
  final int epoch, startedAt;
  String? operationId;
  PrivacyEmailDescriptor? descriptor;
  CollectAuthSession? candidate;
  bool unknown = false, busy = false, cancelled = false, adopted = false;
  bool cleanupStarted = false;
  String cleanup = 'not_required';
  Map<String, dynamic> get envelope => {
    'contract_version': 1,
    'purpose': privacyEmailPurpose,
    'mode': 'current_session',
    'challenge_id': challengeId,
    'challenge_context': context,
  };
  @override
  String toString() => 'PrivacyEmailAttempt';
}

/// Native-only current_session counterpart. All context, operation, code and
/// candidate material is memory-only. Status cannot create/adopt a lost token.
final class PrivacyEmailVerification {
  PrivacyEmailVerification({
    required this.authority,
    required this.transport,
    String Function()? newId,
    String Function()? newContext,
    int Function()? now,
  }) : _id = newId ?? const Uuid().v4,
       _context = newContext ?? _newPrivacyEmailContext,
       _now = now ?? _seconds;
  final PrivacyEmailSessionAuthority authority;
  final PrivacyEmailWireTransport transport;
  final String Function() _id, _context;
  final int Function() _now;
  _EmailAttempt? _attempt;
  int _epoch = 0;
  bool get available => transport.privacyEmailAvailable;
  bool get hasAttempt =>
      _attempt != null && !_attempt!.adopted && !_attempt!.cancelled;
  bool get unknown => hasAttempt && _attempt!.unknown;
  String? get destinationHint =>
      hasAttempt ? _attempt!.descriptor?.destinationHint : null;
  int get resendSeconds {
    final a = _attempt;
    if (a == null) return 0;
    final left = (a.descriptor?.createdAt ?? a.startedAt) + 60 - _now();
    return max(0, left);
  }

  bool get canStart {
    final a = _attempt;
    if (a == null || a.cancelled || a.adopted) return true;
    final d = a.descriptor;
    return !a.busy &&
        !a.unknown &&
        d != null &&
        !d.cancelled &&
        const {'not_started', 'rejected'}.contains(d.verificationState) &&
        resendSeconds == 0;
  }

  bool get codeReady {
    final a = _attempt, d = a?.descriptor;
    return a != null &&
        d != null &&
        !a.cancelled &&
        !a.adopted &&
        !a.unknown &&
        !d.cancelled &&
        d.expiresAt >= _now() &&
        const {'not_started', 'rejected'}.contains(d.verificationState);
  }

  String get message {
    final a = _attempt;
    if (a == null) {
      return 'Use the confirmed email for your signed-in Collect account.';
    }
    if (a.cleanup == 'unconfirmed') {
      return 'Verification was cancelled locally. Candidate sign-out could not be confirmed.';
    }
    if (a.cancelled) {
      return 'Email verification was cancelled. This does not cancel a deletion request.';
    }
    if (a.adopted) {
      return 'Identity verified. You can submit your request for review.';
    }
    if (a.unknown ||
        const {
          'verifying',
          'unconfirmed',
          'verified',
        }.contains(a.descriptor?.verificationState)) {
      return 'The verification result is unconfirmed. Check the original verification. Status cannot recover a lost sign-in session.';
    }
    if (a.descriptor?.deliveryStatus == 'rejected') {
      return 'The code request was not accepted. Get help or explicitly request a new code after the wait.';
    }
    if (a.descriptor?.deliveryStatus == 'unknown') {
      return 'Code delivery is unconfirmed. If a code arrives, enter it before requesting another.';
    }
    return 'Enter the code for this verification. Inbox delivery is not confirmed.';
  }

  void _managed(PrivacySessionSnapshot s) {
    final managed = s.session.user.authUserId;
    if (!privacyUuid(managed) ||
        s.session.claims['sub'] != managed ||
        s.session.authSubject != managed ||
        !s.session.usesMappedAuthUser) {
      throw const PrivacyRequestException(PrivacyFailure.sessionChanged);
    }
  }

  bool _current(_EmailAttempt a) {
    if (a.cancelled || a.epoch != _epoch || a.adopted) return false;
    try {
      final current = authority.capture();
      _managed(current);
      return current.sameFence(a.original) &&
          current.session.user.authUserId == a.original.session.user.authUserId;
    } catch (_) {
      return false;
    }
  }

  void _fence(_EmailAttempt a) {
    if (!_current(a)) {
      throw const PrivacyRequestException(PrivacyFailure.sessionChanged);
    }
  }

  void _envelope(Map<String, dynamic> v, _EmailAttempt a) {
    if (v['contract_version'] is! int ||
        v['contract_version'] != 1 ||
        v['purpose'] != privacyEmailPurpose ||
        v['mode'] != 'current_session' ||
        v['identity_type'] != 'email' ||
        v['channel'] != 'email' ||
        v['challenge_id'] != a.challengeId ||
        v['challenge_context'] != a.context) {
      _unconfirmed();
    }
  }

  PrivacyEmailDescriptor _descriptor(Map<String, dynamic> v, _EmailAttempt a) {
    _envelope(v, a);
    const fields = {
      'contract_version',
      'purpose',
      'mode',
      'identity_type',
      'channel',
      'challenge_id',
      'challenge_context',
      'destination_hint',
      'retry_after',
      'created_at',
      'expires_at',
      'delivery_status',
      'verification_state',
      'operation_id',
      'cancelled',
      'candidate_cleanup',
    };
    if (!_keys(v, fields) ||
        v['destination_hint'] is! String ||
        (v['destination_hint'] as String).length > 254 ||
        !(v['destination_hint'] as String).contains('***') ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(v['destination_hint'] as String) ||
        v['retry_after'] != 60 ||
        !_integer(v['created_at']) ||
        !_integer(v['expires_at']) ||
        (v['created_at'] as int) > _now() ||
        (v['created_at'] as int) < a.startedAt - 300 ||
        (v['expires_at'] as int) <= (v['created_at'] as int) ||
        (v['expires_at'] as int) > (v['created_at'] as int) + 300 ||
        !const {
          'reserved',
          'accepted',
          'rejected',
          'unknown',
        }.contains(v['delivery_status']) ||
        !const {
          'not_started',
          'verifying',
          'rejected',
          'unconfirmed',
          'verified',
        }.contains(v['verification_state']) ||
        !const {
          'not_required',
          'confirmed',
          'unconfirmed',
        }.contains(v['candidate_cleanup']) ||
        v['cancelled'] is! bool ||
        (v['operation_id'] != null && !privacyUuid(v['operation_id'])) ||
        (a.operationId != null &&
            v['operation_id'] != a.operationId &&
            !(v['operation_id'] == null &&
                v['verification_state'] == 'not_started'))) {
      _unconfirmed();
    }
    return PrivacyEmailDescriptor._(
      v['destination_hint'] as String,
      v['created_at'] as int,
      v['expires_at'] as int,
      v['delivery_status'] as String,
      v['verification_state'] as String,
      v['operation_id'] as String?,
      v['cancelled'] as bool,
      v['candidate_cleanup'] as String,
    );
  }

  Future<void> challenge(
    PrivacySessionSnapshot original, {
    String? captchaToken,
  }) async {
    if (!available || !canStart) {
      throw const PrivacyRequestException(PrivacyFailure.busy);
    }
    _managed(original);
    final id = _id(), context = _context();
    if (!privacyUuid(id)) _unconfirmed();
    _contextCheck(context);
    final a = _EmailAttempt(original, id, context, ++_epoch, _now());
    _attempt = a;
    _fence(a);
    a.busy = true;
    a.unknown = true;
    try {
      final response = await transport
          .privacyEmailRequest(original, 'challenge', {
            ...a.envelope,
            'allow_registration': false,
            'should_create_user': false,
            'captcha_token': ?captchaToken,
          }, dispatchCurrent: () => _current(a));
      _fence(a);
      if (response.status != 202) _unconfirmed();
      a.descriptor = _descriptor(response.body, a);
      a.unknown = false;
    } on PrivacyRequestException catch (error) {
      // These fixed failures occur in the transport before HTTP dispatch.
      // A known local CAPTCHA failure is not a lost server acknowledgment.
      if (const {
        PrivacyFailure.captchaRequired,
        PrivacyFailure.cancelled,
      }.contains(error.failure)) {
        a.cancelled = true;
        a.unknown = false;
      }
      rethrow;
    } finally {
      a.busy = false;
    }
  }

  CollectAuthSession _candidate(Map<String, dynamic> v, _EmailAttempt a) {
    _envelope(v, a);
    if (v['operation_id'] != a.operationId ||
        v['auth_event'] is! Map<String, dynamic> ||
        v['purpose_proof'] is! Map<String, dynamic> ||
        v['user'] is! Map<String, dynamic>) {
      _unconfirmed();
    }
    final event = v['auth_event'] as Map<String, dynamic>,
        proof = v['purpose_proof'] as Map<String, dynamic>;
    final d = a.descriptor!, at = _now(), rawTime = event['timestamp'];
    if (!_integer(rawTime)) _unconfirmed();
    final t = rawTime as int;
    if (!_keys(event, {'method', 'timestamp'}) ||
        event['method'] != 'otp' ||
        !_integer(t) ||
        t < d.createdAt ||
        t > at ||
        t > d.expiresAt ||
        !_keys(proof, {
          'purpose',
          'challenge_id',
          'user_id',
          'auth_user_id',
          'initiating_session_id',
          'session_id',
          'method',
          'authenticated_at',
          'expires_at',
        }) ||
        proof['purpose'] != privacyEmailPurpose ||
        proof['challenge_id'] != a.challengeId ||
        proof['user_id'] != a.original.subjectId ||
        proof['auth_user_id'] != a.original.session.user.authUserId ||
        proof['initiating_session_id'] != a.original.sessionId ||
        proof['method'] != 'otp' ||
        proof['authenticated_at'] != t ||
        proof['expires_at'] != d.expiresAt ||
        (v['user'] as Map<String, dynamic>)['auth_user_id'] !=
            a.original.session.user.authUserId) {
      _unconfirmed();
    }
    final session = CollectAuthSession.fromJson(
      v,
      allowMappedAuthUser: true,
      expectedIssuer: transport.privacyEmailIssuer,
    );
    if (session == null ||
        session.user.id != a.original.subjectId ||
        session.user.authUserId != a.original.session.user.authUserId ||
        !privacyUuid(session.claims['session_id']) ||
        session.claims['session_id'] == a.original.sessionId ||
        session.claims['session_id'] != proof['session_id'] ||
        session.refreshToken?.isNotEmpty != true ||
        session.claims['amr'] is! List ||
        !(session.claims['amr'] as List).any(
          (row) =>
              row is Map &&
              row['method'] == 'otp' &&
              row['timestamp'] is int &&
              row['timestamp'] == t,
        )) {
      _unconfirmed();
    }
    return session;
  }

  Future<PrivacySessionSnapshot> verify(
    String code, {
    String? captchaToken,
  }) async {
    final a = _attempt;
    if (a == null || !codeReady) {
      throw const PrivacyRequestException(PrivacyFailure.codeRequired);
    }
    if (a.busy) throw const PrivacyRequestException(PrivacyFailure.busy);
    if (!RegExp(r'^[0-9]{6,10}$').hasMatch(code)) {
      throw const PrivacyRequestException(PrivacyFailure.invalidCode);
    }
    _fence(a);
    final operation = _id();
    if (!privacyUuid(operation)) _unconfirmed();
    a.operationId = operation;
    a.busy = true;
    a.unknown = true;
    try {
      final response = await transport
          .privacyEmailRequest(a.original, 'verify', {
            ...a.envelope,
            'operation_id': operation,
            'code': code,
            'captcha_token': ?captchaToken,
          }, dispatchCurrent: () => _current(a));
      if (const {401, 429}.contains(response.status) &&
          response.body['code'] == 'privacy_email_code_rejected') {
        final descriptor = Map<String, dynamic>.from(response.body)
          ..remove('code')
          ..remove('message');
        final observed = _descriptor(descriptor, a);
        _fence(a);
        if (observed.verificationState != 'rejected') _unconfirmed();
        a.descriptor = observed;
        a.unknown = false;
        throw PrivacyRequestException(
          response.status == 429
              ? PrivacyFailure.rateLimited
              : PrivacyFailure.invalidCode,
        );
      }
      if (response.status != 200 ||
          !response.body.containsKey('access_token')) {
        _unconfirmed();
      }
      // Parse a received candidate even after cancellation/authority loss so its
      // exact captured token can be retired. Never read the SDK's current token.
      a.candidate = _candidate(response.body, a);
      _fence(a);
      final event = response.body['auth_event'] as Map<String, dynamic>;
      if (_now() > a.descriptor!.expiresAt ||
          _now() - (event['timestamp'] as int) > 300 ||
          PrivacySessionSnapshot.parse(a.candidate, a.original.generation) ==
              null) {
        throw const PrivacyRequestException(
          PrivacyFailure.verificationUnavailable,
        );
      }
      final adopted = authority.adoptEmail(
        a.original,
        a.candidate!,
        onInstalled: () => a.adopted = true,
      );
      if (!a.adopted) _unconfirmed();
      a.unknown = false;
      return adopted;
    } on PrivacyRequestException catch (error) {
      if (a.candidate == null &&
          const {
            PrivacyFailure.captchaRequired,
            PrivacyFailure.cancelled,
          }.contains(error.failure)) {
        a.operationId = null;
        a.unknown = false;
      }
      rethrow;
    } finally {
      a.busy = false;
      if (a.candidate != null && !a.adopted) await _cleanup(a);
      if (a.adopted) a.candidate = null;
    }
  }

  Future<void> status() async {
    final a = _attempt;
    if (a == null || a.busy || a.adopted || a.cancelled) {
      throw const PrivacyRequestException(PrivacyFailure.busy);
    }
    _fence(a);
    a.busy = true;
    try {
      final response = await transport.privacyEmailRequest(
        a.original,
        'status',
        {
          ...a.envelope,
          if (a.operationId != null) 'operation_id': a.operationId,
        },
        dispatchCurrent: () => _current(a),
      );
      _fence(a);
      if (response.status != 200) _unconfirmed();
      a.descriptor = _descriptor(response.body, a);
      // Metadata, including recorded verified, cannot reconstruct lost tokens.
      a.unknown =
          a.operationId != null &&
              a.descriptor!.verificationState != 'rejected' ||
          const {
            'verifying',
            'unconfirmed',
            'verified',
          }.contains(a.descriptor!.verificationState);
    } finally {
      a.busy = false;
    }
  }

  Future<void> _cleanup(_EmailAttempt a) async {
    if (a.adopted || a.cleanupStarted || a.candidate == null) return;
    a.cleanupStarted = true;
    a.cleanup = 'unconfirmed';
    try {
      final response = await transport
          .privacyEmailRequest(a.original, 'cancel', {
            ...a.envelope,
            'operation_id': a.operationId,
            'candidate_access_token': a.candidate!.accessToken,
          }, dispatchCurrent: () => true);
      if (response.status == 200) {
        final d = _descriptor(response.body, a);
        if (d.candidateCleanup == 'confirmed') a.cleanup = 'confirmed';
      }
    } catch (_) {
      /* Unknown cleanup remains unknown. */
    } finally {
      a.candidate = null;
    }
  }

  Future<void> cancel() async {
    final a = _attempt;
    ++_epoch; // Invalidate synchronously, before any await.
    if (a == null || a.adopted || a.cancelled) return;
    a.cancelled = true;
    transport.cancelPrivacyEmailChallenge();
    if (a.candidate != null) {
      await _cleanup(a);
      return;
    }
    a.cleanup = a.operationId == null ? 'not_required' : 'unconfirmed';
    try {
      final response = await transport.privacyEmailRequest(
        a.original,
        'cancel',
        {
          ...a.envelope,
          if (a.operationId != null) 'operation_id': a.operationId,
        },
        dispatchCurrent: () => true,
      );
      if (response.status == 200) {
        final d = _descriptor(response.body, a);
        a.cleanup = d.candidateCleanup;
      }
    } catch (_) {
      if (a.operationId != null) a.cleanup = 'unconfirmed';
    }
  }

  @override
  String toString() => 'PrivacyEmailVerification';
}
