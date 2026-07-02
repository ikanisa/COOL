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
      subtitle: 'Saved groups stay visible',
      bannerStatus: ConnectivityStatus.offlineStale,
      heroIcon: CollectIcons.sync,
      heroTitle: 'Showing saved collection data',
      heroMessage:
          'You can review saved groups and ledgers. New joins, QR scans, and contribution updates resume when the connection returns.',
      primaryLabel: 'Review groups',
      primaryIcon: CollectIcons.collections,
      primaryRoute: '/groups',
      secondaryLabel: 'Home',
      secondaryIcon: CollectIcons.home,
      secondaryRoute: '/home',
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
        _RecoveryRow(
          icon: CollectIcons.qr,
          title: 'Scan/share',
          value: 'Wait online',
          tone: CollectStatusTone.neutral,
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
      subtitle: 'Keep changes verifiable',
      bannerStatus: ConnectivityStatus.degraded,
      heroIcon: CollectIcons.pending,
      heroTitle: 'Sync needs attention',
      heroMessage:
          'Collect keeps visible data privacy-safe while the latest group, payment, and member updates finish syncing.',
      primaryLabel: 'Refresh groups',
      primaryIcon: CollectIcons.sync,
      primaryRoute: '/groups',
      secondaryLabel: 'Home',
      secondaryIcon: CollectIcons.home,
      secondaryRoute: '/home',
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
        _RecoveryRow(
          icon: CollectIcons.check,
          title: 'Verified ledger',
          value: 'Rechecks',
          tone: CollectStatusTone.info,
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
    required this.secondaryLabel,
    required this.secondaryIcon,
    required this.secondaryRoute,
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
  final String secondaryLabel;
  final IconData secondaryIcon;
  final String secondaryRoute;
  final List<_RecoveryRow> rows;

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: title,
      subtitle: subtitle,
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
        const InfoSecurityBanner(
          title: 'Privacy stays on',
          message:
              'Raw phone numbers, receiver MoMo numbers, SMS bodies, OTPs, and transaction IDs stay hidden in recovery states.',
          tone: CollectStatusTone.privacy,
          messageMaxLines: 2,
        ),
        CollectButton(
          label: primaryLabel,
          icon: primaryIcon,
          onPressed: () => context.go(primaryRoute),
          expand: true,
        ),
        CollectButton(
          label: secondaryLabel,
          icon: secondaryIcon,
          variant: CollectButtonVariant.secondary,
          onPressed: () => context.go(secondaryRoute),
          expand: true,
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
          CollectStatusChip(label: value, tone: tone, icon: icon),
        ],
      ),
    );
  }
}
