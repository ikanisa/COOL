/// WhatsApp OTP service — calls existing Supabase Edge Functions.
///
/// - `sendOtp`: POST to `send-otp` with `{ phone, language }`
/// - `verifyOtp`: POST to `verify-otp` with `{ phone, code }`
library;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/json_helpers.dart' as jh;
import 'app_check_service.dart';

// ── Result types ────────────────────────────────────────────────────────

enum OtpSendStatus { sent, rateLimited, error }

class OtpSendResult {
  const OtpSendResult._({
    required this.status,
    this.message,
    this.retryAfterSeconds,
  });

  const OtpSendResult.sent() : this._(status: OtpSendStatus.sent);

  const OtpSendResult.rateLimited(String message, {int? retryAfterSeconds})
    : this._(
        status: OtpSendStatus.rateLimited,
        message: message,
        retryAfterSeconds: retryAfterSeconds,
      );

  const OtpSendResult.error(String message)
    : this._(status: OtpSendStatus.error, message: message);

  final OtpSendStatus status;
  final String? message;
  final int? retryAfterSeconds;

  bool get isSent => status == OtpSendStatus.sent;
}

enum OtpVerifyStatus { verified, invalidCode, expired, rateLimited, error }

class OtpVerifyResult {
  const OtpVerifyResult._({
    required this.status,
    this.message,
    this.accessToken,
    this.refreshToken,
    this.userId,
    this.isNewUser,
    this.attemptsRemaining,
  });

  const OtpVerifyResult.verified({
    required String accessToken,
    required String refreshToken,
    required String userId,
    required bool isNewUser,
  }) : this._(
         status: OtpVerifyStatus.verified,
         accessToken: accessToken,
         refreshToken: refreshToken,
         userId: userId,
         isNewUser: isNewUser,
       );

  const OtpVerifyResult.invalidCode(String message, {int? attemptsRemaining})
    : this._(
        status: OtpVerifyStatus.invalidCode,
        message: message,
        attemptsRemaining: attemptsRemaining,
      );

  const OtpVerifyResult.expired(String message)
    : this._(status: OtpVerifyStatus.expired, message: message);

  const OtpVerifyResult.rateLimited(String message)
    : this._(status: OtpVerifyStatus.rateLimited, message: message);

  const OtpVerifyResult.error(String message)
    : this._(status: OtpVerifyStatus.error, message: message);

  final OtpVerifyStatus status;
  final String? message;
  final String? accessToken;
  final String? refreshToken;
  final String? userId;
  final bool? isNewUser;
  final int? attemptsRemaining;

  bool get isVerified => status == OtpVerifyStatus.verified;
}

// ── Service ─────────────────────────────────────────────────────────────

class WhatsAppOtpService {
  WhatsAppOtpService({
    required SupabaseClient client,
    Future<String?> Function()? getAppCheckToken,
  }) : _client = client,
       _getAppCheckToken = getAppCheckToken ?? _defaultAppCheckToken;

  final SupabaseClient _client;
  final Future<String?> Function() _getAppCheckToken;

  /// Sends a 6-digit OTP to the given E.164 phone via WhatsApp Cloud API.
  Future<OtpSendResult> sendOtp(String e164Phone) async {
    try {
      debugPrint('[OTP] ➜ Sending code to ${_redact(e164Phone)}');
      final response = await _client.functions.invoke(
        'send-otp',
        headers: await _functionHeaders(),
        body: <String, Object?>{'phone': e164Phone, 'language': 'en'},
      );

      final data = jh.asMapOrEmpty(response.data);
      if (data['success'] == true) {
        debugPrint('[OTP] ✓ Code sent');
        return const OtpSendResult.sent();
      }

      final message = _resolveMessage(data, fallback: 'Failed to send OTP');
      final status = response.status;
      if (status == 429) {
        final retryAfter = _resolveRetryAfterSeconds(data);
        return OtpSendResult.rateLimited(
          message,
          retryAfterSeconds: retryAfter,
        );
      }
      return OtpSendResult.error(message);
    } on FunctionException catch (e) {
      final data = jh.asMapOrEmpty(e.details);
      final message = _resolveMessage(
        data,
        fallback: e.reasonPhrase ?? 'Failed to send OTP',
      );
      if (e.status == 429) {
        final retryAfter = _resolveRetryAfterSeconds(data);
        return OtpSendResult.rateLimited(
          message,
          retryAfterSeconds: retryAfter,
        );
      }
      debugPrint('[OTP] ❌ FunctionException: $message');
      return OtpSendResult.error(message);
    } catch (e) {
      debugPrint('[OTP] ❌ Send error: $e');
      return OtpSendResult.error(e.toString());
    }
  }

  /// Verifies the 6-digit code. On success, returns a verified session.
  Future<OtpVerifyResult> verifyOtp(String e164Phone, String code) async {
    try {
      debugPrint('[OTP] ➜ Verifying code for ${_redact(e164Phone)}');
      final response = await _client.functions.invoke(
        'verify-otp',
        headers: await _functionHeaders(),
        body: <String, Object?>{'phone': e164Phone, 'code': code.trim()},
      );

      final data = jh.asMapOrEmpty(response.data);
      if (data['success'] == true) {
        final session = jh.asMapOrEmpty(data['session']);
        final accessToken =
            data['access_token']?.toString() ??
            session['access_token']?.toString() ??
            '';
        final refreshToken =
            data['refresh_token']?.toString() ??
            session['refresh_token']?.toString() ??
            '';
        final userId =
            data['userId']?.toString() ??
            jh.asMapOrEmpty(session['user'])['id']?.toString() ??
            '';
        if (accessToken.isEmpty || refreshToken.isEmpty || userId.isEmpty) {
          debugPrint(
            '[OTP] ❌ Verified response missing session tokens or user id',
          );
          return const OtpVerifyResult.error(
            'Verification succeeded but session setup data was incomplete.',
          );
        }
        debugPrint('[OTP] ✓ Code verified');
        return OtpVerifyResult.verified(
          accessToken: accessToken,
          refreshToken: refreshToken,
          userId: userId,
          isNewUser: data['isNewUser'] == true,
        );
      }

      final message = _resolveMessage(data, fallback: 'Verification failed');
      final status = response.status;
      if (status == 429) {
        return OtpVerifyResult.rateLimited(message);
      }
      final attemptsRemaining = _resolveAttemptsRemaining(data);
      return OtpVerifyResult.invalidCode(
        message,
        attemptsRemaining: attemptsRemaining,
      );
    } on FunctionException catch (e) {
      final data = jh.asMapOrEmpty(e.details);
      final message = _resolveMessage(
        data,
        fallback: e.reasonPhrase ?? 'Verification failed',
      );
      if (e.status == 429) {
        return OtpVerifyResult.rateLimited(message);
      }
      if (e.status == 400) {
        final attemptsRemaining = _resolveAttemptsRemaining(data);
        if (message.toLowerCase().contains('expired')) {
          return OtpVerifyResult.expired(message);
        }
        return OtpVerifyResult.invalidCode(
          message,
          attemptsRemaining: attemptsRemaining,
        );
      }
      debugPrint('[OTP] ❌ FunctionException: $message');
      return OtpVerifyResult.error(message);
    } catch (e) {
      debugPrint('[OTP] ❌ Verify error: $e');
      return OtpVerifyResult.error(e.toString());
    }
  }

  // Local _asMap and _asInt removed — now using shared `jh.*` functions
  // from core/utils/json_helpers.dart

  static String _resolveMessage(
    Map<String, dynamic> data, {
    required String fallback,
  }) {
    final details = jh.asMapOrEmpty(data['details']);
    final message = data['message']?.toString().trim();
    final error = data['error']?.toString().trim();
    final detailsMessage = details['message']?.toString().trim();
    final detailsError = details['error']?.toString().trim();

    for (final candidate in <String?>[
      error,
      message,
      detailsError,
      detailsMessage,
      fallback,
    ]) {
      if (candidate != null && candidate.isNotEmpty) {
        return candidate;
      }
    }

    return fallback;
  }

  static int? _resolveRetryAfterSeconds(Map<String, dynamic> data) {
    final details = jh.asMapOrEmpty(data['details']);
    return jh.asInt(data['retryAfterSeconds']) ??
        jh.asInt(details['retryAfterSeconds']);
  }

  static int? _resolveAttemptsRemaining(Map<String, dynamic> data) {
    final details = jh.asMapOrEmpty(data['details']);
    return jh.asInt(data['attemptsRemaining']) ??
        jh.asInt(details['attemptsRemaining']);
  }

  Future<Map<String, String>> _functionHeaders() async {
    final token = await _getAppCheckToken();
    if (token == null || token.isEmpty) {
      return const <String, String>{};
    }

    return <String, String>{'X-Firebase-AppCheck': token};
  }

  static Future<String?> _defaultAppCheckToken() async {
    final limitedUseToken = await AppCheckService.getLimitedUseToken();
    if (limitedUseToken != null && limitedUseToken.isNotEmpty) {
      return limitedUseToken;
    }

    return AppCheckService.getToken();
  }

  /// Redacts a phone number for safe debug logging: `+250***1234`.
  static String _redact(String phone) {
    if (phone.length <= 4) return '***';
    return '${phone.substring(0, phone.length > 6 ? 4 : 1)}***${phone.substring(phone.length - 4)}';
  }
}
