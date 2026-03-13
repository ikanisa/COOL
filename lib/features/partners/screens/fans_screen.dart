import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../widgets/partner_navigation.dart';

/// Generic fan hub placeholder for partners that do not have a live module yet.
class FansScreen extends StatelessWidget {
  const FansScreen({super.key, required this.partnerId});

  final String partnerId;

  String get _clubName {
    // Derive a readable title from the slug (e.g. 'apr-fc' → 'Apr Fc')
    // without maintaining a hardcoded lookup table.
    if (partnerId.isEmpty) return 'Partner Club';
    return partnerId
        .split('-')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final hasDedicatedHub = partnerId == 'rayon-sports';

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        leading: buildPartnerBackButton(
          context,
          fallbackLocation: AppRoutes.partners,
        ),
        title: Text(
          _clubName,
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        actions: buildPartnerAppBarActions(context, homeColor: AppColors.text),
      ),
      body: CoolScreenBackground(
        primaryColor: AppColors.yellow,
        secondaryColor: AppColors.orange,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 96),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Fan hub not live yet',
                style: GoogleFonts.dmSans(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'The fan module for $_clubName is not live yet.',
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
                    Text(
                      'Currently unavailable',
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _FansExpectationRow(
                      icon: Icons.badge_outlined,
                      text: 'Membership card and stats not available.',
                    ),
                    const SizedBox(height: 10),
                    _FansExpectationRow(
                      icon: Icons.groups_outlined,
                      text: 'Fan clubs and directory disabled.',
                    ),
                    const SizedBox(height: 10),
                    _FansExpectationRow(
                      icon: Icons.route_outlined,
                      text: hasDedicatedHub
                          ? 'Rayon Sports has a dedicated hub.'
                          : 'Route kept reachable for partner links.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: CoolButton(
                      label: 'Back to Partners',
                      onTap: () => context.go(AppRoutes.partners),
                    ),
                  ),
                  if (hasDedicatedHub) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: CoolButton(
                        label: 'Open Rayon',
                        variant: CoolButtonVariant.secondary,
                        onTap: () => context.go(AppRoutes.rayonHome),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FansExpectationRow extends StatelessWidget {
  const _FansExpectationRow({required this.icon, required this.text});

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
