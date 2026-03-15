import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_brand_mark.dart';

/// Welcome / onboarding screen shown to first-time users.
///
/// Features a hero icon and two CTAs leading to the OTP flow.
/// Language is fixed to English (Rwanda market).
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({this.redirectPath, super.key});

  final String? redirectPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              children: [
                const SizedBox(height: 36),
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: AppColors.border),
                  ),
                  alignment: Alignment.center,
                  child: const CoolBrandMark(size: 68),
                ),
                const SizedBox(height: 28),
                Text(
                  'Welcome to Cool',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 300,
                  child: Text(
                    'Save, pay, and move in Rwanda.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.dmSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text2,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 48),
                CoolButton(
                  label: 'Get Started',
                  onTap: () => context.push(
                    AppRoutes.otpLocation(redirect: redirectPath),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
