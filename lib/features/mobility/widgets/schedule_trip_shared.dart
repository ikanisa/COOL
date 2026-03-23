import 'package:flutter/material.dart';

import '../../../core/theme/cool_foundations.dart';

/// Small label above form fields.
class ScheduleTripFieldLabel extends StatelessWidget {
  const ScheduleTripFieldLabel({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return Text(
      label,
      style: theme.textTheme.labelMedium?.copyWith(
        color: colors.secondaryText,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// Responsive pair of fields — vertical on narrow screens, horizontal on wide.
class ScheduleTripAdaptiveFieldPair extends StatelessWidget {
  const ScheduleTripAdaptiveFieldPair({
    required this.first,
    required this.second,
    super.key,
  });

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 420) {
          return Column(children: [first, const SizedBox(height: 12), second]);
        }

        return Row(
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

/// Date/time picker field with a dropdown arrow.
class ScheduleTripPickerField extends StatelessWidget {
  const ScheduleTripPickerField({
    required this.prefix,
    required this.value,
    required this.onTap,
    super.key,
  });

  final String prefix;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return Material(
      color: colors.inputSurface,
      borderRadius: BorderRadius.circular(CoolRadii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CoolRadii.md),
        child: Container(
          constraints: const BoxConstraints(minHeight: CoolTapTargets.minimum),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CoolRadii.md),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Text(
                prefix,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colors.secondaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: colors.tertiaryText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Toggle card with an icon, title, subtitle and a switch.
class ScheduleTripToggleCard extends StatelessWidget {
  const ScheduleTripToggleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return Material(
      color: colors.cardSurfaceStrong,
      borderRadius: BorderRadius.circular(CoolRadii.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(CoolRadii.lg),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: colors.secondaryText),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colors.primaryText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.secondaryText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              activeTrackColor: colors.accent,
              activeThumbColor: Theme.of(context).colorScheme.onPrimary,
              inactiveTrackColor: colors.chipBackground,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

/// Rounded chip for vehicle preference selection.
class ScheduleTripSelectionChip extends StatelessWidget {
  const ScheduleTripSelectionChip({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return Material(
      color: selected ? colors.chipSelectedBackground : colors.chipBackground,
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          constraints: const BoxConstraints(minHeight: CoolTapTargets.minimum),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: selected ? colors.accent : colors.border),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: selected ? colors.primaryText : colors.secondaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

/// Vehicle selection chip with an optional vehicle image asset.
class ScheduleTripVehicleChip extends StatelessWidget {
  const ScheduleTripVehicleChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.assetPath,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? assetPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return Material(
      color: selected ? colors.chipSelectedBackground : colors.chipBackground,
      borderRadius: BorderRadius.circular(CoolRadii.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CoolRadii.lg),
        child: Container(
          width: 92,
          constraints: const BoxConstraints(minHeight: 96),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CoolRadii.lg),
            border: Border.all(
              color: selected ? colors.accent : colors.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (assetPath != null)
                Image.asset(
                  assetPath!,
                  width: 36,
                  height: 36,
                  fit: BoxFit.contain,
                )
              else
                Icon(
                  Icons.commute_rounded,
                  size: 32,
                  color: selected ? colors.accent : colors.tertiaryText,
                ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selected ? colors.primaryText : colors.secondaryText,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Square chip for seat count selection.
class ScheduleTripSeatChip extends StatelessWidget {
  const ScheduleTripSeatChip({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return Material(
      color: selected ? colors.chipSelectedBackground : colors.chipBackground,
      borderRadius: BorderRadius.circular(CoolRadii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CoolRadii.md),
        child: Container(
          width: 56,
          height: CoolTapTargets.minimum,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CoolRadii.md),
            border: Border.all(color: selected ? colors.accent : colors.border),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: selected ? colors.primaryText : colors.secondaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

/// Small chip for weekday selection (recurring trips).
class ScheduleTripDayChip extends StatelessWidget {
  const ScheduleTripDayChip({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return Material(
      color: selected ? colors.chipSelectedBackground : colors.chipBackground,
      borderRadius: BorderRadius.circular(CoolRadii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CoolRadii.md),
        child: Container(
          width: CoolTapTargets.minimum,
          height: CoolTapTargets.minimum,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CoolRadii.md),
            border: Border.all(color: selected ? colors.accent : colors.border),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: selected ? colors.primaryText : colors.tertiaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
