part of 'profile_settings_widgets.dart';

class ProfileAppearanceSheet extends StatelessWidget {
  const ProfileAppearanceSheet({
    required this.currentPreference,
    required this.onSelected,
    super.key,
  });

  final AppThemePreference currentPreference;
  final Future<void> Function(AppThemePreference preference) onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.appearanceLabel,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: CoolSpace.x4),
        CoolCard(
          backgroundColor: colors.cardSurfaceStrong,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (
                var index = 0;
                index < AppThemePreference.values.length;
                index++
              ) ...[
                _ProfileAppearanceOption(
                  preference: AppThemePreference.values[index],
                  isSelected:
                      AppThemePreference.values[index] == currentPreference,
                  onTap: () => onSelected(AppThemePreference.values[index]),
                ),
                if (index < AppThemePreference.values.length - 1)
                  const SizedBox(height: CoolSpace.x2),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileAppearanceOption extends StatelessWidget {
  const _ProfileAppearanceOption({
    required this.preference,
    required this.isSelected,
    required this.onTap,
  });

  final AppThemePreference preference;
  final bool isSelected;
  final VoidCallback onTap;

  String _label(BuildContext context) {
    final l10n = context.l10n;
    return switch (preference) {
      AppThemePreference.system => l10n.appearanceSystemLabel,
      AppThemePreference.dark => l10n.appearanceDarkLabel,
    };
  }

  IconData _icon() {
    return switch (preference) {
      AppThemePreference.system => CoolIcons.themeAuto,
      AppThemePreference.dark => CoolIcons.themeDark,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;

    return Semantics(
      button: true,
      selected: isSelected,
      label: _label(context),
      child: InkWell(
        onTap: onTap,
        splashColor: colors.accent.withValues(alpha: 0.08),
        highlightColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.cardSurface,
                  borderRadius: BorderRadius.circular(CoolRadii.xs),
                ),
                alignment: Alignment.center,
                child: Icon(_icon(), size: 20, color: colors.secondaryText),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  _label(context),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colors.primaryText,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                isSelected ? CoolIcons.selected : CoolIcons.unselected,
                color: isSelected ? colors.accent : colors.tertiaryText,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProfileCompleteProfileBanner extends StatelessWidget {
  const ProfileCompleteProfileBanner({required this.phone, super.key});

  final String phone;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final l10n = context.l10n;
    return Semantics(
      button: true,
      label: l10n.completeProfileTitle,
      hint: l10n.completeProfileTitle,
      child: GestureDetector(
        onTap: () => context.push(AppRoutes.profile),
        child: ExcludeSemantics(
          child: CoolCard(
            backgroundColor: colors.cardSurfaceStrong,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: colors.operationalSurface,
                      borderRadius: BorderRadius.circular(CoolRadii.md),
                      boxShadow: CoolShadows.floating(
                        Theme.of(context).brightness,
                        strength: 0.18,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      CoolIcons.profile,
                      color: colors.accent,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      l10n.completeProfileTitle,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colors.primaryText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    CoolIcons.chevron,
                    size: 16,
                    color: colors.tertiaryText,
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
