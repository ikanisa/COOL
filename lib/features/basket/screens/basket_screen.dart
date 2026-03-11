import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';

/// Basket route placeholder.
///
/// This route stays reachable for deep links, but it no longer pretends that
/// basket balances or basket types are live.
class BasketScreen extends StatelessWidget {
  const BasketScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(
          'Baskets',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
      ),
      body: CoolScreenBackground(
        primaryColor: AppColors.purple,
        secondaryColor: AppColors.accent,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 96),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Baskets are not live yet',
                style: GoogleFonts.dmSans(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This route is kept for navigation and deep-link compatibility, but basket balances and basket categories are not connected to live data in this build.',
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text2,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              CoolCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.purple.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            '🧺',
                            style: TextStyle(fontSize: 22),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Basket creation, balances, and goals will appear here once the savings backend is wired.',
                            style: GoogleFonts.dmSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const _BasketExpectationRow(
                      icon: Icons.account_balance_wallet_outlined,
                      text: 'No live basket totals are shown on this screen.',
                    ),
                    const SizedBox(height: 10),
                    const _BasketExpectationRow(
                      icon: Icons.add_chart_rounded,
                      text:
                          'New basket creation is intentionally disabled until persistence is ready.',
                    ),
                    const SizedBox(height: 10),
                    const _BasketExpectationRow(
                      icon: Icons.link_rounded,
                      text:
                          'The route remains active so existing links do not break.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: CoolButton(
                      label: 'Back Home',
                      onTap: () => context.go('/home'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CoolButton(
                      label: 'Close',
                      variant: CoolButtonVariant.secondary,
                      onTap: () => context.pop(),
                    ),
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

class _BasketExpectationRow extends StatelessWidget {
  const _BasketExpectationRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.text3),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
