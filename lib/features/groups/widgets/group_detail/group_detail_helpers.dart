import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface2.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.text2),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.text2,
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'More actions',
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Keep sharing and invite',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AppColors.text2,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              CoolButton(
                label: 'Share / QR',
                variant: CoolButtonVariant.secondary,
                onTap: onShare,
              ),
              const SizedBox(height: 12),
              CoolButton(
                label: context.l10n.inviteFromContacts,
                variant: CoolButtonVariant.secondary,
                onTap: onInvite,
              ),
            ],
          ),
        ),
      ),
    );
  }
}