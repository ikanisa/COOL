import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'admin_account_api.dart';
import 'admin_email_otp.dart';
import 'cloudflare_admin_transport.dart';
import 'cloudflare_admin_response.dart';
import '../../app/env/app_env.dart';
import '../../core/data/exact_json_values.dart';
import '../../core/logging/collect_diagnostic_queue.dart';
import '../../core/logging/collect_member_diagnostics.dart';
import '../../core/supabase/collect_supabase_configuration.dart';
import '../../core/cloudflare/collect_turnstile.dart';
import '../../core/cloudflare/collect_cloudflare_client.dart'
    show
        collectGoogleAuthorizationUrlAllowed,
        collectSupabaseGoogleCallbackOriginAllowed;

class CloudflareAdminRequestException extends AdminAccountException {
  const CloudflareAdminRequestException(
    super.message, {
    this.statusCode,
    this.code,
    this.outcomeUnknown = false,
    this.emailOtpReceipt,
    this.invitationFailure,
  });
  final int? statusCode;
  final String? code;
  final bool outcomeUnknown;
  final AdminEmailOtpReceipt? emailOtpReceipt;
  final AdminInvitationFailure? invitationFailure;
}

/// Missing or newer source metadata cannot grant ordinary evidence access.
String retainedEvidenceSourceSensitivity(Object? value) =>
    const {'ordinary', 'raw_sms', 'unclassified'}.contains(value)
    ? value as String
    : 'unclassified';

bool retainedEvidenceRequiresReview(Object? value) =>
    retainedEvidenceSourceSensitivity(value) != 'ordinary';

String? retainedEvidenceReviewReason(String? value) {
  if (value == null || RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    return null;
  }
  final reason = value.trim();
  return reason.length >= 8 && reason.length <= 1000 ? reason : null;
}

void requireRetainedEvidenceReviewAccess(CloudflareAdminUser? user) {
  if (user == null ||
      !user.expiresAt.isAfter(DateTime.now()) ||
      !const {
        'payments.evidence.read',
        'sms.read',
        'sms.reveal',
      }.every(user.permissions.contains)) {
    throw const CloudflareAdminRequestException(
      'This account does not have permission to reveal SMS-source evidence.',
      code: 'permission_required',
    );
  }
  if (!user.hasRecentSensitiveVerification()) {
    throw CloudflareAdminRequestException(
      user.usesEmailVerification
          ? 'Verify your email before revealing SMS-source evidence.'
          : 'Complete a current authenticator check before revealing SMS-source evidence.',
      code: user.usesEmailVerification
          ? 'recent_email_sign_in_required'
          : 'recent_verification_required',
    );
  }
}

CloudflareAdminRequestException _retainedEvidenceFailure(
  http.Response response,
) {
  String? code;
  try {
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is Map) {
      final error = body['error'];
      final value = error is String
          ? error
          : error is Map
          ? error['code']
          : body['code'];
      if (const {
        'permission_required',
        '42501',
        'recent_email_sign_in_required',
        'reason_required',
        'admin_session_required',
        'evidence_integrity_failed',
        'evidence_access_changed',
        'admin_access_changed',
        'session_changed',
        'evidence_unavailable',
      }.contains(value)) {
        code = value as String;
      }
    }
  } catch (_) {
    // Raw server bodies and diagnostic details never become public copy.
  }
  final message = switch (code) {
    'permission_required' ||
    '42501' => 'This account does not have permission to read this evidence.',
    'recent_email_sign_in_required' =>
      'Verify your email before revealing SMS-source evidence.',
    'reason_required' =>
      'Enter a review reason of 8 to 1000 printable characters.',
    'admin_session_required' =>
      'Reopen the Admin workspace and sign in before reviewing this evidence.',
    'evidence_access_changed' || 'admin_access_changed' || 'session_changed' =>
      'Evidence access changed. Refresh this record before reading evidence.',
    'evidence_integrity_failed' =>
      'The retained evidence could not be verified. Close this view and contact your super admin.',
    _ =>
      response.statusCode == 403
          ? 'This account does not have permission to read this evidence.'
          : 'Retained evidence could not be read. Refresh and try again.',
  };
  return CloudflareAdminRequestException(
    message,
    statusCode: response.statusCode,
    code: code,
  );
}

class _EmailVerificationSessionMismatch implements Exception {
  const _EmailVerificationSessionMismatch();
}

AdminEmailOtpReceipt _parseAdminEmailOtpReceipt(Map<String, dynamic> body) {
  final challengeId = body['challenge_id'];
  final retry = body['retry_after'];
  final expires = body['expires_in'];
  if (challengeId is! String ||
      challengeId.isEmpty ||
      challengeId.length > 200 ||
      !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(challengeId) ||
      retry is! int ||
      retry < 60 ||
      retry > 3600 ||
      expires is! int ||
      expires < 60 ||
      expires > 3600 ||
      (body.containsKey('emailStatus') && body['emailStatus'] != 'accepted') ||
      (body.containsKey('delivery_status') &&
          body['delivery_status'] != 'accepted' &&
          body['delivery_status'] != 'unknown')) {
    throw const AdminAccountException(
      'The sign-in code request could not be confirmed. Try again.',
    );
  }
  return AdminEmailOtpReceipt(
    challengeId: challengeId,
    retryAfterSeconds: retry,
    expiresInSeconds: expires,
  );
}

/// Only the server can issue the HttpOnly cookie. No password, session secret,
/// invitation token or refresh token is persisted in browser storage.
class CloudflareAdminUser {
  const CloudflareAdminUser({
    required this.id,
    required this.email,
    required this.role,
    required this.sessionId,
    required this.expiresAt,
    required this.permissions,
    this.assuranceLevel = 1,
    this.mfaAt,
    this.emailVerifiedAt,
    this.usesEmailVerification = false,
    this.principalId,
    this.financialModel = 'transaction_journals',
  });

  final String id;
  final String email;
  final AdminAccountRole role;
  final String sessionId;
  final DateTime expiresAt;
  final List<String> permissions;
  final int assuranceLevel;
  final DateTime? mfaAt;

  /// Internal Supabase-sensitive-operation proof, populated only from the
  /// authenticated, same-public-session sidecar, never the ordinary user DTO.
  final DateTime? emailVerifiedAt;
  final bool usesEmailVerification;
  final String? principalId;
  final String financialModel;
  bool get usesCanonicalEvidence =>
      financialModel == 'canonical_evidence_ledger';

  DateTime? get sensitiveVerificationAt => usesEmailVerification
      ? emailVerifiedAt
      : assuranceLevel == 2
      ? mfaAt
      : null;

  bool hasRecentSensitiveVerification({
    DateTime? now,
    Duration maxAge = const Duration(minutes: 5),
  }) {
    final clock = now ?? DateTime.now();
    final verified = sensitiveVerificationAt;
    if (maxAge <= Duration.zero ||
        !expiresAt.isAfter(clock) ||
        verified == null ||
        (usesEmailVerification && !verified.isUtc) ||
        verified.isAfter(
          usesEmailVerification ? clock : clock.add(const Duration(minutes: 1)),
        )) {
      return false;
    }
    return clock.difference(verified) <= maxAge;
  }

  CloudflareAdminUser withEmailVerification(DateTime? verifiedAt) =>
      CloudflareAdminUser(
        id: id,
        email: email,
        role: role,
        sessionId: sessionId,
        expiresAt: expiresAt,
        permissions: permissions,
        assuranceLevel: assuranceLevel,
        mfaAt: mfaAt,
        emailVerifiedAt: verifiedAt,
        usesEmailVerification: true,
        principalId: principalId,
        financialModel: financialModel,
      );

  /// Cookie expiry checks may refresh without changing the operator's access.
  /// Providers and pending requests use this canonical boundary, rather than
  /// each newly decoded session object, to preserve an owned workspace.
  ({
    String id,
    String sessionId,
    String email,
    AdminAccountRole role,
    String permissions,
    int assuranceLevel,
    DateTime? mfaAt,
    String? principalId,
    String financialModel,
  })
  get authorityKey {
    // Renewing a same-session email proof is not an actor or access change.
    // Sensitive operations check the latest proof separately at each boundary.
    final capabilities = permissions.toSet().toList()..sort();
    return (
      id: id,
      sessionId: sessionId,
      email: email,
      role: role,
      permissions: jsonEncode(capabilities),
      assuranceLevel: assuranceLevel,
      mfaAt: mfaAt,
      principalId: principalId,
      financialModel: financialModel,
    );
  }

  factory CloudflareAdminUser.parse(Map<String, dynamic> body) {
    final user = body['user'];
    if (user is! Map ||
        user['id'] is! String ||
        (user['id'] as String).isEmpty ||
        user['email'] is! String ||
        user['sessionId'] is! String ||
        (user['sessionId'] as String).isEmpty ||
        user['permissions'] is! List ||
        !(user['permissions'] as List).every((value) => value is String)) {
      throw const FormatException('Invalid account response.');
    }
    final role = AdminAccountRole.values.byName(user['role'] as String);
    final expiresAt = DateTime.parse(body['expiresAt'] as String);
    if (!expiresAt.isAfter(DateTime.now())) {
      throw const FormatException('Expired account response.');
    }
    final assuranceLevel = user['assuranceLevel'] ?? 1;
    final rawMfaAt = user['mfaAt'];
    final mfaAt = rawMfaAt is String ? DateTime.tryParse(rawMfaAt) : null;
    final principalId = user['principalId'];
    final financialModel = user['financialModel'] ?? 'transaction_journals';
    if (assuranceLevel is! int ||
        !const {1, 2}.contains(assuranceLevel) ||
        (rawMfaAt != null && mfaAt == null) ||
        (assuranceLevel == 2 && mfaAt == null) ||
        (assuranceLevel == 1 && mfaAt != null) ||
        (mfaAt != null &&
            mfaAt.isAfter(DateTime.now().add(const Duration(minutes: 1)))) ||
        !const {
          'transaction_journals',
          'canonical_evidence_ledger',
        }.contains(financialModel) ||
        (principalId != null &&
            (principalId is! String ||
                !RegExp(
                  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
                ).hasMatch(principalId)))) {
      throw const FormatException('Invalid account verification.');
    }
    return CloudflareAdminUser(
      id: user['id'] as String,
      email: user['email'] as String,
      role: role,
      sessionId: user['sessionId'] as String,
      expiresAt: expiresAt,
      permissions: List<String>.unmodifiable(user['permissions'] as List),
      assuranceLevel: assuranceLevel,
      mfaAt: mfaAt,
      principalId: principalId as String?,
      financialModel: financialModel as String,
    );
  }
}

final cloudflareAdminSessionProvider =
    StateNotifierProvider<
      CloudflareAdminSession,
      AsyncValue<CloudflareAdminUser?>
    >((ref) {
      final controller = CloudflareAdminSession(
        createCloudflareAdminTransport(),
        environment: ref.watch(appEnvProvider),
      );
      unawaited(controller.refresh());
      return controller;
    });

class CloudflareAdminSession
    extends StateNotifier<AsyncValue<CloudflareAdminUser?>> {
  CloudflareAdminSession(
    this._http, {
    Uri? origin,
    AppEnv? environment,
    this._googleAuthEnabled = const bool.fromEnvironment('GOOGLE_AUTH_ENABLED'),
  }) : _origin = origin ?? Uri.base,
       _supabase = _configuration(environment ?? AppEnv.fromEnvironment()),
       super(const AsyncLoading()) {
    _supabase?.adminRequest('auth/session', browserOrigin: _origin);
    _authChallenge =
        _supabase != null &&
            (environment ?? AppEnv.fromEnvironment()).authCaptchaEnabled
        ? CollectTurnstileChallenge(endpoint: _supabase.challengeEndpoint)
        : null;
  }

  static CollectSupabaseConfiguration? _configuration(AppEnv env) {
    if (!const {'cloudflare', 'supabase'}.contains(env.backend)) {
      throw ArgumentError('Unsupported Collect backend.');
    }
    return env.usesSupabase
        ? CollectSupabaseConfiguration.fromEnvironment(env)
        : null;
  }

  final http.Client _http;
  final Uri _origin;
  final CollectSupabaseConfiguration? _supabase;
  final bool _googleAuthEnabled;
  String? _csrfToken;
  late final CollectTurnstileChallenge? _authChallenge;
  Timer? _recheck;
  Timer? _expiry;
  int _epoch = 0;
  int _refreshSequence = 0;
  bool _logoutUnconfirmed = false;
  int _emailOtpAttempt = 0;
  int _sensitiveEmailAttempt = 0;
  bool _sensitiveEmailBusy = false;
  bool _sensitiveEmailUnknown = false;
  ({Object key, DateTime? baseline})? _ambiguousEmailVerification;
  ({String challengeId, int attempt, Object fence, DateTime expiresAt})?
  _sensitiveEmail;
  int _googleAttempt = 0;
  ({String email, String challengeId, int epoch, int attempt})? _emailOtp;

  CloudflareAdminUser? get user => state.asData?.value;
  bool get logoutUnconfirmed => _logoutUnconfirmed;
  bool get managedInvitationProtocolAvailable => _supabase != null;
  bool get usesEmailVerification => _supabase != null;
  bool get sensitiveEmailVerificationUnconfirmed {
    final value = _ambiguousEmailVerification;
    return value != null && value.key == user?.authorityKey;
  }

  bool get googleSignInAvailable =>
      _googleAuthEnabled &&
      _supabase != null &&
      _origin.scheme == 'https' &&
      _origin.hasAuthority &&
      _supabase.project.origin == 'https://rrlduytparvsjfmegalh.supabase.co' &&
      collectSupabaseGoogleCallbackOriginAllowed(_origin.origin) &&
      _supabase.api.origin == _origin.origin &&
      _supabase.adminApi?.origin == _origin.origin;

  /// Public account metadata plus a local generation; never cookie material.
  /// The generation prevents an A-to-B-to-A switch from reviving old work.
  ({int epoch, Object? key}) get authorityFence =>
      (epoch: _epoch, key: user?.authorityKey);

  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = false,
    String? method,
    String? idempotencyKey,
    String? reviewReason,
    int? expectedStatus,
    bool Function()? responseCurrent,
  }) async {
    if (responseCurrent?.call() == false) {
      throw const AdminAccountException('Your sign-in changed. Try again.');
    }
    final before = user?.authorityKey;
    final epoch = _epoch;
    if (authenticated && before == null) {
      throw const AdminAccountException('Sign in again to continue.');
    }
    final uri =
        _supabase?.adminRequest(path, browserOrigin: _origin) ??
        _origin.resolve('/api/admin/$path');
    final verb = method ?? (body == null ? 'GET' : 'POST');
    if (!{'GET', 'POST', 'PATCH'}.contains(verb) ||
        (verb == 'GET' && body != null) ||
        (_supabase == null && uri.origin != _origin.origin) ||
        !uri.path.startsWith(
          _supabase == null
              ? '/api/admin/'
              : CollectSupabaseConfiguration.adminPrefix,
        ) ||
        (reviewReason != null &&
            (reviewReason.trim().length < 8 ||
                reviewReason.length > 1000 ||
                RegExp(r'[\r\n]').hasMatch(reviewReason))) ||
        (idempotencyKey != null &&
            !RegExp(r'^[A-Za-z0-9._:-]{8,200}$').hasMatch(idempotencyKey))) {
      throw ArgumentError('Invalid admin request.');
    }
    final mutation = verb != 'GET';
    final managedInvitationV2 =
        _supabase != null &&
        (path == 'team/v2' ||
            path == 'team/v2/invite' ||
            path == 'team/v2/invitation-status' ||
            RegExp(
              r'^team/v2/[0-9a-f-]{36}/(?:resend|access-notice)$',
            ).hasMatch(path));
    final managedInvitation =
        managedInvitationV2 ||
        _supabase != null &&
            (path == 'team/invite' ||
                path == 'team/invitation-status' ||
                RegExp(r'^team/[0-9a-f-]{36}/resend$').hasMatch(path));
    if (_supabase != null && mutation && authenticated && _csrfToken == null) {
      throw const AdminAccountException(
        'Refresh your session before continuing.',
      );
    }
    var requestBody = body;
    if (mutation &&
        _authChallenge != null &&
        const {
          'auth/otp',
          'auth/login',
          'auth/forgot-password',
          'auth/email/request',
        }.contains(path)) {
      final String captcha;
      try {
        captcha = await _authChallenge.acquire();
      } catch (_) {
        throw const AdminAccountException(
          'Security verification could not finish. Try again.',
        );
      }
      if (!mounted ||
          epoch != _epoch ||
          before != user?.authorityKey ||
          responseCurrent?.call() == false) {
        throw const AdminAccountException('Your sign-in changed. Try again.');
      }
      requestBody = {...?body, 'captcha_token': captcha};
    }
    final encoded = requestBody == null ? null : jsonEncode(requestBody);
    final headers = {
      'Accept': 'application/json',
      if (mutation) 'Content-Type': 'application/json',
      if (mutation) 'X-Collect-Admin': '1',
      if (_supabase != null) 'apikey': _supabase.publishableKey,
      if (_supabase != null && mutation)
        'X-Collect-Requested-With': 'collect-admin',
      if (_supabase != null && mutation && _csrfToken != null)
        'X-Collect-CSRF': _csrfToken!,
      'Idempotency-Key': ?idempotencyKey,
      'X-Collect-Review-Reason': ?reviewReason?.trim(),
    };
    late http.Response response;
    try {
      response = await boundedAdminResponse(
        _http,
        uri,
        method: verb,
        headers: headers,
        body: encoded,
      );
    } on TimeoutException {
      throw CloudflareAdminRequestException(
        mutation
            ? 'The result is unknown. Check the request before trying again.'
            : 'The workspace could not be reached. Try again.',
        outcomeUnknown: mutation,
      );
    } on http.ClientException {
      throw CloudflareAdminRequestException(
        mutation
            ? 'The result is unknown. Check the request before trying again.'
            : 'The workspace could not be reached. Try again.',
        outcomeUnknown: mutation,
      );
    }
    if (!mounted ||
        epoch != _epoch ||
        responseCurrent?.call() == false ||
        (authenticated && before != user?.authorityKey)) {
      throw CloudflareAdminRequestException(
        'Your session changed. Reopen this page before continuing.',
        outcomeUnknown: mutation,
      );
    }
    if (response.statusCode == 401 && path != 'auth/verify') {
      clear();
      if (path == 'auth/session' && expectedStatus == null) {
        return {'user': null};
      }
      throw const CloudflareAdminRequestException(
        'Sign in again to continue.',
        statusCode: 401,
        code: 'unauthenticated',
      );
    }
    if (expectedStatus != null &&
        response.statusCode != expectedStatus &&
        (!mutation || response.statusCode < 400)) {
      String? refreshCode;
      if (response.statusCode == 409 &&
          const {'auth/session', 'auth/email-verification'}.contains(path)) {
        try {
          final value = jsonDecode(response.body);
          final error = value is Map ? value['error'] : null;
          final code = error is Map
              ? error['code']
              : value is Map
              ? value['code']
              : null;
          if (code == 'session_refresh_pending') refreshCode = code as String;
        } on Object {
          // An unparseable/nonmatching denial never becomes a retry signal.
        }
      }
      throw CloudflareAdminRequestException(
        'The current session response could not be confirmed.',
        statusCode: response.statusCode,
        code: refreshCode,
        outcomeUnknown: mutation,
      );
    }
    if (managedInvitation &&
        response.statusCode >= 200 &&
        response.statusCode < 300 &&
        response.statusCode != 200) {
      throw CloudflareAdminRequestException(
        'The original invitation response could not be verified.',
        statusCode: response.statusCode,
        outcomeUnknown: mutation,
      );
    }
    // Proxy HTML, empty bodies and malformed JSON never become success.
    Map<String, dynamic> result;
    try {
      result = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      throw CloudflareAdminRequestException(
        'The account service is unavailable. Please try again.',
        statusCode: response.statusCode,
        outcomeUnknown:
            mutation &&
            (response.statusCode >= 500 ||
                (response.statusCode >= 200 && response.statusCode < 300)),
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = result['error'];
      final code = error is String
          ? error
          : error is Map && error['code'] is String
          ? error['code'] as String
          : result['code'] is String
          ? result['code'] as String
          : null;
      final message = switch (code) {
        'google_sign_in_unconfirmed' =>
          'Google sign-in could not be confirmed. Check your session before starting a fresh sign-in.',
        'admin_access_not_approved' =>
          'This email does not have Admin access. Contact your super admin.',
        'invalid_credentials'
            when const {'auth/verify', 'auth/email/verify'}.contains(path) =>
          'That code is invalid or expired. Use the latest email code or request a new one.',
        'email_unavailable' when path == 'auth/otp' =>
          'Email sign-in is unavailable right now. Try again later.',
        'recent_email_sign_in_required' =>
          'Verify your email before making this change.',
        'password_recovery_required' when path == 'auth/change-password' =>
          'Use Set or reset password by email to change the password for this sign-in.',
        _ => switch (response.statusCode) {
          403 =>
            mutation
                ? 'You do not have permission to make this change.'
                : 'You do not have permission to view these records.',
          409 => switch (code) {
            'account_changed' => 'This account changed. Refresh and try again.',
            'state_conflict' =>
              'This record or its related state does not meet the requirements for this request. Refresh the details before continuing.',
            'idempotency_conflict' =>
              'This request reference was already used for different content. Check the original request before making another change.',
            'request_pending' =>
              'The original request is still pending. Check its receipt before continuing.',
            _ =>
              'The request conflicts with the current state. Refresh the details and check the original request before continuing.',
          },
          429 => 'Too many attempts. Please wait before trying again.',
          _ when path == 'auth/login' => 'The email or password is incorrect.',
          _ when path == 'auth/complete-password' =>
            'This link is invalid or expired. Request a new email.',
          _ when path == 'auth/change-password' =>
            'Password change was not confirmed. Check your current password.',
          _ =>
            mutation
                ? 'The request was not confirmed. Refresh before trying again.'
                : 'The records could not be loaded. Refresh and try again.',
        },
      };
      throw CloudflareAdminRequestException(
        message,
        statusCode: response.statusCode,
        code: code,
        outcomeUnknown: mutation && response.statusCode >= 500,
        emailOtpReceipt: path == 'auth/otp' && code == 'email_delivery_unknown'
            ? _parseAdminEmailOtpReceipt(result)
            : null,
        invitationFailure: managedInvitation
            ? parseAdminInvitationFailure(
                result,
                response.statusCode,
                contractVersion: managedInvitationV2 ? 2 : 1,
              )
            : null,
      );
    }
    if (_supabase != null &&
        !const {
          'auth/email-verification',
          'auth/email/request',
          'auth/email/verify',
        }.contains(path) &&
        result.containsKey('csrfToken')) {
      final token = result['csrfToken'];
      if (token == null && path == 'auth/session' && result['user'] == null) {
        _csrfToken = null;
        return result;
      }
      if (token is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{32,200}$').hasMatch(token)) {
        throw const AdminAccountException(
          'Session verification could not finish.',
        );
      }
      _csrfToken = token;
    }
    return result;
  }

  /// Telemetry cannot clear authentication, replay business requests or surface
  /// raw errors. Its fixed batch has its own bounded, best-effort response.
  Future<CollectDiagnosticDelivery> sendDiagnosticBatch(
    Map<String, Object?> body, {
    required bool Function() current,
  }) async {
    final before = authorityFence,
        configuration = _supabase,
        token = _csrfToken;
    if (configuration == null) return CollectDiagnosticDelivery.discard;
    if (!current() ||
        user == null ||
        !user!.expiresAt.isAfter(DateTime.now()) ||
        token == null) {
      return CollectDiagnosticDelivery.retry;
    }
    try {
      final response = await boundedAdminResponse(
        _http,
        configuration.adminRequest('diagnostics', browserOrigin: _origin),
        method: 'POST',
        maximumBytes: 4096,
        body: jsonEncode(body),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'apikey': configuration.publishableKey,
          'X-Collect-Admin': '1',
          'X-Collect-Requested-With': 'collect-admin',
          'X-Collect-CSRF': token,
        },
      );
      if (!mounted || !current() || before != authorityFence) {
        return CollectDiagnosticDelivery.retry;
      }
      Object? value;
      try {
        value = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {}
      return collectDiagnosticReply(response.statusCode, value);
    } catch (_) {
      return CollectDiagnosticDelivery.retry;
    }
  }

  Future<String> retainedEvidence(
    String id, {
    required String sha256Hex,
    required int sizeBytes,
    Object? sourceSensitivity,
    String? reviewReason,
  }) async {
    final before = authorityFence,
        user = this.user,
        protectedSource = retainedEvidenceRequiresReview(sourceSensitivity);
    if (!RegExp(
          r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$',
        ).hasMatch(id) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256Hex) ||
        sizeBytes < 1 ||
        sizeBytes > 1048576 ||
        user == null ||
        !user.expiresAt.isAfter(DateTime.now()) ||
        !user.permissions.contains('payments.evidence.read')) {
      throw const AdminAccountException(
        'Retained evidence is unavailable to this account.',
      );
    }
    String? reason;
    if (protectedSource) {
      requireRetainedEvidenceReviewAccess(user);
      reason = retainedEvidenceReviewReason(reviewReason);
      if (reason == null) {
        throw const CloudflareAdminRequestException(
          'Enter a review reason of 8 to 1000 printable characters.',
          code: 'reason_required',
        );
      }
    }
    http.Response response;
    try {
      response = await boundedAdminResponse(
        _http,
        _origin.resolve('/api/admin/evidence/$id'),
        method: 'GET',
        headers: {'Accept': 'text/plain', 'X-Collect-Review-Reason': ?reason},
        // A denied read may carry a small JSON envelope even for tiny evidence.
        // The successful plaintext must still match the exact retained size.
        maximumBytes: max(sizeBytes, 4096),
      );
    } on Object {
      throw const AdminAccountException(
        'Retained evidence could not be read. Refresh and try again.',
      );
    }
    final current = this.user;
    if (!mounted ||
        before != authorityFence ||
        current == null ||
        !current.expiresAt.isAfter(DateTime.now()) ||
        !current.permissions.contains('payments.evidence.read')) {
      throw const AdminAccountException(
        'The retained evidence or current authorization could not be verified.',
      );
    }
    if (response.statusCode != 200) throw _retainedEvidenceFailure(response);
    final sensitivity = response.headers['x-collect-evidence-sensitivity'];
    if (!const {'ordinary', 'raw_sms', 'unclassified'}.contains(sensitivity) ||
        (!protectedSource && retainedEvidenceRequiresReview(sensitivity))) {
      throw const CloudflareAdminRequestException(
        'Evidence access changed. Refresh this record before reading evidence.',
        code: 'evidence_access_changed',
      );
    }
    // Email proof can disappear without changing the same-session authority
    // fence. Recheck it after the protected response has finished as well.
    if (protectedSource) requireRetainedEvidenceReviewAccess(current);
    if (response.headers['content-type']?.split(';').first.trim() !=
            'text/plain' ||
        response.bodyBytes.length != sizeBytes ||
        sha256.convert(response.bodyBytes).toString() != sha256Hex) {
      throw const AdminAccountException(
        'The retained evidence or current authorization could not be verified.',
      );
    }
    try {
      return utf8.decode(response.bodyBytes);
    } on FormatException {
      throw const FormatException(
        'The retained evidence encoding could not be verified.',
      );
    }
  }

  Future<void> refresh() async {
    await _refresh();
  }

  Future<bool> recheckSession() async {
    final confirmed = await _refresh(requireConfirmation: true);
    if (confirmed == null) {
      throw const AdminAccountSecurityOutcomeUnknown(
        'Your session could not be confirmed. Check your session again.',
      );
    }
    return confirmed;
  }

  Future<bool?> _refresh({bool requireConfirmation = false}) async {
    if (_logoutUnconfirmed) {
      if (requireConfirmation) {
        throw const AdminAccountSecurityOutcomeUnknown(
          'Sign-out is not confirmed. Complete sign-out before signing in again.',
        );
      }
      return null;
    }
    final epoch = _epoch;
    final sequence = ++_refreshSequence;
    try {
      final body = await _readSessionMetadata(
        'auth/session',
        expectedStatus: requireConfirmation ? 200 : null,
        current: () =>
            mounted && epoch == _epoch && sequence == _refreshSequence,
      );
      if (!mounted || epoch != _epoch || sequence != _refreshSequence) {
        return null;
      }
      if (requireConfirmation) {
        final fields = {
          'user',
          'expiresAt',
          'ownerEmail',
          if (_supabase != null) 'csrfToken',
        };
        if (body.length != fields.length ||
            !fields.every(body.containsKey) ||
            body['ownerEmail'] != 'info@ikanisa.com' ||
            (body['user'] == null &&
                (body['expiresAt'] != null || body['csrfToken'] != null)) ||
            (body['user'] != null &&
                (body['user'] is! Map ||
                    (_supabase != null &&
                        (body['csrfToken'] is! String ||
                            !RegExp(
                              r'^[a-f0-9]{64}$',
                            ).hasMatch(body['csrfToken'] as String)))))) {
          throw const FormatException('Invalid session confirmation envelope.');
        }
      }
      var value = body['user'] == null ? null : CloudflareAdminUser.parse(body);
      if (value == null) {
        clear();
        return false;
      }
      value = await _withCurrentEmailVerification(
        value,
        current: () =>
            mounted && epoch == _epoch && sequence == _refreshSequence,
      );
      if (!mounted || epoch != _epoch || sequence != _refreshSequence) {
        return null;
      }
      if (user != null && user!.authorityKey != value.authorityKey) {
        // A role/capability change is a real fence even if the public session ID
        // is unchanged. Responses started under departed access cannot apply.
        _epoch++;
      }
      state = AsyncData(value);
      _expiry?.cancel();
      _recheck?.cancel();
      _expiry = Timer(value.expiresAt.difference(DateTime.now()), clear);
      _recheck = Timer(const Duration(seconds: 60), () => unawaited(refresh()));
      return true;
    } catch (error, stack) {
      if (mounted && epoch == _epoch && sequence == _refreshSequence) {
        // Fence requests started before a failed access check even if the same
        // public session is restored later. Unavailable authority grants none.
        _epoch++;
        _expiry?.cancel();
        _recheck?.cancel();
        state = AsyncError(error, stack);
      }
      if (requireConfirmation) {
        throw const AdminAccountSecurityOutcomeUnknown(
          'Your session could not be confirmed. Check your session again.',
        );
      }
      return null;
    }
  }

  /// Only dedicated refresh-lease contention is retried, and only on these
  /// reads. This never replays a verification, invitation or financial action.
  Future<Map<String, dynamic>> _readSessionMetadata(
    String path, {
    required bool Function() current,
    int? expectedStatus,
  }) async {
    for (var attempt = 0; ; attempt++) {
      if (!current()) {
        throw const AdminAccountException('Your sign-in changed. Try again.');
      }
      try {
        final result = await request(
          path,
          expectedStatus: expectedStatus,
          responseCurrent: current,
        );
        if (!current()) {
          throw const AdminAccountException('Your sign-in changed. Try again.');
        }
        // request() already admits only successful status codes. Session
        // confirmation additionally validates its exact existing envelope.
        return result;
      } on CloudflareAdminRequestException catch (failure) {
        if (failure.statusCode != 409 ||
            failure.code != 'session_refresh_pending' ||
            attempt >= 2 ||
            !current()) {
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
      }
    }
  }

  DateTime? _parseEmailVerification(
    Map<String, dynamic> body,
    CloudflareAdminUser expected,
  ) {
    if (body['sessionId'] is String &&
        body['sessionId'] != expected.sessionId) {
      throw const _EmailVerificationSessionMismatch();
    }
    if (body.length != 3 ||
        body['contractVersion'] is! int ||
        body['contractVersion'] != 1 ||
        body['sessionId'] != expected.sessionId ||
        !body.containsKey('emailVerifiedAt')) {
      throw const FormatException('Invalid email verification response.');
    }
    final raw = body['emailVerifiedAt'];
    if (raw == null) return null;
    if (raw is! String || !RegExp(r'(?:Z|\+00:00)$').hasMatch(raw)) {
      throw const FormatException('Invalid email verification time.');
    }
    final value = exactJsonTimestamp(raw, field: 'Admin email verification');
    if (!value.isUtc || value.isAfter(DateTime.now().toUtc())) {
      throw const FormatException('Invalid email verification time.');
    }
    return value;
  }

  Future<CloudflareAdminUser> _withCurrentEmailVerification(
    CloudflareAdminUser value, {
    required bool Function() current,
  }) async {
    if (_supabase == null) return value;
    try {
      final proof = await _readSessionMetadata(
        'auth/email-verification',
        current: current,
        expectedStatus: 200,
      );
      if (!current()) return value.withEmailVerification(null);
      return value.withEmailVerification(
        _admitEmailProof(_parseEmailVerification(proof, value), value),
      );
    } on _EmailVerificationSessionMismatch {
      // This is an identity consistency failure, not an absent proof. Never
      // install account A using a sidecar issued for account/session B.
      rethrow;
    } on CloudflareAdminRequestException catch (failure) {
      if (failure.statusCode == 401) clear();
      return value.withEmailVerification(null);
    } on Object {
      // A missing/unavailable/malformed proof grants no sensitive authority.
      // It does not turn a confirmed ordinary AAL1 session into a logout.
      return value.withEmailVerification(null);
    }
  }

  DateTime? _admitEmailProof(DateTime? proof, CloudflareAdminUser actor) {
    final ambiguity = _ambiguousEmailVerification;
    if (ambiguity == null) return proof;
    if (ambiguity.key != actor.authorityKey) {
      _ambiguousEmailVerification = null;
      return proof;
    }
    if (proof != null &&
        (ambiguity.baseline == null || proof.isAfter(ambiguity.baseline!))) {
      _ambiguousEmailVerification = null;
      _sensitiveEmailUnknown = false;
      return proof;
    }
    // A still-fresh pre-existing proof is not evidence that an ambiguous
    // verification completed. Ordinary AAL1 remains available, sensitive work
    // stays closed until a genuinely newer proof or explicit fresh sign-in.
    return null;
  }

  Future<void> signIn(String email, String password) async {
    clear();
    await request('auth/login', body: {'email': email, 'password': password});
    await refresh();
    if (user == null) {
      throw const AdminAccountException('Sign-in could not be confirmed.');
    }
  }

  /// Sensitive email verification keeps the original HttpOnly session and
  /// CSRF material. It never calls the ordinary sign-in flow or upgrades AAL.
  CloudflareAdminUser _sensitiveEmailActor() {
    final actor = user;
    if (_supabase == null ||
        actor == null ||
        !actor.expiresAt.isAfter(DateTime.now())) {
      throw const AdminAccountException('Sign in again to verify your email.');
    }
    return actor;
  }

  bool _sensitiveEmailCurrent(int attempt, Object fence) =>
      mounted &&
      attempt == _sensitiveEmailAttempt &&
      fence == authorityFence &&
      user != null &&
      user!.expiresAt.isAfter(DateTime.now());

  Future<AdminEmailOtpReceipt> requestSensitiveEmailVerification() async {
    _sensitiveEmailActor();
    if (_sensitiveEmailBusy ||
        _sensitiveEmailUnknown ||
        sensitiveEmailVerificationUnconfirmed) {
      throw const AdminAccountException(
        'Check the current verification before requesting another code.',
      );
    }
    final fence = authorityFence;
    final attempt = ++_sensitiveEmailAttempt;
    _sensitiveEmail = null;
    _sensitiveEmailBusy = true;
    try {
      final body = await request(
        'auth/email/request',
        body: const {},
        authenticated: true,
        expectedStatus: 202,
        responseCurrent: () => _sensitiveEmailCurrent(attempt, fence),
      );
      if (!_sensitiveEmailCurrent(attempt, fence)) {
        throw const AdminAccountException('Your sign-in changed. Try again.');
      }
      final id = body['challenge_id'];
      final retry = body['retry_after'];
      final expires = body['expires_in'];
      if (body.length != 4 ||
          id is! String ||
          !RegExp(
            r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$',
          ).hasMatch(id) ||
          retry != 60 ||
          retry is! int ||
          expires is! int ||
          expires < 0 ||
          expires > 300 ||
          !const {'accepted', 'unknown'}.contains(body['delivery_status'])) {
        throw const CloudflareAdminRequestException(
          'The code request could not be confirmed. Check verification before requesting another code.',
          outcomeUnknown: true,
        );
      }
      final receipt = AdminEmailOtpReceipt(
        challengeId: id,
        retryAfterSeconds: retry,
        expiresInSeconds: expires,
      );
      _sensitiveEmail = (
        challengeId: id,
        attempt: attempt,
        fence: fence,
        expiresAt: DateTime.now().add(Duration(seconds: expires)),
      );
      if (body['delivery_status'] == 'unknown') {
        throw AdminEmailOtpDeliveryUnknown(receipt);
      }
      return receipt;
    } on CloudflareAdminRequestException catch (failure) {
      if (_sensitiveEmailCurrent(attempt, fence) && failure.outcomeUnknown) {
        _sensitiveEmailUnknown = true;
      }
      rethrow;
    } finally {
      if (attempt == _sensitiveEmailAttempt) _sensitiveEmailBusy = false;
    }
  }

  Future<void> verifySensitiveEmailVerification({
    required String challengeId,
    required String code,
  }) async {
    final actor = _sensitiveEmailActor();
    final pending = _sensitiveEmail;
    if (_sensitiveEmailBusy ||
        _sensitiveEmailUnknown ||
        pending == null ||
        pending.challengeId != challengeId ||
        !_sensitiveEmailCurrent(pending.attempt, pending.fence) ||
        !pending.expiresAt.isAfter(DateTime.now()) ||
        !RegExp(r'^[0-9]{6}$').hasMatch(code)) {
      throw const AdminAccountException(
        'Use the current six-digit email code. Check an unconfirmed verification before trying again.',
      );
    }
    _sensitiveEmailBusy = true;
    final ambiguity = (
      key: actor.authorityKey as Object,
      baseline: actor.emailVerifiedAt,
    );
    _ambiguousEmailVerification = ambiguity;
    ++_refreshSequence;
    state = AsyncData(user!.withEmailVerification(null));
    try {
      final body = await request(
        'auth/email/verify',
        body: {'challenge_id': challengeId, 'code': code},
        authenticated: true,
        expectedStatus: 200,
        responseCurrent: () =>
            _sensitiveEmailCurrent(pending.attempt, pending.fence),
      );
      if (!_sensitiveEmailCurrent(pending.attempt, pending.fence)) {
        throw const AdminAccountException('Your sign-in changed. Try again.');
      }
      DateTime? proof;
      try {
        proof = _parseEmailVerification(body, actor);
        if (proof == null ||
            ambiguity.baseline != null && !proof.isAfter(ambiguity.baseline!) ||
            !actor
                .withEmailVerification(proof)
                .hasRecentSensitiveVerification()) {
          throw const FormatException('Missing new email proof.');
        }
      } on Object {
        // A successful but invalid response may have consumed the code. Only a
        // subsequent read can confirm it; never replay the verification.
        ++_refreshSequence;
        state = AsyncData(user!.withEmailVerification(null));
        throw const CloudflareAdminRequestException(
          'Email verification could not be confirmed. Check verification.',
          outcomeUnknown: true,
        );
      }
      ++_refreshSequence;
      state = AsyncData(user!.withEmailVerification(proof));
      _ambiguousEmailVerification = null;
      _sensitiveEmail = null;
      _sensitiveEmailUnknown = false;
    } on CloudflareAdminRequestException catch (failure) {
      if (_sensitiveEmailCurrent(pending.attempt, pending.fence) &&
          failure.outcomeUnknown) {
        _sensitiveEmailUnknown = true;
      } else if (_sensitiveEmailCurrent(pending.attempt, pending.fence) &&
          _ambiguousEmailVerification == ambiguity) {
        _ambiguousEmailVerification = null;
        state = AsyncData(
          user!.withEmailVerification(
            failure.code == 'invalid_credentials' &&
                    const {400, 422}.contains(failure.statusCode)
                ? ambiguity.baseline
                : null,
          ),
        );
      }
      rethrow;
    } finally {
      if (pending.attempt == _sensitiveEmailAttempt) {
        _sensitiveEmailBusy = false;
      }
    }
  }

  /// Explicit read-only recovery. This does not resend an OTP or replay the
  /// sensitive operation that led the operator here.
  Future<bool> recheckSensitiveEmailVerification() async {
    final actor = _sensitiveEmailActor();
    if (_sensitiveEmailBusy) {
      throw const AdminAccountException('Wait for the current verification.');
    }
    final attempt = _sensitiveEmailAttempt;
    final fence = authorityFence;
    _sensitiveEmailBusy = true;
    try {
      final body = await _readSessionMetadata(
        'auth/email-verification',
        expectedStatus: 200,
        current: () => _sensitiveEmailCurrent(attempt, fence),
      );
      final proof = _admitEmailProof(
        _parseEmailVerification(body, actor),
        actor,
      );
      if (!_sensitiveEmailCurrent(attempt, fence)) {
        throw const AdminAccountException('Your sign-in changed. Try again.');
      }
      ++_refreshSequence;
      state = AsyncData(user!.withEmailVerification(proof));
      if (user!.hasRecentSensitiveVerification()) {
        _sensitiveEmail = null;
        _sensitiveEmailUnknown = false;
        return true;
      }
      return false;
    } on Object {
      if (_sensitiveEmailCurrent(attempt, fence)) {
        ++_refreshSequence;
        state = AsyncData(user!.withEmailVerification(null));
      }
      rethrow;
    } finally {
      if (attempt == _sensitiveEmailAttempt) _sensitiveEmailBusy = false;
    }
  }

  void cancelSensitiveEmailVerification() {
    ++_sensitiveEmailAttempt;
    _sensitiveEmail = null;
    _sensitiveEmailBusy = false;
    _sensitiveEmailUnknown = false;
  }

  void cancelGoogleSignIn() {
    _googleAttempt++;
  }

  Future<void> signInWithGoogle({
    required AdminGoogleAuthorize authorize,
  }) async {
    if (!googleSignInAvailable) {
      throw const AdminAccountException('Google sign-in is unavailable.');
    }
    clear();
    final epoch = _epoch, attempt = ++_googleAttempt;
    final random = Random.secure();
    String nonce() => base64UrlEncode(
      List<int>.generate(32, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
    final verifier = nonce(), clientState = nonce();
    final challenge = base64UrlEncode(
      sha256.convert(utf8.encode(verifier)).bytes,
    ).replaceAll('=', '');
    void checkCurrent() {
      if (!mounted || epoch != _epoch || attempt != _googleAttempt) {
        throw const AdminAccountException('Your sign-in changed. Try again.');
      }
    }

    final reply = await authorize(
      (returnOrigin) async {
        checkCurrent();
        if (returnOrigin != _origin.origin) {
          throw const AdminAccountException(
            'Open the Admin website to sign in.',
          );
        }
        final response = await request(
          'auth/google/start',
          body: {
            'code_challenge': challenge,
            'client_state': clientState,
            'return_origin': returnOrigin,
          },
        );
        checkCurrent();
        final value = response['authorization_url'];
        final uri = value is String ? Uri.tryParse(value) : null;
        if (!collectGoogleAuthorizationUrlAllowed(
          uri,
          usesSupabase: true,
          supabaseCallbackOrigin: _origin.origin,
        )) {
          throw const AdminAccountException('Google sign-in is unavailable.');
        }
        return uri!;
      },
      clientState,
      _origin.origin,
    );
    checkCurrent();
    if (reply['state'] != clientState) {
      throw const AdminAccountException(
        'Google sign-in could not be verified.',
      );
    }
    if (reply['error'] != null) {
      if (reply['error'] == 'google_sign_in_unconfirmed') {
        throw const AdminAccountSecurityOutcomeUnknown(
          'Google sign-in could not be confirmed. Check your session before starting a fresh sign-in.',
        );
      }
      throw const AdminAccountException('Google sign-in could not finish.');
    }
    if (reply['code'] is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(reply['code'] as String)) {
      throw const AdminAccountException(
        'Google sign-in could not be verified.',
      );
    }
    final Map<String, dynamic> response;
    try {
      response = await request(
        'auth/google/exchange',
        body: {
          'code': reply['code'],
          'code_verifier': verifier,
          'client_state': clientState,
        },
      );
    } on CloudflareAdminRequestException catch (failure) {
      if (!failure.outcomeUnknown) rethrow;
      checkCurrent();
      // Read the current cookie once. Never replay a consumed Google handoff,
      // and never label a possibly preexisting session a completed new login.
      await refresh();
      throw const AdminAccountSecurityOutcomeUnknown(
        'Google sign-in could not be confirmed. Check your session before starting a fresh sign-in.',
      );
    }
    checkCurrent();
    final CloudflareAdminUser verified;
    try {
      verified = CloudflareAdminUser.parse(response);
    } on Object {
      await refresh();
      throw const AdminAccountSecurityOutcomeUnknown(
        'Google sign-in could not be confirmed. Check your session before starting a fresh sign-in.',
      );
    }
    await refresh();
    checkCurrent();
    if (user == null || user!.authorityKey != verified.authorityKey) {
      clear();
      throw const AdminAccountException(
        'Google sign-in could not be confirmed.',
      );
    }
    // Assurance remains exactly the server value. Google does not create an
    // email-verification proof for sensitive Admin operations.
  }

  Future<AdminEmailOtpReceipt> requestEmailOtp(String email) async {
    final normalized = normalizeAdminEmail(email);
    clear();
    final epoch = _epoch;
    final attempt = _emailOtpAttempt;
    AdminEmailOtpReceipt receipt;
    var deliveryUnknown = false;
    try {
      final response = await request('auth/otp', body: {'email': normalized});
      receipt = _parseAdminEmailOtpReceipt(response);
      deliveryUnknown = response['delivery_status'] == 'unknown';
    } on CloudflareAdminRequestException catch (failure) {
      if (failure.code != 'email_delivery_unknown' ||
          failure.emailOtpReceipt == null) {
        rethrow;
      }
      receipt = failure.emailOtpReceipt!;
      deliveryUnknown = true;
    }
    if (!mounted || epoch != _epoch || attempt != _emailOtpAttempt) {
      throw const AdminAccountException('Your sign-in changed. Try again.');
    }
    _emailOtp = (
      email: normalized,
      challengeId: receipt.challengeId,
      epoch: epoch,
      attempt: attempt,
    );
    if (deliveryUnknown) throw AdminEmailOtpDeliveryUnknown(receipt);
    return receipt;
  }

  Future<void> verifyEmailOtp({
    required String email,
    required String challengeId,
    required String code,
  }) async {
    final normalized = normalizeAdminEmail(email);
    final token = normalizeAdminEmailOtp(code);
    final pending = _emailOtp;
    if (pending == null ||
        pending.email != normalized ||
        pending.challengeId != challengeId ||
        pending.epoch != _epoch ||
        pending.attempt != _emailOtpAttempt) {
      throw const AdminAccountException('Request a fresh sign-in code.');
    }
    Map<String, dynamic> body;
    try {
      body = await request(
        'auth/verify',
        body: {'email': normalized, 'challenge_id': challengeId, 'code': token},
      );
    } on CloudflareAdminRequestException catch (failure) {
      if (!failure.outcomeUnknown) rethrow;
      // The service may have consumed the code and set its HttpOnly cookie.
      // Check that cookie once; never replay a verification automatically.
      if (await _confirmEmailOtpSession(pending)) return;
      throw const AdminAccountSecurityOutcomeUnknown(
        'Sign-in could not be confirmed. Reload to check your session before requesting a new code.',
      );
    }
    if (!mounted || _emailOtp != pending || _epoch != pending.epoch) {
      throw const AdminAccountException('Your sign-in changed. Try again.');
    }
    CloudflareAdminUser verified;
    try {
      verified = CloudflareAdminUser.parse(body);
    } on Object {
      if (await _confirmEmailOtpSession(pending)) return;
      throw const AdminAccountSecurityOutcomeUnknown(
        'Sign-in could not be confirmed. Reload to check your session before requesting a new code.',
      );
    }
    if (verified.email.toLowerCase() != normalized) {
      clear();
      throw const AdminAccountException('Sign-in could not be confirmed.');
    }
    if (!await _confirmEmailOtpSession(pending, expected: verified)) {
      throw const AdminAccountException('Sign-in could not be confirmed.');
    }
  }

  Future<bool> _confirmEmailOtpSession(
    ({String email, String challengeId, int epoch, int attempt}) pending, {
    CloudflareAdminUser? expected,
  }) async {
    if (!mounted || _emailOtp != pending || _epoch != pending.epoch) {
      return false;
    }
    final sequence = ++_refreshSequence;
    try {
      final body = await _readSessionMetadata(
        'auth/session',
        current: () =>
            mounted &&
            _emailOtp == pending &&
            _epoch == pending.epoch &&
            _refreshSequence == sequence,
      );
      if (!mounted ||
          _epoch != pending.epoch ||
          _refreshSequence != sequence ||
          _emailOtp != pending ||
          body['user'] == null) {
        return false;
      }
      var current = CloudflareAdminUser.parse(body);
      if (current.email.toLowerCase() != pending.email ||
          (expected != null &&
              (current.id != expected.id ||
                  current.sessionId != expected.sessionId))) {
        return false;
      }
      current = await _withCurrentEmailVerification(
        current,
        current: () =>
            mounted &&
            _epoch == pending.epoch &&
            _refreshSequence == sequence &&
            _emailOtp == pending,
      );
      if (!mounted ||
          _epoch != pending.epoch ||
          _refreshSequence != sequence ||
          _emailOtp != pending) {
        return false;
      }
      // Install only after binding the authoritative cookie's public identity
      // to the email being verified. A different cookie must not redirect UI.
      _emailOtp = null;
      state = AsyncData(current);
      _expiry?.cancel();
      _recheck?.cancel();
      _expiry = Timer(current.expiresAt.difference(DateTime.now()), clear);
      _recheck = Timer(const Duration(seconds: 60), () => unawaited(refresh()));
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> verifyAuthenticator({
    required String factorId,
    required String challengeId,
    required String code,
  }) async {
    final before = user;
    if (before == null || before.principalId == null) {
      throw const AdminAccountException('Sign in again to continue.');
    }
    final result = await request(
      'auth/mfa/verify',
      authenticated: true,
      body: {'factor_id': factorId, 'challenge_id': challengeId, 'code': code},
    );
    if (result['ok'] != true) {
      throw const CloudflareAdminRequestException(
        'Verification could not be confirmed. Recheck your session.',
        outcomeUnknown: true,
      );
    }
    // A real verification rotates the HttpOnly cookie on the server. Fence
    // responses started with the old cookie before reading the new authority.
    final rotatedEpoch = ++_epoch;
    ++_refreshSequence;
    _expiry?.cancel();
    _recheck?.cancel();
    final expectedSequence = _refreshSequence + 1;
    await refresh();
    final current = user;
    final expectedEpoch =
        rotatedEpoch +
        (current != null && before.authorityKey != current.authorityKey
            ? 1
            : 0);
    final now = DateTime.now();
    if (!mounted ||
        _logoutUnconfirmed ||
        _epoch != expectedEpoch ||
        _refreshSequence != expectedSequence ||
        current == null ||
        current.id != before.id ||
        current.email != before.email ||
        current.sessionId != before.sessionId ||
        current.principalId != before.principalId ||
        current.role != before.role ||
        current.authorityKey.permissions != before.authorityKey.permissions ||
        current.assuranceLevel != 2 ||
        current.mfaAt == null ||
        current.mfaAt!.isBefore(now.subtract(const Duration(minutes: 5))) ||
        current.mfaAt!.isAfter(now.add(const Duration(minutes: 1)))) {
      throw const CloudflareAdminRequestException(
        'Verification could not be confirmed. Recheck your session.',
        outcomeUnknown: true,
      );
    }
  }

  Future<void> signOut() async {
    _epoch++;
    _refreshSequence++;
    _logoutUnconfirmed = true;
    _expiry?.cancel();
    _recheck?.cancel();
    state = const AsyncLoading();
    try {
      final result = await request('auth/logout', body: const {});
      if (result['ok'] != true) {
        throw const AdminAccountException('Sign-out was not confirmed.');
      }
      clear();
    } catch (error, stack) {
      if (mounted) {
        _logoutUnconfirmed = true;
        state = AsyncError(
          const AdminAccountException('Sign-out was not confirmed. Try again.'),
          stack,
        );
      }
      rethrow;
    }
  }

  void clear() {
    _authChallenge?.cancel();
    _csrfToken = null;
    _epoch++;
    _refreshSequence++;
    _emailOtpAttempt++;
    _ambiguousEmailVerification = null;
    cancelSensitiveEmailVerification();
    _googleAttempt++;
    _emailOtp = null;
    _logoutUnconfirmed = false;
    _expiry?.cancel();
    _recheck?.cancel();
    if (mounted) state = const AsyncData(null);
  }

  @override
  void dispose() {
    cancelSensitiveEmailVerification();
    _authChallenge?.cancel();
    _expiry?.cancel();
    _recheck?.cancel();
    _http.close();
    super.dispose();
  }
}
