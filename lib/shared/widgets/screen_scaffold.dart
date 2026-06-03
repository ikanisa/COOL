import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/collect_app_state.dart';
import '../models/collect_models.dart';
import '../repositories/collect_repository.dart';
import 'collect_components.dart';

class ScreenScaffold extends ConsumerWidget {
  const ScreenScaffold({
    required this.title,
    required this.children,
    this.subtitle,
    this.actions = const [],
    this.bottomAction,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? bottomAction;
  final List<Widget> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ScreenScaffoldLayout(
      title: title,
      subtitle: subtitle,
      actions: actions,
      persistentPill: CollectDynamicIsland(
        activeIntent: _activePaymentIntent(ref),
      ),
      banner: _statusBanner(context, ref),
      bottomAction: bottomAction,
      children: children,
    );
  }

  PaymentIntentModel? _activePaymentIntent(WidgetRef ref) {
    final intents = ref.watch(
      collectRepositoryProvider.select((state) => state.paymentIntents),
    );
    for (final intent in intents.reversed) {
      if (intent.status == 'pending') return intent;
    }
    return null;
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
