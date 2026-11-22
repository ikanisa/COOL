part of 'collect_cloudflare_client.dart';

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
  return CollectApiException(
    code: code,
    message: message,
    httpStatusCode: status,
  );
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
