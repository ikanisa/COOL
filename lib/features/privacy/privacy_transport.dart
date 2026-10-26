import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import '../../core/cloudflare/collect_cloudflare_client.dart';
import '../../core/supabase/collect_supabase_configuration.dart';

import 'privacy_contract.dart';
import 'privacy_email_verification.dart';
import 'privacy_review_contract.dart';
import 'privacy_session.dart';

abstract interface class PrivacyRequestTransport {
  Future<void> sendCode(PrivacySessionSnapshot session, {String? captchaToken});
  Future<CollectAuthSession> verifyCode(
    PrivacySessionSnapshot session,
    String code, {
    String? captchaToken,
  });
  Future<PrivacyIntakeReceipt> submit(
    PrivacySessionSnapshot session,
    String submissionId,
    String? reason,
  );
  Future<PrivacyIntakeReceipt> status(
    PrivacySessionSnapshot session,
    String requestId,
  );
  Future<PrivacyIntakeReceipt?> currentStatus(PrivacySessionSnapshot session);
  Future<PrivacyReviewStatus> reviewStatus(
    PrivacySessionSnapshot session,
    String canonicalRequestId,
  );
}

abstract interface class PrivacyVerificationCancellation {
  void cancelVerification(PrivacySessionSnapshot owner);
}

String privacyAuthPhone(CollectAuthSession session) {
  final phone = session.user.phone;
  if (phone == null || !RegExp(r'^\+?[1-9][0-9]{7,14}$').hasMatch(phone)) {
    throw const PrivacyRequestException(PrivacyFailure.phoneUnavailable);
  }
  return phone.startsWith('+') ? phone : '+$phone';
}

/// Calls Collect authentication and privacy contracts without another Auth
/// client. Verification returns a candidate session for the caller to fence.
final class CollectPrivacyRequestTransport
    implements
        PrivacyRequestTransport,
        PrivacyVerificationCancellation,
        PrivacyEmailWireTransport {
  CollectPrivacyRequestTransport({
    required http.Client httpClient,
    required String apiUrl,
    this.captchaRequired = false,
    this.captchaProvider,
    this.cancelCaptcha,
    this.isSessionCurrent,
    this.timeout = const Duration(seconds: 15),
    this.supabaseConfiguration,
  }) : _http = httpClient,
       _base = Uri.parse('${apiUrl.replaceFirst(RegExp(r'/+$'), '')}/') {
    if ((_base.scheme != 'https' &&
            !(_base.scheme == 'http' &&
                const {
                  'localhost',
                  '127.0.0.1',
                  '::1',
                }.contains(_base.host))) ||
        _base.userInfo.isNotEmpty ||
        _base.query.isNotEmpty ||
        _base.fragment.isNotEmpty) {
      throw const PrivacyRequestException(PrivacyFailure.protocolUnavailable);
    }
    if (supabaseConfiguration != null &&
        _base.origin != supabaseConfiguration!.api.origin) {
      throw const PrivacyRequestException(PrivacyFailure.protocolUnavailable);
    }
  }
  final http.Client _http;
  final Uri _base;
  final bool captchaRequired;
  final Future<String> Function()? captchaProvider;
  final void Function()? cancelCaptcha;
  final bool Function(PrivacySessionSnapshot)? isSessionCurrent;
  final Duration timeout;
  final CollectSupabaseConfiguration? supabaseConfiguration;
  static const maximumResponseBytes = 131072;
  String? _challengeId;
  PrivacySessionSnapshot? _challengeOwner;
  int _verificationEpoch = 0;
  PrivacySessionSnapshot? _verificationOwner;

  @override
  bool get privacyEmailAvailable => supabaseConfiguration != null;
  @override
  void cancelPrivacyEmailChallenge() => cancelCaptcha?.call();
  @override
  String get privacyEmailIssuer =>
      '${supabaseConfiguration!.project.origin}/auth/v1';

  @override
  Future<PrivacyEmailWireResponse> privacyEmailRequest(
    PrivacySessionSnapshot original,
    String operation,
    Map<String, dynamic> body, {
    required bool Function() dispatchCurrent,
  }) async {
    if (!privacyEmailAvailable ||
        !const {
          'challenge',
          'verify',
          'status',
          'cancel',
        }.contains(operation)) {
      throw const PrivacyRequestException(PrivacyFailure.protocolUnavailable);
    }
    final payload = Map<String, dynamic>.from(body);
    // Only received-candidate cleanup can dispatch after original authority loss.
    // The exact captured bearer/context/operation is server-validated; this never
    // substitutes current SDK credentials or grants an intake session.
    final cleanup =
        operation == 'cancel' && payload.containsKey('candidate_access_token');
    if (!cleanup && !dispatchCurrent()) {
      throw const PrivacyRequestException(PrivacyFailure.cancelled);
    }
    if (const {'challenge', 'verify'}.contains(operation)) {
      try {
        final token = captchaProvider == null
            ? payload['captcha_token']
            : await captchaProvider!();
        if (!dispatchCurrent()) {
          throw const PrivacyRequestException(PrivacyFailure.cancelled);
        }
        if (token != null && token is! String) throw const FormatException();
        _captcha(token as String?);
        if (token != null) payload['captcha_token'] = token;
      } on PrivacyRequestException {
        rethrow;
      } catch (_) {
        throw const PrivacyRequestException(PrivacyFailure.captchaRequired);
      }
    }
    final abort = Completer<void>();
    try {
      final raw =
          await _boundedRequest(
            original,
            'v1/privacy/email/$operation',
            payload,
            abort.future,
          ).timeout(
            timeout,
            onTimeout: () {
              if (!abort.isCompleted) abort.complete();
              throw TimeoutException('Privacy email response deadline');
            },
          );
      final value = jsonDecode(utf8.decode(raw.$2));
      if (value is! Map<String, dynamic>) throw const FormatException();
      return PrivacyEmailWireResponse(raw.$1, value);
    } catch (_) {
      throw const PrivacyRequestException(PrivacyFailure.outcomeUnknown);
    } finally {
      if (!abort.isCompleted) abort.complete();
    }
  }

  @override
  void cancelVerification(PrivacySessionSnapshot owner) {
    if (_verificationOwner?.sameFence(owner) != true) return;
    ++_verificationEpoch;
    _verificationOwner = null;
    _challengeId = null;
    _challengeOwner = null;
    cancelCaptcha?.call();
  }

  void _captcha(String? value) {
    if (captchaRequired && (value == null || value.isEmpty)) {
      throw const PrivacyRequestException(PrivacyFailure.captchaRequired);
    }
    if (value != null && value.length > 16384) {
      throw const PrivacyRequestException(
        PrivacyFailure.verificationUnavailable,
      );
    }
  }

  @override
  Future<void> sendCode(
    PrivacySessionSnapshot session, {
    String? captchaToken,
  }) async {
    final epoch = ++_verificationEpoch;
    _verificationOwner = session;
    _challengeId = null;
    _challengeOwner = null;
    captchaToken = await _freshCaptcha(captchaToken, session, epoch);
    _captcha(captchaToken);
    final result = await _request(session, 'v1/auth/otp', {
      'phone': privacyAuthPhone(session.session),
      'surface': 'member',
      'captcha_token': ?captchaToken,
      if (supabaseConfiguration != null) 'should_create_user': false,
    }, auth: true);
    final challenge = result is Map<String, dynamic>
        ? result['challenge_id']
        : null;
    _checkVerification(session, epoch);
    if (challenge is! String || challenge.isEmpty || challenge.length > 200) {
      throw const PrivacyRequestException(
        PrivacyFailure.verificationUnavailable,
      );
    }
    _challengeId = challenge;
    _challengeOwner = session;
  }

  @override
  Future<CollectAuthSession> verifyCode(
    PrivacySessionSnapshot session,
    String code, {
    String? captchaToken,
  }) async {
    if (!RegExp(r'^[0-9]{6}$').hasMatch(code)) {
      throw const PrivacyRequestException(PrivacyFailure.invalidCode);
    }
    final challenge = _challengeId;
    if (challenge == null || _challengeOwner?.sameFence(session) != true) {
      throw const PrivacyRequestException(PrivacyFailure.codeRequired);
    }
    final epoch = _verificationEpoch;
    captchaToken = await _freshCaptcha(captchaToken, session, epoch);
    _captcha(captchaToken);
    if (_challengeId != challenge ||
        _challengeOwner?.sameFence(session) != true) {
      throw const PrivacyRequestException(PrivacyFailure.sessionChanged);
    }
    final result = await _request(session, 'v1/auth/verify', {
      'phone': privacyAuthPhone(session.session),
      'surface': 'member',
      'code': code,
      'challenge_id': challenge,
      'captcha_token': ?captchaToken,
    }, auth: true);
    _checkVerification(session, epoch);
    _challengeId = null;
    _challengeOwner = null;
    try {
      if (result is! Map<String, dynamic>) throw const FormatException();
      final verified = CollectAuthSession.fromJson(
        result,
        allowMappedAuthUser: supabaseConfiguration != null,
        expectedIssuer: supabaseConfiguration == null
            ? null
            : '${supabaseConfiguration!.project.origin}/auth/v1',
      );
      if (verified == null) throw const FormatException();
      return verified;
    } catch (_) {
      throw const PrivacyRequestException(
        PrivacyFailure.verificationUnavailable,
      );
    }
  }

  void _checkVerification(PrivacySessionSnapshot session, int epoch) {
    if (epoch != _verificationEpoch) {
      throw const PrivacyRequestException(PrivacyFailure.cancelled);
    }
    if (isSessionCurrent != null && !isSessionCurrent!(session)) {
      throw const PrivacyRequestException(PrivacyFailure.sessionChanged);
    }
  }

  Future<String?> _freshCaptcha(
    String? provided,
    PrivacySessionSnapshot session,
    int epoch,
  ) async {
    _checkVerification(session, epoch);
    try {
      final token = captchaProvider == null
          ? provided
          : await captchaProvider!();
      _checkVerification(session, epoch);
      _captcha(token);
      return token;
    } on PrivacyRequestException {
      _checkVerification(session, epoch);
      rethrow;
    } catch (_) {
      _checkVerification(session, epoch);
      throw const PrivacyRequestException(PrivacyFailure.captchaRequired);
    }
  }

  @override
  Future<PrivacyIntakeReceipt> submit(
    PrivacySessionSnapshot session,
    String submissionId,
    String? reason,
  ) async {
    if (!privacyUuid(submissionId)) {
      throw const PrivacyRequestException(PrivacyFailure.protocolUnavailable);
    }
    final result = await _request(
      session,
      'v1/rpc/request_account_deletion_v1',
      {'p_request_id': submissionId, 'p_reason': cleanPrivacyReason(reason)},
      submission: true,
    );
    try {
      if (result is! Map<String, dynamic>) throw const FormatException();
      final receipt = PrivacyIntakeReceipt.fromJson(result, submission: true);
      if (receipt.submissionId != submissionId ||
          receipt.reasonSupplied != (cleanPrivacyReason(reason) != null)) {
        throw const FormatException();
      }
      return receipt;
    } catch (_) {
      // A malformed success can still follow a committed server transaction.
      throw const PrivacyRequestException(PrivacyFailure.outcomeUnknown);
    }
  }

  @override
  Future<PrivacyIntakeReceipt> status(
    PrivacySessionSnapshot session,
    String requestId,
  ) async {
    if (!privacyUuid(requestId)) {
      throw const PrivacyRequestException(PrivacyFailure.protocolUnavailable);
    }
    final result = await _request(
      session,
      'v1/rpc/get_account_deletion_request_status_v1',
      {'p_request_id': requestId},
    );
    return _receipt(result);
  }

  @override
  Future<PrivacyIntakeReceipt?> currentStatus(
    PrivacySessionSnapshot session,
  ) async {
    final result = await _request(
      session,
      'v1/rpc/get_current_account_deletion_request_status_v1',
      {},
    );
    return result == null ? null : _receipt(result);
  }

  PrivacyIntakeReceipt _receipt(Object? result) {
    if (result is! Map<String, dynamic>) {
      throw const PrivacyRequestException(PrivacyFailure.protocolUnavailable);
    }
    return PrivacyIntakeReceipt.fromJson(result, submission: false);
  }

  @override
  Future<PrivacyReviewStatus> reviewStatus(
    PrivacySessionSnapshot session,
    String canonicalRequestId,
  ) async {
    if (!privacyUuid(canonicalRequestId)) {
      throw const PrivacyRequestException(PrivacyFailure.protocolUnavailable);
    }
    final result = await _request(
      session,
      'v1/rpc/get_account_deletion_review_status_v1',
      {'p_request_id': canonicalRequestId},
    );
    if (result is! Map<String, dynamic>) {
      throw const PrivacyRequestException(PrivacyFailure.protocolUnavailable);
    }
    final status = PrivacyReviewStatus.fromJson(result);
    if (status.requestId != canonicalRequestId) {
      throw const PrivacyRequestException(PrivacyFailure.protocolUnavailable);
    }
    return status;
  }

  Future<Object?> _request(
    PrivacySessionSnapshot session,
    String path,
    Map<String, dynamic> body, {
    bool auth = false,
    bool submission = false,
  }) async {
    final abort = Completer<void>();
    try {
      final response = await _boundedRequest(session, path, body, abort.future)
          .timeout(
            timeout,
            onTimeout: () {
              if (!abort.isCompleted) abort.complete();
              throw TimeoutException('Privacy request deadline');
            },
          );
      Object? result;
      try {
        result = response.$2.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(utf8.decode(response.$2));
      } catch (_) {
        throw PrivacyRequestException(
          submission
              ? PrivacyFailure.outcomeUnknown
              : auth
              ? PrivacyFailure.verificationUnavailable
              : PrivacyFailure.protocolUnavailable,
        );
      }
      if (response.$1 < 200 || response.$1 >= 300) {
        throw PrivacyRequestException(
          _failure(response.$1, result, auth: auth, submission: submission),
        );
      }
      return result;
    } on PrivacyRequestException {
      rethrow;
    } catch (_) {
      throw PrivacyRequestException(
        submission
            ? PrivacyFailure.outcomeUnknown
            : auth
            ? PrivacyFailure.verificationUnavailable
            : PrivacyFailure.requestUnavailable,
      );
    } finally {
      if (!abort.isCompleted) abort.complete();
    }
  }

  Future<(int, List<int>)> _boundedRequest(
    PrivacySessionSnapshot session,
    String path,
    Map<String, dynamic> body,
    Future<void> abort,
  ) async {
    final request = http.AbortableRequest(
      'POST',
      _base.resolve(
        '${supabaseConfiguration == null ? '' : CollectSupabaseConfiguration.memberPrefix}$path',
      ),
      abortTrigger: abort,
    )..followRedirects = false;
    request.headers.addAll({
      'Authorization': 'Bearer ${session.session.accessToken}',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (supabaseConfiguration != null)
        'apikey': supabaseConfiguration!.publishableKey,
    });
    request.body = jsonEncode(body);
    final response = await _http.send(request);
    if ((response.contentLength ?? 0) > maximumResponseBytes) {
      await response.stream.listen((_) {}).cancel();
      throw const FormatException();
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > maximumResponseBytes) {
        throw const FormatException();
      }
      bytes.addAll(chunk);
    }
    return (response.statusCode, bytes);
  }

  PrivacyFailure _failure(
    int status,
    Object? body, {
    required bool auth,
    required bool submission,
  }) {
    final code = body is Map<String, dynamic> ? body['code'] : null;
    if (auth) {
      if (status == 429) return PrivacyFailure.rateLimited;
      if ((status == 400 && code == 'otp_expired') ||
          (status == 401 && code == 'invalid_credentials')) {
        return PrivacyFailure.invalidCode;
      }
      if (status == 400 &&
          const {'captcha_required', 'captcha_failed'}.contains(code)) {
        return PrivacyFailure.captchaRequired;
      }
      return PrivacyFailure.verificationUnavailable;
    }
    // Recognize the canonical API's explicit refusals by both HTTP status and
    // code. Gateway failures with a copied code still have an unknown outcome.
    if (status == 401 &&
        const {
          'authentication_required',
          'invalid_token',
          'access_revoked',
        }.contains(code)) {
      return PrivacyFailure.sessionChanged;
    }
    if (status == 403 && code == 'session_changed') {
      return PrivacyFailure.sessionChanged;
    }
    if (status == 403 && code == 'fresh_auth_required') {
      return PrivacyFailure.freshSignInRequired;
    }
    if (status == 409 &&
        const {'privacy_request_conflict', 'request_conflict'}.contains(code)) {
      return PrivacyFailure.conflictingRequest;
    }
    if (status == 404 && code == 'privacy_request_unavailable') {
      return PrivacyFailure.requestUnavailable;
    }
    final message = body is Map<String, dynamic> ? body['message'] : null;
    if (status == 403 &&
        code == '42501' &&
        message == 'privacy_request_fresh_session_required') {
      return PrivacyFailure.freshSignInRequired;
    }
    if (status == 403 &&
        code == '42501' &&
        message == 'privacy_request_session_required') {
      return PrivacyFailure.sessionChanged;
    }
    if (status == 403 &&
        code == '42501' &&
        message == 'privacy_request_unavailable') {
      return PrivacyFailure.requestUnavailable;
    }
    if (status == 400 &&
        code == '22023' &&
        message == 'privacy_request_reason_invalid') {
      return PrivacyFailure.invalidReason;
    }
    if (status == 400 &&
        code == '22023' &&
        const {
          'privacy_request_conflict',
          'privacy_request_active_scope_conflict',
        }.contains(message)) {
      return PrivacyFailure.conflictingRequest;
    }
    if (status == 429 &&
        code == '54000' &&
        message == 'privacy_request_submission_limit') {
      return PrivacyFailure.submissionLimit;
    }
    // Unknown gateways, network timeouts and 5xx have no trustworthy commit
    // outcome. Never mint another UUID or automatically replay a write.
    return submission
        ? PrivacyFailure.outcomeUnknown
        : PrivacyFailure.requestUnavailable;
  }
}
