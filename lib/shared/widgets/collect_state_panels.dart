import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/theme/collect_colors.dart';
import '../../app/theme/collect_icons.dart';
import '../../app/theme/collect_radius.dart';
import '../../app/theme/collect_shadows.dart';
import '../../app/theme/collect_spacing.dart';
import '../../app/theme/collect_typography.dart';
import 'collect_chrome.dart';
import 'collect_display_primitives.dart';
import 'collect_foundation.dart';
import 'collect_tone_icon.dart';

class MinimalStatePanel extends StatelessWidget {
  const MinimalStatePanel({
    required this.icon,
    required this.title,
    required this.message,
    this.tone = CollectStatusTone.info,
    this.primaryAction,
    this.secondaryAction,
    this.titleMaxLines = 1,
    this.messageMaxLines = 1,
    this.contentMaxWidth = 250,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final CollectStatusTone tone;
  final Widget? primaryAction;
  final Widget? secondaryAction;
  final int titleMaxLines;
  final int messageMaxLines;
  final double contentMaxWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final asset = _minimalStateAsset(icon, tone);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? colors.onImagePrimary : colors.surfaceReadable;
    final scrimBase = isDark
        ? CollectColors.referencePaymentsPurpleDeep
        : colors.textPrimary;
    Widget stateImage = Image.asset(
      asset,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) => DecoratedBox(
        decoration: BoxDecoration(gradient: colors.screenGradient),
      ),
    );
    if (isDark) {
      stateImage = ColorFiltered(
        colorFilter: ColorFilter.mode(
          scrimBase.withValues(alpha: 0.44),
          BlendMode.multiply,
        ),
        child: stateImage,
      );
    }
    return CollectCard(
      emphasis: CollectCardEmphasis.glow,
      accentColor: colors.statusForeground(tone),
      padding: EdgeInsets.zero,
      backgroundGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(
            colors.statusForeground(tone).withValues(alpha: 0.28),
            scrimBase,
          ),
          Color.alphaBlend(
            colors.periwinklePaint.withValues(alpha: 0.24),
            CollectColors.referencePaymentsPurple,
          ),
          CollectColors.referenceAssetNavy,
        ],
      ),
      child: Semantics(
        container: true,
        label: message.trim().isEmpty ? title : '$title, $message',
        child: ClipRRect(
          borderRadius: CollectRadius.cardLargeBorder,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 156),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FractionallySizedBox(
                      widthFactor: 0.48,
                      heightFactor: 1,
                      child: stateImage,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          scrimBase.withValues(alpha: isDark ? 0.98 : 0.98),
                          scrimBase.withValues(alpha: isDark ? 0.84 : 0.82),
                          scrimBase.withValues(alpha: isDark ? 0.26 : 0.20),
                        ],
                        stops: const [0, 0.56, 1],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: CollectSpacing.cardPaddingComfortable,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: contentMaxWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CollectToneIcon(icon: icon, tone: tone, large: true),
                        CollectSpacing.gap16,
                        Text(
                          title,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: foreground,
                                fontWeight: FontWeight.w900,
                              ),
                          maxLines: titleMaxLines,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (message.trim().isNotEmpty) ...[
                          CollectSpacing.gap8,
                          Text(
                            message,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: foreground.withValues(alpha: 0.76),
                                ),
                            maxLines: messageMaxLines,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (primaryAction != null ||
                            secondaryAction != null) ...[
                          CollectSpacing.gap20,
                          ?primaryAction,
                          if (secondaryAction != null) ...[
                            CollectSpacing.gap12,
                            secondaryAction!,
                          ],
                        ],
                      ],
                    ),
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

String _minimalStateAsset(IconData icon, CollectStatusTone tone) {
  if (icon == CollectIcons.qr ||
      icon == CollectIcons.public ||
      icon == CollectIcons.share ||
      icon == CollectIcons.search) {
    return 'assets/brand/generated/collect_visual_qr_share.png';
  }
  if (icon == CollectIcons.sms ||
      icon == CollectIcons.momo ||
      icon == CollectIcons.money ||
      icon == CollectIcons.shield ||
      tone == CollectStatusTone.warning ||
      tone == CollectStatusTone.danger) {
    return 'assets/brand/generated/collect_visual_momo_signal.png';
  }
  return 'assets/brand/generated/collect_visual_group_momentum.png';
}

class EmptySearchState extends StatelessWidget {
  const EmptySearchState({
    required this.title,
    required this.message,
    this.onClear,
    super.key,
  });

  final String title;
  final String message;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return MinimalStatePanel(
      icon: CollectIcons.search,
      title: title,
      message: message,
      tone: CollectStatusTone.neutral,
      primaryAction: onClear == null
          ? null
          : CollectButton(
              label: 'Clear search',
              icon: CollectIcons.sync,
              onPressed: onClear,
              expand: true,
            ),
    );
  }
}

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
    super.key,
  });

  final String title;
  final String message;
  final String meta;
  final CollectStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Padding(
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
  }
}

class CollectEmptyState extends StatelessWidget {
  const CollectEmptyState({
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
    return CollectGradientBackground(
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: CollectSpacing.screenPadding,
            child: CollectCard(
              emphasis: CollectCardEmphasis.flat,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CollectToneIcon(
                    icon: icon,
                    tone: CollectStatusTone.info,
                    large: true,
                  ),
                  CollectSpacing.gap16,
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  CollectSpacing.gap8,
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (action != null) ...[CollectSpacing.gap20, action!],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CollectErrorState extends StatelessWidget {
  const CollectErrorState({
    required this.title,
    required this.message,
    this.onRetry,
    super.key,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return CollectEmptyState(
      icon: CollectIcons.error,
      title: title,
      message: message,
      action: onRetry == null
          ? null
          : CollectButton(label: 'Try again', onPressed: onRetry),
    );
  }
}

class LoadingSkeleton extends StatelessWidget {
  const LoadingSkeleton({
    this.lines = 3,
    this.semanticsLabel = 'Loading content',
    this.showCard = true,
    super.key,
  });

  final int lines;
  final String semanticsLabel;
  final bool showCard;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final skeleton = Semantics(
      container: true,
      liveRegion: true,
      label: semanticsLabel,
      child: Column(
        children: [
          for (var index = 0; index < lines; index++) ...[
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.border.withValues(alpha: 0.42),
                borderRadius: CollectRadius.pillBorder,
              ),
              child: SizedBox(
                height: index == 0 ? 22 : 14,
                width: double.infinity,
              ),
            ),
            if (index != lines - 1) CollectSpacing.gap12,
          ],
        ],
      ),
    );
    if (!showCard) return skeleton;
    return CollectCard(child: skeleton);
  }
}

class LoadingStatePanel extends StatelessWidget {
  const LoadingStatePanel({
    required this.title,
    required this.message,
    this.icon = CollectIcons.sync,
    this.lines = 3,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;
  final int lines;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Loading: $title',
      child: CollectCard(
        emphasis: CollectCardEmphasis.flat,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CollectToneIcon(icon: icon, tone: CollectStatusTone.info),
                CollectSpacing.gapW12,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      CollectSpacing.gap4,
                      Text(
                        message,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            CollectSpacing.gap16,
            LoadingSkeleton(
              lines: lines,
              semanticsLabel: 'Loading placeholder for $title',
              showCard: false,
            ),
          ],
        ),
      ),
    );
  }
}

class CollectBottomSheet extends StatelessWidget {
  const CollectBottomSheet({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(CollectRadius.bottomSheet),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.glassPanel,
            border: Border.all(color: colors.glassBorder),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(CollectRadius.bottomSheet),
            ),
            boxShadow: CollectShadows.card(),
          ),
          child: Padding(
            padding: CollectSpacing.cardPaddingComfortable,
            child: child,
          ),
        ),
      ),
    );
  }
}

class InfoSecurityBanner extends StatelessWidget {
  const InfoSecurityBanner({
    required this.message,
    this.title = 'Safety note',
    this.tone = CollectStatusTone.info,
    super.key,
  });

  final String title;
  final String message;
  final CollectStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final visibleMessage = message.trim();
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
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
                if (visibleMessage.isNotEmpty) ...[
                  CollectSpacing.gap4,
                  Text(
                    visibleMessage,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
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
