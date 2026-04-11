import 'package:flutter/material.dart';

import '../../../core/config/country_catalog.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_card.dart';

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
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
              .copyWith(fontWeight: FontWeight.w700, letterSpacing: 1.0),
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

  String _label(BuildContext context, String value) {
    return switch (value) {
      'daily' => context.l10n.daily,
      'weekly' => context.l10n.weekly,
      'monthly' => context.l10n.monthly,
      'one_off' => context.l10n.oneOff,
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
                  label: _label(context, option),
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

/// Shared MoMo route editor used by create/settings flows.
class GroupMomoRouteSection extends StatelessWidget {
  const GroupMomoRouteSection({
    required this.routeType,
    required this.momoNumberController,
    required this.momoCodeController,
    required this.supportsMomoCode,
    required this.onRouteTypeChanged,
    this.useCustom,
    this.onToggleCustom,
    super.key,
  });

  final bool? useCustom;
  final ValueChanged<bool>? onToggleCustom;
  final MomoRecipientType routeType;
  final TextEditingController momoNumberController;
  final TextEditingController momoCodeController;
  final bool supportsMomoCode;
  final ValueChanged<MomoRecipientType> onRouteTypeChanged;

  bool get _showsToggle => useCustom != null && onToggleCustom != null;
  bool get _showsEditor => !_showsToggle || useCustom == true;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    final text = context.coolText;

    return CoolCard(
      borderRadius: CoolRadii.xl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_showsToggle)
            InkWell(
              onTap: () => onToggleCustom!.call(!useCustom!),
              borderRadius: BorderRadius.circular(CoolRadii.lg),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: space.x1),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: CoolMotion.quick,
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: useCustom!
                            ? colors.accent
                            : colors.cardSurfaceStrong,
                        borderRadius: BorderRadius.circular(CoolRadii.xs),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        useCustom! ? Icons.check_rounded : Icons.add_rounded,
                        size: 16,
                        color: useCustom!
                            ? colors.accentForeground
                            : colors.secondaryText,
                      ),
                    ),
                    SizedBox(width: space.x3),
                    Expanded(
                      child: Text(
                        'USE DIFFERENT MOMO FOR THIS GROUP',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.primaryText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_showsEditor) ...[
            if (_showsToggle) SizedBox(height: space.x3),
            const GroupSectionLabel(label: 'RECEIVE PAYMENTS VIA'),
            SizedBox(height: space.x2),
            CoolCard(
              backgroundColor: colors.cardSurfaceStrong,
              borderRadius: CoolRadii.lg,
              padding: const EdgeInsets.all(6),
              child: Row(
                children: [
                  Expanded(
                    child: GroupSegmentTab(
                      label: 'NUMBER',
                      selected: routeType == MomoRecipientType.phoneNumber,
                      onTap: () =>
                          onRouteTypeChanged(MomoRecipientType.phoneNumber),
                    ),
                  ),
                  if (supportsMomoCode)
                    Expanded(
                      child: GroupSegmentTab(
                        label: 'CODE',
                        selected: routeType == MomoRecipientType.code,
                        onTap: () => onRouteTypeChanged(MomoRecipientType.code),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(height: space.x3),
            CoolCard(
              backgroundColor: colors.cardSurfaceStrong,
              borderRadius: CoolRadii.lg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    routeType == MomoRecipientType.code
                        ? 'MERCHANT CODE'
                        : 'MOMO NUMBER',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.tertiaryText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: space.x2),
                  TextField(
                    controller: routeType == MomoRecipientType.code
                        ? momoCodeController
                        : momoNumberController,
                    keyboardType: TextInputType.number,
                    style: text.display(
                      theme.textTheme.headlineSmall,
                      color: colors.primaryText,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                    decoration: InputDecoration(
                      hintText: routeType == MomoRecipientType.code
                          ? '23456'
                          : '0788123456',
                      hintStyle: text.display(
                        theme.textTheme.headlineSmall,
                        color: colors.tertiaryText,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
