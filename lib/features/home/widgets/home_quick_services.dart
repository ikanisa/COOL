import 'package:flutter/material.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';

// ═════════════════════════════════════════════════════════════════════
// QUICK ACTIONS  (4-icon row)
// ═════════════════════════════════════════════════════════════════════

class HomeQuickServices extends StatelessWidget {
  const HomeQuickServices({super.key});

  static const _items = [
    (
      icon: Icons.phone_android_rounded,
      label: 'MOMO',
      route: AppRoutes.momo,
    ),
    (
      icon: Icons.volunteer_activism_rounded,
      label: 'CONTRIBUTE',
      route: AppRoutes.contributionCircles,
    ),
    (icon: Icons.qr_code_2_rounded, label: 'SCAN', route: AppRoutes.scanner),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Column(
      children: [
        Row(
          children: [
            Text(
              'QUICK ACTIONS',
              style: context.coolText.mono(
                Theme.of(context).textTheme.labelSmall,
                fontWeight: FontWeight.w700,
                color: colors.secondaryText,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
        const SizedBox(height: CoolSpace.x4),

        // Icon row
        Row(
          children: [
            for (final (i, item) in _items.indexed)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: i == _items.length - 1 ? 0 : CoolSpace.x3,
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(CoolRadii.lg),
                    onTap: () => openQuickActionRoute(context, item.route),
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(CoolRadii.lg),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.10),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            item.icon,
                            color: colors.primaryText,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: CoolSpace.x2),
                        Text(
                          item.label,
                          textAlign: TextAlign.center,
                          style: context.coolText.mono(
                            Theme.of(context).textTheme.labelSmall,
                            fontWeight: FontWeight.w700,
                            color: colors.secondaryText,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
