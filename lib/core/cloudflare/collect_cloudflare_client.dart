import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../supabase/collect_supabase_configuration.dart';
import 'collect_cloudflare_types.dart';
import 'collect_google_authorization_policy.dart';

export 'collect_cloudflare_types.dart';
export 'collect_google_authorization_policy.dart';

part 'collect_cloudflare_auth.dart';
part 'collect_cloudflare_auth_google.dart';
part 'collect_cloudflare_auth_guest.dart';
part 'collect_cloudflare_auth_otp.dart';
part 'collect_cloudflare_auth_restore.dart';
part 'collect_cloudflare_auth_session.dart';
part 'collect_cloudflare_auth_transport.dart';
part 'collect_cloudflare_requests.dart';

final class CollectCloudflareClient {
  CollectCloudflareClient(
    String apiUrl, {
    http.Client? httpClient,
    CollectAuthSessionStorage? sessionStorage,
    this.captchaProvider,
    this.cancelCaptcha,
    String surface = 'member',
    this.timeout = const Duration(seconds: 20),
    this.supabaseConfiguration,
    bool allowAnonymousSignIn = false,
  }) : _http = httpClient ?? http.Client(),
       _base = _validatedBase(apiUrl) {
    if (supabaseConfiguration != null &&
        _base.origin != supabaseConfiguration!.api.origin) {
      throw ArgumentError(
        'Supabase credentials must stay on the configured API origin.',
      );
    }
    if (!const {'member', 'admin'}.contains(surface)) {
      throw ArgumentError.value(surface, 'surface');
    }
    auth = CollectAuthClient(
      this,
      sessionStorage ?? CollectMemorySessionStorage(),
      surface: surface,
      allowAnonymousSignIn: allowAnonymousSignIn,
    );
    functions = CollectFunctionsClient(this);
  }

  final http.Client _http;
  final Uri _base;
  final Duration timeout;
  final CollectSupabaseConfiguration? supabaseConfiguration;
  final Future<String> Function()? captchaProvider;
  final void Function()? cancelCaptcha;
  late final CollectAuthClient auth;
  late final CollectFunctionsClient functions;
  final Set<Completer<void>> _requests = {};
  bool _disposed = false;
  static const maximumResponseBytes = 2 * 1024 * 1024;
  static const maximumRequestBytes = 1024 * 1024;

  static Uri _validatedBase(String value) {
    final base = Uri.parse(value.trim());
    if ((base.scheme != 'https' &&
            !(base.scheme == 'http' &&
                const {'localhost', '127.0.0.1', '::1'}.contains(base.host))) ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.query.isNotEmpty ||
        base.fragment.isNotEmpty ||
        (base.path.isNotEmpty && base.path != '/')) {
      throw ArgumentError('Collect API URL must be an HTTPS origin.');
    }
    return base.replace(path: '/');
  }

  Future<void> initialize() => auth.initialize();

  CollectRequest<T> rpc<T>(String operation, {Map<String, dynamic>? params}) {
    _name(operation);
    return CollectRequest<T>._(
      this,
      'POST',
      'v1/rpc/$operation',
      Map<String, dynamic>.unmodifiable(params ?? const {}),
      auth.currentSession?.accessToken,
      null,
    );
  }

  /// Only the two explicit scoped read contracts are supported. No generic
  /// table access or SQL filter language is exposed to an app credential.
  CollectQueryRequest from(String table) {
    final route = switch (table) {
      'public_collections_view' => 'public-collections',
      'notification_events' => 'notification-events',
      _ => throw ArgumentError('Unsupported Collect read contract'),
    };
    return CollectQueryRequest._(
      this,
      route,
      bearer: auth.currentSession?.accessToken,
    );
  }

  static void _name(String value) {
    if (!RegExp(r'^[a-z][a-z0-9_-]{0,119}$').hasMatch(value)) {
      throw ArgumentError('Invalid Collect operation name');
    }
  }

  Future<(int, dynamic)> request(
    String method,
    String path, {
    Object? body,
    String? bearer,
    Map<String, String>? query,
    int responseLimit = maximumResponseBytes,
  }) async {
    if (_disposed) throw StateError('Collect client is disposed');
    if (!path.startsWith('v1/') ||
        path.contains('..') ||
        path.contains('?') ||
        path.contains('#') ||
        path.contains(RegExp(r'[\r\n]'))) {
      throw ArgumentError('Invalid Collect API path');
    }
    if (bearer != null &&
        (bearer.isEmpty ||
            bearer.length > 32768 ||
            bearer.contains(RegExp(r'[\r\n]')))) {
      throw const CollectAuthException(
        'Sign in again.',
        code: 'invalid_session',
      );
    }
    if (auth.currentGuest != null &&
        bearer == auth.currentSession?.accessToken &&
        !path.startsWith('v1/auth/') &&
        !(method == 'GET' && path == 'v1/query/public-collections') &&
        !(method == 'POST' &&
            const {
              'v1/rpc/get_public_runtime_config',
              'v1/rpc/get_collection_type_catalog',
              'v1/rpc/get_active_policy_document',
              'v1/rpc/list_account_request_reasons',
            }.contains(path))) {
      throw const CollectAuthException(
        'Verify an email address or phone number to continue.',
        code: 'verified_identity_required',
        statusCode: '403',
      );
    }
    final abort = Completer<void>();
    _requests.add(abort);
    final prefix = supabaseConfiguration == null
        ? ''
        : CollectSupabaseConfiguration.memberPrefix;
    final uri = _base.resolve('$prefix$path').replace(queryParameters: query);
    final request = http.AbortableRequest(
      method,
      uri,
      abortTrigger: abort.future,
    )..followRedirects = false;
    request.headers.addAll({
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (bearer != null) 'Authorization': 'Bearer $bearer',
      if (supabaseConfiguration != null)
        'apikey': supabaseConfiguration!.publishableKey,
    });
    if (body != null) {
      request.body = jsonEncode(body);
      if (request.bodyBytes.length > maximumRequestBytes) {
        _requests.remove(abort);
        throw const CollectApiException(code: 'request_too_large');
      }
    }
    // A refused private snapshot read must not fall back to cache when the
    // response body is unreadable. Retain write response handling separately.
    final memberSnapshotRead =
        (method == 'POST' &&
            const {
              'v1/rpc/get_current_member_profile',
              'v1/rpc/list_current_user_collections',
              'v1/rpc/list_current_member_recent_intents',
              'v1/rpc/list_current_member_history_page',
              'v1/rpc/list_current_member_collection_balances',
              'v1/rpc/get_notification_preferences_v2',
            }.contains(path)) ||
        (method == 'GET' && path == 'v1/query/notification-events');
    int? receivedMemberDenial;
    var requestDeadline = false;
    try {
      return await _readResponse(
        request,
        responseLimit,
        onStatus: memberSnapshotRead
            ? (status) {
                if (status == 401 || status == 403) {
                  receivedMemberDenial = status;
                }
              }
            : null,
      ).timeout(
        timeout,
        onTimeout: () {
          if (!abort.isCompleted) {
            requestDeadline = true;
            abort.complete();
          }
          throw TimeoutException('Collect request deadline');
        },
      );
    } catch (error, stack) {
      final status = receivedMemberDenial;
      if (status != null && (requestDeadline || !abort.isCompleted)) {
        throw CollectApiException(code: '$status', httpStatusCode: status);
      }
      Error.throwWithStackTrace(error, stack);
    } finally {
      _requests.remove(abort);
      if (!abort.isCompleted) abort.complete();
    }
  }

  Future<(int, dynamic)> _readResponse(
    http.BaseRequest request,
    int limit, {
    void Function(int status)? onStatus,
  }) async {
    final response = await _http.send(request);
    onStatus?.call(response.statusCode);
    if (response.statusCode >= 300 && response.statusCode < 400) {
      await response.stream.listen((_) {}).cancel();
      throw const CollectApiException(code: 'redirect_denied');
    }
    if ((response.contentLength ?? 0) > limit) {
      await response.stream.listen((_) {}).cancel();
      throw const CollectApiException(code: 'response_too_large');
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > limit) {
        throw const CollectApiException(code: 'response_too_large');
      }
      bytes.addAll(chunk);
    }
    if (bytes.isEmpty) return (response.statusCode, null);
    try {
      return (response.statusCode, jsonDecode(utf8.decode(bytes)));
    } catch (_) {
      throw const CollectApiException(code: 'invalid_response');
    }
  }

  /// Cancels local work at logout initiation. Server commit outcomes must still
  /// be reconciled by the owning workflow; cancellation never means rollback.
  void cancelPendingRequests() {
    for (final request in _requests.toList()) {
      if (!request.isCompleted) request.complete();
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    cancelPendingRequests();
    await auth.dispose();
    _http.close();
  }
}
