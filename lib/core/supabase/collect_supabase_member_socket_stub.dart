import 'package:realtime_client/realtime_client.dart' show WebSocketTransport;

/// Native-only transport. Web/Admin consumers retain authorized HTTP polling.
class CollectMemberSocketTransport {
  CollectMemberSocketTransport({required Duration connectTimeout});
  WebSocketTransport get connect =>
      (_, _) => throw StateError('Native transport unavailable');
  void close() {}
}
