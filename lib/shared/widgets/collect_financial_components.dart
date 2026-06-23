import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/collect_colors.dart';
import '../../app/theme/collect_icons.dart';
import '../../app/theme/collect_motion.dart';
import '../../app/theme/collect_radius.dart';
import '../../app/theme/collect_shadows.dart';
import '../../app/theme/collect_spacing.dart';
import '../../app/theme/collect_typography.dart';
import '../../core/security/phone_normalizer.dart';
import '../../core/utils/date_format.dart';
import '../../core/utils/money_format.dart';
import '../models/collect_models.dart';
import 'collect_display_primitives.dart';
import 'collect_foundation.dart';
import 'collect_state_panels.dart';
import 'collect_tone_icon.dart';

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
              CollectToneIcon(icon: icon, tone: tone),
              CollectSpacing.gapW12,
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
            Text(
              detail!,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
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
        if (label.trim().isNotEmpty) ...[
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          CollectSpacing.gap8,
        ],
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            formatRwf(amount),
            maxLines: 1,
            style: CollectTypography.amountHero(colors.textPrimary),
          ),
        ),
        if (detail != null) ...[
          CollectSpacing.gap8,
          Text(
            detail!,
            style: Theme.of(context).textTheme.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

class FinancialListRow extends StatelessWidget {
  const FinancialListRow({
    required this.title,
    required this.meta,
    this.amountRwf,
    this.subtitle,
    this.transactionId,
    this.leading,
    this.tone = CollectStatusTone.success,
    this.onTap,
    super.key,
  });

  final String title;
  final int? amountRwf;
  final String meta;
  final String? subtitle;
  final String? transactionId;
  final IconData? leading;
  final CollectStatusTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Material(
      color: colors.transparent,
      child: InkWell(
        borderRadius: CollectRadius.controlBorder,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: CollectSpacing.x4),
          child: Row(
            children: [
              CollectToneIcon(icon: leading ?? CollectIcons.money, tone: tone),
              CollectSpacing.gapW12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _IdentityTitle(title: title),
                    if (subtitle != null) ...[
                      CollectSpacing.gap4,
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    CollectSpacing.gap4,
                    Text(
                      meta,
                      style: CollectTypography.transactionMeta(
                        colors.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (transactionId != null) ...[
                      CollectSpacing.gap4,
                      SelectableText(
                        transactionId!,
                        style: CollectTypography.transactionMeta(
                          colors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (amountRwf != null) ...[
                CollectSpacing.gapW12,
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    formatRwf(amountRwf!),
                    style: CollectTypography.amountCompact(colors.textPrimary),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class AmountEntryPanel extends StatelessWidget {
  const AmountEntryPanel({
    required this.controller,
    required this.amount,
    required this.quickAmounts,
    required this.onQuickAmount,
    this.label,
    this.detail,
    this.error,
    super.key,
  });

  final TextEditingController controller;
  final int amount;
  final List<int> quickAmounts;
  final ValueChanged<int> onQuickAmount;
  final String? label;
  final String? detail;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final amountStyle = CollectTypography.amountDisplay(
      colors.textPrimary,
    ).copyWith(fontSize: 44, height: 1.05);
    final prefixStyle = amountStyle.copyWith(color: colors.textSecondary);
    return CollectCard(
      emphasis: CollectCardEmphasis.compact,
      padding: CollectSpacing.cardPaddingComfortable,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (label?.trim().isNotEmpty == true ? label! : 'Amount'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.glassControl,
                  borderRadius: CollectRadius.pillBorder,
                  border: Border.all(color: colors.glassBorder),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CollectSpacing.x3,
                    vertical: CollectSpacing.x1,
                  ),
                  child: Text(
                    'RWF',
                    style: CollectTypography.eyebrowLabel(colors.textMuted),
                  ),
                ),
              ),
            ],
          ),
          CollectSpacing.gap16,
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.glassControl,
              borderRadius: CollectRadius.panelBorder,
              border: Border.all(color: colors.glassBorder),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: CollectSpacing.x4,
                vertical: CollectSpacing.x3,
              ),
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: amountStyle,
                maxLines: 1,
                decoration: InputDecoration(
                  hintText: '0',
                  prefixText: 'RWF ',
                  prefixStyle: prefixStyle,
                  hintStyle: amountStyle.copyWith(color: colors.textMuted),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          if (detail != null) ...[
            CollectSpacing.gap8,
            Text(detail!, style: Theme.of(context).textTheme.bodyMedium),
          ],
          CollectSpacing.gap16,
          Wrap(
            spacing: CollectSpacing.x2,
            runSpacing: CollectSpacing.x2,
            children: [
              for (final option in quickAmounts)
                ChoiceChip(
                  label: Text(_compactAmount(option)),
                  selected: amount == option,
                  selectedColor: CollectColors.brandPeriwinkle,
                  backgroundColor: colors.glassControl,
                  showCheckmark: false,
                  side: BorderSide(
                    color: amount == option
                        ? colors.borderAccent
                        : colors.borderSoft,
                    width: amount == option ? 1.5 : 1,
                  ),
                  labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: amount == option
                        ? colors.selectedOnAccent
                        : colors.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                  onSelected: (_) => onQuickAmount(option),
                ),
            ],
          ),
          if (error != null) ...[
            CollectSpacing.gap12,
            Text(
              error!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.danger),
            ),
          ],
        ],
      ),
    );
  }
}

class PaymentReviewSummary extends StatelessWidget {
  const PaymentReviewSummary({
    required this.amountRwf,
    required this.groupTitle,
    required this.receiverLabel,
    required this.receiverMomoNumber,
    this.onEdit,
    super.key,
  });

  final int amountRwf;
  final String groupTitle;
  final String receiverLabel;
  final String receiverMomoNumber;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return CollectCard(
      emphasis: CollectCardEmphasis.hero,
      padding: CollectSpacing.cardPaddingComfortable,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Review contribution',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (onEdit != null)
                CollectButton(
                  label: 'Edit',
                  icon: CollectIcons.tune,
                  onPressed: onEdit,
                  variant: CollectButtonVariant.subtle,
                ),
            ],
          ),
          CollectSpacing.gap16,
          Text(
            formatRwf(amountRwf),
            style: CollectTypography.amountDisplay(colors.textPrimary),
          ),
          CollectSpacing.gap20,
          _ReviewLine(label: 'Group', value: groupTitle),
          _ReviewLine(
            label: 'MoMo',
            value: maskMomoNumberForDisplay(receiverMomoNumber),
          ),
        ],
      ),
    );
  }
}

class _ReviewLine extends StatelessWidget {
  const _ReviewLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CollectSpacing.x2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label.toUpperCase(),
              style: CollectTypography.eyebrowLabel(colors.textMuted),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: Theme.of(context).textTheme.titleSmall,
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
    required this.status,
    super.key,
  });

  final int amountRwf;
  final String receiverLabel;
  final String receiverMomoNumber;
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
          AmountHero(amount: amountRwf, label: 'Payment amount'),
          CollectSpacing.gap20,
          Wrap(
            spacing: CollectSpacing.x2,
            runSpacing: CollectSpacing.x2,
            children: [
              CollectStatusChip(
                label: paymentStatusLabel(status),
                tone: paymentStatusTone(status),
              ),
            ],
          ),
          CollectSpacing.gap20,
          Text(receiverLabel, style: Theme.of(context).textTheme.labelLarge),
          CollectSpacing.gap4,
          SelectableText(
            maskMomoNumberForDisplay(receiverMomoNumber),
            style: CollectTypography.amountLarge(colors.textPrimary),
          ),
          CollectSpacing.gap16,
          const InfoSecurityBanner(
            title: 'SMS verification',
            message: 'Ledger updates after SMS.',
            tone: CollectStatusTone.privacy,
          ),
        ],
      ),
    );
  }
}

class PaymentPipelineIndicator extends StatelessWidget {
  const PaymentPipelineIndicator({required this.status, super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final activeStep = _pipelineStep(status);
    const stages = [
      (label: 'Start', icon: CollectIcons.pending),
      (label: 'Check', icon: CollectIcons.sms),
      (label: 'Done', icon: CollectIcons.ledger),
    ];
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Payment progress: ${paymentStatusLabel(status)}',
      child: CollectCard(
        emphasis: CollectCardEmphasis.flat,
        padding: const EdgeInsets.all(CollectSpacing.x4),
        child: Row(
          children: [
            for (var index = 0; index < stages.length; index++) ...[
              Expanded(
                child: _PipelineStage(
                  label: stages[index].label,
                  icon: stages[index].icon,
                  complete: activeStep > index,
                  current: activeStep == index,
                ),
              ),
              if (index != stages.length - 1)
                Expanded(child: _PipelineLine(active: activeStep > index + 1)),
            ],
          ],
        ),
      ),
    );
  }
}

class PaymentVerifiedRing extends StatelessWidget {
  const PaymentVerifiedRing({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return CollectCard(
      padding: CollectSpacing.cardPaddingComfortable,
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: colors.success, width: 6),
              color: colors.statusBackground(CollectStatusTone.success),
            ),
            child: Icon(CollectIcons.check, color: colors.success, size: 42),
          ),
          CollectSpacing.gap20,
          Text(
            'Payment recorded',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          CollectSpacing.gap8,
          Text(
            'Ledger updated.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class CollectIdCard extends StatelessWidget {
  const CollectIdCard({required this.publicId, super.key});

  final String publicId;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final value = publicId.trim().isEmpty ? '------' : publicId.trim();
    return CollectCard(
      emphasis: CollectCardEmphasis.hero,
      padding: CollectSpacing.cardPaddingComfortable,
      child: Row(
        children: [
          _GroupIconBadge(
            icon: CollectIcons.profile,
            accent: colors.actionColor,
            size: 52,
          ),
          CollectSpacing.gapW12,
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: CollectTypography.amountHero(colors.textPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LedgerRow extends StatelessWidget {
  LedgerRow.confirmed({required Contribution contribution, super.key})
    : title = compactCollectIdLabel(contribution.supporterLabel),
      amountRwf = contribution.amountRwf,
      meta = formatCollectDateTime(contribution.createdAt),
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
    final colors = context.collectColors;
    return CollectCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: CollectSpacing.x2,
            runSpacing: CollectSpacing.x2,
            children: [
              CollectStatusChip(
                label: flagsEnabled ? 'Enabled' : 'Off',
                tone: flagsEnabled
                    ? CollectStatusTone.success
                    : CollectStatusTone.neutral,
              ),
              CollectStatusChip(
                label: consented ? 'Active' : 'Required',
                tone: consented
                    ? CollectStatusTone.success
                    : CollectStatusTone.warning,
              ),
            ],
          ),
          CollectSpacing.gap16,
          const InfoSecurityBanner(
            title: 'Consent',
            message:
                'Owner approval required. Private confirmation messages are used only for payment matching.',
            tone: CollectStatusTone.privacy,
          ),
          CollectSpacing.gap16,
          Material(
            color: colors.transparent,
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
            label: isSyncing ? 'Syncing...' : 'Sync',
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
    final heroColor = colors.periwinklePaint;
    return AnimatedContainer(
      duration: CollectMotion.duration(context, CollectMotion.medium),
      curve: CollectMotion.standard,
      decoration: BoxDecoration(
        color: heroColor,
        borderRadius: CollectRadius.cardLargeBorder,
        boxShadow: CollectShadows.card(),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: CollectRadius.cardLargeBorder,
                border: Border.all(
                  color: colors.onImagePrimary.withValues(alpha: 0.08),
                ),
              ),
            ),
          ),
          Padding(
            padding: CollectSpacing.cardPaddingComfortable,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label.trim().isNotEmpty) ...[
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colors.onImagePrimary.withValues(alpha: 0.78),
                    ),
                  ),
                  CollectSpacing.gap8,
                ],
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    formatRwf(amount),
                    style: CollectTypography.amountHero(colors.onImagePrimary),
                  ),
                ),
                if (detail != null) ...[
                  CollectSpacing.gap8,
                  Text(
                    detail!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onImagePrimary.withValues(alpha: 0.76),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

class ActivityFeedItem extends StatelessWidget {
  const ActivityFeedItem({
    required this.title,
    required this.amount,
    required this.meta,
    this.transactionId,
    this.tone = CollectStatusTone.info,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final amountColor = isDark ? colors.onImagePrimary : colors.textPrimary;
    return Material(
      color: colors.transparent,
      child: InkWell(
        borderRadius: CollectRadius.mdBorder,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: CollectSpacing.x3),
          child: Row(
            children: [
              CollectToneIcon(icon: CollectIcons.profile, tone: tone),
              CollectSpacing.gapW12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _IdentityTitle(title: title),
                    CollectSpacing.gap4,
                    Text(
                      meta,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (transactionId != null) ...[
                      CollectSpacing.gap4,
                      Text(
                        transactionId!,
                        style: CollectTypography.mono(colors.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                  style: CollectTypography.amountCompact(amountColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String compactCollectIdLabel(String label) {
  return label
      .replaceFirst(RegExp(r'^Collect ID\s+'), '')
      .replaceFirst(RegExp(r'^#'), '');
}

class _IdentityTitle extends StatelessWidget {
  const _IdentityTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final cleaned = compactCollectIdLabel(title);
    final isIdentity =
        cleaned != title.replaceFirst(RegExp(r'^#'), '') ||
        RegExp(r'^\d{4,}$').hasMatch(cleaned);
    if (!isIdentity) {
      return Text(
        title,
        style: Theme.of(context).textTheme.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Row(
      children: [
        Icon(
          CollectIcons.profile,
          size: 18,
          color: context.collectColors.textSecondary,
        ),
        CollectSpacing.gapW8,
        Expanded(
          child: Text(
            cleaned,
            style: Theme.of(context).textTheme.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

String _compactAmount(int amount) {
  if (amount >= 1000000 && amount % 1000000 == 0) {
    return '${amount ~/ 1000000}M';
  }
  if (amount >= 1000 && amount % 1000 == 0) {
    return '${amount ~/ 1000}k';
  }
  return formatRwf(amount);
}

class _GroupIconBadge extends StatelessWidget {
  const _GroupIconBadge({
    required this.icon,
    required this.accent,
    required this.size,
  });

  final IconData icon;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(icon, color: accent, size: size * 0.52),
      ),
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

int _pipelineStep(String status) {
  return switch (status) {
    'matched' || 'confirmed' || 'paid' => 3,
    'needs_review' || 'review' => 2,
    'expired' || 'failed' => 1,
    _ => 1,
  };
}

class _PipelineStage extends StatelessWidget {
  const _PipelineStage({
    required this.label,
    required this.icon,
    required this.complete,
    required this.current,
  });

  final String label;
  final IconData icon;
  final bool complete;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final tone = complete
        ? CollectStatusTone.success
        : current
        ? CollectStatusTone.info
        : CollectStatusTone.neutral;
    final foreground = colors.statusForeground(tone);
    final stateLabel = complete
        ? 'complete'
        : current
        ? 'current'
        : 'pending';
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '$label step $stateLabel',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.statusBackground(tone),
              border: Border.all(color: foreground.withValues(alpha: 0.26)),
            ),
            child: SizedBox.square(
              dimension: 38,
              child: Icon(
                complete ? CollectIcons.check : icon,
                color: foreground,
              ),
            ),
          ),
          CollectSpacing.gap8,
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w800,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PipelineLine extends StatelessWidget {
  const _PipelineLine({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Container(
        height: 3,
        decoration: BoxDecoration(
          color: active
              ? colors.success
              : colors.border.withValues(alpha: 0.72),
          borderRadius: CollectRadius.pillBorder,
        ),
      ),
    );
  }
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

String maskMomoNumberForDisplay(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed == 'Not configured') return trimmed;
  final localMomo = PhoneNormalizer.tryNormalizeMtnMomoLocal(trimmed);
  if (localMomo != null) {
    return '${localMomo.substring(0, 3)}***${localMomo.substring(6)}';
  }
  final digits = trimmed.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 4) return 'MoMo linked';
  final suffix = digits.substring(digits.length - 4);
  return '***$suffix';
}
