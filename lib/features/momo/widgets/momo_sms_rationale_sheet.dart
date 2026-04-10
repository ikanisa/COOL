import 'package:flutter/material.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';

class MomoSmsRationaleSheet extends StatelessWidget {
  const MomoSmsRationaleSheet({
    required this.onAccept,
    required this.onDecline,
    super.key,
  });

  final VoidCallback onAccept;
  final VoidCallback onDecline;

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onAccept,
    required VoidCallback onDecline,
  }) {
    return showCoolBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          MomoSmsRationaleSheet(onAccept: onAccept, onDecline: onDecline),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(space.x5, space.x4, space.x5, space.x8),
      decoration: BoxDecoration(
        color: colors.elevatedBackground,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(CoolRadii.xl),
          topRight: Radius.circular(CoolRadii.xl),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.borderStrong,
                borderRadius: const BorderRadius.all(
                  Radius.circular(CoolRadii.pill),
                ),
              ),
            ),
          ),
          const SizedBox(height: CoolSpace.x6),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(CoolSpace.x3),
                decoration: BoxDecoration(
                  color: colors.accentGlow,
                  borderRadius: const BorderRadius.all(
                    Radius.circular(CoolRadii.md),
                  ),
                ),
                child: Icon(Icons.sms_rounded, color: colors.accent, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Sync your M-Money statements',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colors.primaryText,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x5),
          Text(
            'If you opt in',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: colors.secondaryText,
              height: 1.5,
            ),
          ),
          const SizedBox(height: CoolSpace.x6),
          _RationalePoint(
            icon: Icons.history_rounded,
            title: context.l10n.deepHistoricalSync,
            message:
                'First-time setup scans the past year for M-Money '
                'confirmations. Only matched payment messages are stored '
                'and synced.',
          ),
          const SizedBox(height: CoolSpace.x4),
          _RationalePoint(
            icon: Icons.security_rounded,
            title: context.l10n.privacyFocused,
            message:
                'Cool only reacts to approved M-Money sender IDs such '
                'as M-Money and MoMo. Matching payment confirmations are '
                'queued locally and synced securely. Other SMS stays on '
                'your device and is ignored by Cool.',
          ),
          const SizedBox(height: CoolSpace.x4),
          _RationalePoint(
            icon: Icons.sync_rounded,
            title: context.l10n.alwaysInSync,
            message:
                'Approved payment confirmations are stored for ledger '
                'history and matched to contributions, subscriptions, and '
                'partner transactions.',
          ),
          const SizedBox(height: CoolSpace.x7),
          Row(
            children: [
              Expanded(
                child: CoolButton(
                  label: context.l10n.maybeLater,
                  variant: CoolButtonVariant.secondary,
                  onTap: () {
                    Navigator.pop(context);
                    onDecline();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CoolButton(
                  label: context.l10n.allowAccess,
                  onTap: () {
                    Navigator.pop(context);
                    onAccept();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RationalePoint extends StatelessWidget {
  const _RationalePoint({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: colors.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: CoolSpace.x1),
              Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w400,
                  color: colors.secondaryText,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
