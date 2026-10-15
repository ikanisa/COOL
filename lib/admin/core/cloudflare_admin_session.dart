import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'admin_account_api.dart';
import 'cloudflare_admin_transport.dart';

class CloudflareAdminRequestException extends AdminAccountException {
  const CloudflareAdminRequestException(
    super.message, {
    this.statusCode,
    this.code,
    this.outcomeUnknown = false,
  });
  final int? statusCode;
  final String? code;
  final bool outcomeUnknown;
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
  });

  final String id;
  final String email;
  final AdminAccountRole role;
  final String sessionId;
  final DateTime expiresAt;
  final List<String> permissions;

  /// Cookie expiry checks may refresh without changing the operator's access.
  /// Providers and pending requests use this canonical boundary, rather than
  /// each newly decoded session object, to preserve an owned workspace.
  ({
    String id,
    String sessionId,
    String email,
    AdminAccountRole role,
    String permissions,
  })
  get authorityKey {
    final capabilities = permissions.toSet().toList()..sort();
    return (
      id: id,
      sessionId: sessionId,
      email: email,
      role: role,
      permissions: jsonEncode(capabilities),
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
    return CloudflareAdminUser(
      id: user['id'] as String,
      email: user['email'] as String,
      role: role,
      sessionId: user['sessionId'] as String,
      expiresAt: expiresAt,
      permissions: List<String>.unmodifiable(user['permissions'] as List),
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
      );
      unawaited(controller.refresh());
      return controller;
    });

class CloudflareAdminSession
    extends StateNotifier<AsyncValue<CloudflareAdminUser?>> {
  CloudflareAdminSession(this._http, {Uri? origin})
    : _origin = origin ?? Uri.base,
      super(const AsyncLoading());

  final http.Client _http;
  final Uri _origin;
  Timer? _recheck;
  Timer? _expiry;
  int _epoch = 0;
  int _refreshSequence = 0;
  bool _logoutUnconfirmed = false;

  CloudflareAdminUser? get user => state.asData?.value;
  bool get logoutUnconfirmed => _logoutUnconfirmed;

  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = false,
    String? method,
    String? idempotencyKey,
    String? reviewReason,
  }) async {
    final before = user?.authorityKey;
    final epoch = _epoch;
    if (authenticated && before == null) {
      throw const AdminAccountException('Sign in again to continue.');
    }
    final uri = _origin.resolve('/api/admin/$path');
    final verb = method ?? (body == null ? 'GET' : 'POST');
    if (!{'GET', 'POST', 'PATCH'}.contains(verb) ||
        (verb == 'GET' && body != null) ||
        uri.origin != _origin.origin ||
        !uri.path.startsWith('/api/admin/') ||
        (reviewReason != null &&
            (reviewReason.trim().length < 8 ||
                reviewReason.length > 1000 ||
                RegExp(r'[\r\n]').hasMatch(reviewReason))) ||
        (idempotencyKey != null &&
            !RegExp(r'^[A-Za-z0-9._:-]{8,200}$').hasMatch(idempotencyKey))) {
      throw ArgumentError('Invalid admin request.');
    }
    final mutation = verb != 'GET';
    final encoded = body == null ? null : jsonEncode(body);
    final headers = {
      'Accept': 'application/json',
      if (mutation) 'Content-Type': 'application/json',
      if (mutation) 'X-Collect-Admin': '1',
      'Idempotency-Key': ?idempotencyKey,
      'X-Collect-Review-Reason': ?reviewReason?.trim(),
    };
    late http.Response response;
    try {
      response = await switch (verb) {
        'GET' => _http.get(uri, headers: headers),
        'PATCH' => _http.patch(uri, headers: headers, body: encoded),
        _ => _http.post(uri, headers: headers, body: encoded),
      }.timeout(const Duration(seconds: 30));
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
        (authenticated && before != user?.authorityKey)) {
      throw CloudflareAdminRequestException(
        'Your session changed. Reopen this page before continuing.',
        outcomeUnknown: mutation,
      );
    }
    if (response.statusCode == 401) {
      clear();
      if (path == 'auth/session') return {'user': null};
      throw const CloudflareAdminRequestException(
        'Sign in again to continue.',
        statusCode: 401,
        code: 'unauthenticated',
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
          : null;
      final message = switch (response.statusCode) {
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
      };
      throw CloudflareAdminRequestException(
        message,
        statusCode: response.statusCode,
        code: code,
        outcomeUnknown: mutation && response.statusCode >= 500,
      );
    }
    return result;
  }

  Future<void> refresh() async {
    if (_logoutUnconfirmed) return;
    final epoch = _epoch;
    final sequence = ++_refreshSequence;
    try {
      final body = await request('auth/session');
      if (!mounted || epoch != _epoch || sequence != _refreshSequence) return;
      final value = body['user'] == null
          ? null
          : CloudflareAdminUser.parse(body);
      if (value == null) {
        clear();
        return;
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
    } catch (error, stack) {
      if (mounted && epoch == _epoch && sequence == _refreshSequence) {
        // Fence requests started before a failed access check even if the same
        // public session is restored later. Unavailable authority grants none.
        _epoch++;
        _expiry?.cancel();
        _recheck?.cancel();
        state = AsyncError(error, stack);
      }
    }
  }

  Future<void> signIn(String email, String password) async {
    clear();
    await request('auth/login', body: {'email': email, 'password': password});
    await refresh();
    if (user == null) {
      throw const AdminAccountException('Sign-in could not be confirmed.');
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
    _epoch++;
    _refreshSequence++;
    _logoutUnconfirmed = false;
    _expiry?.cancel();
    _recheck?.cancel();
    if (mounted) state = const AsyncData(null);
  }

  @override
  void dispose() {
    _expiry?.cancel();
    _recheck?.cancel();
    _http.close();
    super.dispose();
  }
}
