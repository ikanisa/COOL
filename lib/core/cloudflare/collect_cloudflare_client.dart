import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'package:http/http.dart' as http;

import 'collect_cloudflare_types.dart';
import '../supabase/collect_supabase_configuration.dart';
export 'collect_cloudflare_types.dart';

const collectSupabaseGoogleCallbackOrigin =
    'https://platform-admin.collect.ikanisa.com';

const collectSupabaseGoogleQaCallbackOrigin =
    'https://admin-supabase-qa.collect.ikanisa.com';

bool collectSupabaseGoogleCallbackOriginAllowed(String origin) =>
    origin == collectSupabaseGoogleCallbackOrigin ||
    origin == collectSupabaseGoogleQaCallbackOrigin;

/// Select one callback authority from the configured API, never from a reply.
String? collectSupabaseGoogleCallbackOriginForApi(Uri api) {
  if (api.scheme != 'https' ||
      !api.hasAuthority ||
      api.userInfo.isNotEmpty ||
      api.fragment.isNotEmpty) {
    return null;
  }
  if (api.origin == collectSupabaseGoogleQaCallbackOrigin) {
    return collectSupabaseGoogleQaCallbackOrigin;
  }
  if (api.origin == collectSupabaseGoogleCallbackOrigin ||
      api.origin == 'https://rrlduytparvsjfmegalh.supabase.co') {
    return collectSupabaseGoogleCallbackOrigin;
  }
  return null;
}

/// Validate the configured authorize hop; never trust an origin from a reply.
bool collectGoogleAuthorizationUrlAllowed(
  Uri? candidate, {
  required bool usesSupabase,
  String supabaseCallbackOrigin = collectSupabaseGoogleCallbackOrigin,
  CollectSupabaseConfiguration? supabaseConfiguration,
}) {
  try {
    if (candidate == null ||
        !candidate.hasAuthority ||
        candidate.scheme != 'https' ||
        candidate.userInfo.isNotEmpty ||
        candidate.fragment.isNotEmpty) {
      return false;
    }
    if (!usesSupabase) {
      return candidate.host == 'accounts.google.com' &&
          candidate.path == '/o/oauth2/v2/auth';
    }
    final configuration = supabaseConfiguration;
    final callbackAllowed = configuration == null
        ? collectSupabaseGoogleCallbackOriginAllowed(supabaseCallbackOrigin)
        : configuration.googleCallbackOrigin == supabaseCallbackOrigin;
    final authorizationOrigin =
        configuration?.googleAuthorizationOrigin ??
        'https://rrlduytparvsjfmegalh.supabase.co';
    if (!callbackAllowed ||
        candidate.origin != authorizationOrigin ||
        candidate.path != '/auth/v1/authorize') {
      return false;
    }
    final query = candidate.queryParametersAll;
    const allowed = {
      'provider',
      'redirect_to',
      'code_challenge',
      'code_challenge_method',
      'scopes',
      'prompt',
    };
    if (query.keys.any((key) => !allowed.contains(key)) ||
        query.values.any((values) => values.length != 1) ||
        query['provider']?.single != 'google' ||
        query['code_challenge_method']?.single != 's256' ||
        !RegExp(
          r'^[A-Za-z0-9_-]{43}$',
        ).hasMatch(query['code_challenge']?.single ?? '') ||
        (query.containsKey('scopes') &&
            query['scopes']!.single != 'openid email profile') ||
        (query.containsKey('prompt') &&
            query['prompt']!.single != 'select_account')) {
      return false;
    }
    final redirect = Uri.tryParse(query['redirect_to']?.single ?? '');
    return redirect != null &&
        redirect.hasAuthority &&
        redirect.scheme == 'https' &&
        redirect.origin == supabaseCallbackOrigin &&
        redirect.path == '/functions/v1/collect-api/v1/auth/google/callback' &&
        redirect.userInfo.isEmpty &&
        redirect.fragment.isEmpty &&
        redirect.queryParametersAll.length == 1 &&
        redirect.queryParametersAll['state']?.length == 1 &&
        RegExp(
          r'^[A-Za-z0-9_-]{43}$',
        ).hasMatch(redirect.queryParameters['state'] ?? '');
  } on FormatException {
    return false;
  }
}

abstract interface class CollectAuthSessionStorage {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

/// Page memory only: no browser storage, cookie, BroadcastChannel or URL token.
final class CollectMemorySessionStorage implements CollectAuthSessionStorage {
  String? _value;
  @override
  Future<String?> read() async => _value;
  @override
  Future<void> write(String value) async {
    _value = value;
  }

  @override
  Future<void> clear() async {
    _value = null;
  }
}

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
    try {
      return await _readResponse(request, responseLimit).timeout(
        timeout,
        onTimeout: () {
          if (!abort.isCompleted) abort.complete();
          throw TimeoutException('Collect request deadline');
        },
      );
    } finally {
      _requests.remove(abort);
      if (!abort.isCompleted) abort.complete();
    }
  }

  Future<(int, dynamic)> _readResponse(
    http.BaseRequest request,
    int limit,
  ) async {
    final response = await _http.send(request);
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

/// A Collect request executes once even if more than one consumer awaits it.
/// Automatic network retries are deliberately absent for RPCs and functions.
class CollectRequest<T> implements Future<T> {
  CollectRequest._(
    this._client,
    this._method,
    this._path,
    this._body,
    this._bearer,
    this._query,
  );
  final CollectCloudflareClient _client;
  final String _method;
  final String _path;
  final Object? _body;
  final String? _bearer;
  final Map<String, String>? _query;
  Future<T>? _started;

  CollectRequest<T> setHeader(String name, String value) {
    if (name.toLowerCase() != 'authorization' || !value.startsWith('Bearer ')) {
      throw ArgumentError('Only captured bearer authorization is supported');
    }
    return CollectRequest<T>._(
      _client,
      _method,
      _path,
      _body,
      value.substring(7),
      _query,
    );
  }

  CollectRequest<T> retry({required bool enabled}) => this;

  Future<T> _execute() => _started ??= _perform();
  Future<T> _perform() async {
    final (status, data) = await _client.request(
      _method,
      _path,
      body: _body,
      bearer: _bearer,
      query: _query,
    );
    if (status < 200 || status >= 300) throw collectApiFailure(status, data);
    return data as T;
  }

  @override
  Stream<T> asStream() => _execute().asStream();
  @override
  Future<T> catchError(Function onError, {bool Function(Object)? test}) =>
      _execute().catchError(onError, test: test);
  @override
  Future<R> then<R>(FutureOr<R> Function(T) onValue, {Function? onError}) =>
      _execute().then(onValue, onError: onError);
  @override
  Future<T> timeout(Duration timeLimit, {FutureOr<T> Function()? onTimeout}) =>
      _execute().timeout(timeLimit, onTimeout: onTimeout);
  @override
  Future<T> whenComplete(FutureOr<void> Function() action) =>
      _execute().whenComplete(action);
}

final class CollectQueryRequest
    extends CollectRequest<List<Map<String, dynamic>>> {
  CollectQueryRequest._(
    CollectCloudflareClient client,
    this._route, {
    String? bearer,
    Map<String, String> filters = const {},
  }) : _filters = Map.unmodifiable(filters),
       super._(client, 'GET', 'v1/query/$_route', null, bearer, filters);
  final String _route;
  final Map<String, String> _filters;
  CollectQueryRequest select([String columns = '*']) {
    if (columns != '*') {
      throw ArgumentError('Explicit read contracts return their DTO');
    }
    return this;
  }

  CollectQueryRequest eq(String field, Object value) {
    if (_route != 'notification-events' ||
        field != 'user_id' ||
        value is! String) {
      throw ArgumentError('Unsupported Collect read filter');
    }
    return CollectQueryRequest._(
      _client,
      _route,
      bearer: _bearer,
      filters: {..._filters, field: value},
    );
  }

  CollectQueryRequest order(String field, {bool ascending = true}) {
    if (field != 'created_at') {
      throw ArgumentError('Unsupported Collect ordering');
    }
    return CollectQueryRequest._(
      _client,
      _route,
      bearer: _bearer,
      filters: {..._filters, 'order': field, 'ascending': '$ascending'},
    );
  }

  CollectQueryRequest limit(int count) {
    if (count < 1 || count > 100) {
      throw ArgumentError('Collect read limit exceeded');
    }
    return CollectQueryRequest._(
      _client,
      _route,
      bearer: _bearer,
      filters: {..._filters, 'limit': '$count'},
    );
  }

  @override
  CollectQueryRequest setHeader(String name, String value) {
    if (name.toLowerCase() != 'authorization' || !value.startsWith('Bearer ')) {
      throw ArgumentError('Only captured bearer authorization is supported');
    }
    return CollectQueryRequest._(
      _client,
      _route,
      bearer: value.substring(7),
      filters: _filters,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> _perform() async {
    final (status, data) = await _client.request(
      'GET',
      'v1/query/$_route',
      bearer: _bearer,
      query: _filters,
    );
    if (status < 200 || status >= 300) throw collectApiFailure(status, data);
    if (data is! List ||
        data.length > 100 ||
        data.any((row) => row is! Map<String, dynamic>)) {
      throw const CollectApiException(code: 'invalid_read_response');
    }
    return List.unmodifiable(
      data.map(
        (row) => Map<String, dynamic>.unmodifiable(row as Map<String, dynamic>),
      ),
    );
  }
}

CollectApiException collectApiFailure(int status, Object? body) {
  final nestedError = body is Map ? body['error'] : null;
  final usesAuthEnvelope =
      body is Map &&
      body['code'] == null &&
      body['error_code'] == null &&
      nestedError is Map;
  final details = usesAuthEnvelope ? nestedError : body;
  final rawCode = details is Map
      ? details['code'] ?? details['error_code']
      : null;
  // Auth envelopes supply reason codes; their upstream text stays private.
  final rawMessage = !usesAuthEnvelope && details is Map
      ? details['message']
      : null;
  final code =
      rawCode is String && RegExp(r'^[a-zA-Z0-9_.-]{1,100}$').hasMatch(rawCode)
      ? rawCode
      : '$status';
  // Contract reason codes are required by existing guarded workflows. Never
  // copy arbitrary upstream exception text, token strings or request payloads.
  final message =
      rawMessage is String &&
          RegExp(r'^[a-zA-Z0-9_.-]{1,160}$').hasMatch(rawMessage)
      ? rawMessage
      : 'Collect could not complete this request.';
  return CollectApiException(code: code, message: message);
}

final class CollectFunctionsClient {
  const CollectFunctionsClient(this._client);
  final CollectCloudflareClient _client;
  Future<CollectFunctionResponse> invoke(
    String name, {
    Object? body,
    Map<String, String>? headers,
  }) async {
    CollectCloudflareClient._name(name);
    var bearer = _client.auth.currentSession?.accessToken;
    if (headers != null) {
      if (headers.length != 1 ||
          !headers.containsKey('Authorization') ||
          !headers['Authorization']!.startsWith('Bearer ')) {
        throw ArgumentError('Only captured bearer authorization is supported');
      }
      bearer = headers['Authorization']!.substring(7);
    }
    final (status, data) = await _client.request(
      'POST',
      'v1/functions/$name',
      body: body ?? const {},
      bearer: bearer,
    );
    if (status < 200 || status >= 300) {
      final error = collectApiFailure(status, data);
      throw CollectFunctionException(
        status: status,
        details: {'code': error.code, 'message': error.message},
      );
    }
    return CollectFunctionResponse(data: data, status: status);
  }
}

final class _CollectOtpUnconfirmedReply extends CollectAuthException {
  _CollectOtpUnconfirmedReply(this.payload)
    : super(
        'Delivery could not be confirmed.',
        statusCode: '503',
        code: 'otp_delivery_unknown',
      );
  final Map<String, dynamic> payload;
}

final class _CollectGuestUpgrade {
  const _CollectGuestUpgrade({
    required this.key,
    required this.challengeId,
    required this.authSubject,
    required this.sessionId,
    this.phone,
    this.email,
    this.channel,
    this.unconfirmed = false,
    this.recoveryRefreshToken,
  });
  final String key, challengeId, authSubject, sessionId;
  final String? phone, email;
  final CollectOtpChannel? channel;
  final bool unconfirmed;
  final String? recoveryRefreshToken;
  _CollectGuestUpgrade uncertain() => _CollectGuestUpgrade(
    key: key,
    challengeId: challengeId,
    authSubject: authSubject,
    sessionId: sessionId,
    phone: phone,
    email: email,
    channel: channel,
    unconfirmed: true,
    recoveryRefreshToken: recoveryRefreshToken,
  );
  _CollectGuestUpgrade withRecoveryToken(String value) => _CollectGuestUpgrade(
    key: key,
    challengeId: challengeId,
    authSubject: authSubject,
    sessionId: sessionId,
    phone: phone,
    email: email,
    channel: channel,
    unconfirmed: true,
    recoveryRefreshToken: value,
  );
  Map<String, dynamic> toJson() => {
    'challenge_id': challengeId,
    'auth_subject': authSubject,
    'session_id': sessionId,
    'phone': phone,
    'email': email,
    'channel': channel?.name,
    'unconfirmed': unconfirmed,
    'recovery_refresh_token': ?recoveryRefreshToken,
  };
}

final class CollectAuthClient {
  CollectAuthClient(
    this._client,
    this._storage, {
    required this.surface,
    bool allowAnonymousSignIn = false,
  }) : anonymousSignInAvailable =
           allowAnonymousSignIn &&
           surface == 'member' &&
           _client.supabaseConfiguration != null;
  final CollectCloudflareClient _client;
  final CollectAuthSessionStorage _storage;
  final String surface;
  final bool anonymousSignInAvailable;
  final _events = StreamController<CollectAuthState>.broadcast(sync: true);
  CollectAuthSession? _session;
  int _generation = 0;
  int _otpGeneration = 0;
  int _googleGeneration = 0;
  int _anonymousGeneration = 0;
  final Map<String, String> _challenges = {};
  final Map<String, CollectOtpChannel?> _challengeChannels = {};
  _CollectGuestUpgrade? _guestUpgrade;
  Timer? _refreshTimer;
  Future<CollectAuthResponse>? _refreshInFlight;
  Future<CollectAuthResponse>? _guestReconcileInFlight;
  Future<void> _storageTail = Future.value();
  bool _disposed = false;
  CollectAuthSession? get currentSession => _session;
  // Guest credentials never become application/member ownership. Existing
  // financial/device consumers continue to see the signed-out public surface.
  CollectAuthUser? get currentUser =>
      _session?.user.isAnonymous == true ? null : _session?.user;
  CollectAuthUser? get currentGuest =>
      _session?.user.isAnonymous == true ? _session?.user : null;
  CollectGuestUpgradeStatus? get pendingGuestUpgrade =>
      currentGuest == null || _guestUpgrade == null
      ? null
      : CollectGuestUpgradeStatus(
          phone: _guestUpgrade!.phone,
          email: _guestUpgrade!.email,
          channel: _guestUpgrade!.channel,
          unconfirmed: _guestUpgrade!.unconfirmed,
        );
  Stream<CollectAuthState> get onAuthStateChange => _events.stream;
  Stream<CollectAuthState> get onAuthStateChangeSync => _events.stream;

  Future<CollectAuthResponse> signInAnonymously({String? captchaToken}) async {
    if (!anonymousSignInAvailable) {
      throw const CollectAuthException(
        'Guest access is unavailable.',
        code: 'anonymous_unavailable',
        statusCode: '503',
      );
    }
    if (_session != null) {
      throw const CollectAuthException(
        'An account is already open.',
        code: 'session_exists',
      );
    }
    final generation = _generation, attempt = ++_anonymousGeneration;
    cancelGoogleSignIn();
    ++_otpGeneration;
    _challenges.clear();
    _challengeChannels.clear();
    captchaToken = await _freshCaptcha(captchaToken);
    void checkCurrent() {
      if (_disposed ||
          _generation != generation ||
          attempt != _anonymousGeneration ||
          _session != null) {
        throw const CollectAuthException(
          'Your sign-in changed.',
          code: 'session_changed',
        );
      }
    }

    checkCurrent();
    final data = await _authRequest('anonymous', {
      'surface': 'member',
      'captcha_token': ?captchaToken,
    });
    checkCurrent();
    final session = _verifiedSession(data);
    if (!session.user.isAnonymous) {
      throw const CollectAuthException(
        'Guest access could not be verified.',
        code: 'invalid_session',
      );
    }
    _install(session, CollectAuthEvent.signedIn);
    await _persist();
    if (_session?.accessToken != session.accessToken) {
      throw const CollectAuthException(
        'Your sign-in changed.',
        code: 'session_changed',
      );
    }
    return CollectAuthResponse(session: session);
  }

  Future<void> initialize() async {
    final stored = await _storage.read();
    if (stored == null || _disposed) return;
    CollectAuthSession? session;
    try {
      if (stored.length > 131072) throw const FormatException();
      final decoded = jsonDecode(stored);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      session = _decodeSession(
        decoded,
        allowRetainedGuest: decoded['guest_upgrade'] != null,
      );
      if (session == null || session.refreshToken == null) {
        throw const FormatException();
      }
      final pending = decoded['guest_upgrade'];
      if (pending != null) {
        if (!session.user.isAnonymous ||
            pending is! Map<String, dynamic> ||
            pending['auth_subject'] != session.authSubject ||
            pending['session_id'] != session.claims['session_id'] ||
            pending['unconfirmed'] is! bool ||
            pending['challenge_id'] is! String ||
            !RegExp(
              r'^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$',
            ).hasMatch(pending['challenge_id'] as String) ||
            (pending['channel'] != null &&
                !const {'sms', 'whatsapp'}.contains(pending['channel'])) ||
            (pending['recovery_refresh_token'] != null &&
                (pending['recovery_refresh_token'] is! String ||
                    (pending['recovery_refresh_token'] as String).isEmpty ||
                    (pending['recovery_refresh_token'] as String).length >
                        4096 ||
                    pending['unconfirmed'] != true))) {
          throw const FormatException();
        }
        final phone = pending['phone'] as String?,
            email = pending['email'] as String?;
        final key = _otpKey(phone, email);
        final channel = pending['channel'] == null
            ? null
            : CollectOtpChannel.values.byName(pending['channel'] as String);
        if ((phone == null) != (channel == null)) throw const FormatException();
        _guestUpgrade = _CollectGuestUpgrade(
          key: key,
          challengeId: pending['challenge_id'] as String,
          authSubject: session.authSubject,
          sessionId: pending['session_id'] as String,
          phone: phone,
          email: email,
          channel: channel,
          unconfirmed: pending['unconfirmed'] as bool,
          recoveryRefreshToken: pending['recovery_refresh_token'] as String?,
        );
        _challenges[key] = _guestUpgrade!.challengeId;
        _challengeChannels[key] = channel;
      }
    } catch (_) {
      await _storage.clear();
      return;
    }
    _session = session;
    if (_guestUpgrade?.unconfirmed == true) {
      // The original guest credential and challenge are recovery evidence.
      // Refreshing an identity that GoTrue may already have converted could
      // replace them before the application projection is acknowledged.
      _events.add(CollectAuthState(CollectAuthEvent.initialSession, session));
      return;
    }
    if (session.isExpired) {
      try {
        await refreshSession();
      } catch (_) {
        await clearLocalSession();
      }
    } else {
      _events.add(CollectAuthState(CollectAuthEvent.initialSession, session));
      _scheduleRefresh();
    }
  }

  Future<CollectOtpRequestReceipt> signInWithOtp({
    String? phone,
    String? email,
    CollectOtpChannel? channel,
    bool shouldCreateUser = true,
    String? captchaToken,
  }) async {
    final key = _otpKey(phone, email);
    final guestSession = currentGuest == null ? null : _session;
    if (guestSession != null && _guestUpgrade?.unconfirmed == true) {
      throw const CollectAuthException(
        'Check the existing verification before requesting another code.',
        code: 'guest_upgrade_unknown',
        statusCode: '503',
      );
    }
    if (email != null && channel != null) {
      throw const CollectAuthException(
        'Invalid sign-in channel.',
        code: 'invalid_channel',
      );
    }
    final epoch = ++_otpGeneration;
    final generation = _generation;
    _challenges.remove(key);
    _challengeChannels.remove(key);
    captchaToken = await _freshCaptcha(captchaToken);
    if (_disposed || epoch != _otpGeneration || generation != _generation) {
      throw const CollectAuthException(
        'Your sign-in changed.',
        code: 'session_changed',
      );
    }
    Map<String, dynamic> data;
    var deliveryUnconfirmed = false;
    try {
      data = await _authRequest(
        guestSession == null ? 'otp' : 'upgrade/otp',
        {
          'phone': ?phone,
          'email': ?email,
          'surface': surface,
          'captcha_token': ?captchaToken,
          if (_client.supabaseConfiguration != null && guestSession == null)
            'should_create_user': shouldCreateUser,
          if (_client.supabaseConfiguration != null && channel != null)
            'channel': channel.name,
        },
        bearer: guestSession?.accessToken,
      );
    } on _CollectOtpUnconfirmedReply catch (reply) {
      data = reply.payload;
      deliveryUnconfirmed = true;
    }
    if (_disposed || epoch != _otpGeneration || generation != _generation) {
      throw const CollectAuthException(
        'Your sign-in changed.',
        code: 'session_changed',
      );
    }
    final id = data['challenge_id'];
    if (id is! String || id.isEmpty || id.length > 200) {
      throw const CollectAuthException(
        'Verification is unavailable.',
        code: 'invalid_challenge',
      );
    }
    final retryAfterSeconds = data['retry_after'] ?? 60;
    if (retryAfterSeconds is! int ||
        retryAfterSeconds < 60 ||
        retryAfterSeconds > 3600) {
      throw const CollectAuthException(
        'Verification is unavailable.',
        code: 'invalid_response',
      );
    }
    if (_client.supabaseConfiguration != null &&
        data.containsKey('delivery_status')) {
      final delivery = data['delivery_status'];
      if (delivery != 'accepted' && delivery != 'unknown') {
        throw const CollectAuthException(
          'Verification is unavailable.',
          code: 'invalid_response',
        );
      }
      deliveryUnconfirmed = deliveryUnconfirmed || delivery == 'unknown';
    }
    _challenges[key] = id;
    _challengeChannels[key] = phone == null
        ? null
        : channel ?? CollectOtpChannel.whatsapp;
    if (guestSession != null) {
      _guestUpgrade = _CollectGuestUpgrade(
        key: key,
        challengeId: id,
        authSubject: guestSession.authSubject,
        sessionId: guestSession.claims['session_id'] as String,
        phone: phone,
        email: email,
        channel: _challengeChannels[key],
      );
      await _persist();
      if (_disposed || generation != _generation || epoch != _otpGeneration) {
        throw const CollectAuthException(
          'Your sign-in changed.',
          code: 'session_changed',
        );
      }
    }
    if (deliveryUnconfirmed) {
      throw CollectOtpDeliveryUnknownException(
        retryAfterSeconds: retryAfterSeconds,
      );
    }
    return CollectOtpRequestReceipt(retryAfterSeconds: retryAfterSeconds);
  }

  Future<CollectAuthResponse> verifyOTP({
    String? phone,
    String? email,
    required String token,
    required CollectOtpType type,
    CollectOtpChannel? channel,
    String? captchaToken,
  }) async {
    final key = _otpKey(phone, email);
    final challenge = _challenges[key];
    final upgrade = _guestUpgrade?.key == key ? _guestUpgrade : null;
    final guestSession = upgrade == null ? null : _session;
    if (upgrade != null &&
        (guestSession?.user.isAnonymous != true ||
            guestSession?.authSubject != upgrade.authSubject ||
            guestSession?.claims['session_id'] != upgrade.sessionId)) {
      throw const CollectAuthException(
        'Your sign-in changed.',
        code: 'session_changed',
      );
    }
    if (upgrade?.unconfirmed == true) return reconcileGuestUpgrade();
    final generation = _generation;
    final otpGeneration = _otpGeneration;
    if (challenge == null ||
        type != (phone == null ? CollectOtpType.email : CollectOtpType.sms) ||
        (channel != null && _challengeChannels[key] != channel) ||
        !RegExp(r'^[0-9]{6}$').hasMatch(token)) {
      throw const CollectAuthException(
        'Request a fresh verification code.',
        code: 'invalid_challenge',
      );
    }
    captchaToken = await _freshCaptcha(captchaToken);
    if (_disposed ||
        generation != _generation ||
        otpGeneration != _otpGeneration ||
        _challenges[key] != challenge) {
      throw const CollectAuthException(
        'Your sign-in changed.',
        code: 'session_changed',
      );
    }
    Map<String, dynamic> data;
    if (upgrade != null) {
      // Journal uncertainty before the network await. Process death, a lost
      // reply or route cancellation cannot turn a provider mutation into a retry.
      _guestUpgrade = upgrade.uncertain();
      _refreshTimer?.cancel();
      _refreshTimer = null;
      await _persist();
      if (_disposed ||
          generation != _generation ||
          otpGeneration != _otpGeneration) {
        throw const CollectAuthException(
          'Your sign-in changed.',
          code: 'session_changed',
        );
      }
    }
    try {
      data = await _authRequest(
        upgrade == null ? 'verify' : 'upgrade/verify',
        {
          'phone': ?phone,
          'email': ?email,
          'code': token,
          'challenge_id': challenge,
          'surface': surface,
          'captcha_token': ?captchaToken,
        },
        bearer: guestSession?.accessToken,
      );
    } on CollectAuthException catch (error) {
      if (upgrade != null &&
          generation == _generation &&
          otpGeneration == _otpGeneration) {
        final knownRejection = error.code == 'guest_otp_rejected';
        _guestUpgrade = knownRejection ? upgrade : upgrade.uncertain();
        await _persist();
        if (!knownRejection) {
          throw const CollectAuthException(
            'Check the existing verification before trying again.',
            code: 'guest_upgrade_unknown',
            statusCode: '503',
          );
        }
      }
      rethrow;
    }
    if (_disposed ||
        generation != _generation ||
        otpGeneration != _otpGeneration ||
        _challenges[key] != challenge) {
      throw const CollectAuthException(
        'Your sign-in changed.',
        code: 'session_changed',
      );
    }
    final session = _verifiedSession(data);
    if (session.user.isAnonymous ||
        upgrade != null && session.authSubject != upgrade.authSubject) {
      throw const CollectAuthException(
        'The verified account changed.',
        code: 'verified_identity_mismatch',
      );
    }
    _guestUpgrade = null;
    _challenges.remove(key);
    _challengeChannels.remove(key);
    _install(session, CollectAuthEvent.signedIn);
    await _persist();
    if (_session?.accessToken != session.accessToken) {
      throw const CollectAuthException(
        'Your sign-in changed.',
        code: 'session_changed',
      );
    }
    return CollectAuthResponse(session: session);
  }

  void cancelGoogleSignIn() {
    ++_googleGeneration;
    _client.cancelCaptcha?.call();
  }

  void cancelOtpSignIn() {
    ++_otpGeneration;
    ++_anonymousGeneration;
    _challenges.clear();
    _challengeChannels.clear();
    if (_guestUpgrade case final pending?) {
      _challenges[pending.key] = pending.challengeId;
      _challengeChannels[pending.key] = pending.channel;
    }
    _client.cancelCaptcha?.call();
  }

  Future<CollectAuthResponse> reconcileGuestUpgrade() {
    final running = _guestReconcileInFlight;
    if (running != null) return running;
    final operation = _reconcileGuestUpgrade();
    _guestReconcileInFlight = operation;
    return operation.whenComplete(() {
      if (identical(_guestReconcileInFlight, operation)) {
        _guestReconcileInFlight = null;
      }
    });
  }

  Future<CollectAuthResponse> _reconcileGuestUpgrade() async {
    final pending = _guestUpgrade,
        original = _session,
        generation = _generation,
        epoch = _otpGeneration;
    if (pending == null ||
        !pending.unconfirmed ||
        original?.user.isAnonymous != true ||
        original?.authSubject != pending.authSubject ||
        original?.claims['session_id'] != pending.sessionId ||
        original?.refreshToken == null) {
      throw const CollectAuthException(
        'No retained verification is available.',
        code: 'invalid_challenge',
      );
    }
    final data = await _authRequest('upgrade/reconcile', {
      'challenge_id': pending.challengeId,
      'refresh_token': pending.recoveryRefreshToken ?? original!.refreshToken,
    }, bearer: original!.accessToken);
    if (_disposed ||
        generation != _generation ||
        epoch != _otpGeneration ||
        !identical(_guestUpgrade, pending)) {
      throw const CollectAuthException(
        'Your sign-in changed.',
        code: 'session_changed',
      );
    }
    if (data['upgrade_status'] == 'unconfirmed') {
      final recoveryToken = data['recovery_refresh_token'];
      if (data.length != 5 ||
          data['challenge_id'] != pending.challengeId ||
          data['auth_user_id'] != pending.authSubject ||
          data['initiating_session_id'] != pending.sessionId ||
          recoveryToken is! String ||
          recoveryToken.isEmpty ||
          recoveryToken.length > 4096) {
        throw const CollectAuthException(
          'The retained verification could not be confirmed.',
          code: 'invalid_session',
        );
      }
      // This credential is recovery evidence only. It never changes the
      // current guest/user, activates business work, or permits a code replay.
      _guestUpgrade = pending.withRecoveryToken(recoveryToken);
      await _persist();
      throw const CollectAuthException(
        'The verification is still unconfirmed. Check this request again.',
        code: 'guest_upgrade_unknown',
        statusCode: '503',
      );
    }
    final session = _verifiedSession(data);
    if (session.user.isAnonymous ||
        session.authSubject != pending.authSubject) {
      throw const CollectAuthException(
        'The verified account changed.',
        code: 'verified_identity_mismatch',
      );
    }
    _guestUpgrade = null;
    _guestReconcileInFlight = null;
    _challenges.clear();
    _challengeChannels.clear();
    _install(session, CollectAuthEvent.signedIn);
    await _persist();
    if (_session?.accessToken != session.accessToken) {
      throw const CollectAuthException(
        'Your sign-in changed.',
        code: 'session_changed',
      );
    }
    return CollectAuthResponse(session: session);
  }

  Future<CollectAuthResponse> signInWithGoogle({
    required Future<Map<String, dynamic>> Function(
      Future<Uri> Function(String? returnOrigin) createUrl,
      String state,
      String apiOrigin,
    )
    authorize,
  }) async {
    if (surface != 'member') {
      throw const CollectAuthException(
        'Member sign-in is required.',
        code: 'invalid_surface',
      );
    }
    if (currentGuest != null) {
      throw const CollectAuthException(
        'Verify an email address or phone number to keep this guest session.',
        code: 'guest_upgrade_required',
      );
    }
    final supabase = _client.supabaseConfiguration;
    final callbackOrigin = supabase == null
        ? _client._base.origin
        : supabase.googleCallbackOrigin;
    if (callbackOrigin == null) {
      throw const CollectAuthException(
        'Google sign-in is unavailable.',
        code: 'invalid_response',
      );
    }
    final generation = _generation;
    final googleGeneration = ++_googleGeneration;
    ++_otpGeneration;
    final random = Random.secure();
    String nonce() => base64UrlEncode(
      List<int>.generate(32, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
    final verifier = nonce(), state = nonce();
    final challenge = base64UrlEncode(
      sha256.convert(utf8.encode(verifier)).bytes,
    ).replaceAll('=', '');
    void checkCurrent() {
      if (_disposed ||
          generation != _generation ||
          googleGeneration != _googleGeneration) {
        throw const CollectAuthException(
          'Your sign-in changed.',
          code: 'session_changed',
        );
      }
    }

    final reply = await authorize(
      (origin) async {
        final captcha = await _freshCaptcha(null);
        checkCurrent();
        final data = await _authRequest('google/start', {
          'surface': 'member',
          'captcha_token': ?captcha,
          'code_challenge': challenge,
          'client_state': state,
          'return_origin': ?origin,
        });
        checkCurrent();
        final url = data['authorization_url'] is String
            ? Uri.tryParse(data['authorization_url'] as String)
            : null;
        if (!collectGoogleAuthorizationUrlAllowed(
          url,
          usesSupabase: _client.supabaseConfiguration != null,
          supabaseCallbackOrigin: callbackOrigin,
          supabaseConfiguration: supabase,
        )) {
          throw const CollectAuthException(
            'Google sign-in is unavailable.',
            code: 'invalid_response',
          );
        }
        return url!;
      },
      state,
      callbackOrigin,
    );
    checkCurrent();
    if (reply['error'] != null) {
      final code = reply['error'];
      throw CollectAuthException(
        'Google sign-in could not finish.',
        code:
            const {
              'google_cancelled',
              'google_use_email_sign_in',
            }.contains(code)
            ? code as String
            : 'invalid_google_sign_in',
      );
    }
    if (reply['state'] != state ||
        reply['code'] is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(reply['code'] as String)) {
      throw const CollectAuthException(
        'Google sign-in could not finish.',
        code: 'invalid_google_sign_in',
      );
    }
    final data = await _authRequest('google/exchange', {
      'code': reply['code'],
      'code_verifier': verifier,
      if (_client.supabaseConfiguration != null) 'client_state': state,
    });
    checkCurrent();
    final session = _verifiedSession(data);
    _install(session, CollectAuthEvent.signedIn);
    await _persist();
    if (_session?.accessToken != session.accessToken) {
      throw const CollectAuthException(
        'Your sign-in changed.',
        code: 'session_changed',
      );
    }
    return CollectAuthResponse(session: session);
  }

  String _otpKey(String? phone, String? email) {
    if ((phone == null) == (email == null) ||
        (phone != null && !RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(phone)) ||
        (email != null &&
            (email.length > 254 ||
                !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)))) {
      throw const CollectAuthException(
        'Enter a valid account address.',
        code: 'invalid_identity',
      );
    }
    return '$surface:${phone ?? email}';
  }

  Future<String?> _freshCaptcha(String? provided) async {
    final provider = _client.captchaProvider;
    try {
      // A shipping client always acquires a fresh challenge. A caller token
      // never replaces the configured browser challenge acquisition.
      final token = provider == null ? provided : await provider();
      if ((provider != null && token == null) ||
          (token != null && (token.isEmpty || token.length > 2048))) {
        throw const FormatException();
      }
      return token;
    } on CollectAuthException {
      rethrow;
    } catch (_) {
      throw const CollectAuthException(
        'Security verification could not finish.',
        code: 'captcha_unavailable',
      );
    }
  }

  Future<CollectAuthResponse> refreshSession() =>
      _refreshInFlight ??= _refresh().whenComplete(() {
        _refreshInFlight = null;
      });
  Future<CollectAuthResponse> _refresh() async {
    final original = _session;
    final generation = _generation;
    if (original?.user.isAnonymous == true &&
        _guestUpgrade?.unconfirmed == true) {
      throw const CollectAuthException(
        'Check the retained account verification before refreshing.',
        code: 'guest_upgrade_unknown',
        statusCode: '503',
      );
    }
    if (original?.refreshToken == null || _disposed) {
      throw const CollectAuthException(
        'Sign in again.',
        code: 'session_required',
      );
    }
    final data = await _authRequest('refresh', {
      'refresh_token': original!.refreshToken,
    });
    if (_disposed ||
        generation != _generation ||
        _session?.accessToken != original.accessToken) {
      throw const CollectAuthException(
        'Your sign-in changed.',
        code: 'session_changed',
      );
    }
    final next = _verifiedSession(data);
    if (next.user.id != original.user.id ||
        next.authSubject != original.authSubject ||
        next.user.isAnonymous != original.user.isAnonymous ||
        next.claims['session_id'] != original.claims['session_id']) {
      throw const CollectAuthException(
        'Sign in again.',
        code: 'invalid_session',
      );
    }
    _install(next, CollectAuthEvent.tokenRefreshed);
    await _persist();
    return CollectAuthResponse(session: next);
  }

  CollectAuthSession _verifiedSession(Map<String, dynamic> data) {
    final session = _decodeSession(data);
    if (session == null || session.isExpired || session.refreshToken == null) {
      throw const CollectAuthException(
        'Verification is unavailable.',
        code: 'invalid_session',
      );
    }
    return session;
  }

  CollectAuthSession? _decodeSession(
    Map<String, dynamic> data, {
    bool allowRetainedGuest = false,
  }) => CollectAuthSession.fromJson(
    data,
    allowMappedAuthUser: _client.supabaseConfiguration != null,
    allowAnonymous:
        anonymousSignInAvailable ||
        allowRetainedGuest &&
            surface == 'member' &&
            _client.supabaseConfiguration != null,
    expectedIssuer: _client.supabaseConfiguration?.authIssuer,
  );

  /// Installs a previously verified response synchronously after its caller's
  /// account fence. It never fetches, refreshes or trusts a browser broadcast.
  Future<CollectAuthResponse> recoverSession(
    String encoded, {
    CollectAuthEvent event = CollectAuthEvent.signedIn,
    void Function()? onInstalled,
  }) {
    if (_disposed || encoded.length > 131072) {
      throw const CollectAuthException(
        'Verification is unavailable.',
        code: 'invalid_session',
      );
    }
    final data = jsonDecode(encoded);
    if (data is! Map<String, dynamic>) {
      throw const CollectAuthException(
        'Verification is unavailable.',
        code: 'invalid_session',
      );
    }
    final session = _verifiedSession(data);
    _install(session, event, onInstalled: onInstalled);
    return _persist().then((_) => CollectAuthResponse(session: session));
  }

  void notifyAllSubscribers(CollectAuthEvent event) {
    if (!_disposed) _events.add(CollectAuthState(event, _session));
  }

  void _install(
    CollectAuthSession session,
    CollectAuthEvent event, {
    void Function()? onInstalled,
  }) {
    if (_disposed) throw StateError('Collect Auth is disposed');
    ++_generation;
    _session = session;
    // Record ownership before synchronous observers can cancel their view.
    onInstalled?.call();
    _events.add(CollectAuthState(event, session));
    _scheduleRefresh();
  }

  Future<void> _persist() {
    final session = _session;
    final generation = _generation;
    final pending = _guestUpgrade;
    final operation = _storageTail.catchError((Object _) {}).then((_) async {
      if (_disposed || generation != _generation || session == null) return;
      await _storage.write(
        jsonEncode({
          ...session.toJson(),
          if (session.user.isAnonymous && pending != null)
            'guest_upgrade': pending.toJson(),
        }),
      );
    });
    _storageTail = operation;
    return operation.catchError((Object _) {
      if (generation == _generation && !_disposed) {
        _clearLocal();
        final clear = _storageTail
            .catchError((Object _) {})
            .then((_) => _storage.clear());
        _storageTail = clear;
        unawaited(clear.catchError((Object _) {}));
      }
      throw const CollectAuthException(
        'Protected sign-in storage is unavailable.',
        code: 'protected_storage_unavailable',
      );
    });
  }

  Future<void> revokeCapturedSession(String accessToken) async {
    await _authRequest('logout', const {}, bearer: accessToken);
  }

  Future<void> clearLocalSession() {
    _client.cancelPendingRequests();
    _clearLocal();
    final clear = _storageTail
        .catchError((Object _) {})
        .then((_) => _storage.clear());
    _storageTail = clear;
    return clear;
  }

  Future<void> signOut({
    CollectSignOutScope scope = CollectSignOutScope.local,
  }) async {
    final original = _session;
    if (scope != CollectSignOutScope.local) {
      throw const CollectAuthException(
        'Use the device revocation workflow.',
        code: 'global_revocation_unavailable',
      );
    }
    final clear = clearLocalSession();
    Object? failure;
    if (original != null) {
      try {
        await _authRequest('logout', {
          'refresh_token': original.refreshToken,
        }, bearer: original.accessToken);
      } catch (error) {
        failure = error;
      }
    }
    await clear;
    if (failure != null) throw failure;
  }

  void _clearLocal() {
    _client.cancelCaptcha?.call();
    ++_generation;
    ++_otpGeneration;
    ++_anonymousGeneration;
    _session = null;
    _guestUpgrade = null;
    _guestReconcileInFlight = null;
    _challenges.clear();
    _challengeChannels.clear();
    _refreshTimer?.cancel();
    _refreshTimer = null;
    if (!_disposed) {
      _events.add(const CollectAuthState(CollectAuthEvent.signedOut, null));
    }
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    final session = _session;
    if (session?.user.isAnonymous == true &&
        _guestUpgrade?.unconfirmed == true) {
      return;
    }
    final expiration = session?.claims['exp'];
    if (_disposed || session?.refreshToken == null || expiration is! int) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final seconds = (expiration - now - 60).clamp(1, 86400);
    _refreshTimer = Timer(Duration(seconds: seconds), () async {
      try {
        await refreshSession();
      } catch (error) {
        if (_disposed || _session?.accessToken != session!.accessToken) return;
        if (session.isExpired ||
            (error is CollectAuthException &&
                const {'401', '403'}.contains(error.statusCode))) {
          try {
            await clearLocalSession();
          } catch (_) {}
        } else {
          _refreshTimer = Timer(const Duration(seconds: 15), _scheduleRefresh);
        }
      }
    });
  }

  Future<Map<String, dynamic>> _authRequest(
    String path,
    Map<String, dynamic> body, {
    String? bearer,
  }) async {
    try {
      final (status, data) = await _client.request(
        'POST',
        'v1/auth/$path',
        body: body,
        bearer: bearer,
        responseLimit: 131072,
      );
      if (status < 200 || status >= 300) {
        final error = collectApiFailure(status, data);
        if ((path == 'otp' || path == 'upgrade/otp') &&
            status == 503 &&
            error.code == 'otp_delivery_unknown') {
          final id = data is Map<String, dynamic> ? data['challenge_id'] : null;
          final retry = data is Map<String, dynamic>
              ? data['retry_after']
              : null;
          if (data is Map<String, dynamic> &&
              id is String &&
              RegExp(
                r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
              ).hasMatch(id) &&
              data['request_id'] == id &&
              retry is int &&
              retry >= 60 &&
              retry <= 3600) {
            throw _CollectOtpUnconfirmedReply(data);
          }
          throw const CollectAuthException(
            'Verification is unavailable.',
            statusCode: '503',
            code: 'invalid_response',
          );
        }
        throw CollectAuthException(
          error.message,
          statusCode: '$status',
          code: error.code,
        );
      }
      if (data is! Map<String, dynamic>) {
        throw const CollectAuthException(
          'Verification is unavailable.',
          code: 'invalid_response',
        );
      }
      return data;
    } on CollectAuthException {
      rethrow;
    } catch (_) {
      throw const CollectAuthException(
        'Verification is unavailable.',
        code: 'auth_transport_unavailable',
      );
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _client.cancelCaptcha?.call();
    ++_generation;
    ++_otpGeneration;
    _refreshTimer?.cancel();
    _challenges.clear();
    _challengeChannels.clear();
    _session = null;
    await _storageTail.catchError((Object _) {});
    await _events.close();
  }
}
