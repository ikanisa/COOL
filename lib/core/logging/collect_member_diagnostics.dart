import 'dart:async';
import 'dart:convert';

import '../cloudflare/collect_cloudflare_client.dart';
import 'collect_diagnostic_queue.dart';

CollectDiagnosticDelivery collectDiagnosticReply(int status, Object? body) {
  if (status == 202 &&
      body is Map &&
      body.length == 2 &&
      body['contract_version'] == 1 &&
      body['accepted'] == true) {
    return CollectDiagnosticDelivery.accepted;
  }
  return const {400, 404, 405, 409, 413, 415, 422}.contains(status)
      ? CollectDiagnosticDelivery.discard
      : CollectDiagnosticDelivery.retry;
}

/// Uses the already-owned member client. Never creates another auth session or
/// refreshes credentials as a side effect of telemetry.
class CollectMemberDiagnostics {
  CollectMemberDiagnostics(this.queue);
  final CollectDiagnosticQueue queue;
  CollectCloudflareClient? _client;
  StreamSubscription<CollectAuthState>? _subscription;

  String? _fence(CollectCloudflareClient? client) {
    final session = client?.auth.currentSession;
    if (client?.supabaseConfiguration == null || session == null) return null;
    try {
      final claims = jsonDecode(
        utf8.decode(
          base64Url.decode(
            base64Url.normalize(session.accessToken.split('.')[1]),
          ),
        ),
      );
      final sid = claims is Map ? claims['session_id'] : null;
      if (sid is! String || !RegExp(r'^[a-f0-9-]{36}$').hasMatch(sid)) {
        return null;
      }
      return collectDiagnosticSessionFence('${session.user.id}|$sid');
    } catch (_) {
      return null;
    }
  }

  void bind(CollectCloudflareClient? client) {
    if (identical(client, _client)) return;
    unawaited(_subscription?.cancel());
    _client = client;
    void update() {
      final fence = _fence(client);
      bool current() =>
          identical(_client, client) &&
          fence != null &&
          _fence(client) == fence;
      queue.activate(
        fence: fence,
        current: current,
        send: (body) async {
          if (!current()) return CollectDiagnosticDelivery.retry;
          final token = client!.auth.currentSession?.accessToken;
          if (token == null) return CollectDiagnosticDelivery.retry;
          final (status, reply) = await client.request(
            'POST',
            'v1/diagnostics',
            body: body,
            bearer: token,
            responseLimit: 4096,
          );
          return current()
              ? collectDiagnosticReply(status, reply)
              : CollectDiagnosticDelivery.retry;
        },
      );
    }

    _subscription = client?.auth.onAuthStateChange.listen((_) => update());
    update();
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _client = null;
    await queue.dispose();
  }
}
