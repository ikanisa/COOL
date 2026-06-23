import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

export '../../app/theme/collect_colors.dart';
export '../../app/theme/collect_icons.dart';
export '../../app/theme/collect_radius.dart';
export '../../app/theme/collect_spacing.dart';
export '../../app/theme/collect_typography.dart';
export 'collect_chrome.dart';
export 'collect_foundation.dart';
export 'collect_display_primitives.dart';
export 'collect_tone_icon.dart';
export 'collect_state_panels.dart';
export 'collect_action_controls.dart';
export 'collect_inputs.dart';
export 'collect_financial_components.dart';

import '../../app/theme/collect_colors.dart';
import '../../app/theme/collect_icons.dart';
import '../../app/theme/collect_radius.dart';
import '../../app/theme/collect_spacing.dart';
import '../../app/theme/collect_typography.dart';
import 'collect_foundation.dart';
import 'collect_tone_icon.dart';

class CollectVisualFeatureCard extends StatelessWidget {
  const CollectVisualFeatureCard({
    required this.asset,
    required this.title,
    required this.message,
    required this.icon,
    this.tone = CollectStatusTone.info,
    this.onTap,
    super.key,
  });

  final String asset;
  final String title;
  final String message;
  final IconData icon;
  final CollectStatusTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? colors.onImagePrimary : colors.textPrimary;
    final panelGradient = isDark
        ? LinearGradient(
            colors: [
              CollectColors.referencePaymentsPurpleDeep,
              Color.alphaBlend(
                colors.statusForeground(tone).withValues(alpha: 0.16),
                CollectColors.referencePaymentsPurple,
              ),
              CollectColors.referenceAssetNavy,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : LinearGradient(
            colors: [
              Color.alphaBlend(
                colors.statusForeground(tone).withValues(alpha: 0.14),
                colors.glassPanel,
              ),
              Color.alphaBlend(
                colors.mintPaint.withValues(alpha: 0.08),
                colors.glassPanel,
              ),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );
    Widget featureImage = Image.asset(
      asset,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      filterQuality: FilterQuality.high,
    );
    if (isDark) {
      featureImage = ColorFiltered(
        colorFilter: ColorFilter.mode(
          CollectColors.referencePaymentsPurpleDeep.withValues(alpha: 0.46),
          BlendMode.multiply,
        ),
        child: featureImage,
      );
    }
    return CollectCard(
      onTap: onTap,
      emphasis: CollectCardEmphasis.glow,
      accentColor: colors.statusForeground(tone),
      padding: EdgeInsets.zero,
      backgroundGradient: panelGradient,
      child: ClipRRect(
        borderRadius: CollectRadius.cardLargeBorder,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 132),
          child: Stack(
            children: [
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FractionallySizedBox(
                    widthFactor: 0.48,
                    heightFactor: 1,
                    child: featureImage,
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        (isDark
                                ? CollectColors.referencePaymentsPurpleDeep
                                : colors.glassPanel)
                            .withValues(alpha: isDark ? 0.98 : 0.98),
                        (isDark
                                ? CollectColors.referencePaymentsPurple
                                : colors.glassPanel)
                            .withValues(alpha: isDark ? 0.88 : 0.88),
                        (isDark
                                ? CollectColors.referenceAssetNavy
                                : colors.glassPanel)
                            .withValues(alpha: isDark ? 0.30 : 0.18),
                      ],
                      stops: const [0, 0.58, 1],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: CollectSpacing.cardPaddingComfortable,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 230),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CollectToneIcon(icon: icon, tone: tone),
                      CollectSpacing.gap16,
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w900,
                        ),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                      CollectSpacing.gap8,
                      Text(
                        message,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: foreground.withValues(alpha: 0.76),
                        ),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
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

class CollectListTile extends StatelessWidget {
  const CollectListTile({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    super.key,
  });

  final String title;
  final String? subtitle;
  final IconData? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final visibleSubtitle = _compactDataSubtitle(subtitle);
    return InkWell(
      borderRadius: CollectRadius.mdBorder,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CollectSpacing.x3),
        child: Row(
          children: [
            if (leading != null) ...[
              CollectToneIcon(icon: leading!, tone: CollectStatusTone.info),
              CollectSpacing.gapW12,
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (visibleSubtitle != null) ...[
                    CollectSpacing.gap4,
                    Text(
                      visibleSubtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null || onTap != null) ...[
              CollectSpacing.gapW12,
              trailing ?? Icon(CollectIcons.chevron, color: colors.textMuted),
            ],
          ],
        ),
      ),
    );
  }
}

String? _compactDataSubtitle(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return null;
  if (text.length > 28) return null;
  if (text.startsWith('#') ||
      text.startsWith('+') ||
      text.startsWith('RWF') ||
      text.contains('MoMo')) {
    return text;
  }
  return null;
}

class CollectBentoGrid extends StatelessWidget {
  const CollectBentoGrid({
    required this.primary,
    required this.top,
    required this.bottom,
    super.key,
  });

  final Widget primary;
  final Widget top;
  final Widget bottom;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final compact = constraints.maxWidth < 340 || textScale > 1.15;
        if (compact) {
          return Column(
            children: [
              primary,
              CollectSpacing.gap12,
              top,
              CollectSpacing.gap12,
              bottom,
            ],
          );
        }
        return SizedBox(
          height: 236,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 6, child: primary),
              CollectSpacing.gapW12,
              Expanded(
                flex: 5,
                child: Column(
                  children: [
                    Expanded(child: top),
                    CollectSpacing.gap12,
                    Expanded(child: bottom),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class BentoMetricCell extends StatelessWidget {
  const BentoMetricCell({
    required this.label,
    required this.value,
    this.detail,
    this.icon = CollectIcons.dashboard,
    this.tone = CollectStatusTone.info,
    this.emphasis = false,
    super.key,
  });

  final String label;
  final String value;
  final String? detail;
  final IconData icon;
  final CollectStatusTone tone;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return CollectCard(
      emphasis: emphasis ? CollectCardEmphasis.hero : CollectCardEmphasis.flat,
      padding: EdgeInsets.all(emphasis ? CollectSpacing.x4 : CollectSpacing.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              emphasis
                  ? CollectToneIcon(icon: icon, tone: tone)
                  : _BentoToneIcon(icon: icon, tone: tone),
              CollectSpacing.gapW8,
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: emphasis
                      ? CollectTypography.amountLarge(colors.textPrimary)
                      : Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                ),
              ),
              if (detail != null) ...[
                CollectSpacing.gap4,
                Text(
                  detail!,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _BentoToneIcon extends StatelessWidget {
  const _BentoToneIcon({required this.icon, required this.tone});

  final IconData icon;
  final CollectStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.statusBackground(tone),
        borderRadius: CollectRadius.pillBorder,
      ),
      child: SizedBox.square(
        dimension: 30,
        child: Icon(icon, color: colors.statusForeground(tone), size: 17),
      ),
    );
  }
}

class QuickActionButton extends StatelessWidget {
  const QuickActionButton({
    required this.icon,
    required this.label,
    this.detail,
    this.onTap,
    this.tone = CollectStatusTone.info,
    super.key,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final VoidCallback? onTap;
  final CollectStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      button: true,
      container: true,
      explicitChildNodes: true,
      label: detail == null ? label : '$label, $detail',
      child: Material(
        color: colors.glassControl,
        borderRadius: CollectRadius.cardBorder,
        child: InkWell(
          borderRadius: CollectRadius.cardBorder,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 128, minWidth: 124),
            child: Padding(
              padding: const EdgeInsets.all(CollectSpacing.x4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CollectToneIcon(icon: icon, tone: tone),
                  CollectSpacing.gap12,
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class QuickActionRail extends StatelessWidget {
  const QuickActionRail({
    required this.children,
    this.semanticLabel = 'Quick actions',
    super.key,
  });

  final List<Widget> children;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Semantics(
      container: true,
      label: semanticLabel,
      child: SizedBox(
        height: 152,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: EdgeInsets.zero,
          itemCount: children.length,
          separatorBuilder: (_, _) => CollectSpacing.gapW12,
          itemBuilder: (context, index) =>
              SizedBox(width: 142, child: children[index]),
        ),
      ),
    );
  }
}

class InsightCard extends StatelessWidget {
  const InsightCard({
    required this.title,
    required this.message,
    this.icon = CollectIcons.tips,
    this.tone = CollectStatusTone.info,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;
  final CollectStatusTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return CollectCard(
      emphasis: CollectCardEmphasis.flat,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CollectToneIcon(icon: icon, tone: tone),
          CollectSpacing.gapW12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (actionLabel != null) ...[
                  CollectSpacing.gap8,
                  CollectButton(
                    label: actionLabel!,
                    icon: CollectIcons.arrowForward,
                    onPressed: onAction,
                    variant: CollectButtonVariant.subtle,
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

class EmptyIllustrationState extends StatelessWidget {
  const EmptyIllustrationState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: '$title. $message',
      child: CollectCard(
        emphasis: CollectCardEmphasis.compact,
        padding: const EdgeInsets.symmetric(
          horizontal: CollectSpacing.x4,
          vertical: CollectSpacing.x3,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CollectToneIcon(icon: icon, tone: CollectStatusTone.info),
                CollectSpacing.gapW12,
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (action != null) ...[
              CollectSpacing.gap12,
              SizedBox(width: double.infinity, child: action!),
            ],
          ],
        ),
      ),
    );
  }
}

class PremiumSegmentedFilter<T> extends StatelessWidget {
  const PremiumSegmentedFilter({
    required this.values,
    required this.selected,
    required this.labelFor,
    required this.onChanged,
    super.key,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelFor;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      container: true,
      label: 'Filter options',
      child: Scrollbar(
        thumbVisibility: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: SegmentedButton<T>(
              showSelectedIcon: false,
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return colors.actionColor.withValues(alpha: 0.12);
                  }
                  return colors.surfaceRaised;
                }),
              ),
              segments: [
                for (final value in values)
                  ButtonSegment<T>(
                    value: value,
                    label: Text(
                      labelFor(value),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              selected: {selected},
              onSelectionChanged: (value) => onChanged(value.first),
            ),
          ),
        ),
      ),
    );
  }
}

void copyToClipboard(BuildContext context, String text, {String? message}) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message ?? 'Copied securely.')));
}
