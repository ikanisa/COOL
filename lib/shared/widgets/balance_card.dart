import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';

/// A hero card showing the user's total balance with a gradient background,
/// a change indicator, and four quick-action buttons (Send, Request, MOMO,
/// Top Up).
class BalanceCard extends StatelessWidget {
  const BalanceCard({
    required this.amount,
    required this.currency,
    required this.changeAmount,
    super.key,
  });

  final int amount;
  final String currency;
  final int changeAmount;

  @override
  Widget build(BuildContext context) {
    final isPositiveChange = changeAmount >= 0;

    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // ── Radial accent glow (top-right) ────────────────────────
          Positioned(
            top: -30,
            right: -30,
            child: Container(
              width: 120,
              height: 120,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [AppColors.accentGlow, Colors.transparent],
                ),
              ),
            ),
          ),

          // ── Content ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Label
                Text(
                  'Total Balance',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text2,
                  ),
                ),
                const SizedBox(height: 6),

                // Amount
                Semantics(
                  label: 'Total balance: ${_formatAmount(amount)} $currency',
                  child: Text(
                    '${_formatAmount(amount)} $currency',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmMono(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // Change indicator
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accentGlow,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isPositiveChange
                                ? Icons.arrow_upward_rounded
                                : Icons.arrow_downward_rounded,
                            size: 12,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${_formatAmount(changeAmount)} $currency',
                            style: GoogleFonts.dmMono(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                // Action buttons row
                const Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    _ActionButton(icon: Icons.upload_rounded, label: 'Send'),
                    _ActionButton(
                      icon: Icons.download_rounded,
                      label: 'Request',
                    ),
                    _ActionButton(
                      icon: Icons.phone_android_rounded,
                      label: 'MOMO',
                    ),
                    _ActionButton(
                      icon: Icons.account_balance_wallet_rounded,
                      label: 'Top Up',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatAmount(int value) {
    final s = value.abs().toString();
    final buf = StringBuffer();
    if (value < 0) buf.write('-');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

// ── Action button ───────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        button: true,
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.surface3,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              alignment: Alignment.center,
              child: ExcludeSemantics(
                child: Icon(icon, size: 20, color: AppColors.text2),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.text2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
