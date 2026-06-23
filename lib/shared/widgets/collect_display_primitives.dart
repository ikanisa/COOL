import 'package:flutter/material.dart';

import '../../app/theme/collect_colors.dart';
import '../../app/theme/collect_icons.dart';
import '../../app/theme/collect_radius.dart';
import '../../app/theme/collect_spacing.dart';
import '../../app/theme/collect_typography.dart';
import 'collect_chrome.dart';
import 'collect_foundation.dart';
import 'collect_tone_icon.dart';

class CollectIdDisplay extends StatelessWidget {
  const CollectIdDisplay({
    required this.publicId,
    this.label = 'Collect ID',
    this.onCopy,
    super.key,
  });

  final String publicId;
  final String label;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final value = publicId.trim().isEmpty ? '------' : publicId.trim();
    return CollectCard(
      emphasis: CollectCardEmphasis.hero,
      padding: CollectSpacing.cardPaddingComfortable,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: CollectTypography.eyebrowLabel(colors.textMuted),
                ),
                CollectSpacing.gap8,
                SelectableText(
                  value,
                  style: CollectTypography.collectIdDisplay(colors.textPrimary),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Copy Collect ID',
            onPressed: onCopy,
            icon: const Icon(CollectIcons.copy),
          ),
        ],
      ),
    );
  }
}

class CollectStatusChip extends StatelessWidget {
  const CollectStatusChip({
    required this.label,
    this.tone = CollectStatusTone.neutral,
    this.icon,
    super.key,
  });

  final String label;
  final CollectStatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = colors.statusForeground(tone);
    return Semantics(
      label: 'Status: $label',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.statusBackground(tone),
            borderRadius: CollectRadius.pillBorder,
            border: Border.all(color: foreground.withValues(alpha: 0.22)),
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
                  collectStatusIcon(tone, icon),
                  size: 15,
                  color: foreground,
                ),
                CollectSpacing.gapW8,
                Flexible(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CollectAvatar extends StatelessWidget {
  const CollectAvatar({
    required this.label,
    this.imageUrl,
    this.size = 40,
    super.key,
  });

  final String label;
  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: colors.statusBackground(CollectStatusTone.privacy),
      foregroundColor: colors.periwinklePaint,
      backgroundImage: hasImage ? NetworkImage(imageUrl!) : null,
      child: hasImage
          ? null
          : ClipOval(
              child: Image.asset(
                CollectBrandMark.appIconAssetPath,
                width: (size * 0.72).clamp(24, 42).toDouble(),
                height: (size * 0.72).clamp(24, 42).toDouble(),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                errorBuilder: (context, error, stackTrace) => Icon(
                  CollectIcons.people,
                  color: colors.periwinklePaint,
                  size: (size * 0.68).clamp(22, 38).toDouble(),
                ),
              ),
            ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    const foreground = CollectColors.brandPaper;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: foreground,
              padding: const EdgeInsets.symmetric(
                horizontal: CollectSpacing.x2,
                vertical: CollectSpacing.x1,
              ),
              textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            child: Text(
              actionLabel!,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}
