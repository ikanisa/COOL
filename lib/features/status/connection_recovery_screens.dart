import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/providers/collect_app_state.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class OfflineRecoveryScreen extends StatelessWidget {
  const OfflineRecoveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ConnectionRecoveryScreen(
      title: 'Offline mode',
      subtitle: 'Saved data is available',
      bannerStatus: ConnectivityStatus.offlineStale,
      heroIcon: CollectIcons.sync,
      heroTitle: 'You are offline',
      heroMessage:
          'Saved groups and ledgers remain available. New activity resumes when you reconnect.',
      primaryLabel: 'Review groups',
      primaryIcon: CollectIcons.collections,
      primaryRoute: '/groups',
      rows: [
        _RecoveryRow(
          icon: CollectIcons.collections,
          title: 'Groups',
          value: 'Saved',
          tone: CollectStatusTone.warning,
        ),
        _RecoveryRow(
          icon: CollectIcons.ledger,
          title: 'Ledgers',
          value: 'Read only',
          tone: CollectStatusTone.info,
        ),
      ],
    );
  }
}

class SyncRecoveryScreen extends StatelessWidget {
  const SyncRecoveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ConnectionRecoveryScreen(
      title: 'Sync status',
      subtitle: 'Latest changes are pending',
      bannerStatus: ConnectivityStatus.degraded,
      heroIcon: CollectIcons.pending,
      heroTitle: 'Sync needs attention',
      heroMessage:
          'Saved data remains available while Collect checks for updates.',
      primaryLabel: 'Review groups',
      primaryIcon: CollectIcons.sync,
      primaryRoute: '/groups',
      rows: [
        _RecoveryRow(
          icon: CollectIcons.pending,
          title: 'Queued updates',
          value: 'Protected',
          tone: CollectStatusTone.warning,
        ),
        _RecoveryRow(
          icon: CollectIcons.lock,
          title: 'Private data',
          value: 'Masked',
          tone: CollectStatusTone.privacy,
        ),
      ],
    );
  }
}

class _ConnectionRecoveryScreen extends StatelessWidget {
  const _ConnectionRecoveryScreen({
    required this.title,
    required this.subtitle,
    required this.bannerStatus,
    required this.heroIcon,
    required this.heroTitle,
    required this.heroMessage,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.primaryRoute,
    required this.rows,
  });

  final String title;
  final String subtitle;
  final ConnectivityStatus bannerStatus;
  final IconData heroIcon;
  final String heroTitle;
  final String heroMessage;
  final String primaryLabel;
  final IconData primaryIcon;
  final String primaryRoute;
  final List<_RecoveryRow> rows;

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: title,
      subtitle: subtitle,
      showHeader: false,
      compact: true,
      persistentPill: CollectConnectivityBanner(status: bannerStatus),
      children: [
        MinimalStatePanel(
          icon: heroIcon,
          title: heroTitle,
          message: heroMessage,
          tone: bannerStatus == ConnectivityStatus.offlineStale
              ? CollectStatusTone.warning
              : CollectStatusTone.info,
        ),
        CollectCard(
          emphasis: CollectCardEmphasis.glow,
          child: Column(
            children: [
              for (var index = 0; index < rows.length; index += 1) ...[
                rows[index],
                if (index != rows.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
        CollectButton(
          label: primaryLabel,
          icon: primaryIcon,
          onPressed: () => context.go(primaryRoute),
          expand: true,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => context.go('/settings/legal/privacy'),
            icon: const Icon(CollectIcons.privacy),
            label: const Text('Privacy in recovery'),
          ),
        ),
      ],
    );
  }
}

class _RecoveryRow extends StatelessWidget {
  const _RecoveryRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.tone,
  });

  final IconData icon;
  final String title;
  final String value;
  final CollectStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.4;
    final status = CollectStatusChip(label: value, tone: tone, icon: icon);
    if (largeText) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: CollectSpacing.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CollectToneIcon(icon: icon, tone: tone),
                CollectSpacing.gapW12,
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            CollectSpacing.gap8,
            status,
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CollectSpacing.x3),
      child: Row(
        children: [
          CollectToneIcon(icon: icon, tone: tone),
          CollectSpacing.gapW12,
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          status,
        ],
      ),
    );
  }
}
