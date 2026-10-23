import 'dart:async';
import 'dart:io';

import 'package:realtime_client/realtime_client.dart' show WebSocketTransport;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef CollectMemberSocketOpener =
    Future<WebSocket> Function(
      String url,
      Map<String, String> headers,
      HttpClient client,
    );

/// One native attempt owns its HTTP handshake and socket. Retiring it aborts
/// the handshake synchronously; timeout alone would leave WebSocket.connect alive.
class CollectMemberSocketTransport {
  CollectMemberSocketTransport({
    required this.connectTimeout,
    HttpClient Function()? httpClientFactory,
    CollectMemberSocketOpener? openSocket,
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _openSocket = openSocket ?? _open;
  final Duration connectTimeout;
  final HttpClient Function() _httpClientFactory;
  final CollectMemberSocketOpener _openSocket;
  _Attempt? _attempt;
  bool _retired = false;
  WebSocketTransport get connect => _connect;

  static Future<WebSocket> _open(
    String url,
    Map<String, String> headers,
    HttpClient client,
  ) => WebSocket.connect(url, headers: headers, customClient: client);

  WebSocketChannel _connect(String url, Map<String, String> headers) {
    if (_retired || _attempt != null) {
      throw StateError('Member connection unavailable');
    }
    final uri = Uri.parse(url);
    // Auth is exclusively in the private SDK join. Transport configuration is
    // public and cannot acquire a bearer via a query/header override.
    if (uri.scheme != 'wss' ||
        uri.userInfo.isNotEmpty ||
        headers.keys.any((key) => key.toLowerCase() == 'authorization') ||
        uri.queryParameters.keys.any(
          (key) => !const {'apikey', 'vsn'}.contains(key),
        )) {
      throw StateError('Member connection unavailable');
    }
    final attempt = _Attempt(_httpClientFactory(), connectTimeout);
    _attempt = attempt;
    attempt.start(() => _openSocket(url, headers, attempt.client));
    return attempt.channel;
  }

  void close() {
    _retired = true;
    _attempt?.close();
  }
}

class _Attempt {
  _Attempt(this.client, Duration timeout) {
    channel = _OwnedChannel(_socket.future, close);
    _deadline = Timer(timeout, close);
  }
  final HttpClient client;
  final _socket = Completer<WebSocket>();
  late final _OwnedChannel channel;
  Timer? _deadline;
  WebSocket? _connected;
  bool _closed = false;

  void start(Future<WebSocket> Function() open) {
    unawaited(
      Future<WebSocket>.sync(open).then(
        (socket) {
          if (_closed) {
            _closeSocket(socket);
            return;
          }
          try {
            _deadline?.cancel();
            _deadline = null;
            _connected = socket;
            socket.pingInterval = const Duration(seconds: 25);
            _socket.complete(socket);
          } catch (_) {
            _closeSocket(socket);
            close();
          }
        },
        onError: (Object _, StackTrace _) {
          close();
        },
      ),
    );
  }

  static void _closeSocket(WebSocket socket) {
    try {
      unawaited(
        socket.close().then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
    } catch (_) {
      /* Fixed closed state; never surface transport details. */
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _deadline?.cancel();
    _deadline = null;
    try {
      client.close(force: true);
    } catch (_) {
      /* Keep retirement fenced. */
    }
    if (!_socket.isCompleted) {
      _socket.completeError(StateError('Member connection unavailable'));
    }
    final connected = _connected;
    _connected = null;
    if (connected != null) _closeSocket(connected);
    channel.closeInner();
  }
}

class _OwnedChannel extends IOWebSocketChannel {
  _OwnedChannel(super.webSocket, this.retire);
  final void Function() retire;
  // This wrapper and SDK disconnect own the inner sink's close lifecycle.
  // ignore: close_sinks
  late final _OwnedSink _ownedSink = _OwnedSink(super.sink, retire);
  @override
  WebSocketSink get sink => _ownedSink;
  void closeInner() {
    try {
      unawaited(
        super.sink.close().then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        ),
      );
    } catch (_) {}
  }
}

class _OwnedSink implements WebSocketSink {
  _OwnedSink(this.inner, this.retire);
  final WebSocketSink inner;
  final void Function() retire;
  @override
  void add(Object? value) => inner.add(value);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      inner.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<dynamic> stream) => inner.addStream(stream);
  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    retire();
  }

  @override
  Future<void> get done => inner.done.then<void>((_) {});
}
