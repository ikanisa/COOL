part of '../screens/manage_ai_content_screen.dart';

EdgeInsets _aiGenerationCardPadding() =>
    CoolSpace.pagePadding.copyWith(top: 0, bottom: 0);

const BorderRadius _aiContentHeroRadius = BorderRadius.all(
  Radius.circular(CoolRadii.md),
);
const BorderRadius _aiContentChipRadius = BorderRadius.all(
  Radius.circular(CoolRadii.pill),
);
EdgeInsets _aiContentStatusChipPadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x3,
  right: CoolSpace.x3,
  top: CoolSpace.x1,
  bottom: CoolSpace.x1,
);

EdgeInsets _aiContentInactiveChipPadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x2,
  right: CoolSpace.x2,
  top: CoolSpace.x1,
  bottom: CoolSpace.x1,
);

Color _aiContentStatusTone(BuildContext context, AiContentStatus status) {
  final colors = context.coolSemanticColors;
  switch (status) {
    case AiContentStatus.draft:
      return colors.neutral;
    case AiContentStatus.pendingReview:
      return colors.warning;
    case AiContentStatus.approved:
      return colors.success;
    case AiContentStatus.rejected:
      return colors.danger;
  }
}

class _GenerationControlsCard extends StatefulWidget {
  const _GenerationControlsCard({
    required this.isEnabled,
    required this.intervalHours,
    required this.lastGeneratedAt,
    required this.onToggle,
    required this.onGenerateNow,
  });

  final bool isEnabled;
  final int? intervalHours;
  final DateTime? lastGeneratedAt;
  final ValueChanged<bool> onToggle;
  final Future<void> Function() onGenerateNow;

  @override
  State<_GenerationControlsCard> createState() =>
      _GenerationControlsCardState();
}

class _GenerationControlsCardState extends State<_GenerationControlsCard> {
  bool _isGenerating = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final lastGen = widget.lastGeneratedAt;
    final lastLabel = lastGen != null
        ? '${lastGen.day}/${lastGen.month}/${lastGen.year} ${lastGen.hour}:${lastGen.minute.toString().padLeft(2, '0')}'
        : 'Never';

    return Padding(
      padding: _aiGenerationCardPadding(),
      child: CoolCard(
        backgroundColor: colors.analyticsSurface,
        useGradient: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.accent.withValues(alpha: 0.12),
                    borderRadius: _aiContentHeroRadius,
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: 20,
                    color: colors.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Auto Generation',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colors.primaryText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.isEnabled
                            ? '1 item every ${widget.intervalHours ?? 12}h'
                            : 'Generation paused',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.tertiaryText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: widget.isEnabled,
                  activeTrackColor: colors.accent,
                  onChanged: widget.onToggle,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Last run: $lastLabel',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.tertiaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            CoolButton(
              label: 'Generate Now',
              onTap: _isGenerating
                  ? null
                  : () async {
                      setState(() => _isGenerating = true);
                      try {
                        await widget.onGenerateNow();
                      } finally {
                        if (mounted) {
                          setState(() => _isGenerating = false);
                        }
                      }
                    },
              isLoading: _isGenerating,
              variant: CoolButtonVariant.secondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _AiContentCard extends StatelessWidget {
  const _AiContentCard({
    required this.item,
    required this.onEdit,
    this.onApprove,
    this.onReject,
    this.onToggle,
    this.onDelete,
  });

  final NexusRecommendation item;
  final VoidCallback onEdit;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback? onToggle;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final statusTone = _aiContentStatusTone(context, item.status);
    return CoolCard(
      onTap: onEdit,
      backgroundColor: colors.operationalSurface,
      useGradient: false,
      semanticsLabel: 'Edit ${item.title}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: _aiContentStatusChipPadding(),
                decoration: BoxDecoration(
                  color: statusTone.withValues(alpha: 0.15),
                  borderRadius: _aiContentChipRadius,
                ),
                child: Text(
                  item.status.label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: statusTone,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: _aiContentStatusChipPadding(),
                decoration: BoxDecoration(
                  color: colors.chipBackground,
                  borderRadius: _aiContentChipRadius,
                  border: Border.all(color: colors.border),
                ),
                child: Text(
                  item.contentType.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colors.tertiaryText,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const Spacer(),
              if (!item.isActive && item.status == AiContentStatus.approved)
                Container(
                  padding: _aiContentInactiveChipPadding(),
                  decoration: BoxDecoration(
                    color: colors.danger.withValues(alpha: 0.12),
                    borderRadius: _aiContentChipRadius,
                  ),
                  child: Text(
                    'INACTIVE',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: colors.danger,
                    ),
                  ),
                ),
              PopupMenuButton<String>(
                tooltip: 'Content actions',
                icon: Icon(
                  Icons.more_vert_rounded,
                  size: 20,
                  color: colors.tertiaryText,
                ),
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      onEdit();
                    case 'toggle':
                      onToggle?.call();
                    case 'delete':
                      onDelete?.call();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Text(context.l10n.editChildTextedit),
                  ),
                  if (onToggle != null)
                    PopupMenuItem(
                      value: 'toggle',
                      child: Text(item.isActive ? 'Deactivate' : 'Activate'),
                    ),
                  if (onDelete != null)
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        'Delete',
                        style: TextStyle(color: colors.danger),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                item.iconEmoji,
                style: theme.textTheme.headlineSmall?.copyWith(height: 1),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colors.primaryText,
                  ),
                ),
              ),
            ],
          ),
          if (item.subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              item.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.secondaryText,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (onApprove != null || onReject != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                if (onApprove != null)
                  Expanded(
                    child: _ActionButton(
                      label: 'Approve',
                      icon: Icons.check_circle_rounded,
                      foregroundColor: colors.accentForeground,
                      backgroundColor: colors.accent,
                      borderColor: colors.accent,
                      onTap: onApprove!,
                    ),
                  ),
                if (onApprove != null && onReject != null)
                  const SizedBox(width: 10),
                if (onReject != null)
                  Expanded(
                    child: _ActionButton(
                      label: 'Reject',
                      icon: Icons.cancel_rounded,
                      foregroundColor: colors.danger,
                      backgroundColor: colors.cardSurfaceStrong,
                      borderColor: colors.danger.withValues(alpha: 0.45),
                      onTap: onReject!,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.foregroundColor,
    required this.backgroundColor,
    required this.borderColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color foregroundColor;
  final Color backgroundColor;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: CoolTapTargets.comfortable),
      child: FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        style: FilledButton.styleFrom(
          foregroundColor: foregroundColor,
          backgroundColor: backgroundColor,
          side: BorderSide(color: borderColor),
          shape: const RoundedRectangleBorder(
            borderRadius: _aiContentHeroRadius,
          ),
        ),
      ),
    );
  }
}
