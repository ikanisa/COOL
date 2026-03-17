import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';


import '../../../core/theme/cool_palette.dart';

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
