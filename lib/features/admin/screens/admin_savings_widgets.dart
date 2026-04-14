import 'package:flutter/material.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/money_formatters.dart';
import '../../../shared/widgets/cool_card.dart';

const BorderRadius _metricRadius = BorderRadius.all(
  Radius.circular(CoolRadii.xs),
);

// ═══════════════════════════════════════════════════════════════
// Create form
// ═══════════════════════════════════════════════════════════════

/// Form for creating a new savings group.
class CreateSavingsGroupForm extends StatelessWidget {
  const CreateSavingsGroupForm({
    required this.nameController,
    required this.descriptionController,
    required this.targetAmountController,
    required this.monthlyContributionController,
    required this.frequency,
    required this.isCreating,
    required this.onFrequencyChanged,
    required this.onSubmit,
    super.key,
  });

  final TextEditingController nameController;
  final TextEditingController descriptionController;
  final TextEditingController targetAmountController;
  final TextEditingController monthlyContributionController;
  final String frequency;
  final bool isCreating;
  final ValueChanged<String> onFrequencyChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return CoolCard(
      backgroundColor: colors.operationalSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'New Savings Group',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x4),
          SavingsTextField(
            controller: nameController,
            label: 'Group name',
            hint: 'e.g. Umuganda 2026',
          ),
          const SizedBox(height: CoolSpace.x3),
          SavingsTextField(
            controller: descriptionController,
            label: 'Description (optional)',
            hint: 'Brief description',
            maxLines: 2,
          ),
          const SizedBox(height: CoolSpace.x3),
          Row(
            children: [
              Expanded(
                child: SavingsTextField(
                  controller: targetAmountController,
                  label: 'Target (RWF)',
                  hint: '0',
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: CoolSpace.x3),
              Expanded(
                child: SavingsTextField(
                  controller: monthlyContributionController,
                  label: 'Monthly (RWF)',
                  hint: '0',
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x3),
          Text(
            'Frequency',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Wrap(
            spacing: 8,
            children: [
              for (final freq in const ['monthly', 'weekly', 'one_off'])
                ChoiceChip(
                  showCheckmark: false,
                  label: Text(freq.replaceAll('_', ' ')),
                  selected: frequency == freq,
                  onSelected: (_) => onFrequencyChanged(freq),
                  backgroundColor: colors.chipBackground,
                  selectedColor: colors.chipSelectedBackground,
                  labelStyle: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: frequency == freq
                        ? colors.primaryText
                        : colors.secondaryText,
                  ),
                  side: BorderSide.none,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(
                      Radius.circular(CoolRadii.pill),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: CoolSpace.x5),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: isCreating ? null : onSubmit,
              style: FilledButton.styleFrom(
                backgroundColor: colors.accent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(CoolRadii.sm),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                isCreating ? 'Creating…' : 'Create Savings Group',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Metric tile
// ═══════════════════════════════════════════════════════════════

/// Compact metric display with icon, value, and label.
class SavingsMetricTile extends StatelessWidget {
  const SavingsMetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return CoolCard(
      backgroundColor: colors.analyticsSurface,
      useGradient: false,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: _metricRadius,
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colors.primaryText,
                  ),
                ),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colors.tertiaryText,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Group tile
// ═══════════════════════════════════════════════════════════════

/// List tile for a savings or community group in the admin list.
class SavingsGroupTile extends StatelessWidget {
  const SavingsGroupTile({
    required this.group,
    required this.isSavings,
    this.onTap,
    super.key,
  });

  final Map<String, dynamic> group;
  final bool isSavings;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final name = group['name']?.toString() ?? 'Unnamed';
    final memberCount = _asInt(group['member_count']);
    final isClosed = group['is_closed'] == true;
    final statusColor = isClosed ? colors.danger : colors.success;
    final total = _asInt(group['total_collected']);

    return CoolCard(
      backgroundColor: colors.operationalSurface,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: _metricRadius,
                ),
                alignment: Alignment.center,
                child: Icon(
                  isSavings ? CoolIcons.savings : CoolIcons.groupsFilled,
                  size: 20,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colors.primaryText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        '$memberCount member${memberCount == 1 ? '' : 's'}',
                        if (isSavings && total > 0)
                          '${formatWholeMoneyAmount(total)} RWF',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: colors.tertiaryText,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(CoolRadii.pill),
                ),
                child: Text(
                  isClosed ? 'CLOSED' : 'ACTIVE',
                  style: context.coolText.mono(
                    theme.textTheme.labelSmall,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: CoolSpace.x2),
                Icon(
                  CoolIcons.chevronRight,
                  color: colors.tertiaryText,
                  size: 20,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}

// ═══════════════════════════════════════════════════════════════
// Text field
// ═══════════════════════════════════════════════════════════════

/// Labelled text field used in admin savings forms.
class SavingsTextField extends StatelessWidget {
  const SavingsTextField({
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.secondaryText,
          ),
        ),
        const SizedBox(height: CoolSpace.x1),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.primaryText,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: theme.textTheme.bodyMedium?.copyWith(
              color: colors.tertiaryText,
            ),
            filled: true,
            fillColor: colors.chipBackground,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CoolRadii.sm),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}
