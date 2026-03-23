import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/cool_foundations.dart';
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final currentPreference = ref.watch(themePreferenceProvider);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.overlaySurface,
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
                    color: colors.borderStrong,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Appearance',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.primaryText,
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.chipSelectedBackground
              : colors.cardSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? colors.accent : colors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isSelected
                    ? colors.cardSurfaceStrong
                    : colors.operationalSurface,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                color: isSelected ? colors.accent : colors.primaryText,
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.primaryText,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: colors.accent, size: 24),
          ],
        ),
      ),
    );
  }
}
