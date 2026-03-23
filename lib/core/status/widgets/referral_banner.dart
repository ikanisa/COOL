import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_glass_card.dart';

class ReferralBanner extends StatelessWidget {
  const ReferralBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    final theme = Theme.of(context);

    return CoolGlassCard(
      onTap: () => context.push(AppRoutes.referral),
      padding: EdgeInsets.zero,
      borderRadius: radii.lg,
      opacity: 0.1,
      child: Container(
        padding: EdgeInsets.all(space.x5),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colors.accent.withValues(alpha: 0.4),
              colors.accent.withValues(alpha: 0.1),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Row(
          children: [
            const Text('🎁', style: TextStyle(fontSize: 28)),
            SizedBox(width: space.x4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Share Cool & Earn Tokens',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colors.primaryText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Invite friends & grow together',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: colors.accent, size: 28),
          ],
        ),
      ),
    );
  }
}
