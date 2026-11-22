part of 'contribution_flow_screen.dart';

class _NativeContributionAppBar extends StatelessWidget {
  const _NativeContributionAppBar({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CollectSpacing.x2,
        CollectSpacing.x2,
        CollectSpacing.x4,
        CollectSpacing.x2,
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: CollectSpacing.target,
            child: IconButton(
              tooltip: 'Back',
              onPressed: onBack,
              icon: const Icon(CollectIcons.back),
            ),
          ),
          CollectSpacing.gapW8,
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: CollectTypography.weightBold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _NativeAmountEntry extends StatelessWidget {
  const _NativeAmountEntry({
    required this.controller,
    required this.focusNode,
    required this.errorText,
    required this.onSubmitted,
    required this.onPreset,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String? errorText;
  final VoidCallback onSubmitted;
  final ValueChanged<int> onPreset;
  final VoidCallback onChanged;

  static const _presets = [1000, 2000, 5000, 10000];

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final l10n = CollectLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.text('howMuch'),
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: colors.textPrimary,
            fontWeight: CollectTypography.weightBold,
          ),
        ),
        CollectSpacing.gap24,
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: CollectSpacing.x5,
            vertical: CollectSpacing.x3,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceReadable,
            borderRadius: CollectRadius.cardLargeBorder,
          ),
          child: ContributionAmountInput(
            controller: controller,
            focusNode: focusNode,
            label: l10n.text('contributionAmount'),
            errorText: errorText,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
          ),
        ),
        CollectSpacing.gap20,
        Text(
          l10n.text('quickAmounts'),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colors.textMuted,
            fontWeight: CollectTypography.weightSemibold,
          ),
        ),
        CollectSpacing.gap12,
        Wrap(
          spacing: CollectSpacing.x2,
          runSpacing: CollectSpacing.x2,
          children: [
            for (final amount in _presets)
              _NativeAmountPreset(
                amount: amount,
                selected:
                    controller.text.replaceAll(',', '') == amount.toString(),
                onTap: () => onPreset(amount),
              ),
          ],
        ),
      ],
    );
  }
}

class _NativeAmountPreset extends StatelessWidget {
  const _NativeAmountPreset({
    required this.amount,
    required this.selected,
    required this.onTap,
  });

  final int amount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      button: true,
      selected: selected,
      label: 'RWF $amount',
      child: Material(
        color: selected ? colors.textPrimary : colors.surfaceRaised,
        borderRadius: CollectRadius.pillBorder,
        child: InkWell(
          onTap: onTap,
          borderRadius: CollectRadius.pillBorder,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: CollectSpacing.x4,
                vertical: CollectSpacing.x3,
              ),
              child: Text(
                formatRwf(amount).replaceFirst('RWF ', ''),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected ? colors.canvas : colors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NativeAmountReview extends StatelessWidget {
  const _NativeAmountReview({
    required this.amountRwf,
    this.title,
    this.description,
  });

  final int amountRwf;
  final String? title, description;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final l10n = CollectLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title ?? l10n.text('reviewContribution'),
          style:
              (MediaQuery.textScalerOf(context).scale(1) >= 1.3
                      ? Theme.of(context).textTheme.titleLarge
                      : Theme.of(context).textTheme.headlineMedium)
                  ?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: CollectTypography.weightBold,
                  ),
        ),
        CollectSpacing.gap8,
        Text(
          description ?? l10n.text('youWillContribute'),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
        ),
        CollectSpacing.gap16,
        ContributionAmountValue(amountRwf: amountRwf),
      ],
    );
  }
}

class _NativeMomoReceiverTile extends StatelessWidget {
  const _NativeMomoReceiverTile({required this.name, required this.receiver});

  final String name;
  final String receiver;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      container: true,
      label: receiver.isEmpty ? name : '$name, $receiver',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(CollectSpacing.x4),
          decoration: BoxDecoration(
            color: colors.surfaceReadable,
            borderRadius: CollectRadius.cardLargeBorder,
          ),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.statusBackground(CollectStatusTone.info),
                  border: Border.all(
                    color: CollectRuntimeTokens.badgeBorder(
                      colors,
                      colors.statusForeground(CollectStatusTone.info),
                    ),
                  ),
                ),
                child: SizedBox.square(
                  dimension: 48,
                  child: Icon(
                    CollectIcons.momo,
                    color: colors.statusForeground(CollectStatusTone.info),
                    size: 23,
                  ),
                ),
              ),
              CollectSpacing.gapW12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: CollectTypography.weightBold,
                                ),
                          ),
                        ),
                        CollectSpacing.gapW4,
                        Icon(
                          CollectIcons.check,
                          size: 17,
                          color: colors.textSecondary,
                        ),
                      ],
                    ),
                    if (receiver.isNotEmpty) ...[
                      CollectSpacing.gap4,
                      Text(
                        receiver,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NativeMomoTrustNote extends StatelessWidget {
  const _NativeMomoTrustNote({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colors.surfaceRaised,
            shape: BoxShape.circle,
          ),
          child: Icon(CollectIcons.lock, size: 18, color: colors.textPrimary),
        ),
        CollectSpacing.gapW12,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: CollectTypography.weightBold,
                ),
              ),
              CollectSpacing.gap4,
              Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NativeMomoStatus extends StatelessWidget {
  const _NativeMomoStatus({
    required this.title,
    required this.message,
    this.isError = false,
  });

  final String title;
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      container: true,
      liveRegion: true,
      label: '$title. $message',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(CollectSpacing.x4),
          decoration: BoxDecoration(
            color: isError ? colors.dangerContainer : colors.infoContainer,
            borderRadius: CollectRadius.cardBorder,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isError ? CollectIcons.warning : CollectIcons.sms,
                size: 20,
                color: isError
                    ? colors.dangerForeground
                    : colors.infoForeground,
              ),
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
        ),
      ),
    );
  }
}

class _NativeContributionBottomBar extends StatelessWidget {
  const _NativeContributionBottomBar({
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: BoxDecoration(color: colors.canvas),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          CollectSpacing.x5,
          CollectSpacing.x3,
          CollectSpacing.x5,
          CollectSpacing.x4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CollectButton(
              label: primaryLabel,
              icon: primaryIcon,
              onPressed: onPrimary,
              expand: true,
            ),
            if (secondaryLabel != null) ...[
              CollectSpacing.gap8,
              CollectButton(
                label: secondaryLabel!,
                onPressed: onSecondary,
                variant: CollectButtonVariant.subtle,
                expand: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
