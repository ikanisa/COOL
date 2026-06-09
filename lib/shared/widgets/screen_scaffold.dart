import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/collect_app_state.dart';
import 'collect_components.dart';

class ScreenScaffold extends ConsumerWidget {
  const ScreenScaffold({
    required this.title,
    required this.children,
    this.subtitle,
    this.actions = const [],
    this.persistentPill,
    this.bottomAction,
    this.showHeader = true,
    this.compact = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? persistentPill;
  final Widget? bottomAction;
  final List<Widget> children;
  final bool showHeader;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ScreenScaffoldLayout(
      title: title,
      subtitle: subtitle,
      actions: actions,
      banner: _statusBanner(context, ref),
      persistentPill: persistentPill,
      bottomAction: bottomAction,
      showHeader: showHeader,
      compact: compact,
      children: children,
    );
  }

  Widget? _statusBanner(BuildContext context, WidgetRef ref) {
    final String path;
    try {
      path = GoRouterState.of(context).uri.path;
    } catch (_) {
      return null;
    }
    final connectivity = ref.watch(connectivityStatusProvider);
    final sync = ref.watch(realtimeSyncStatusProvider);
    if (path != '/offline' && connectivity != ConnectivityStatus.online) {
      return InfoSecurityBanner(
        title: connectivity == ConnectivityStatus.offline
            ? 'Connection issue'
            : 'Poor connection',
        message: 'Refresh when the connection recovers.',
        tone: CollectStatusTone.warning,
      );
    }
    if (path != '/sync' && sync == RealtimeSyncStatus.needsAttention) {
      return const InfoSecurityBanner(
        title: 'Sync needs attention',
        message: 'Open sync status if this continues.',
        tone: CollectStatusTone.warning,
      );
    }
    if (path != '/sync' && sync == RealtimeSyncStatus.syncing) {
      return const InfoSecurityBanner(
        title: 'Syncing updates',
        message: 'Refreshing.',
        tone: CollectStatusTone.info,
      );
    }
    return null;
  }
}
