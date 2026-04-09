part of 'momo_send_sheet.dart';

class _MomoSendReviewCard extends StatelessWidget {
  const _MomoSendReviewCard({
    required this.country,
    required this.sourceDisplayNumber,
    required this.recipient,
    required this.amount,
    required this.recipientType,
  });

  final CoolCountry country;
  final String sourceDisplayNumber;
  final String recipient;
  final int? amount;
  final MomoRecipientType recipientType;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label:
          '${l10n.momoReviewTitle}. ${l10n.momoReviewRecipientLabel}: ${recipient.isEmpty ? l10n.momoReviewMissingRecipient : recipient}.'
          '${l10n.momoReviewAmountLabel}: ${amount == null ? l10n.momoReviewMissingAmount : _formatAmount(amount!, country.currencyCode, localeTag)}.',
      child: CoolCard(
        backgroundColor: colors.surface,
        padding: const EdgeInsets.all(CoolSpace.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.momoReviewTitle,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.primaryText,
              ),
            ),
            const SizedBox(height: CoolSpace.x3),
            _MomoReviewRow(
              label: l10n.momoReviewRecipientLabel,
              value: recipient.isEmpty
                  ? l10n.momoReviewMissingRecipient
                  : recipient,
              emphasizeValue: recipient.isNotEmpty,
            ),
            const SizedBox(height: 10),
            _MomoReviewRow(
              label: l10n.momoReviewAmountLabel,
              value: amount == null
                  ? l10n.momoReviewMissingAmount
                  : _formatAmount(amount!, country.currencyCode, localeTag),
              emphasizeValue: amount != null,
            ),
            const SizedBox(height: 10),
            _MomoReviewRow(
              label: l10n.momoReviewRouteLabel,
              value: recipientType == MomoRecipientType.code
                  ? l10n.momoRouteCodeLabel
                  : l10n.momoRoutePhoneLabel,
              emphasizeValue: true,
            ),
            if (sourceDisplayNumber.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              _MomoReviewRow(
                label: l10n.momoReviewFromLabel,
                value: sourceDisplayNumber,
                emphasizeValue: true,
              ),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(vertical: CoolSpace.x3),
              child: Divider(height: 1, color: colors.border),
            ),
            Text(
              l10n.momoWhatHappensNextTitle,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.primaryText,
              ),
            ),
            const SizedBox(height: 10),
            _MomoStepRow(
              step: '1',
              text: l10n.momoWhatHappensNextOpen(country.name),
            ),
            const SizedBox(height: CoolSpace.x2),
            _MomoStepRow(step: '2', text: l10n.momoWhatHappensNextConfirm),
            const SizedBox(height: CoolSpace.x2),
            _MomoStepRow(step: '3', text: l10n.momoWhatHappensNextReceipt),
          ],
        ),
      ),
    );
  }

  static String _formatAmount(int amount, String currency, String localeTag) {
    final formatter = NumberFormat.decimalPattern(localeTag);
    return '$currency ${formatter.format(amount)}';
  }
}

class _MomoReviewRow extends StatelessWidget {
  const _MomoReviewRow({
    required this.label,
    required this.value,
    required this.emphasizeValue,
  });

  final String label;
  final String value;
  final bool emphasizeValue;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.secondaryText,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: emphasizeValue ? FontWeight.w700 : FontWeight.w500,
              color: emphasizeValue ? colors.primaryText : colors.secondaryText,
            ),
          ),
        ),
      ],
    );
  }
}

class _MomoStepRow extends StatelessWidget {
  const _MomoStepRow({required this.step, required this.text});

  final String step;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: colors.accentGlow,
            borderRadius: const BorderRadius.all(
              Radius.circular(CoolRadii.pill),
            ),
            border: Border.all(color: colors.border),
          ),
          alignment: Alignment.center,
          child: Text(
            step,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.accent,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w500,
              color: colors.secondaryText,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class MomoRouteTypeChip extends StatelessWidget {
  const MomoRouteTypeChip({
    required this.label,
    required this.isActive,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: isActive,
      label: '$label route type',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: CoolSpace.x3),
          decoration: BoxDecoration(
            color: isActive ? colors.accentGlow : colors.surface,
            borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.sm)),
            border: Border.all(color: isActive ? colors.accent : colors.border),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: isActive ? colors.accent : colors.secondaryText,
            ),
          ),
        ),
      ),
    );
  }
}
