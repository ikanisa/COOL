import 'package:flutter/material.dart';

import '../../../core/theme/cool_foundations.dart';

// ═══════════════════════════════════════════════════════════════════════
// Shared form widgets used by GroupCreateScreen and GroupSettingsScreen.
// Extracted to eliminate duplication per Tactile Monolith audit.
// ═══════════════════════════════════════════════════════════════════════

/// Uppercase mono label used for form sections (e.g. "TYPE", "FREQUENCY").
class GroupSectionLabel extends StatelessWidget {
  const GroupSectionLabel({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: context.coolText.mobiLabel(
        color: context.coolSemanticColors.tertiaryText,
      ),
    );
  }
}

/// Two-option row (e.g. Saving / Community).
class GroupOptionRow extends StatelessWidget {
  const GroupOptionRow({
    required this.firstLabel,
    required this.firstSelected,
    required this.onFirstTap,
    required this.secondLabel,
    required this.secondSelected,
    required this.onSecondTap,
    super.key,
  });

  final String firstLabel;
  final bool firstSelected;
  final VoidCallback onFirstTap;
  final String secondLabel;
  final bool secondSelected;
  final VoidCallback onSecondTap;

  @override
  Widget build(BuildContext context) {
    final space = context.coolSpace;
    return Row(
      children: [
        Expanded(
          child: GroupOptionChip(
            label: firstLabel,
            selected: firstSelected,
            onTap: onFirstTap,
          ),
        ),
        SizedBox(width: space.x2),
        Expanded(
          child: GroupOptionChip(
            label: secondLabel,
            selected: secondSelected,
            onTap: onSecondTap,
          ),
        ),
      ],
    );
  }
}

/// Single selectable chip (used in frequency pickers and type toggles).
class GroupOptionChip extends StatelessWidget {
  const GroupOptionChip({
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
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CoolRadii.md),
      child: AnimatedContainer(
        duration: CoolMotion.quick,
        padding: const EdgeInsets.symmetric(vertical: CoolSpace.x3),
        decoration: BoxDecoration(
          color: selected ? colors.accent : colors.cardSurface,
          borderRadius: BorderRadius.circular(CoolRadii.md),
          boxShadow: selected ? null : CoolShadows.ambientFloat(strength: 0.2),
        ),
        alignment: Alignment.center,
        child: Text(
          label.toUpperCase(),
          style: text
              .mobiLabel(
                color: selected ? colors.accentForeground : colors.primaryText,
              )
              .copyWith(fontWeight: FontWeight.w800, letterSpacing: 1.0),
        ),
      ),
    );
  }
}

/// Row of option chips for frequency selection (daily/weekly/monthly/one_off).
class GroupFrequencyPicker extends StatelessWidget {
  const GroupFrequencyPicker({
    required this.options,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;

  String _label(String value) {
    return switch (value) {
      'daily' => 'Daily',
      'weekly' => 'Weekly',
      'monthly' => 'Monthly',
      'one_off' => 'One-Off',
      _ => value,
    };
  }

  @override
  Widget build(BuildContext context) {
    final space = context.coolSpace;
    return Row(
      children: options
          .map((option) {
            final isSelected = option == selected;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: option != options.last ? space.x2 : 0,
                ),
                child: GroupOptionChip(
                  label: _label(option),
                  selected: isSelected,
                  onTap: () => onSelected(option),
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

/// MoMo route segmented control tab (NUMBER / CODE).
class GroupSegmentTab extends StatelessWidget {
  const GroupSegmentTab({
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
    final colors = context.coolSemanticColors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: CoolMotion.quick,
        curve: Curves.easeOut,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? colors.cardSurfaceStrong : Colors.transparent,
          borderRadius: BorderRadius.circular(CoolRadii.xs),
          boxShadow: selected ? CoolShadows.ambientFloat(strength: 0.4) : null,
        ),
        child: Text(
          label,
          style: context.coolText.mono(
            Theme.of(context).textTheme.labelLarge,
            color: selected ? colors.accent : colors.secondaryText,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.2,
          ),
        ),
      ),
    );
  }
}
