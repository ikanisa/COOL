part of 'momo_screen.dart';

// ─── Build‑method section extractors ───────────────────────────────────────

/// Balance card with wallet metrics and quick-action strip.
Widget _buildBalanceSection({
  required BuildContext context,
  required CoolSemanticColors colors,
  required ThemeData theme,
  required int walletBalance,
  required int walletInflows,
  required int walletOutflows,
  required int savingsTotal,
  required CoolCountry country,
  required String momoNumber,
  required String? momoCode,
  required VoidCallback onSendMoney,
  required VoidCallback onOpenStatements,
  required VoidCallback onOpenQrCode,
}) {
  final l10n = context.l10n;
  return BalanceCard(
    amount: walletBalance,
    currency: 'RWF',
    changeAmount: walletInflows - walletOutflows,
    metrics: [
      BalanceCardMetric(
        label: 'Inflow',
        value: '${_formatCompactAmount(walletInflows)} RWF',
        accentColor: colors.success,
      ),
      BalanceCardMetric(
        label: 'Outflow',
        value: '${_formatCompactAmount(walletOutflows)} RWF',
        accentColor: colors.warning,
      ),
      BalanceCardMetric(
        label: 'Savings',
        value: '${_formatCompactAmount(savingsTotal)} RWF',
        accentColor: colors.info,
      ),
    ],
    actions: [
      BalanceCardAction(
        label: l10n.sendMoney,
        icon: Icons.send_rounded,
        isPrimary: true,
        onTap: onSendMoney,
      ),
      BalanceCardAction(
        label: l10n.statements,
        icon: Icons.receipt_long_rounded,
        onTap: onOpenStatements,
      ),
      BalanceCardAction(
        label: l10n.momoQr,
        icon: Icons.qr_code_2_rounded,
        onTap: onOpenQrCode,
      ),
    ],
  );
}

/// BioPay promo card — only shown when the feature flag is on.
Widget _buildBiopayCard({
  required BuildContext context,
  required CoolSemanticColors colors,
  required CoolSpaceTokens space,
  required ThemeData theme,
  required VoidCallback onOpen,
}) {
  return CoolCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colors.info.withValues(alpha: 0.14),
                borderRadius: const BorderRadius.all(
                  Radius.circular(CoolRadii.lg),
                ),
              ),
              child: Icon(
                Icons.face_retouching_natural_rounded,
                color: colors.info,
              ),
            ),
            SizedBox(width: space.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'BioPay',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: colors.primaryText,
                    ),
                  ),
                  SizedBox(height: space.x1),
                  Text(
                    'Face payments',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.secondaryText,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: space.x4),
        CoolButton(
          label: 'Open BioPay',
          icon: Icons.arrow_outward_rounded,
          onTap: onOpen,
        ),
      ],
    ),
  );
}

/// Payment action grid combined with the "Trust and controls" header.
Widget _buildTrustAndActionsCard({
  required BuildContext context,
  required CoolSemanticColors colors,
  required CoolSpaceTokens space,
  required ThemeData theme,
  required VoidCallback onOpenStatements,
  required VoidCallback onScanQr,
  required VoidCallback onOpenQrCode,
  required VoidCallback onOpenNfcTools,
}) {
  return MomoActionGrid(
    onOpenStatements: onOpenStatements,
    onScanQr: onScanQr,
    onOpenQrCode: onOpenQrCode,
    onOpenNfcTools: onOpenNfcTools,
  );
}



/// Semi‑transparent overlay while USSD handoff is launching.
Widget _buildLaunchingOverlay({
  required BuildContext context,
  required CoolSemanticColors colors,
  required CoolSpaceTokens space,
  required ThemeData theme,
}) {
  final l10n = context.l10n;
  return Positioned(
    left: 18,
    right: 18,
    top: 12,
    child: Semantics(
      liveRegion: true,
      label: l10n.momoNfcLaunchingOverlay,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: colors.elevatedBackground,
            borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.md)),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CupertinoActivityIndicator(radius: 9),
              ),
              SizedBox(width: space.x3),
              Expanded(
                child: Text(
                  l10n.momoNfcLaunchingOverlay,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.primaryText,
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



// ─── Pure helpers ──────────────────────────────────────────────────────────

int _walletBalance(MomoStatementBundle? bundle) {
  if (bundle == null) return 0;
  var total = 0;
  for (final entry in bundle.walletEntries) {
    if (entry.ledgerStatus != 'posted') continue;
    total += entry.isCredit ? entry.amount : -entry.amount;
  }
  return total;
}

int _walletInflows(MomoStatementBundle? bundle) {
  if (bundle == null) return 0;
  return bundle.walletEntries
      .where((entry) => entry.isCredit && entry.ledgerStatus == 'posted')
      .fold<int>(0, (sum, entry) => sum + entry.amount);
}

int _walletOutflows(MomoStatementBundle? bundle) {
  if (bundle == null) return 0;
  return bundle.walletEntries
      .where((entry) => entry.isDebit && entry.ledgerStatus == 'posted')
      .fold<int>(0, (sum, entry) => sum + entry.amount);
}

int _savingsTotal(MomoStatementBundle? bundle) {
  if (bundle == null) return 0;
  return bundle.savingsEntries
      .where((entry) => entry.isConfirmed)
      .fold<int>(0, (sum, entry) => sum + entry.amount);
}

String _formatCompactAmount(int amount) {
  if (amount >= 1000000) {
    return '${(amount / 1000000).toStringAsFixed(amount % 1000000 == 0 ? 0 : 1)}M';
  }
  if (amount >= 1000) {
    return '${(amount / 1000).toStringAsFixed(amount % 1000 == 0 ? 0 : 1)}K';
  }
  return '$amount';
}
