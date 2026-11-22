import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/collect_theme_controller.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

import 'settings_subpage_widgets.dart';

class AppearanceSettingsScreen extends ConsumerWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(collectThemeModeProvider);
    return ScreenScaffold(
      title: 'Appearance',
      showHeader: false,
      compact: true,
      topChrome: const SettingsSubpageHeader(title: 'Appearance'),
      children: [
        _AppearancePreview(mode: mode),
        const SectionHeader(title: 'Mode'),
        LayoutBuilder(
          builder: (context, constraints) {
            final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
            final choices = [
              _AppearanceModeChoice(
                label: 'Dark',
                icon: Icons.dark_mode_rounded,
                selected: mode == ThemeMode.dark,
                onTap: () => unawaited(
                  ref
                      .read(collectThemeModeProvider.notifier)
                      .setMode(ThemeMode.dark),
                ),
              ),
              _AppearanceModeChoice(
                label: 'Light',
                icon: Icons.light_mode_rounded,
                selected: mode == ThemeMode.light,
                onTap: () => unawaited(
                  ref
                      .read(collectThemeModeProvider.notifier)
                      .setMode(ThemeMode.light),
                ),
              ),
              _AppearanceModeChoice(
                label: 'System',
                icon: Icons.devices_rounded,
                selected: mode == ThemeMode.system,
                onTap: () => unawaited(
                  ref
                      .read(collectThemeModeProvider.notifier)
                      .setMode(ThemeMode.system),
                ),
              ),
            ];
            if (constraints.maxWidth < 330 || largeText) {
              return Column(
                children: [
                  for (final choice in choices) ...[
                    choice,
                    if (choice != choices.last) CollectSpacing.gap12,
                  ],
                ],
              );
            }
            return Row(
              children: List.generate(choices.length * 2 - 1, (index) {
                if (index.isOdd) return CollectSpacing.gapW12;
                return Expanded(child: choices[index ~/ 2]);
              }),
            );
          },
        ),
      ],
    );
  }
}

class _AppearancePreview extends StatelessWidget {
  const _AppearancePreview({required this.mode});

  final ThemeMode mode;

  @override
  Widget build(BuildContext context) {
    final effectiveBrightness = switch (mode) {
      ThemeMode.dark => Brightness.dark,
      ThemeMode.light => Brightness.light,
      ThemeMode.system => Theme.of(context).brightness,
    };
    final previewColors = effectiveBrightness == Brightness.dark
        ? CollectColors.dark
        : CollectColors.light;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      container: true,
      image: true,
      label: '${_appearanceModeLabel(mode)} Collect home preview',
      child: ExcludeSemantics(
        child: MediaQuery.withNoTextScaling(
          child: Container(
            key: const ValueKey('appearance-live-preview'),
            height: 356,
            padding: const EdgeInsets.all(CollectSpacing.x4),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: previewColors.canvas,
              gradient: CollectRuntimeTokens.overviewBackdrop(
                previewColors,
                effectiveBrightness,
                CollectBackdropTone.account,
                highContrast: MediaQuery.highContrastOf(context),
              ),
              borderRadius: CollectRadius.cardLargeBorder,
              border: Border.all(color: previewColors.border),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      padding: const EdgeInsets.all(CollectSpacing.x1),
                      decoration: BoxDecoration(
                        color: CollectRuntimeTokens.chromeControl(
                          previewColors,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Image.asset(
                        CollectRuntimeAssets.officialLogo,
                        fit: BoxFit.contain,
                      ),
                    ),
                    CollectSpacing.gapW8,
                    Expanded(
                      child: Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(
                          horizontal: CollectSpacing.x3,
                        ),
                        decoration: BoxDecoration(
                          color: CollectRuntimeTokens.chromeControl(
                            previewColors,
                          ),
                          borderRadius: CollectRadius.pillBorder,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              CollectIcons.search,
                              size: 14,
                              color: previewColors.textSecondary,
                            ),
                            CollectSpacing.gapW4,
                            Text(
                              'Search',
                              style: textTheme.labelSmall?.copyWith(
                                color: previewColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                CollectSpacing.gap20,
                Text(
                  'RWF 35,000',
                  style: textTheme.headlineMedium?.copyWith(
                    color: previewColors.textPrimary,
                    fontWeight: CollectTypography.weightSemibold,
                  ),
                ),
                CollectSpacing.gap16,
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Expanded(
                      child: _AppearancePreviewAction(
                        icon: CollectIcons.donate,
                        label: 'Contribute',
                        colors: previewColors,
                      ),
                    ),
                    Expanded(
                      child: _AppearancePreviewAction(
                        icon: CollectIcons.people,
                        label: 'Explore Groups',
                        colors: previewColors,
                      ),
                    ),
                    Expanded(
                      child: _AppearancePreviewAction(
                        icon: CollectIcons.share,
                        label: 'Share',
                        colors: previewColors,
                      ),
                    ),
                  ],
                ),
                CollectSpacing.gap16,
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(CollectSpacing.x3),
                    decoration: BoxDecoration(
                      color: CollectRuntimeTokens.cardBackground(
                        previewColors,
                        effectiveBrightness,
                        CollectRuntimeCardEmphasis.normal,
                        null,
                        tone: CollectBackdropTone.account,
                        highContrast: MediaQuery.highContrastOf(context),
                      ),
                      borderRadius: CollectRadius.cardBorder,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Activity',
                          style: textTheme.titleSmall?.copyWith(
                            color: previewColors.textPrimary,
                            fontWeight: CollectTypography.weightBold,
                          ),
                        ),
                        const Spacer(),
                        _AppearancePreviewLedgerRow(
                          amount: 'RWF 10,000',
                          colors: previewColors,
                        ),
                        Divider(color: previewColors.borderSoft, height: 12),
                        _AppearancePreviewLedgerRow(
                          amount: 'RWF 25,000',
                          colors: previewColors,
                        ),
                      ],
                    ),
                  ),
                ),
                CollectSpacing.gap12,
                Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(
                    horizontal: CollectSpacing.x3,
                  ),
                  decoration: BoxDecoration(
                    color: CollectColors.referenceChromeBlack,
                    borderRadius: CollectRadius.pillBorder,
                    border: Border.all(
                      color: CollectRuntimeTokens.navigationForeground
                          .withValues(alpha: 0.36),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      for (final icon in const [
                        CollectIcons.home,
                        CollectIcons.people,
                        CollectIcons.activity,
                        CollectIcons.profile,
                      ])
                        Container(
                          width: 40,
                          height: 30,
                          decoration: BoxDecoration(
                            color: icon == CollectIcons.home
                                ? CollectRuntimeTokens.navigationForeground
                                      .withValues(alpha: 0.14)
                                : previewColors.transparent,
                            borderRadius: CollectRadius.pillBorder,
                          ),
                          child: Icon(
                            icon,
                            size: 16,
                            color: CollectRuntimeTokens.navigationForeground
                                .withValues(
                                  alpha: icon == CollectIcons.home ? 1 : 0.72,
                                ),
                          ),
                        ),
                    ],
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

class _AppearancePreviewCircle extends StatelessWidget {
  const _AppearancePreviewCircle({required this.icon, required this.colors});

  final IconData icon;
  final CollectColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: CollectRuntimeTokens.quickActionFill(colors),
        border: Border.all(
          color: CollectRuntimeTokens.chromeControlBorder(colors),
        ),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 16, color: colors.textPrimary),
    );
  }
}

class _AppearancePreviewAction extends StatelessWidget {
  const _AppearancePreviewAction({
    required this.icon,
    required this.label,
    required this.colors,
  });

  final IconData icon;
  final String label;
  final CollectColors colors;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        _AppearancePreviewCircle(icon: icon, colors: colors),
        CollectSpacing.gap4,
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: textTheme.labelSmall?.copyWith(color: colors.textSecondary),
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}

class _AppearancePreviewLedgerRow extends StatelessWidget {
  const _AppearancePreviewLedgerRow({
    required this.amount,
    required this.colors,
  });

  final String amount;
  final CollectColors colors;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(CollectIcons.check, size: 14, color: colors.success),
        CollectSpacing.gapW8,
        Expanded(
          child: Text(
            '038491',
            style: textTheme.labelSmall?.copyWith(color: colors.textPrimary),
          ),
        ),
        Text(
          amount,
          style: textTheme.labelSmall?.copyWith(
            color: colors.textPrimary,
            fontWeight: CollectTypography.weightBold,
          ),
        ),
      ],
    );
  }
}

class _AppearanceModeChoice extends StatelessWidget {
  const _AppearanceModeChoice({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label mode',
      child: InkWell(
        onTap: onTap,
        borderRadius: CollectRadius.cardBorder,
        child: AnimatedContainer(
          duration: CollectMotion.duration(context, CollectMotion.medium),
          constraints: const BoxConstraints(minHeight: CollectSpacing.target),
          padding: const EdgeInsets.symmetric(
            horizontal: CollectSpacing.x2,
            vertical: CollectSpacing.x3,
          ),
          decoration: BoxDecoration(
            color: selected ? colors.infoContainer : colors.surfaceReadable,
            borderRadius: CollectRadius.cardBorder,
            border: Border.all(
              color: selected ? colors.focusRing : colors.borderSoft,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: selected ? colors.info : colors.textSecondary,
                size: 20,
              ),
              CollectSpacing.gapW4,
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: selected
                        ? CollectTypography.weightBold
                        : CollectTypography.weightMedium,
                  ),
                ),
              ),
              if (selected)
                Icon(CollectIcons.check, color: colors.success, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

String _appearanceModeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.dark => 'Dark',
  ThemeMode.light => 'Light',
  ThemeMode.system => 'System',
};
