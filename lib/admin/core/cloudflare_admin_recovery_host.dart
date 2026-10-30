import 'package:flutter/widgets.dart';

import '../../core/logging/app_logger.dart';
import '../../core/startup/collect_global_error_handlers.dart';
import '../../core/startup/collect_startup_host.dart';

/// The cookie workspace has no bearer-client initializer. Keep its provider
/// scope above this host so a fatal rendering/platform fault cannot discard
/// journaled requests or create a new request by retrying application startup.
class CloudflareAdminRecoveryHost extends StatefulWidget {
  const CloudflareAdminRecoveryHost({
    required this.child,
    this.diagnostics,
    super.key,
  });

  final Widget child;
  final CollectDiagnostics? diagnostics;

  @override
  State<CloudflareAdminRecoveryHost> createState() =>
      _CloudflareAdminRecoveryHostState();
}

class _CloudflareAdminRecoveryHostState
    extends State<CloudflareAdminRecoveryHost> {
  late final CollectGlobalErrorHandlers _handlers;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _handlers = CollectGlobalErrorHandlers(
      diagnostics:
          widget.diagnostics ??
          CollectDiagnostics(
            surface: CollectDiagnosticSurface.admin,
            environmentName: const String.fromEnvironment(
              'APP_ENVIRONMENT',
              defaultValue: 'local',
            ),
          ),
      onApplicationFault: () {
        if (mounted && !_failed) setState(() => _failed = true);
      },
    )..install();
  }

  @override
  void dispose() {
    _handlers.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _failed ? const CollectFatalRecoveryApp() : widget.child;
}
