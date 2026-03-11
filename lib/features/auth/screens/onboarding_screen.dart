import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/l10n/locale_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_brand_mark.dart';

/// Welcome / onboarding screen shown to first-time users.
///
/// Features a hero icon, a language selector that persists in Hive,
/// and two CTAs leading to the OTP flow.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({this.redirectPath, super.key});

  final String? redirectPath;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  String get _selectedLang => ref.watch(localeProvider).languageCode;

  Future<void> _selectLang(String code) async {
    await ref.read(localeProvider.notifier).setLocale(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          // ── Radial glow top ─────────────────────────────────────
          Positioned(
            top: -80,
            left: 0,
            right: 0,
            child: Container(
              height: 300,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 0.9,
                  colors: [
                    AppColors.accent.withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ── Content ─────────────────────────────────────────────
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  children: [
                    const SizedBox(height: 80),

                    // ── Icon ─────────────────────────────────────
                    Container(
                      width: 116,
                      height: 116,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(32),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.blueGlow.withValues(alpha: 0.34),
                            AppColors.accentGlow.withValues(alpha: 0.5),
                          ],
                        ),
                        border: Border.all(color: AppColors.border2),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.blueGlow.withValues(alpha: 0.2),
                            blurRadius: 28,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const CoolBrandMark(size: 84),
                    ),
                    const SizedBox(height: 32),

                    // ── Title ────────────────────────────────────
                    RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: GoogleFonts.dmSans(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                          height: 1.2,
                        ),
                        children: const [
                          TextSpan(text: 'Welcome to\n'),
                          TextSpan(
                            text: 'Cool',
                            style: TextStyle(color: AppColors.blue),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── Subtitle ─────────────────────────────────
                    SizedBox(
                      width: 280,
                      child: Text(
                        'Community savings, group funds & mobility '
                        '— all in one simple app',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.dmSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: AppColors.text2,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),

                    // ── Language selector ────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _LangButton(
                          flag: '🇬🇧',
                          label: 'English',
                          isSelected: _selectedLang == 'en',
                          onTap: () => _selectLang('en'),
                        ),
                        const SizedBox(width: 12),
                        _LangButton(
                          flag: '🇫🇷',
                          label: 'Français',
                          isSelected: _selectedLang == 'fr',
                          onTap: () => _selectLang('fr'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 48),

                    // ── CTAs ─────────────────────────────────────
                    CoolButton(
                      label: 'Get Started',
                      onTap: () => context.push(
                        AppRoutes.otpLocation(redirect: widget.redirectPath),
                      ),
                    ),
                    const SizedBox(height: 12),
                    CoolButton(
                      label: 'Already have an account? Sign In',
                      variant: CoolButtonVariant.secondary,
                      onTap: () => context.push(
                        AppRoutes.otpLocation(redirect: widget.redirectPath),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ── Footer ───────────────────────────────────
                    Text(
                      '🔒 Secured · MOMO Powered · No bank card needed',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: AppColors.text3,
                      ),
                    ),
                    const SizedBox(height: 80), // bottom padding for nav
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Language button ─────────────────────────────────────────────────────

class _LangButton extends StatelessWidget {
  const _LangButton({
    required this.flag,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String flag;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accentGlow : AppColors.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(flag, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isSelected ? AppColors.accent : AppColors.text2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
