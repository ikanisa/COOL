import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'privacy_contract.dart';
import 'privacy_session.dart';

abstract interface class PrivacyRequestTransport {
  Future<void> sendCode(PrivacySessionSnapshot session, {String? captchaToken});
  Future<Session> verifyCode(
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
}

String privacyAuthPhone(Session session) {
  final phone = session.user.phone;
  if (phone == null || !RegExp(r'^\+?[1-9][0-9]{7,14}$').hasMatch(phone)) {
    throw const PrivacyRequestException(PrivacyFailure.phoneUnavailable);
  }
  return phone.startsWith('+') ? phone : '+$phone';
}

/// Uses the phone OTP contracts of the pinned gotrue 2.27.1 implementation.
/// It neither constructs another Auth client nor installs a verify response.
final class SupabasePrivacyRequestTransport implements PrivacyRequestTransport {
  SupabasePrivacyRequestTransport({
    required http.Client httpClient,
    required String supabaseUrl,
    required String publishableKey,
    this.captchaRequired = false,
    this.timeout = const Duration(seconds: 15),
  }) : _http = httpClient,
       _key = publishableKey,
       _base = Uri.parse('${supabaseUrl.replaceFirst(RegExp(r'/+$'), '')}/') {
    if ((_base.scheme != 'https' &&
            !(_base.scheme == 'http' &&
                const {
                  'localhost',
                  '127.0.0.1',
                  '::1',
                }.contains(_base.host))) ||
        _base.userInfo.isNotEmpty ||
        _base.query.isNotEmpty ||
        _base.fragment.isNotEmpty ||
        _key.isEmpty ||
        _key.contains(RegExp(r'[\r\n]'))) {
      throw const PrivacyRequestException(PrivacyFailure.protocolUnavailable);
    }
  }
  final http.Client _http;
  final Uri _base;
  final String _key;
  final bool captchaRequired;
  final Duration timeout;
  static const maximumResponseBytes = 65536;

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
    _captcha(captchaToken);
    await _request(session, 'auth/v1/otp', {
      'phone': privacyAuthPhone(session.session),
      'data': <String, dynamic>{},
      'create_user': false,
      'gotrue_meta_security': {'captcha_token': captchaToken},
      'channel': OtpChannel.whatsapp.name,
    }, auth: true);
  }

  @override
  Future<Session> verifyCode(
    PrivacySessionSnapshot session,
    String code, {
    String? captchaToken,
  }) async {
    _captcha(captchaToken);
    if (!RegExp(r'^[0-9]{6}$').hasMatch(code)) {
      throw const PrivacyRequestException(PrivacyFailure.invalidCode);
    }
    final result = await _request(session, 'auth/v1/verify', {
      'phone': privacyAuthPhone(session.session),
      'token': code,
      'type': 'sms',
      'redirect_to': null,
      'gotrue_meta_security': {'captcha_token': captchaToken},
    }, auth: true);
    try {
      if (result is! Map<String, dynamic>) throw const FormatException();
      final verified = Session.fromJson(result);
      if (verified == null) throw const FormatException();
      return verified;
    } catch (_) {
      throw const PrivacyRequestException(
        PrivacyFailure.verificationUnavailable,
      );
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
      'rest/v1/rpc/request_account_deletion_v1',
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
      'rest/v1/rpc/get_account_deletion_request_status_v1',
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
      'rest/v1/rpc/get_current_account_deletion_request_status_v1',
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

  Future<Object?> _request(
    PrivacySessionSnapshot session,
    String path,
    Map<String, dynamic> body, {
    bool auth = false,
    bool submission = false,
  }) async {
    try {
      final response = await _boundedRequest(
        session,
        path,
        body,
      ).timeout(timeout);
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
    }
  }

  Future<(int, List<int>)> _boundedRequest(
    PrivacySessionSnapshot session,
    String path,
    Map<String, dynamic> body,
  ) async {
    final request = http.Request('POST', _base.resolve(path))
      ..followRedirects = false;
    request.headers.addAll({
      'apikey': _key,
      'Authorization': 'Bearer ${session.session.accessToken}',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'X-Supabase-Api-Version': '2024-01-01',
    });
    request.body = jsonEncode(body);
    final response = await _http.send(request);
    if ((response.contentLength ?? 0) > maximumResponseBytes) {
      await response.stream.listen((_) {}).cancel();
      throw const FormatException();
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > maximumResponseBytes)
        throw const FormatException();
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
    if (auth) {
      if (status == 429) return PrivacyFailure.rateLimited;
      final code = body is Map<String, dynamic>
          ? body['code'] ?? body['error_code']
          : null;
      if (code == 'otp_expired') return PrivacyFailure.invalidCode;
      if (code == 'captcha_failed') return PrivacyFailure.captchaRequired;
      return PrivacyFailure.verificationUnavailable;
    }
    final code = body is Map<String, dynamic> ? body['code'] : null;
    final message = body is Map<String, dynamic> ? body['message'] : null;
    if (code == '42501' && message == 'privacy_request_fresh_session_required')
      return PrivacyFailure.freshSignInRequired;
    if (code == '42501' && message == 'privacy_request_session_required')
      return PrivacyFailure.sessionChanged;
    if (code == '42501' && message == 'privacy_request_unavailable')
      return PrivacyFailure.requestUnavailable;
    if (code == '22023' && message == 'privacy_request_reason_invalid')
      return PrivacyFailure.invalidReason;
    if (code == '22023' &&
        const {
          'privacy_request_conflict',
          'privacy_request_active_scope_conflict',
        }.contains(message))
      return PrivacyFailure.conflictingRequest;
    if (code == '54000' && message == 'privacy_request_submission_limit')
      return PrivacyFailure.submissionLimit;
    // Unknown gateways, network timeouts and 5xx have no trustworthy commit
    // outcome. Never mint another UUID or automatically replay a write.
    return submission
        ? PrivacyFailure.outcomeUnknown
        : PrivacyFailure.requestUnavailable;
  }
}
