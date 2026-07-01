part of 'collect_financial_components.dart';

class PaymentReviewSummary extends StatelessWidget {
  const PaymentReviewSummary({
    required this.amountRwf,
    required this.groupTitle,
    required this.receiverLabel,
    required this.receiverMomoNumber,
    this.onEdit,
    this.showFullReceiverNumber = false,
    super.key,
  });

  final int amountRwf;
  final String groupTitle;
  final String receiverLabel;
  final String receiverMomoNumber;
  final VoidCallback? onEdit;
  final bool showFullReceiverNumber;

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
            value: showFullReceiverNumber
                ? receiverMomoNumber
                : maskMomoNumberForDisplay(receiverMomoNumber),
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
