import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../app/env/app_env.dart';
import '../../core/cloudflare/cloudflare_module.dart';

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
  Future<List<String>> verifiedTotpFactors(CollectAuthSession session);
  Future<String> challenge(CollectAuthSession session, String factorId);
  Future<CollectAuthSession> verify(
    CollectAuthSession session,
    String factorId,
    String challengeId,
    String code,
  );
}

final adminReconciliationMfaTransportProvider =
    Provider<AdminReconciliationMfaTransport?>((ref) {
      final env = ref.watch(appEnvProvider);
      if (!env.hasBackendConfig) return null;
      final httpClient = http.Client();
      ref.onDispose(httpClient.close);
      return CollectReconciliationMfaTransport(
        httpClient: httpClient,
        apiUrl: env.apiUrl,
      );
    });

final adminReconciliationStepUpProvider = Provider<Future<void> Function(String)>(
  (ref) {
    final client = ref.watch(collectBackendClientProvider);
    final transport = ref.watch(adminReconciliationMfaTransportProvider);
    if (client == null || transport == null) {
      return (_) async => throw _unavailable;
    }
    final controller = AdminReconciliationStepUp(
      currentSession: () => client.auth.currentSession,
      transport: transport,
      adoptSession: (session) async {
        // Collect installs a nonexpired verified session synchronously.
        // The caller checks identity and >30s validity immediately before this
        // call, so this path cannot refresh or restore a switched account.
        final recovery = client.auth.recoverSession(
          jsonEncode(session.toJson()),
          event: CollectAuthEvent.mfaChallengeVerified,
        );
        // Recovery emits exactly one MFA event after its synchronous adoption.
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

  final CollectAuthSession? Function() currentSession;
  final AdminReconciliationMfaTransport transport;
  final Future<void> Function(CollectAuthSession) adoptSession;
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

  void _fence(CollectAuthSession original) {
    final current = currentSession();
    if (_disposed ||
        current == null ||
        !_sameOwner(original, current) ||
        !_usable(current)) {
      throw _sessionChanged;
    }
  }
}

Map<String, dynamic> _claims(CollectAuthSession session) {
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

bool _usable(CollectAuthSession session) {
  final claims = _claims(session);
  return claims['sub'] == session.user.id &&
      claims['session_id'] is String &&
      (claims['session_id'] as String).isNotEmpty &&
      claims['exp'] is int &&
      (claims['exp'] as int) >
          DateTime.now().millisecondsSinceEpoch ~/ 1000 + 30;
}

bool _sameOwner(CollectAuthSession a, CollectAuthSession b) =>
    a.user.id == b.user.id &&
    _claims(a)['session_id'] == _claims(b)['session_id'];

/// This transport owns no Auth state or persistence. Only the existing main
/// client installs a successful server response after the workflow's fence.
class CollectReconciliationMfaTransport
    implements AdminReconciliationMfaTransport {
  CollectReconciliationMfaTransport({
    required http.Client httpClient,
    required String apiUrl,
  }) : _http = httpClient,
       _base = Uri.parse(apiUrl).replace(path: '/') {
    if ((_base.scheme != 'https' &&
            !(_base.scheme == 'http' &&
                const {
                  'localhost',
                  '127.0.0.1',
                  '::1',
                }.contains(_base.host))) ||
        _base.host.isEmpty ||
        _base.userInfo.isNotEmpty ||
        _base.query.isNotEmpty ||
        _base.fragment.isNotEmpty ||
        !const {'', '/'}.contains(Uri.parse(apiUrl).path)) {
      throw _unavailable;
    }
  }
  final http.Client _http;
  final Uri _base;
  static const _maximumResponseBytes = 131072;
  Future<Map<String, dynamic>> _request(
    CollectAuthSession session,
    String path, [
    Map<String, String>? body,
  ]) async {
    final abort = Completer<void>();
    try {
      final request = http.AbortableRequest(
        body == null ? 'GET' : 'POST',
        _base.resolve('v1/auth/$path'),
        abortTrigger: abort.future,
      )..followRedirects = false;
      request.headers.addAll({
        'Authorization': 'Bearer ${session.accessToken}',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      });
      if (body != null) request.body = jsonEncode(body);
      Future<(int, Map<String, dynamic>)> read() async {
        final response = await _http.send(request);
        if ((response.contentLength ?? 0) > _maximumResponseBytes ||
            (response.statusCode >= 300 && response.statusCode < 400)) {
          await response.stream.listen((_) {}).cancel();
          throw _unavailable;
        }
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > _maximumResponseBytes) {
            throw _unavailable;
          }
          bytes.addAll(chunk);
        }
        Map<String, dynamic> decoded;
        try {
          final value = jsonDecode(utf8.decode(bytes));
          if (value is! Map<String, dynamic>) throw const FormatException();
          decoded = value;
        } catch (_) {
          if (response.statusCode >= 200 && response.statusCode < 300) {
            throw _unavailable;
          }
          // Non-JSON upstream errors carry no trusted provider text.
          decoded = const {};
        }
        return (response.statusCode, decoded);
      }

      final (status, result) = await read().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          if (!abort.isCompleted) abort.complete();
          throw _unavailable;
        },
      );
      if (status < 200 || status >= 300) {
        if (status == 429) {
          throw const AdminReconciliationStepUpException(
            'verification_rate_limited',
            'Too many verification attempts. Wait before trying again.',
          );
        }
        if (const {
          'mfa_verification_failed',
          'mfa_verification_rejected',
          'mfa_challenge_expired',
        }.contains(result['code'] ?? result['error_code'])) {
          throw const AdminReconciliationStepUpException(
            'verification_failed',
            'The code was not accepted. Use a fresh authenticator code and retry.',
          );
        }
        throw _unavailable;
      }
      return result;
    } on AdminReconciliationStepUpException {
      rethrow;
    } catch (_) {
      throw _unavailable;
    } finally {
      if (!abort.isCompleted) abort.complete();
    }
  }

  @override
  Future<List<String>> verifiedTotpFactors(CollectAuthSession session) async {
    final user = CollectAuthUser.fromJson(await _request(session, 'user'));
    if (user?.id != session.user.id) throw _sessionChanged;
    return [
      for (final factor in user!.factors ?? <CollectAuthFactor>[])
        if (factor.factorType == CollectFactorType.totp &&
            factor.status == CollectFactorStatus.verified)
          factor.id,
    ];
  }

  @override
  Future<String> challenge(CollectAuthSession session, String factorId) async {
    final result = await _request(session, 'mfa/challenge', {
      'factor_id': factorId,
    });
    final id = result['challenge_id'];
    if (id is! String || id.isEmpty || id.length > 200) throw _unavailable;
    return id;
  }

  @override
  Future<CollectAuthSession> verify(
    CollectAuthSession session,
    String factorId,
    String challengeId,
    String code,
  ) async {
    final result = await _request(session, 'mfa/verify', {
      'factor_id': factorId,
      'challenge_id': challengeId,
      'code': code,
    });
    return CollectAuthSession.fromJson(result) ?? (throw _unavailable);
  }
}
