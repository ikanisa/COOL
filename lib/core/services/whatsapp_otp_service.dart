/// WhatsApp OTP service — calls existing Supabase Edge Functions.
///
/// - `sendOtp`: POST to `send-otp` with `{ phone, language }`
/// - `verifyOtp`: POST to `verify-otp` with `{ phone, code }`
library;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Result types ────────────────────────────────────────────────────────

enum OtpSendStatus { sent, rateLimited, error }

class OtpSendResult {
  const OtpSendResult._({
    required this.status,
    this.message,
    this.retryAfterSeconds,
  });

  const OtpSendResult.sent()
      : this._(status: OtpSendStatus.sent);

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
  WhatsAppOtpService({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  /// Sends a 6-digit OTP to the given E.164 phone via WhatsApp Cloud API.
  Future<OtpSendResult> sendOtp(String e164Phone) async {
    try {
      debugPrint('[OTP] ➜ Sending code to ${_redact(e164Phone)}');
      final response = await _client.functions.invoke(
        'send-otp',
        body: <String, Object?>{
          'phone': e164Phone,
          'language': 'en',
        },
      );

      final data = _asMap(response.data);
      if (data['success'] == true) {
        debugPrint('[OTP] ✓ Code sent');
        return const OtpSendResult.sent();
      }

      final message = data['error']?.toString() ?? 'Failed to send OTP';
      final status = response.status;
      if (status == 429) {
        final retryAfter = _asInt(data['retryAfterSeconds']);
        return OtpSendResult.rateLimited(message,
            retryAfterSeconds: retryAfter);
      }
      return OtpSendResult.error(message);
    } on FunctionException catch (e) {
      final data = _asMap(e.details);
      final message = data['error']?.toString() ??
          e.reasonPhrase ??
          'Failed to send OTP';
      if (e.status == 429) {
        final retryAfter = _asInt(data['retryAfterSeconds']);
        return OtpSendResult.rateLimited(message,
            retryAfterSeconds: retryAfter);
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
        body: <String, Object?>{
          'phone': e164Phone,
          'code': code.trim(),
        },
      );

      final data = _asMap(response.data);
      if (data['success'] == true) {
        debugPrint('[OTP] ✓ Code verified');
        return OtpVerifyResult.verified(
          accessToken: data['access_token']?.toString() ?? '',
          refreshToken: data['refresh_token']?.toString() ?? '',
          userId: data['userId']?.toString() ?? '',
          isNewUser: data['isNewUser'] == true,
        );
      }

      final message = data['error']?.toString() ?? 'Verification failed';
      final status = response.status;
      if (status == 429) {
        return OtpVerifyResult.rateLimited(message);
      }
      final attemptsRemaining = _asInt(data['attemptsRemaining']);
      return OtpVerifyResult.invalidCode(message,
          attemptsRemaining: attemptsRemaining);
    } on FunctionException catch (e) {
      final data = _asMap(e.details);
      final message = data['error']?.toString() ??
          e.reasonPhrase ??
          'Verification failed';
      if (e.status == 429) {
        return OtpVerifyResult.rateLimited(message);
      }
      if (e.status == 400) {
        final attemptsRemaining = _asInt(data['attemptsRemaining']);
        if (message.toLowerCase().contains('expired')) {
          return OtpVerifyResult.expired(message);
        }
        return OtpVerifyResult.invalidCode(message,
            attemptsRemaining: attemptsRemaining);
      }
      debugPrint('[OTP] ❌ FunctionException: $message');
      return OtpVerifyResult.error(message);
    } catch (e) {
      debugPrint('[OTP] ❌ Verify error: $e');
      return OtpVerifyResult.error(e.toString());
    }
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// Redacts a phone number for safe debug logging: `+250***1234`.
  static String _redact(String phone) {
    if (phone.length <= 4) return '***';
    return '${phone.substring(0, phone.length > 6 ? 4 : 1)}***${phone.substring(phone.length - 4)}';
  }
}
