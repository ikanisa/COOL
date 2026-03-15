import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_button.dart';

/// Shared step enum used across schedule-trip widget files.
enum ScheduleTripStep { route, timing, options, review }

/// Accent-tinted info banner with a lightbulb icon.
class ScheduleTripInfoBanner extends StatelessWidget {
  const ScheduleTripInfoBanner({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.accentGlow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lightbulb_outline_rounded,
            size: 18,
            color: palette.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: palette.accent,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal 4-step indicator for the schedule-trip wizard.
class ScheduleTripStepper extends StatelessWidget {
  const ScheduleTripStepper({required this.activeStep, super.key});

  final ScheduleTripStep activeStep;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    const labels = <String>['Route', 'Time', 'Options', 'Review'];
    final activeIndex = ScheduleTripStep.values.indexOf(activeStep);

    return Row(
      children: List<Widget>.generate(labels.length, (index) {
        final isActive = index == activeIndex;
        final isComplete = index < activeIndex;

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index == labels.length - 1 ? 0 : 8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: isActive
                    ? palette.accentGlow
                    : isComplete
                    ? palette.surface2
                    : palette.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isActive
                      ? palette.accent
                      : isComplete
                      ? palette.border2
                      : palette.border,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    '${index + 1}',
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isActive
                          ? palette.accent
                          : isComplete
                          ? palette.text
                          : palette.text3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    labels[index],
                    textAlign: TextAlign.center,
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isActive ? palette.text : palette.text2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Back / Continue action bar shared across all wizard steps.
class ScheduleTripStepActionBar extends StatelessWidget {
  const ScheduleTripStepActionBar({
    required this.primaryLabel,
    required this.onPrimary,
    this.showBack = false,
    this.onBack,
    this.isPrimaryLoading = false,
    super.key,
  }) : assert(!showBack || onBack != null);

  final String primaryLabel;
  final VoidCallback onPrimary;
  final bool showBack;
  final VoidCallback? onBack;
  final bool isPrimaryLoading;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showBack) ...[
          Expanded(
            child: CoolButton(
              label: 'Back',
              variant: CoolButtonVariant.secondary,
              onTap: onBack!,
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: CoolButton(
            label: primaryLabel,
            onTap: onPrimary,
            isLoading: isPrimaryLoading,
          ),
        ),
      ],
    );
  }
}

/// Small label above form fields.
class ScheduleTripFieldLabel extends StatelessWidget {
  const ScheduleTripFieldLabel({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Text(
      label,
      style: GoogleFonts.dmSans(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: palette.text2,
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
    final palette = context.coolPalette;
    return Material(
      color: palette.surface2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              Text(prefix, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value,
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: palette.text,
                  ),
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: palette.text3,
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
    final palette = context.coolPalette;
    return Material(
      color: palette.surface3,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: palette.text2),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: palette.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: palette.text2,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              activeTrackColor: palette.accent,
              activeThumbColor: Theme.of(context).colorScheme.onPrimary,
              inactiveTrackColor: palette.surface2,
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
    final palette = context.coolPalette;
    return Material(
      color: selected ? palette.accentGlow : palette.surface2,
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: selected ? palette.accent : palette.border,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? palette.accent : palette.text2,
            ),
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
    final palette = context.coolPalette;
    return Material(
      color: selected ? palette.accentGlow : palette.surface2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 52,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? palette.accent : palette.border,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.dmMono(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: selected ? palette.accent : palette.text2,
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
    final palette = context.coolPalette;
    return Material(
      color: selected ? palette.accentGlow : palette.surface2,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 44,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? palette.accent : palette.border,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? palette.accent : palette.text3,
            ),
          ),
        ),
      ),
    );
  }
}
