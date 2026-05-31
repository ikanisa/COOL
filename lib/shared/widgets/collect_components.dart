import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

export '../../app/theme/collect_colors.dart';
export '../../app/theme/collect_icons.dart';
export '../../app/theme/collect_spacing.dart';
export '../../app/theme/collect_typography.dart';

import '../../app/theme/collect_colors.dart';
import '../../app/theme/collect_component_tokens.dart';
import '../../app/theme/collect_icons.dart';
import '../../app/theme/collect_motion.dart';
import '../../app/theme/collect_radius.dart';
import '../../app/theme/collect_shadows.dart';
import '../../app/theme/collect_spacing.dart';
import '../../app/theme/collect_typography.dart';
import '../../core/utils/money_format.dart';
import '../models/collect_models.dart';

class CollectButton extends StatelessWidget {
  const CollectButton({
    required this.label,
    this.icon,
    this.onPressed,
    this.variant = CollectButtonVariant.primary,
    this.expand = false,
    super.key,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final CollectButtonVariant variant;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final style = switch (variant) {
      CollectButtonVariant.primary => CollectComponentTokens.filledButton(
        context,
      ),
      CollectButtonVariant.secondary => CollectComponentTokens.outlinedButton(
        context,
      ),
      CollectButtonVariant.subtle => TextButton.styleFrom(
        minimumSize: const Size(CollectSpacing.target, CollectSpacing.target),
        foregroundColor: colors.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: CollectRadius.mdBorder),
      ),
      CollectButtonVariant.danger => CollectComponentTokens.filledButton(
        context,
      ).copyWith(backgroundColor: WidgetStatePropertyAll(colors.danger)),
    };
    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon),
              CollectSpacing.gapW8,
              Flexible(child: Text(label)),
            ],
          );
    final button = switch (variant) {
      CollectButtonVariant.primary || CollectButtonVariant.danger =>
        FilledButton(onPressed: onPressed, style: style, child: child),
      CollectButtonVariant.secondary => OutlinedButton(
        onPressed: onPressed,
        style: style,
        child: child,
      ),
      CollectButtonVariant.subtle => TextButton(
        onPressed: onPressed,
        style: style,
        child: child,
      ),
    };
    if (!expand) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}

enum CollectButtonVariant { primary, secondary, subtle, danger }

class CollectCard extends StatelessWidget {
  const CollectCard({
    required this.child,
    this.onTap,
    this.padding = CollectSpacing.cardPadding,
    this.emphasis = CollectCardEmphasis.normal,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final CollectCardEmphasis emphasis;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = emphasis == CollectCardEmphasis.hero
        ? CollectRadius.cardLargeBorder
        : CollectRadius.cardBorder;
    final decorated = AnimatedContainer(
      duration: CollectMotion.duration(context, CollectMotion.fast),
      curve: CollectMotion.standard,
      decoration: BoxDecoration(
        color: emphasis == CollectCardEmphasis.flat
            ? colors.surface
            : colors.surfaceMuted,
        borderRadius: radius,
        border: emphasis == CollectCardEmphasis.flat
            ? null
            : Border.all(color: colors.border),
        boxShadow: emphasis == CollectCardEmphasis.flat
            ? const []
            : CollectShadows.card(isDark),
      ),
      child: Padding(padding: padding, child: child),
    );
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: onTap == null
          ? decorated
          : InkWell(borderRadius: radius, onTap: onTap, child: decorated),
    );
  }
}

enum CollectCardEmphasis { flat, normal, hero }

class MoneyCard extends StatelessWidget {
  const MoneyCard({
    required this.label,
    required this.amount,
    this.detail,
    this.icon = CollectIcons.money,
    this.tone = CollectStatusTone.info,
    super.key,
  });

  final String label;
  final int amount;
  final String? detail;
  final IconData icon;
  final CollectStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return CollectCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ToneIcon(icon: icon, tone: tone),
              CollectSpacing.gapW12,
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          CollectSpacing.gap12,
          Text(
            formatRwf(amount),
            style: CollectTypography.amountLarge(colors.textPrimary),
          ),
          if (detail != null) ...[
            CollectSpacing.gap4,
            Text(detail!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class AmountHero extends StatelessWidget {
  const AmountHero({
    required this.amount,
    required this.label,
    this.detail,
    super.key,
  });

  final int amount;
  final String label;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        CollectSpacing.gap8,
        Text(
          formatRwf(amount),
          style: CollectTypography.amountHero(colors.textPrimary),
        ),
        if (detail != null) ...[
          CollectSpacing.gap8,
          Text(detail!, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ],
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
                Icon(_statusIcon(tone, icon), size: 15, color: foreground),
                CollectSpacing.gapW8,
                Flexible(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w800,
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

class CollectProgressBar extends StatelessWidget {
  const CollectProgressBar({required this.value, this.label, super.key});

  final double value;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: CollectRadius.pillBorder,
          child: LinearProgressIndicator(
            minHeight: CollectSpacing.x2,
            value: clamped,
          ),
        ),
        if (label != null) ...[
          CollectSpacing.gap8,
          Text(label!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
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
    final initial = label.trim().isEmpty ? 'C' : label.trim()[0].toUpperCase();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: colors.statusBackground(CollectStatusTone.privacy),
      foregroundColor: colors.purple,
      backgroundImage: imageUrl == null || imageUrl!.isEmpty
          ? null
          : NetworkImage(imageUrl!),
      child: imageUrl == null || imageUrl!.isEmpty
          ? Text(initial, style: Theme.of(context).textTheme.labelLarge)
          : null,
    );
  }
}

class CollectAvatarStack extends StatelessWidget {
  const CollectAvatarStack({required this.labels, super.key});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final visible = labels.take(3).toList();
    return SizedBox(
      width: 24.0 + (visible.length * 24.0),
      height: 40,
      child: Stack(
        children: [
          for (var index = 0; index < visible.length; index++)
            Positioned(
              left: index * 22.0,
              child: CollectAvatar(label: visible[index], size: 36),
            ),
        ],
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
    return InkWell(
      borderRadius: CollectRadius.mdBorder,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CollectSpacing.x3),
        child: Row(
          children: [
            if (leading != null) ...[
              _ToneIcon(icon: leading!, tone: CollectStatusTone.info),
              CollectSpacing.gapW12,
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  if (subtitle != null) ...[
                    CollectSpacing.gap4,
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            trailing ?? Icon(CollectIcons.chevron, color: colors.textMuted),
          ],
        ),
      ),
    );
  }
}

class ActivityRow extends StatelessWidget {
  const ActivityRow({
    required this.title,
    required this.amount,
    required this.meta,
    this.tone = CollectStatusTone.success,
    this.transactionId,
    super.key,
  });

  final String title;
  final int amount;
  final String meta;
  final CollectStatusTone tone;
  final String? transactionId;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return CollectCard(
      emphasis: CollectCardEmphasis.flat,
      child: Row(
        children: [
          _ToneIcon(icon: CollectIcons.money, tone: tone),
          CollectSpacing.gapW12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                CollectSpacing.gap4,
                Text(meta, style: Theme.of(context).textTheme.bodySmall),
                if (transactionId != null) ...[
                  CollectSpacing.gap4,
                  Text(
                    transactionId!,
                    style: CollectTypography.mono(colors.textMuted),
                  ),
                ],
              ],
            ),
          ),
          Text(
            formatRwf(amount),
            style: CollectTypography.amountCompact(colors.textPrimary),
          ),
        ],
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
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (actionLabel != null)
          CollectButton(
            label: actionLabel!,
            onPressed: onAction,
            variant: CollectButtonVariant.subtle,
          ),
      ],
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
    return SafeArea(
      child: Center(
        child: Padding(
          padding: CollectSpacing.screenPadding,
          child: CollectCard(
            emphasis: CollectCardEmphasis.flat,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ToneIcon(
                  icon: icon,
                  tone: CollectStatusTone.info,
                  large: true,
                ),
                CollectSpacing.gap16,
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                CollectSpacing.gap8,
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                if (action != null) ...[CollectSpacing.gap20, action!],
              ],
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
  const LoadingSkeleton({this.lines = 3, super.key});

  final int lines;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return CollectCard(
      child: Column(
        children: [
          for (var index = 0; index < lines; index++) ...[
            Container(
              height: index == 0 ? 22 : 14,
              width: double.infinity,
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                borderRadius: CollectRadius.pillBorder,
              ),
            ),
            if (index != lines - 1) CollectSpacing.gap12,
          ],
        ],
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(CollectRadius.bottomSheet),
        ),
      ),
      child: Padding(
        padding: CollectSpacing.cardPaddingComfortable,
        child: child,
      ),
    );
  }
}

class CollectSearchField extends StatelessWidget {
  const CollectSearchField({
    required this.controller,
    required this.label,
    super.key,
  });

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: CollectComponentTokens.inputDecoration(
        context: context,
        label: label,
      ).copyWith(prefixIcon: const Icon(CollectIcons.search)),
    );
  }
}

class CollectFilterBar extends StatelessWidget {
  const CollectFilterBar({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: CollectSpacing.x2,
      runSpacing: CollectSpacing.x2,
      children: children,
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
    return CollectCard(
      emphasis: CollectCardEmphasis.flat,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ToneIcon(icon: _statusIcon(tone, null), tone: tone),
          CollectSpacing.gapW12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                CollectSpacing.gap4,
                Text(message, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PaymentIntentStatusCard extends StatelessWidget {
  const PaymentIntentStatusCard({
    required this.amountRwf,
    required this.receiverLabel,
    required this.receiverMomoNumber,
    required this.memberLabel,
    required this.network,
    required this.status,
    super.key,
  });

  final int amountRwf;
  final String receiverLabel;
  final String receiverMomoNumber;
  final String memberLabel;
  final String network;
  final String status;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return CollectCard(
      emphasis: CollectCardEmphasis.hero,
      padding: CollectSpacing.cardPaddingComfortable,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AmountHero(
            amount: amountRwf,
            label: 'Payment intent',
            detail: 'MoMo dialer opened. Collect waits for SMS confirmation.',
          ),
          CollectSpacing.gap20,
          Wrap(
            spacing: CollectSpacing.x2,
            runSpacing: CollectSpacing.x2,
            children: [
              CollectStatusChip(
                label: paymentStatusLabel(status),
                tone: paymentStatusTone(status),
              ),
              CollectStatusChip(
                label: memberLabel,
                tone: CollectStatusTone.warning,
              ),
              CollectStatusChip(
                label: network,
                tone: CollectStatusTone.neutral,
              ),
            ],
          ),
          CollectSpacing.gap20,
          Text(receiverLabel, style: Theme.of(context).textTheme.labelLarge),
          CollectSpacing.gap4,
          SelectableText(
            receiverMomoNumber,
            style: CollectTypography.amountLarge(colors.textPrimary),
          ),
          CollectSpacing.gap16,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _ToneIcon(
                icon: CollectIcons.lock,
                tone: CollectStatusTone.privacy,
              ),
              CollectSpacing.gapW12,
              Expanded(
                child: Text(
                  'Complete the MoMo PIN flow outside Collect. Do not paste SMS or payment references; Collect allocates from the receiver MoMo SMS automatically.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class QRCard extends StatelessWidget {
  const QRCard({
    required this.link,
    required this.caption,
    this.onCopy,
    super.key,
  });

  final String link;
  final String caption;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return CollectCard(
      child: Column(
        children: [
          Semantics(
            label: 'QR code for group link',
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceRaised,
                borderRadius: CollectRadius.cardBorder,
              ),
              child: Padding(
                padding: const EdgeInsets.all(CollectSpacing.x3),
                child: QrImageView(data: link, size: 208),
              ),
            ),
          ),
          CollectSpacing.gap16,
          Text(caption, style: Theme.of(context).textTheme.bodyMedium),
          CollectSpacing.gap8,
          SelectableText(
            link,
            style: CollectTypography.mono(colors.textPrimary),
          ),
          CollectSpacing.gap16,
          CollectButton(
            label: 'Copy group share text',
            icon: CollectIcons.copy,
            onPressed: onCopy,
            expand: true,
          ),
        ],
      ),
    );
  }
}

class LedgerRow extends StatelessWidget {
  LedgerRow.confirmed({required Contribution contribution, super.key})
    : title = contribution.supporterLabel,
      amountRwf = contribution.amountRwf,
      meta = 'Confirmed contribution',
      transactionId = contribution.transactionId,
      tone = CollectStatusTone.success,
      action = null;

  LedgerRow.review({
    required ParsedPaymentEvent event,
    required this.action,
    super.key,
  }) : title = 'Needs review',
       amountRwf = event.amountRwf,
       meta =
           'Confidence ${(event.confidence * 100).round()}% · ${event.senderLabel}',
       transactionId = event.transactionId,
       tone = CollectStatusTone.warning;

  final String title;
  final int amountRwf;
  final String meta;
  final String? transactionId;
  final CollectStatusTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return CollectCard(
      emphasis: CollectCardEmphasis.flat,
      child: Column(
        children: [
          ActivityFeedItem(
            title: title,
            amount: amountRwf,
            meta: meta,
            transactionId: transactionId,
            tone: tone,
          ),
          if (action != null) ...[CollectSpacing.gap12, action!],
        ],
      ),
    );
  }
}

class ReceiverConsentCard extends StatelessWidget {
  const ReceiverConsentCard({
    required this.flagsEnabled,
    required this.consented,
    required this.isSyncing,
    required this.onConsentChanged,
    required this.onSync,
    super.key,
  });

  final bool flagsEnabled;
  final bool consented;
  final bool isSyncing;
  final ValueChanged<bool>? onConsentChanged;
  final VoidCallback? onSync;

  @override
  Widget build(BuildContext context) {
    return CollectCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: CollectSpacing.x2,
            runSpacing: CollectSpacing.x2,
            children: [
              CollectStatusChip(
                label: flagsEnabled ? 'Internal SMS flags on' : 'SMS flags off',
                tone: flagsEnabled
                    ? CollectStatusTone.success
                    : CollectStatusTone.neutral,
              ),
              CollectStatusChip(
                label: consented ? 'Consent active' : 'Consent required',
                tone: consented
                    ? CollectStatusTone.success
                    : CollectStatusTone.warning,
              ),
            ],
          ),
          CollectSpacing.gap16,
          const InfoSecurityBanner(
            title: 'Receiver consent',
            message:
                'Collect can monitor approved receiver notifications only after explicit consent. Raw SMS is never public and is stored securely for audit only.',
            tone: CollectStatusTone.privacy,
          ),
          CollectSpacing.gap16,
          Material(
            color: Colors.transparent,
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: consented,
              onChanged: flagsEnabled ? onConsentChanged : null,
              title: const Text('Enable SMS app access'),
              subtitle: const Text(
                'Approved Android build and consent required.',
              ),
            ),
          ),
          CollectSpacing.gap12,
          CollectButton(
            label: isSyncing ? 'Syncing...' : 'Sync consented SMS',
            icon: CollectIcons.sync,
            onPressed: flagsEnabled && consented && !isSyncing ? onSync : null,
            variant: CollectButtonVariant.secondary,
            expand: true,
          ),
        ],
      ),
    );
  }
}

class AdminReviewCard extends StatelessWidget {
  const AdminReviewCard({
    required this.title,
    required this.status,
    required this.detail,
    this.amountRwf,
    this.confidence,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    super.key,
  });

  final String title;
  final String status;
  final String detail;
  final int? amountRwf;
  final double? confidence;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return CollectCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              CollectStatusChip(
                label: status.replaceAll('_', ' '),
                tone: statusToneFromText(status),
              ),
            ],
          ),
          CollectSpacing.gap8,
          Text(detail, style: Theme.of(context).textTheme.bodyMedium),
          if (amountRwf != null || confidence != null) ...[
            CollectSpacing.gap12,
            Wrap(
              spacing: CollectSpacing.x2,
              runSpacing: CollectSpacing.x2,
              children: [
                if (amountRwf != null)
                  Text(
                    formatRwf(amountRwf!),
                    style: CollectTypography.amountCompact(colors.textPrimary),
                  ),
                if (confidence != null)
                  CollectStatusChip(
                    label: 'Confidence ${(confidence! * 100).round()}%',
                    tone: confidence! >= 0.85
                        ? CollectStatusTone.success
                        : CollectStatusTone.warning,
                  ),
              ],
            ),
          ],
          if (primaryLabel != null || secondaryLabel != null) ...[
            CollectSpacing.gap16,
            Wrap(
              spacing: CollectSpacing.x2,
              runSpacing: CollectSpacing.x2,
              children: [
                if (primaryLabel != null)
                  CollectButton(label: primaryLabel!, onPressed: onPrimary),
                if (secondaryLabel != null)
                  CollectButton(
                    label: secondaryLabel!,
                    onPressed: onSecondary,
                    variant: CollectButtonVariant.secondary,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class MoneyHeroCard extends StatelessWidget {
  const MoneyHeroCard({
    required this.amount,
    required this.label,
    this.detail,
    this.primaryAction,
    this.secondaryAction,
    this.chips = const [],
    super.key,
  });

  final int amount;
  final String label;
  final String? detail;
  final Widget? primaryAction;
  final Widget? secondaryAction;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final heroColor = isDark ? const Color(0xFF101827) : colors.navy;
    return AnimatedContainer(
      duration: CollectMotion.duration(context, CollectMotion.medium),
      curve: CollectMotion.standard,
      decoration: BoxDecoration(
        color: heroColor,
        borderRadius: CollectRadius.cardLargeBorder,
        boxShadow: CollectShadows.card(isDark),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: CollectRadius.cardLargeBorder,
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
            ),
          ),
          Padding(
            padding: CollectSpacing.cardPaddingComfortable,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.78),
                  ),
                ),
                CollectSpacing.gap8,
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    formatRwf(amount),
                    style: CollectTypography.amountHero(Colors.white),
                  ),
                ),
                if (detail != null) ...[
                  CollectSpacing.gap8,
                  Text(
                    detail!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.76),
                    ),
                  ),
                ],
                if (chips.isNotEmpty) ...[
                  CollectSpacing.gap20,
                  Wrap(
                    spacing: CollectSpacing.x2,
                    runSpacing: CollectSpacing.x2,
                    children: chips,
                  ),
                ],
                if (primaryAction != null || secondaryAction != null) ...[
                  CollectSpacing.gap20,
                  Wrap(
                    spacing: CollectSpacing.x2,
                    runSpacing: CollectSpacing.x2,
                    children: [
                      // ignore: use_null_aware_elements
                      if (primaryAction != null) primaryAction!,
                      // ignore: use_null_aware_elements
                      if (secondaryAction != null) secondaryAction!,
                    ],
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
    return Material(
      color: colors.surfaceRaised,
      borderRadius: CollectRadius.cardBorder,
      child: InkWell(
        borderRadius: CollectRadius.cardBorder,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 92, minWidth: 112),
          child: Padding(
            padding: const EdgeInsets.all(CollectSpacing.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ToneIcon(icon: icon, tone: tone),
                CollectSpacing.gap12,
                Text(label, style: Theme.of(context).textTheme.titleSmall),
                if (detail != null) ...[
                  CollectSpacing.gap4,
                  Text(detail!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
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
          _ToneIcon(icon: icon, tone: tone),
          CollectSpacing.gapW12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                CollectSpacing.gap4,
                Text(message, style: Theme.of(context).textTheme.bodySmall),
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

class SecurityNotice extends StatelessWidget {
  const SecurityNotice({
    required this.message,
    this.title = 'Trust boundary',
    this.tone = CollectStatusTone.privacy,
    super.key,
  });

  final String title;
  final String message;
  final CollectStatusTone tone;

  @override
  Widget build(BuildContext context) {
    return InfoSecurityBanner(title: title, message: message, tone: tone);
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
    final colors = context.collectColors;
    return CollectCard(
      emphasis: CollectCardEmphasis.hero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.statusBackground(CollectStatusTone.info),
              borderRadius: CollectRadius.cardLargeBorder,
            ),
            child: SizedBox.square(
              dimension: 76,
              child: Icon(icon, color: colors.blue, size: 34),
            ),
          ),
          CollectSpacing.gap16,
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          CollectSpacing.gap8,
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[CollectSpacing.gap20, action!],
        ],
      ),
    );
  }
}

class BottomActionBar extends StatelessWidget {
  const BottomActionBar({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(CollectSpacing.x4),
          child: Wrap(
            spacing: CollectSpacing.x2,
            runSpacing: CollectSpacing.x2,
            children: children,
          ),
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
    return SegmentedButton<T>(
      showSelectedIcon: false,
      segments: [
        for (final value in values)
          ButtonSegment<T>(value: value, label: Text(labelFor(value))),
      ],
      selected: {selected},
      onSelectionChanged: (value) => onChanged(value.first),
    );
  }
}

class ActivityFeedItem extends StatelessWidget {
  const ActivityFeedItem({
    required this.title,
    required this.amount,
    required this.meta,
    this.transactionId,
    this.tone = CollectStatusTone.success,
    this.onTap,
    super.key,
  });

  final String title;
  final int amount;
  final String meta;
  final String? transactionId;
  final CollectStatusTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: CollectRadius.mdBorder,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: CollectSpacing.x3),
          child: Row(
            children: [
              _ToneIcon(icon: CollectIcons.money, tone: tone),
              CollectSpacing.gapW12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    CollectSpacing.gap4,
                    Text(meta, style: Theme.of(context).textTheme.bodySmall),
                    if (transactionId != null) ...[
                      CollectSpacing.gap4,
                      Text(
                        transactionId!,
                        style: CollectTypography.mono(colors.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
              CollectSpacing.gapW12,
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  formatRwf(amount),
                  style: CollectTypography.amountCompact(colors.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GroupCard extends StatelessWidget {
  const GroupCard({
    required this.collection,
    required this.summary,
    this.onTap,
    this.primaryAction,
    super.key,
  });

  final CollectCollection collection;
  final CollectionSummary summary;
  final VoidCallback? onTap;
  final Widget? primaryAction;

  @override
  Widget build(BuildContext context) {
    return CollectCard(
      onTap: onTap,
      padding: CollectSpacing.cardPaddingComfortable,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _ToneIcon(
                icon: CollectIcons.target,
                tone: CollectStatusTone.info,
              ),
              CollectSpacing.gapW12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      collection.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (collection.description.trim().isNotEmpty) ...[
                      CollectSpacing.gap4,
                      Text(
                        collection.description,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              const CollectStatusChip(
                label: 'Group',
                tone: CollectStatusTone.privacy,
              ),
            ],
          ),
          CollectSpacing.gap20,
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: AmountHero(
                  amount: summary.amountRaisedRwf,
                  label: 'Raised',
                  detail: '${summary.supporterCount} members',
                ),
              ),
            ],
          ),
          CollectSpacing.gap16,
          Wrap(
            spacing: CollectSpacing.x2,
            runSpacing: CollectSpacing.x2,
            children: [
              const CollectStatusChip(
                label: 'Collect ID',
                tone: CollectStatusTone.neutral,
              ),
              if (collection.receiverMomoNumber != null)
                const CollectStatusChip(
                  label: 'MoMo receiver',
                  tone: CollectStatusTone.success,
                ),
              const CollectStatusChip(
                label: 'SMS auto-match',
                tone: CollectStatusTone.info,
              ),
            ],
          ),
          if (primaryAction != null) ...[CollectSpacing.gap16, primaryAction!],
        ],
      ),
    );
  }
}

class CollectionSummaryCard extends StatelessWidget {
  const CollectionSummaryCard({
    required this.collection,
    required this.summary,
    this.onTap,
    super.key,
  });

  final CollectCollection collection;
  final CollectionSummary summary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GroupCard(collection: collection, summary: summary, onTap: onTap);
  }
}

class PremiumScaffold extends StatelessWidget {
  const PremiumScaffold({
    required this.title,
    required this.children,
    this.subtitle,
    this.actions = const [],
    this.banner,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? banner;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: CollectSpacing.screenPadding,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    if (subtitle != null) ...[
                      CollectSpacing.gap8,
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
              if (actions.isNotEmpty) ...[
                CollectSpacing.gapW12,
                Wrap(spacing: CollectSpacing.x2, children: actions),
              ],
            ],
          ),
          if (banner != null) ...[CollectSpacing.gap20, banner!],
          CollectSpacing.gap24,
          ..._withGaps(children),
        ],
      ),
    );
  }

  static List<Widget> _withGaps(List<Widget> children) {
    final spaced = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      spaced.add(children[index]);
      if (index != children.length - 1) spaced.add(CollectSpacing.gap16);
    }
    return spaced;
  }
}

class ScreenScaffoldLayout extends StatelessWidget {
  const ScreenScaffoldLayout({
    required this.title,
    required this.children,
    this.subtitle,
    this.actions = const [],
    this.banner,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? banner;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return PremiumScaffold(
      title: title,
      subtitle: subtitle,
      actions: actions,
      banner: banner,
      children: children,
    );
  }
}

CollectStatusTone paymentStatusTone(String status) {
  return switch (status) {
    'matched' || 'confirmed' || 'paid' => CollectStatusTone.success,
    'needs_review' || 'review' => CollectStatusTone.warning,
    'expired' || 'failed' => CollectStatusTone.danger,
    'pending' => CollectStatusTone.info,
    _ => CollectStatusTone.neutral,
  };
}

String paymentStatusLabel(String status) {
  return switch (status) {
    'matched' => 'Matched',
    'confirmed' || 'paid' => 'Confirmed',
    'needs_review' || 'review' => 'Needs review',
    'expired' => 'Expired',
    'pending' => 'Pending',
    _ => status.replaceAll('_', ' '),
  };
}

CollectStatusTone statusToneFromText(String status) {
  final normalized = status.toLowerCase();
  if (normalized.contains('approved') ||
      normalized.contains('allocated') ||
      normalized.contains('matched') ||
      normalized.contains('confirmed')) {
    return CollectStatusTone.success;
  }
  if (normalized.contains('pending') ||
      normalized.contains('review') ||
      normalized.contains('requested')) {
    return CollectStatusTone.warning;
  }
  if (normalized.contains('reject') ||
      normalized.contains('danger') ||
      normalized.contains('expired')) {
    return CollectStatusTone.danger;
  }
  if (normalized.contains('private')) {
    return CollectStatusTone.privacy;
  }
  return CollectStatusTone.neutral;
}

InputDecoration collectInputDecoration(
  BuildContext context, {
  required String label,
  String? helper,
  String? prefix,
}) {
  return CollectComponentTokens.inputDecoration(
    context: context,
    label: label,
    helper: helper,
    prefix: prefix,
  );
}

void copyToClipboard(BuildContext context, String text, {String? message}) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message ?? 'Copied securely.')));
}

void goBackOrHome(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/home');
  }
}

IconData _statusIcon(CollectStatusTone tone, IconData? override) {
  if (override != null) return override;
  return switch (tone) {
    CollectStatusTone.success => CollectIcons.check,
    CollectStatusTone.warning => CollectIcons.warning,
    CollectStatusTone.danger => CollectIcons.error,
    CollectStatusTone.info => CollectIcons.info,
    CollectStatusTone.privacy => CollectIcons.lock,
    CollectStatusTone.neutral => CollectIcons.info,
  };
}

class _ToneIcon extends StatelessWidget {
  const _ToneIcon({required this.icon, required this.tone, this.large = false});

  final IconData icon;
  final CollectStatusTone tone;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.statusBackground(tone),
        borderRadius: CollectRadius.pillBorder,
      ),
      child: SizedBox.square(
        dimension: large ? 56 : 40,
        child: Icon(
          icon,
          color: colors.statusForeground(tone),
          size: large ? 28 : 20,
        ),
      ),
    );
  }
}
