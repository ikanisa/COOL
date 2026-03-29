import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';

/// ROUGEBLACK navigation helpers — shared across Rayon feature screens.
///
/// Provides consistent back button and app bar action styling for
/// screens using [CoreAppScaffold], [RsAdminShell], and standalone screens.

/// Builds a glass-circle back button that pops or navigates to [fallbackLocation].
Widget buildPartnerBackButton(
  BuildContext context, {
  String fallbackLocation = AppRoutes.rayonHome,
  Color? color,
}) {
  final chromeColor = color ?? context.coolSemanticColors.accentForeground;

  return Padding(
    padding: const EdgeInsets.only(left: 8),
    child: Center(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(CoolRadii.pill),
          onTap: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(fallbackLocation);
            }
          },
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.arrow_back_rounded,
              color: chromeColor,
              size: 20,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Builds app bar trailing actions: optional custom [actions] + home button.
List<Widget> buildPartnerAppBarActions(
  BuildContext context, {
  List<Widget>? actions,
  bool showHomeButton = true,
  Color? homeColor,
}) {
  final chromeColor =
      homeColor ?? context.coolSemanticColors.accentForeground;

  return [
    if (actions != null) ...actions,
    if (showHomeButton) ...[
      Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(CoolRadii.pill),
          onTap: () => context.go(AppRoutes.rayonHome),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.home_rounded,
              color: chromeColor,
              size: 20,
            ),
          ),
        ),
      ),
      const SizedBox(width: 12),
    ],
  ];
}
