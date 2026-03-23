import 'package:flutter/material.dart';

import '../../../../core/theme/cool_foundations.dart';
import '../../../../shared/widgets/cool_button.dart';
import '../../../../core/l10n/l10n.dart';

// ═════════════════════════════════════════════════════════════════════════
// Shared formatters (moved from _GroupDetailScreenState)
// ═════════════════════════════════════════════════════════════════════════

/// Format an integer with comma separators (e.g. 5,000).
String groupFormatAmount(int value) {
  final s = value.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// Capitalise a frequency value (daily/weekly/monthly).
String groupFormatFrequency(String value) {
  switch (value.trim().toLowerCase()) {
    case 'daily':
      return 'Daily';
    case 'weekly':
      return 'Weekly';
    default:
      return 'Monthly';
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Hero info chip (inline in hero card)
// ═════════════════════════════════════════════════════════════════════════

class GroupHeroInfoChip extends StatelessWidget {
  const GroupHeroInfoChip({required this.icon, required this.label, super.key});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final radii = context.coolRadii;
    final space = context.coolSpace;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: space.x3, vertical: space.x2),
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong.withValues(alpha: 0.76),
        borderRadius: BorderRadius.all(Radius.circular(radii.sm)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colors.secondaryText),
          SizedBox(width: space.x2),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// More-actions sheet (Share / Invite from Contacts)
// ═════════════════════════════════════════════════════════════════════════

class GroupMoreActionsSheet extends StatelessWidget {
  const GroupMoreActionsSheet({
    required this.onShare,
    required this.onInvite,
    super.key,
  });

  final VoidCallback onShare;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final radii = context.coolRadii;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colors.borderStrong,
              borderRadius: BorderRadius.all(Radius.circular(radii.xs)),
            ),
          ),
        ),
        SizedBox(height: space.x5),
        Text(
          'More actions',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: colors.primaryText,
          ),
        ),
        SizedBox(height: space.x1 + space.x0),
        Text(
          'Share this group or invite members directly.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.secondaryText,
            height: 1.45,
          ),
        ),
        SizedBox(height: space.x5),
        CoolButton(
          label: 'Share / QR',
          variant: CoolButtonVariant.secondary,
          onTap: onShare,
        ),
        SizedBox(height: space.x3),
        CoolButton(
          label: context.l10n.inviteFromContacts,
          variant: CoolButtonVariant.secondary,
          onTap: onInvite,
        ),
      ],
    );
  }
}
