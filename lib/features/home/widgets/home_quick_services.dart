import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/rs_colors.dart';

// ═════════════════════════════════════════════════════════════════════
// QUICK SERVICES  (4-icon row)
// ═════════════════════════════════════════════════════════════════════

class HomeQuickServices extends StatelessWidget {
  const HomeQuickServices({super.key});

  static const _items = [
    (icon: Icons.groups_rounded, label: 'GROUPS', route: AppRoutes.groups),
    (icon: Icons.qr_code_2_rounded, label: 'SCAN', route: AppRoutes.scanner),
    (
      icon: Icons.face_retouching_natural_rounded,
      label: 'BIOPAY',
      route: AppRoutes.biopayHome,
    ),
    (
      icon: Icons.shopping_bag_rounded,
      label: 'SHOP',
      route: AppRoutes.rayonShop,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Column(
      children: [
        // QUICK SERVICES + VIEW ALL
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'QUICK SERVICES',
              style: context.coolText.mono(
                Theme.of(context).textTheme.labelSmall,
                fontWeight: FontWeight.w700,
                color: colors.secondaryText,
                letterSpacing: 1.0,
              ),
            ),
            GestureDetector(
              onTap: () => context.push(AppRoutes.partners),
              child: Text(
                'VIEW ALL',
                style: context.coolText.mono(
                  Theme.of(context).textTheme.labelSmall,
                  fontWeight: FontWeight.w700,
                  color: RsColors.rsBlue,
                  letterSpacing: 1.0,
                ),
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
