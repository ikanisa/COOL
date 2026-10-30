import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/collect_diagnostic_queue.dart';
import 'cloudflare_admin_session.dart';

/// Lives above fatal recovery so a rendering failure can still be delivered.
/// No bearer client, raw error data, visual changes or session mutations.
class CloudflareAdminDiagnosticsHost extends ConsumerStatefulWidget {
  const CloudflareAdminDiagnosticsHost({
    required this.queue,
    required this.child,
    super.key,
  });
  final CollectDiagnosticQueue queue;
  final Widget child;
  @override
  ConsumerState<CloudflareAdminDiagnosticsHost> createState() => _State();
}

class _State extends ConsumerState<CloudflareAdminDiagnosticsHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual(cloudflareAdminSessionProvider, (_, next) {
      final session = ref.read(cloudflareAdminSessionProvider.notifier),
          user = next.asData?.value;
      final authority = session.authorityFence;
      final fence = user != null && session.usesEmailVerification
          ? collectDiagnosticSessionFence('${user.id}|${user.sessionId}')
          : null;
      bool current() =>
          mounted && user != null && session.authorityFence == authority;
      widget.queue.activate(
        fence: fence,
        current: current,
        send: (body) => session.sendDiagnosticBatch(body, current: current),
      );
    }, fireImmediately: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.queue.wake();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.queue.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
