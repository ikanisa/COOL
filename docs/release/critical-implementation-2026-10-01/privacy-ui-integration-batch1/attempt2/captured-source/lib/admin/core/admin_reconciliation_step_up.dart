import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/env/app_env.dart';
import '../../core/supabase/supabase_module.dart';

class AdminReconciliationStepUpException implements Exception {
  const AdminReconciliationStepUpException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

const _sessionChanged = AdminReconciliationStepUpException(
  'session_changed',
  'Your sign-in changed. Reopen reconciliation and try again.',
);
const _unavailable = AdminReconciliationStepUpException(
  'step_up_unavailable',
  'Authenticator verification is unavailable. Try again shortly.',
);

abstract interface class AdminReconciliationMfaTransport {
  Future<List<String>> verifiedTotpFactors(Session session);
  Future<String> challenge(Session session, String factorId);
  Future<Session> verify(
    Session session,
    String factorId,
    String challengeId,
    String code,
  );
}

final adminReconciliationMfaTransportProvider =
    Provider<AdminReconciliationMfaTransport?>((ref) {
      final env = ref.watch(appEnvProvider);
      if (!env.hasSupabaseConfig) return null;
      final httpClient = http.Client();
      ref.onDispose(httpClient.close);
      return SupabaseReconciliationMfaTransport(
        httpClient: httpClient,
        supabaseUrl: env.supabaseUrl,
        publishableKey: env.supabaseAnonKey,
      );
    });

final adminReconciliationStepUpProvider = Provider<Future<void> Function(String)>(
  (ref) {
    final client = ref.watch(supabaseClientProvider);
    final transport = ref.watch(adminReconciliationMfaTransportProvider);
    if (client == null || transport == null) {
      return (_) async => throw _unavailable;
    }
    final controller = AdminReconciliationStepUp(
      currentSession: () => client.auth.currentSession,
      transport: transport,
      adoptSession: (session) async {
        // gotrue 2.27.1 saves a nonexpired recovered session synchronously.
        // The caller checks identity and >30s validity immediately before this
        // call, so this path cannot refresh or restore a switched account.
        final recovery = client.auth.recoverSession(
          jsonEncode(session.toJson()),
        );
        // recoverSession emits no event for the same user. Emit the normal MFA
        // event so Supabase Flutter persists the upgraded session and listeners
        // refresh authorization. This pinned SDK bridge needs rechecking on an
        // Auth SDK upgrade.
        // ignore: invalid_use_of_internal_member
        client.auth.notifyAllSubscribers(AuthChangeEvent.mfaChallengeVerified);
        await recovery;
      },
    );
    ref.onDispose(controller.dispose);
    return controller.call;
  },
);

/// Coordinates network awaits without allowing an old account's MFA response
/// to replace the current account. JWT parsing here is only a local ownership
/// fence; Auth verifies the code and SQL independently enforces real AAL2.
class AdminReconciliationStepUp {
  AdminReconciliationStepUp({
    required this.currentSession,
    required this.transport,
    required this.adoptSession,
  });

  final Session? Function() currentSession;
  final AdminReconciliationMfaTransport transport;
  final Future<void> Function(Session) adoptSession;
  bool _busy = false;
  bool _disposed = false;

  void dispose() => _disposed = true;

  Future<void> call(String code) async {
    if (!RegExp(r'^[0-9]{6}$').hasMatch(code)) {
      throw const AdminReconciliationStepUpException(
        'invalid_code',
        'Enter the six-digit code from your authenticator.',
      );
    }
    if (_busy) {
      throw const AdminReconciliationStepUpException(
        'verification_in_progress',
        'Authenticator verification is already in progress.',
      );
    }
    final original = currentSession();
    if (_disposed || original == null || !_usable(original)) {
      throw _sessionChanged;
    }
    _busy = true;
    try {
      _fence(original);
      final factors = await transport.verifiedTotpFactors(original);
      _fence(original);
      if (factors.isEmpty) {
        throw const AdminReconciliationStepUpException(
          'verified_authenticator_required',
          'A verified authenticator is required. Ask the Admin owner for help '
              'with the approved MFA setup.',
        );
      }
      if (factors.length != 1) {
        throw const AdminReconciliationStepUpException(
          'authenticator_selection_required',
          'Multiple authenticators are registered. Ask the Admin owner to '
              'confirm the approved authenticator before continuing.',
        );
      }
      final challenge = await transport.challenge(original, factors.single);
      _fence(original);
      final verified = await transport.verify(
        original,
        factors.single,
        challenge,
        code,
      );
      _fence(original);
      if (!_sameOwner(original, verified) ||
          !_usable(verified) ||
          _claims(verified)['aal'] != 'aal2' ||
          verified.refreshToken?.isNotEmpty != true) {
        throw _unavailable;
      }
      // No await between the final fence and synchronous SDK session adoption.
      await adoptSession(verified);
      _fence(original);
    } on AdminReconciliationStepUpException {
      rethrow;
    } catch (_) {
      // Never surface provider payloads, OTPs, access/refresh tokens or secrets.
      throw _unavailable;
    } finally {
      _busy = false;
    }
  }

  void _fence(Session original) {
    final current = currentSession();
    if (_disposed ||
        current == null ||
        !_sameOwner(original, current) ||
        !_usable(current)) {
      throw _sessionChanged;
    }
  }
}

Map<String, dynamic> _claims(Session session) {
  try {
    final parts = session.accessToken.split('.');
    if (parts.length != 3) return {};
    final value = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    return value is Map<String, dynamic> ? value : {};
  } catch (_) {
    return {};
  }
}

bool _usable(Session session) {
  final claims = _claims(session);
  return claims['sub'] == session.user.id &&
      claims['session_id'] is String &&
      (claims['session_id'] as String).isNotEmpty &&
      claims['exp'] is int &&
      (claims['exp'] as int) >
          DateTime.now().millisecondsSinceEpoch ~/ 1000 + 30;
}

bool _sameOwner(Session a, Session b) =>
    a.user.id == b.user.id &&
    _claims(a)['session_id'] == _claims(b)['session_id'];

/// Uses the Auth endpoints implemented by the pinned gotrue 2.27.1 SDK without
/// its MFA.verify session mutation. A second GoTrueClient is unsafe on web:
/// its shared BroadcastChannel can restore a stale account before a caller's
/// post-await fence. Only the main SDK receives a fenced successful session.
class SupabaseReconciliationMfaTransport
    implements AdminReconciliationMfaTransport {
  SupabaseReconciliationMfaTransport({
    required http.Client httpClient,
    required String supabaseUrl,
    required this.publishableKey,
  }) : _http = httpClient,
       _authUrl = Uri.parse(
         '${supabaseUrl.replaceFirst(RegExp(r'/+$'), '')}/auth/v1/',
       );

  final http.Client _http;
  final Uri _authUrl;
  final String publishableKey;

  Future<Map<String, dynamic>> _request(
    Session session,
    String path, [
    Map<String, String>? body,
  ]) async {
    final request = http.Request(
      body == null ? 'GET' : 'POST',
      _authUrl.resolve(path),
    );
    request.headers.addAll({
      'apikey': publishableKey,
      'Authorization': 'Bearer ${session.accessToken}',
      'Content-Type': 'application/json',
      'X-Supabase-Api-Version': '2024-01-01',
    });
    if (body != null) request.body = jsonEncode(body);
    final response = await _http
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 429) {
        throw const AdminReconciliationStepUpException(
          'verification_rate_limited',
          'Too many verification attempts. Wait before trying again.',
        );
      }
      Map<String, dynamic>? error;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) error = decoded;
      } catch (_) {}
      if ({
        'mfa_verification_failed',
        'mfa_verification_rejected',
        'mfa_challenge_expired',
      }.contains(error?['code'] ?? error?['error_code'])) {
        throw const AdminReconciliationStepUpException(
          'verification_failed',
          'The code was not accepted. Use a fresh authenticator code and retry.',
        );
      }
      throw _unavailable;
    }
    final result = jsonDecode(response.body);
    if (result is! Map<String, dynamic>) throw _unavailable;
    return result;
  }

  @override
  Future<List<String>> verifiedTotpFactors(Session session) async {
    // GET /user returns current factors without rotating a refresh token.
    final user = User.fromJson(await _request(session, 'user'));
    if (user?.id != session.user.id) throw _sessionChanged;
    return [
      for (final factor in user!.factors ?? <Factor>[])
        if (factor.factorType == FactorType.totp &&
            factor.status == FactorStatus.verified)
          factor.id,
    ];
  }

  @override
  Future<String> challenge(Session session, String factorId) async {
    final response = await _request(
      session,
      'factors/${Uri.encodeComponent(factorId)}/challenge',
      {},
    );
    final id = response['id'];
    if (id is! String || id.isEmpty || id.length > 200) throw _unavailable;
    return id;
  }

  @override
  Future<Session> verify(
    Session session,
    String factorId,
    String challengeId,
    String code,
  ) async {
    final response = await _request(
      session,
      'factors/${Uri.encodeComponent(factorId)}/verify',
      {'challenge_id': challengeId, 'code': code},
    );
    return Session.fromJson(response) ?? (throw _unavailable);
  }
}
