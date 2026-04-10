import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_card.dart';

class ReferralBanner extends ConsumerWidget {
  const ReferralBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    final theme = Theme.of(context);
    const title = 'Share COOL & earn points';
    const subtitle = 'Invite friends & grow together';

    return CoolCard(
      variant: CoolCardVariant.glass,
      onTap: () => context.push(AppRoutes.referral),
      padding: EdgeInsets.zero,
      borderRadius: radii.lg,
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
            Text('🎁', style: context.coolText.display(null).copyWith(fontSize: 28)),
            SizedBox(width: space.x4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colors.primaryText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
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
