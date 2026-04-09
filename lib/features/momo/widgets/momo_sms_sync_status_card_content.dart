part of 'momo_sms_sync_status_card.dart';

List<Widget> _buildChips(MomoSmsSyncStatus status, {int retryQueueSize = 0}) {
  final chips = <Widget>[];
  final latest = status.latestSuccessfulRun;
  if (status.initialBackfillCompleted) {
    chips.add(const _SyncChip(label: '12-month backfill'));
  }
  if (latest != null && latest.incremental) {
    chips.add(const _SyncChip(label: 'Incremental sync'));
  }
  if (latest != null && latest.uploadedMessages > 0) {
    chips.add(_SyncChip(label: '+${latest.uploadedMessages} new'));
  }
  if (latest != null && latest.duplicateMessages > 0) {
    chips.add(_SyncChip(label: '${latest.duplicateMessages} duplicates'));
  }
  if (retryQueueSize > 0) {
    chips.add(_SyncChip(label: '$retryQueueSize pending retry'));
  }
  return chips;
}

String _titleFor(
  AppAccessSnapshot? snapshot,
  MomoSmsSyncStatus status,
  BuildContext context,
) {
  switch (snapshot?.kind) {
    case AppAccessStateKind.ready:
      if (!status.initialBackfillCompleted) {
        return 'Import past year';
      }
      return 'SMS sync ready';
    case AppAccessStateKind.disabledInApp:
      return 'SMS sync off';
    case AppAccessStateKind.needsSystemPermission:
      return 'Allow SMS access';
    case AppAccessStateKind.blockedInSystem:
      return 'SMS blocked';
    case AppAccessStateKind.notAvailable:
    case AppAccessStateKind.serviceDisabled:
      return 'SMS unavailable';
    case null:
      return 'SMS sync';
  }
}

String _subtitleFor(
  AppAccessSnapshot? snapshot,
  MomoSmsSyncStatus status,
  BuildContext context,
) {
  final latest = status.latestRun;
  final dateFormat = DateFormat('dd MMM, HH:mm');
  switch (snapshot?.kind) {
    case AppAccessStateKind.ready:
      if (!status.initialBackfillCompleted) {
        return 'Run a one-time 12-month import of approved M-Money confirmations.';
      }
      if (latest?.isFailed == true) {
        return latest?.errorMessage?.trim().isNotEmpty == true
            ? 'Last sync failed: ${latest!.errorMessage!}'
            : 'Last sync failed. Try again to refresh approved confirmations.';
      }
      final completedAt =
          status.latestSuccessfulRun?.scanCompletedAt ??
          status.latestSuccessfulRun?.scanStartedAt;
      if (completedAt != null) {
        return 'Approved sender IDs only. Last synced ${dateFormat.format(completedAt.toLocal())}.';
      }
      return 'Approved sender IDs only. New confirmations sync into your ledger.';
    case AppAccessStateKind.disabledInApp:
      return 'Turn this on only if you want Cool to read approved M-Money confirmations.';
    case AppAccessStateKind.needsSystemPermission:
      return 'Grant Android SMS access to verify Mobile Money payments automatically.';
    case AppAccessStateKind.blockedInSystem:
      return 'Android blocked SMS access. Open settings to continue historical sync.';
    case AppAccessStateKind.notAvailable:
      return 'Automatic M-Money SMS sync is available on Android only.';
    case AppAccessStateKind.serviceDisabled:
      return 'Automatic SMS sync is currently unavailable on this device.';
    case null:
      if (latest?.isFailed == true && latest?.errorMessage != null) {
        return latest!.errorMessage!;
      }
      return 'Checking SMS access and sync history.';
  }
}

String? _primaryLabelFor(
  AppAccessSnapshot? snapshot,
  MomoSmsSyncStatus status,
  BuildContext context,
) {
  switch (snapshot?.kind) {
    case AppAccessStateKind.ready:
      return 'Sync now';
    case AppAccessStateKind.disabledInApp:
    case AppAccessStateKind.needsSystemPermission:
      return 'Enable SMS';
    case AppAccessStateKind.blockedInSystem:
      return 'Open access';
    case AppAccessStateKind.notAvailable:
    case AppAccessStateKind.serviceDisabled:
    case null:
      return null;
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.isWorking,
    required this.primaryLabel,
    required this.onPrimaryTap,
    this.syncProgress = 0,
    this.secondaryLabel,
    this.onSecondaryTap,
  });

  final bool isWorking;
  final int syncProgress;
  final String? primaryLabel;
  final VoidCallback? onPrimaryTap;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    if (primaryLabel == null && secondaryLabel == null) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        if (secondaryLabel != null && onSecondaryTap != null)
          Expanded(
            child: CoolButton(
              label: secondaryLabel!,
              variant: CoolButtonVariant.secondary,
              onTap: onSecondaryTap!,
            ),
          ),
        if (secondaryLabel != null &&
            onSecondaryTap != null &&
            primaryLabel != null &&
            onPrimaryTap != null)
          const SizedBox(width: 10),
        if (primaryLabel != null && onPrimaryTap != null)
          Expanded(
            child: CoolButton(
              label: isWorking && syncProgress > 0
                  ? 'Scanning $syncProgress messages…'
                  : primaryLabel!,
              isLoading: isWorking,
              onTap: onPrimaryTap!,
            ),
          ),
      ],
    );
  }
}

class _SyncChip extends StatelessWidget {
  const _SyncChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CoolSpace.x3,
        vertical: CoolSpace.x2 - 1,
      ),
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong,
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.pill)),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: colors.secondaryText,
        ),
      ),
    );
  }
}
