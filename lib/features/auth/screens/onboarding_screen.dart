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
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 300,
                  child: Text(
                    'Save, pay, and move — together.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.dmSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: AppColors.text2,
                      height: 1.45,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _LangButton(
                      flag: '🇬🇧',
                      label: 'English',
                      isSelected: _selectedLang == 'en',
                      onTap: () => _selectLang('en'),
                    ),
                    _LangButton(
                      flag: '🇫🇷',
                      label: 'Français',
                      isSelected: _selectedLang == 'fr',
                      onTap: () => _selectLang('fr'),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                CoolButton(
                  label: 'Continue',
                  onTap: () => context.push(
                    AppRoutes.otpLocation(redirect: widget.redirectPath),
                  ),
                ),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: () => context.push(
                    AppRoutes.otpLocation(redirect: widget.redirectPath),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Text(
                      'I already have an account',
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text2,
                      ),
                    ),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accentGlow : AppColors.surface2,
          borderRadius: BorderRadius.circular(999),
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
