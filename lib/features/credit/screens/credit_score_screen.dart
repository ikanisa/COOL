import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../groups/providers/groups_provider.dart';
import '../../momo/models/momo_statement.dart';
import '../../momo/providers/momo_statement_providers.dart';

/// Simplified credit readiness screen.
///
/// Shows a two-item checklist:
///  1. Is the user a member of a savings group?
///  2. Has the user linked MoMo statements?
///
/// When both are checked, credit readiness is complete.
class CreditScoreScreen extends ConsumerWidget {
  const CreditScoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.coolPalette;
    final groups = ref.watch(groupsListProvider);
    final statementsAsync = ref.watch(
      momoStatementBundleProvider(const MomoStatementQuery()),
    );

    final hasSavingsGroup = groups.isNotEmpty;
    final hasMomoStatements = statementsAsync.valueOrNull != null &&
        (statementsAsync.valueOrNull!.walletEntries.isNotEmpty ||
            statementsAsync.valueOrNull!.savingsEntries.isNotEmpty);
    final allReady = hasSavingsGroup && hasMomoStatements;

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: Icon(Icons.arrow_back_rounded, color: palette.text),
        ),
        title: Text(
          'Credit',
          style: GoogleFonts.dmSans(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: palette.text,
          ),
        ),
        centerTitle: false,
      ),
      body: CoolScreenBackground(
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Status banner ──────────────────────────────
                _StatusBanner(allReady: allReady),
                const SizedBox(height: 20),

                // ── Checklist ─────────────────────────────────
                Text(
                  'Readiness checklist',
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                  ),
                ),
                const SizedBox(height: 12),
                _ChecklistItem(
                  checked: hasSavingsGroup,
                  icon: Icons.group_rounded,
                  title: 'Savings group',
                  subtitle: hasSavingsGroup
                      ? 'Member of ${groups.length} group${groups.length > 1 ? 's' : ''}'
                      : 'Join or create a savings group',
                  onTap: hasSavingsGroup
                      ? null
                      : () => context.go(AppRoutes.groups),
                ),
                const SizedBox(height: 10),
                _ChecklistItem(
                  checked: hasMomoStatements,
                  icon: Icons.receipt_long_rounded,
                  title: 'MoMo statements',
                  subtitle: hasMomoStatements
                      ? 'Statements linked'
                      : 'Link your mobile money activity',
                  onTap: hasMomoStatements
                      ? null
                      : () => context.push(AppRoutes.momo),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Status banner ─────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.allReady});

  final bool allReady;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final color = allReady ? AppColors.accent : AppColors.yellow;

    return CoolCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.14),
            ),
            child: Icon(
              allReady
                  ? Icons.check_circle_rounded
                  : Icons.hourglass_top_rounded,
              size: 22,
              color: color,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  allReady ? 'Credit ready' : 'Not ready yet',
                  style: GoogleFonts.dmSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: palette.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  allReady
                      ? 'You meet all requirements'
                      : 'Complete the checklist below',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: palette.text2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Checklist item ────────────────────────────────────────────────

class _ChecklistItem extends StatelessWidget {
  const _ChecklistItem({
    required this.checked,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final bool checked;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: checked
                ? AppColors.accent.withValues(alpha: 0.3)
                : palette.border,
          ),
        ),
        child: Row(
          children: [
            // Check circle
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: checked
                    ? AppColors.accent.withValues(alpha: 0.14)
                    : palette.surface2,
              ),
              child: Icon(
                checked ? Icons.check_rounded : icon,
                size: 18,
                color: checked ? AppColors.accent : palette.text3,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.dmSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: palette.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: checked ? AppColors.accent : palette.text3,
                    ),
                  ),
                ],
              ),
            ),
            if (!checked && onTap != null)
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: palette.text3,
              ),
          ],
        ),
      ),
    );
  }
}
