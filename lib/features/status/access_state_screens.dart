import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/providers/collect_app_state.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class OfflineStateScreen extends StatelessWidget {
  const OfflineStateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'Connection issue',
      children: [
        const CollectVisualFeatureCard(
          asset: 'assets/brand/collect_runtime/media/group-momentum.png',
          icon: CollectIcons.warning,
          title: 'Connection issue',
          message: 'Saved groups stay readable.',
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
              ? 'Groups, payments, and ledgers are current.'
              : status == RealtimeSyncStatus.syncing
              ? 'Refreshing updates.'
              : 'Live updates need a stable connection.',
          tone: status == RealtimeSyncStatus.needsAttention
              ? CollectStatusTone.warning
              : CollectStatusTone.info,
        ),
      ],
    );
  }
}
