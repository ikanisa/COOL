import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;

import '../../shared/providers/collect_app_state.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class SmsPermissionDeniedScreen extends StatelessWidget {
  const SmsPermissionDeniedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'SMS access needed',
      children: [
        CollectBottomSheet(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MinimalStatePanel(
                icon: CollectIcons.sms,
                title: 'Enable Android SMS access',
                message:
                    'Group creation needs Android SMS access for owner-side MoMo verification.',
                tone: CollectStatusTone.warning,
              ),
              CollectSpacing.gap16,
              const CollectButton(
                label: 'Open app settings',
                icon: CollectIcons.settings,
                onPressed: permissions.openAppSettings,
                expand: true,
              ),
              CollectButton(
                label: 'Try again',
                icon: CollectIcons.sync,
                onPressed: () => context.go('/groups/create'),
                variant: CollectButtonVariant.secondary,
                expand: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class IphoneCreateUnavailableScreen extends StatelessWidget {
  const IphoneCreateUnavailableScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'Create group',
      children: [
        const MinimalStatePanel(
          icon: CollectIcons.momo,
          title: 'Group creation is available only on Android',
          message:
              'You can still join groups and contribute from iPhone. Group creation needs Android SMS capture for owner-side MoMo verification.',
          tone: CollectStatusTone.info,
        ),
        CollectButton(
          label: 'Scan QR',
          icon: CollectIcons.qr,
          onPressed: () => context.go('/groups/scan'),
          expand: true,
        ),
        CollectButton(
          label: 'Groups',
          icon: CollectIcons.collections,
          onPressed: () => context.go('/groups'),
          variant: CollectButtonVariant.secondary,
          expand: true,
        ),
      ],
    );
  }
}

class OfflineStateScreen extends StatelessWidget {
  const OfflineStateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'Connection issue',
      children: [
        const CollectVisualFeatureCard(
          asset: 'assets/brand/generated/collect_visual_group_momentum.png',
          icon: CollectIcons.warning,
          title: 'Connection issue',
          message: 'Cached groups stay readable. Live payment checks pause.',
          tone: CollectStatusTone.warning,
        ),
        const CollectBentoGrid(
          primary: BentoMetricCell(
            label: 'Offline-safe behavior',
            value: 'Readable',
            detail: 'Existing groups and ledgers',
            icon: CollectIcons.collections,
            tone: CollectStatusTone.success,
            emphasis: true,
          ),
          top: BentoMetricCell(
            label: 'Live checks',
            value: 'Paused',
            detail: 'MoMo verification',
            icon: CollectIcons.pending,
            tone: CollectStatusTone.warning,
          ),
          bottom: BentoMetricCell(
            label: 'Next step',
            value: 'Retry',
            detail: 'Refresh sync state',
            icon: CollectIcons.sync,
            tone: CollectStatusTone.info,
          ),
        ),
        const CollectCard(
          emphasis: CollectCardEmphasis.flat,
          child: CollectListTile(
            leading: CollectIcons.info,
            title: 'Offline-safe behavior',
            subtitle: 'Existing screens stay visible.',
          ),
        ),
        CollectButton(
          label: 'Retry sync',
          icon: CollectIcons.sync,
          onPressed: () => context.go('/sync'),
          expand: true,
        ),
      ],
    );
  }
}

class SyncStatusScreen extends ConsumerWidget {
  const SyncStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(realtimeSyncStatusProvider);
    final title = switch (status) {
      RealtimeSyncStatus.current => 'Realtime current',
      RealtimeSyncStatus.syncing => 'Syncing',
      RealtimeSyncStatus.needsAttention => 'Sync issue',
    };
    return ScreenScaffold(
      title: 'Sync status',
      children: [
        MinimalStatePanel(
          icon: status == RealtimeSyncStatus.current
              ? CollectIcons.check
              : CollectIcons.sync,
          title: title,
          message: status == RealtimeSyncStatus.current
              ? 'Groups, payments, and ledger data are current.'
              : status == RealtimeSyncStatus.syncing
              ? 'Refreshing groups, payments, and ledger updates.'
              : 'Live updates need a stable connection.',
          tone: status == RealtimeSyncStatus.needsAttention
              ? CollectStatusTone.warning
              : CollectStatusTone.info,
        ),
      ],
    );
  }
}
