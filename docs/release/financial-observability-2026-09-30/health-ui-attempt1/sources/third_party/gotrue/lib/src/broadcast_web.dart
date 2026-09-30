import 'dart:async';
import 'dart:js_interop';

import 'package:gotrue/src/types/types.dart';
import 'package:logging/logging.dart';
import 'package:web/web.dart' as web;

final _log = Logger('supabase.auth');

BroadcastChannel getBroadcastChannel(String broadcastKey) {
  final broadcast = web.BroadcastChannel(broadcastKey);
  final controller = StreamController<Map<String, dynamic>>();

  void onMessage(web.MessageEvent event) {
    try {
      final data = event.data.dartify();
      if (data is! Map || data.length != 8 || !data.keys.every((key) => key is String)) return;
      // Bounds precede interpretation. Nested Session objects are rejected here.
      if (data.values.any((value) => value is! String && value is! int)) return;
      if (data.values.any((value) => value is String && value.length > 1024)) return;
      controller.add(Map<String, dynamic>.from(data));
    } catch (_) {
      // Untrusted channel input must not cause a runtime error or leak its data.
    }
  }

  broadcast.onmessage = onMessage.toJS;

  return (
    onMessage: controller.stream,
    postMessage: (message) {
      _log.fine('Broadcasting event: ${message['event']}');
      broadcast.postMessage(message.jsify()!);
    },
    close: () {
      broadcast.close();
      unawaited(controller.close());
    },
  );
}
