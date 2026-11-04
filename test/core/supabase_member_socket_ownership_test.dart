import 'dart:async';
import 'dart:io';
import 'package:collect_app/core/supabase/collect_supabase_member_socket_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const _url =
    'wss://rrlduytparvsjfmegalh.supabase.co/realtime/v1/websocket?apikey=synthetic_public&vsn=1.0.0';

class _Client implements HttpClient {
  bool forced = false;
  @override
  void close({bool force = false}) {
    forced = force;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  List<String>? operator [](String name) => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DetachedSocket implements Socket {
  bool destroyed = false;
  @override
  void destroy() => destroyed = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RedirectResponse implements HttpClientResponse {
  _RedirectResponse(this.socket);
  final _DetachedSocket socket;
  @override
  int get statusCode => HttpStatus.found;
  @override
  final HttpHeaders headers = _Headers();
  @override
  Future<Socket> detachSocket() async => socket;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A synthetic request models a redirect only when the SDK leaves its default
/// redirect setting enabled. No HTTP server or network connection is used.
class _RedirectRequest implements HttpClientRequest {
  @override
  bool followRedirects = true;
  @override
  final HttpHeaders headers = _Headers();
  final socket = _DetachedSocket();
  bool? followRedirectsAtClose;
  int redirectTargetRequests = 0;
  int closeCalls = 0;
  @override
  Future<HttpClientResponse> close() async {
    closeCalls++;
    followRedirectsAtClose = followRedirects;
    if (followRedirects) redirectTargetRequests++;
    return _RedirectResponse(socket);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RedirectClient extends _Client {
  final request = _RedirectRequest();
  String? method;
  Uri? uri;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri uri) async {
    this.method = method;
    this.uri = uri;
    return request;
  }
}

class _Socket extends Stream<dynamic> implements WebSocket {
  final input = StreamController<dynamic>();
  int closes = 0;
  @override
  Duration? pingInterval;
  @override
  String? get protocol => null;
  @override
  int? get closeCode => 1000;
  @override
  String? get closeReason => null;
  @override
  void add(dynamic data) {}
  @override
  Future<void> close([int? code, String? reason]) async {
    closes++;
    if (!input.isClosed) unawaited(input.close());
  }

  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => input.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'native default opener refuses redirect before HTTP handshake closes',
    () async {
      final client = _RedirectClient(), unrelated = _Client();
      final owner = CollectMemberSocketTransport(
        connectTimeout: const Duration(seconds: 20),
        httpClientFactory: () => client,
      );
      final channel = owner.connect(_url, {});
      await expectLater(
        channel.ready,
        throwsA(
          predicate<Object>(
            (error) =>
                error is WebSocketChannelException &&
                error.toString().contains('Member connection unavailable'),
          ),
        ),
      );
      expect(client.method, 'GET');
      expect(client.uri?.scheme, 'https');
      expect(client.uri?.host, 'rrlduytparvsjfmegalh.supabase.co');
      expect(client.request.closeCalls, 1);
      expect(client.request.followRedirectsAtClose, isFalse);
      expect(client.request.redirectTargetRequests, 0);
      expect(client.forced, isTrue);
      expect(unrelated.forced, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(client.request.socket.destroyed, isTrue);
      owner.close();
    },
  );

  test('unsafe handshake parameters are refused before acquiring a client', () {
    var acquired = 0;
    final owner = CollectMemberSocketTransport(
      connectTimeout: const Duration(seconds: 20),
      httpClientFactory: () {
        acquired++;
        return _Client();
      },
    );
    expect(
      () => owner.connect(_url.replaceFirst('wss:', 'ws:'), {}),
      throwsStateError,
    );
    expect(
      () => owner.connect(_url, {'Authorization': 'Bearer synthetic'}),
      throwsStateError,
    );
    expect(
      () => owner.connect('$_url&access_token=synthetic', {}),
      throwsStateError,
    );
    expect(acquired, 0);
    owner.close();
  });

  test(
    'never-ready native handshake deadline force-closes owned HttpClient and settles ready',
    () async {
      final client = _Client();
      final pending = Completer<WebSocket>();
      final owner = CollectMemberSocketTransport(
        connectTimeout: const Duration(milliseconds: 20),
        httpClientFactory: () => client,
        openSocket: (_, _, _) => pending.future,
      );
      final channel = owner.connect(_url, {});
      await expectLater(
        channel.ready,
        throwsA(isA<WebSocketChannelException>()),
      );
      expect(client.forced, true);
      await channel.sink.close().timeout(const Duration(seconds: 1));
      owner.close();
      final late = _Socket();
      pending.complete(late);
      await Future<void>.delayed(Duration.zero);
      expect(late.closes, 1);
    },
  );
  test(
    'dispose before ready cancels owned handshake and closes late success without joining',
    () async {
      final client = _Client(), unrelated = _Client();
      final pending = Completer<WebSocket>();
      final owner = CollectMemberSocketTransport(
        connectTimeout: const Duration(seconds: 20),
        httpClientFactory: () => client,
        openSocket: (_, headers, actualClient) {
          expect(actualClient, same(client));
          expect(headers, isEmpty);
          return pending.future;
        },
      );
      final channel = owner.connect(_url, {});
      final failedReady = expectLater(
        channel.ready,
        throwsA(isA<WebSocketChannelException>()),
      );
      owner.close();
      expect(client.forced, true);
      expect(unrelated.forced, false);
      await failedReady;
      await channel.sink.close().timeout(const Duration(seconds: 1));
      final late = _Socket();
      pending.complete(late);
      await Future<void>.delayed(Duration.zero);
      expect(late.closes, 1);
      expect(late.pingInterval, isNull);
      expect(() => owner.connect(_url, {}), throwsStateError);
    },
  );
  test(
    'accepted native socket preserves25s ping and only closes its owned resources',
    () async {
      final client = _Client(), unrelated = _Client();
      // The attempt owner explicitly closes this accepted socket below.
      // ignore: close_sinks
      final socket = _Socket();
      final owner = CollectMemberSocketTransport(
        connectTimeout: const Duration(seconds: 20),
        httpClientFactory: () => client,
        openSocket: (_, _, _) async => socket,
      );
      final channel = owner.connect(_url, {});
      await channel.ready;
      final received = <dynamic>[];
      final listener = channel.stream.listen(received.add);
      expect(socket.pingInterval, const Duration(seconds: 25));
      owner.close();
      await channel.sink.close().timeout(const Duration(seconds: 1));
      await Future<void>.delayed(Duration.zero);
      expect(client.forced, true);
      expect(unrelated.forced, false);
      expect(socket.closes, greaterThanOrEqualTo(1));
      expect(received, isEmpty);
      await listener.cancel();
    },
  );
  test(
    'handshake rejection is fixed and never propagates opener error secret',
    () async {
      final client = _Client();
      final owner = CollectMemberSocketTransport(
        connectTimeout: const Duration(seconds: 20),
        httpClientFactory: () => client,
        openSocket: (_, _, _) =>
            Future<WebSocket>.error(StateError('SYNTHETIC_RAW_SECRET')),
      );
      final channel = owner.connect(_url, {});
      await expectLater(
        channel.ready,
        throwsA(
          predicate<Object>(
            (error) =>
                error is WebSocketChannelException &&
                error.toString().contains('Member connection unavailable') &&
                !error.toString().contains('SYNTHETIC_RAW_SECRET'),
          ),
        ),
      );
      expect(client.forced, true);
      owner.close();
    },
  );
}
