import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/cool_palette.dart';
import '../../../core/theme/theme_preference.dart';
import '../../../core/theme/theme_preference_provider.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';

class ProfileThemeSheet extends ConsumerWidget {
  const ProfileThemeSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showCoolBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const ProfileThemeSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.coolPalette;
    final currentPreference = ref.watch(themePreferenceProvider);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.border2,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Appearance',
                style: GoogleFonts.dmSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: palette.text,
                ),
              ),
              const SizedBox(height: 20),
              _ThemeOptionCard(
                preference: AppThemePreference.system,
                title: context.l10n.systemDefault,
                icon: Icons.brightness_auto_rounded,
                isSelected: currentPreference == AppThemePreference.system,
                onTap: () => _setTheme(ref, AppThemePreference.system),
              ),
              const SizedBox(height: 12),
              _ThemeOptionCard(
                preference: AppThemePreference.light,
                title: context.l10n.lightMode,
                icon: Icons.light_mode_rounded,
                isSelected: currentPreference == AppThemePreference.light,
                onTap: () => _setTheme(ref, AppThemePreference.light),
              ),
              const SizedBox(height: 12),
              _ThemeOptionCard(
                preference: AppThemePreference.dark,
                title: context.l10n.darkMode,
                icon: Icons.dark_mode_rounded,
                isSelected: currentPreference == AppThemePreference.dark,
                onTap: () => _setTheme(ref, AppThemePreference.dark),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setTheme(WidgetRef ref, AppThemePreference preference) {
    ref.read(themePreferenceProvider.notifier).setPreference(preference);
  }
}

class _ThemeOptionCard extends StatelessWidget {
  const _ThemeOptionCard({
    required this.preference,
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final AppThemePreference preference;
  final String title;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? palette.accentGlow : palette.surface2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? palette.accent : palette.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isSelected ? palette.surface : palette.surface3,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                color: isSelected ? palette.accent : palette.text,
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.dmSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: palette.text,
                ),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle_rounded,
                color: palette.accent,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }
}