part of 'collect_state_panels.dart';

class CollectWizardProgress extends StatelessWidget {
  const CollectWizardProgress({
    required this.labels,
    required this.currentStep,
    super.key,
  });

  final List<String> labels;
  final int currentStep;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();
    final safeStep = currentStep.clamp(0, labels.length - 1).toInt();
    return Semantics(
      container: true,
      label: 'Step ${safeStep + 1} of ${labels.length}: ${labels[safeStep]}',
      child: CollectCard(
        emphasis: CollectCardEmphasis.compact,
        child: Wrap(
          spacing: CollectSpacing.x2,
          runSpacing: CollectSpacing.x2,
          children: [
            for (var index = 0; index < labels.length; index += 1)
              CollectStatusChip(
                label: labels[index],
                icon: index < currentStep
                    ? CollectIcons.check
                    : index == currentStep
                    ? CollectIcons.pending
                    : CollectIcons.info,
                tone: index < currentStep
                    ? CollectStatusTone.success
                    : index == currentStep
                    ? CollectStatusTone.info
                    : CollectStatusTone.neutral,
              ),
          ],
        ),
      ),
    );
  }
}

class FormSectionCard extends StatelessWidget {
  const FormSectionCard({
    required this.children,
    this.title,
    this.message,
    this.errorTitle,
    this.errorMessage,
    this.actions = const [],
    super.key,
  });

  final String? title;
  final String? message;
  final String? errorTitle;
  final String? errorMessage;
  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return CollectCard(
      padding: CollectSpacing.cardPaddingComfortable,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title!, style: Theme.of(context).textTheme.titleLarge),
            if (message != null) ...[
              CollectSpacing.gap4,
              Text(message!, style: Theme.of(context).textTheme.bodyMedium),
            ],
            if (children.isNotEmpty) CollectSpacing.gap16,
          ],
          for (var index = 0; index < children.length; index += 1) ...[
            children[index],
            if (index != children.length - 1) CollectSpacing.gap12,
          ],
          if (errorMessage != null) ...[
            CollectSpacing.gap12,
            InfoSecurityBanner(
              title: errorTitle ?? 'Action failed',
              message: errorMessage!,
              tone: CollectStatusTone.danger,
            ),
          ],
          if (actions.isNotEmpty) ...[
            CollectSpacing.gap16,
            for (var index = 0; index < actions.length; index += 1) ...[
              actions[index],
              if (index != actions.length - 1) CollectSpacing.gap12,
            ],
          ],
        ],
      ),
    );
  }
}

class CollectPermissionRecoveryPanel extends StatelessWidget {
  const CollectPermissionRecoveryPanel({
    required this.icon,
    required this.title,
    required this.message,
    required this.settingsMessage,
    this.tone = CollectStatusTone.warning,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final String settingsMessage;
  final CollectStatusTone tone;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        MinimalStatePanel(
          icon: icon,
          title: title,
          message: message,
          tone: tone,
        ),
        InfoSecurityBanner(
          title: 'Settings recovery',
          message: settingsMessage,
          tone: CollectStatusTone.info,
        ),
      ],
    );
  }
}

class NotificationUpdateRow extends StatelessWidget {
  const NotificationUpdateRow({
    required this.title,
    required this.message,
    required this.meta,
    this.tone = CollectStatusTone.info,
    this.onTap,
    super.key,
  });

  final String title;
  final String message;
  final String meta;
  final CollectStatusTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: CollectSpacing.x3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CollectToneIcon(icon: collectStatusIcon(tone, null), tone: tone),
          CollectSpacing.gapW12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
                CollectSpacing.gap4,
                Text(
                  message,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
                CollectSpacing.gap4,
                Text(
                  meta,
                  style: CollectTypography.transactionMeta(colors.textMuted),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return Semantics(
      button: true,
      label: 'Mark $title as read',
      child: InkWell(
        borderRadius: CollectRadius.mdBorder,
        onTap: onTap,
        child: row,
      ),
    );
  }
}

class InfoSecurityBanner extends StatelessWidget {
  const InfoSecurityBanner({
    required this.message,
    this.title = 'Safety note',
    this.tone = CollectStatusTone.info,
    this.titleMaxLines = 2,
    this.messageMaxLines = 3,
    super.key,
  });

  final String title;
  final String message;
  final CollectStatusTone tone;
  final int titleMaxLines;
  final int messageMaxLines;

  @override
  Widget build(BuildContext context) {
    final visibleMessage = message.trim();
    final usesAccessibilityText =
        MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    return CollectCard(
      emphasis: CollectCardEmphasis.flat,
      padding: const EdgeInsets.symmetric(
        horizontal: CollectSpacing.x3,
        vertical: CollectSpacing.x2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CollectToneIcon(icon: collectStatusIcon(tone, null), tone: tone),
          CollectSpacing.gapW12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: usesAccessibilityText ? null : titleMaxLines,
                  softWrap: true,
                  overflow: TextOverflow.clip,
                ),
                if (visibleMessage.isNotEmpty) ...[
                  CollectSpacing.gap4,
                  Text(
                    visibleMessage,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: usesAccessibilityText ? null : messageMaxLines,
                    softWrap: true,
                    overflow: TextOverflow.clip,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CollectConnectivityBanner extends StatelessWidget {
  const CollectConnectivityBanner({required this.status, super.key});

  final ConnectivityStatus status;

  @override
  Widget build(BuildContext context) {
    final details = _ConnectivityBannerDetails.fromStatus(status);
    if (details == null) return const SizedBox.shrink();
    final colors = context.collectColors;
    final usesAccessibilityText =
        MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    return Semantics(
      container: true,
      liveRegion: true,
      label: details.semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.statusBackground(details.tone),
          borderRadius: CollectRadius.pillBorder,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CollectSpacing.x3,
            vertical: CollectSpacing.x2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                details.icon,
                color: colors.statusForeground(details.tone),
                size: 18,
              ),
              CollectSpacing.gapW8,
              Flexible(
                child: Text(
                  details.label,
                  maxLines: usesAccessibilityText ? 2 : 1,
                  softWrap: usesAccessibilityText,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.statusForeground(details.tone),
                    fontWeight: CollectTypography.weightBold,
                    letterSpacing: CollectTypography.trackingDefault,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectivityBannerDetails {
  const _ConnectivityBannerDetails({
    required this.label,
    required this.semanticLabel,
    required this.icon,
    required this.tone,
  });

  final String label;
  final String semanticLabel;
  final IconData icon;
  final CollectStatusTone tone;

  static _ConnectivityBannerDetails? fromStatus(ConnectivityStatus status) {
    return switch (status) {
      ConnectivityStatus.online => null,
      ConnectivityStatus.degraded => const _ConnectivityBannerDetails(
        label: 'Connection needs attention',
        semanticLabel: 'Connection needs attention',
        icon: CollectIcons.pending,
        tone: CollectStatusTone.warning,
      ),
      ConnectivityStatus.offline => const _ConnectivityBannerDetails(
        label: 'No connection',
        semanticLabel: 'No connection',
        icon: CollectIcons.sync,
        tone: CollectStatusTone.danger,
      ),
      ConnectivityStatus.offlineStale => const _ConnectivityBannerDetails(
        label: 'Showing saved data',
        semanticLabel: 'Offline. Showing saved data.',
        icon: CollectIcons.sync,
        tone: CollectStatusTone.warning,
      ),
    };
  }
}
