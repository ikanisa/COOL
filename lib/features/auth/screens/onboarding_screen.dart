import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/brand/app_brand.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_brand_mark.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/widgets/cool_screen_background.dart';

/// Welcome / onboarding screen shown to first-time users.
///
/// Features a hero icon and two CTAs leading to the OTP flow.
/// Language is fixed to English (Rwanda market).
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({this.redirectPath, super.key});

  final String? redirectPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = ref.watch(appBrandProvider);
    final colors = context.coolSemanticColors;
    final radii = context.coolRadii;
    final space = context.coolSpace;
    final theme = Theme.of(context);

    return CoolScreenBackground(
      showGlow: true,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              space.x6,
              space.x8,
              space.x6,
              space.x10,
            ),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                children: [
                  SizedBox(height: space.x9),
                  SizedBox(
                    width: 96,
                    height: 96,
                    child: CoolCard(
                      useGradient: false,
                      backgroundColor: colors.cardSurface,
                      borderRadius: radii.xl,
                      padding: EdgeInsets.zero,
                      child: const Center(child: CoolBrandMark(size: 68)),
                    ),
                  ),
                  SizedBox(height: space.x7),
                  Text(
                    brand.welcomeTitle,
                    textAlign: TextAlign.center,
                    style: brand.isRayonDominant
                        ? context.coolText.rayonCondensed(
                            theme.textTheme.displaySmall,
                            fontWeight: FontWeight.w900,
                            color: colors.primaryText,
                            height: 1.0,
                          )
                        : theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: colors.primaryText,
                            height: 1.1,
                          ),
                  ),
                  SizedBox(height: space.x4),
                  SizedBox(
                    width: 300,
                    child: Text(
                      brand.welcomeSubtitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colors.secondaryText,
                        height: 1.4,
                      ),
                    ),
                  ),
                  SizedBox(height: space.x12),
                  CoolButton(
                    label: context.l10n.getStarted,
                    onTap: () => context.push(
                      AppRoutes.otpLocation(redirect: redirectPath),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
