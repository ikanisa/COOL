import 'package:flutter/material.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../core/l10n/l10n.dart';

// ═════════════════════════════════════════════════════════════════════════════
// MOMO ACTION GRID
// ═════════════════════════════════════════════════════════════════════════════

class MomoActionGrid extends StatelessWidget {
  const MomoActionGrid({
    required this.onOpenStatements,
    required this.onScanQr,
    required this.onOpenQrCode,
    required this.onOpenNfcTools,
    super.key,
  });

  final VoidCallback onOpenStatements;
  final VoidCallback onScanQr;
  final VoidCallback onOpenQrCode;
  final VoidCallback onOpenNfcTools;

  @override
  Widget build(BuildContext context) {
    final space = context.coolSpace;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: space.x3,
      crossAxisSpacing: space.x3,
      childAspectRatio: 1.02,
      children: [
        MomoActionCard(
          actionKey: const ValueKey<String>('momo-action-statements'),
          icon: Icons.receipt_long_rounded,
          title: context.l10n.statements,
          subtitle: 'Ledger and statements',
          onTap: onOpenStatements,
        ),
        MomoActionCard(
          actionKey: const ValueKey<String>('momo-action-scan-qr'),
          icon: Icons.center_focus_strong_rounded,
          title: context.l10n.scanQr,
          subtitle: 'Scan a payment request',
          onTap: onScanQr,
          isPrimary: true,
        ),
        MomoActionCard(
          actionKey: const ValueKey<String>('momo-action-receive-qr'),
          icon: Icons.qr_code_2_rounded,
          title: context.l10n.momoQr,
          subtitle: 'Share your receive code',
          onTap: onOpenQrCode,
        ),
        MomoActionCard(
          actionKey: const ValueKey<String>('momo-action-nfc-pay'),
          icon: Icons.nfc_rounded,
          title: context.l10n.nfcPay,
          subtitle: 'Tap and receive',
          onTap: onOpenNfcTools,
        ),
      ],
    );
  }
}

class MomoActionCard extends StatelessWidget {
  const MomoActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.actionKey,
    this.isPrimary = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Key? actionKey;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    return Semantics(
      button: true,
      label: title,
      child: InkWell(
        key: actionKey,
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.md)),
        child: Container(
          padding: const EdgeInsets.all(CoolSpace.x4),
          decoration: BoxDecoration(
            gradient: isPrimary ? colors.accentGradient : null,
            color: isPrimary ? null : colors.cardSurface,
            borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.md)),
            border: Border.all(
              color: isPrimary ? colors.accent : colors.borderStrong,
              width: 1.1,
            ),
            boxShadow: isPrimary
                ? CoolShadows.floating(brightness, strength: 0.52)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: CoolTapTargets.minimum,
                height: CoolTapTargets.minimum,
                decoration: BoxDecoration(
                  color: isPrimary
                      ? colors.glassSurface
                      : colors.cardSurfaceStrong,
                  borderRadius: const BorderRadius.all(
                    Radius.circular(CoolRadii.sm),
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 22,
                  color: isPrimary ? Colors.white : colors.primaryText,
                ),
              ),
              SizedBox(height: space.x3),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isPrimary ? Colors.white : colors.primaryText,
                ),
              ),
              SizedBox(height: space.x1 + space.x1 / 2),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: isPrimary
                      ? Colors.white.withValues(alpha: 0.78)
                      : colors.secondaryText,
                  height: 1.35,
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Text(
                    isPrimary ? 'Launch' : 'Open',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isPrimary ? Colors.white : colors.primaryText,
                    ),
                  ),
                  SizedBox(width: space.x1 + space.x1 / 2),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: isPrimary ? Colors.white : colors.primaryText,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MomoToolRow extends StatelessWidget {
  const MomoToolRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      hint: 'Open $title',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.sm)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: CoolSpace.x3),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.cardSurfaceStrong,
                    borderRadius: const BorderRadius.all(
                      Radius.circular(CoolRadii.xs),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 20, color: colors.primaryText),
                ),
                SizedBox(width: space.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.primaryText,
                        ),
                      ),
                      SizedBox(height: space.x1 / 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w400,
                          color: colors.secondaryText,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: space.x3),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: colors.tertiaryText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
