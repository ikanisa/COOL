import 'package:cool_app/core/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/cool_foundations.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_empty_view.dart';
import '../../models/bank_admin_models.dart';
import 'bank_admin_helpers.dart';

OutlineInputBorder _bankContributionFilterBorder(
  CoolSemanticColors colors, {
  Color? borderColor,
  double width = 1,
}) {
  return OutlineInputBorder(
    borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.lg)),
    borderSide: BorderSide(color: borderColor ?? colors.border, width: width),
  );
}

class BankContributionsTab extends StatelessWidget {
  const BankContributionsTab({
    required this.contributions,
    required this.totalCount,
    required this.statusFilter,
    required this.onStatusFilterChanged,
    required this.groupFilter,
    required this.onGroupFilterChanged,
    required this.groups,
    super.key,
  });

  final List<BankAdminContributionRecord> contributions;
  final int totalCount;
  final String statusFilter;
  final ValueChanged<String> onStatusFilterChanged;
  final String? groupFilter;
  final ValueChanged<String?> onGroupFilterChanged;
  final List<BankAdminGroupSummary> groups;

  static const List<String> _statuses = <String>['all', 'confirmed', 'pending'];

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final moneyFormat = NumberFormat.decimalPattern('en_US');
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

    var filtered = contributions;
    if (statusFilter != 'all') {
      filtered = filtered.where((contribution) {
        if (statusFilter == 'confirmed') {
          return bankIsConfirmedContributionStatus(contribution.status);
        }
        return contribution.status == statusFilter;
      }).toList();
    }
    if (groupFilter != null && groupFilter!.isNotEmpty) {
      filtered = filtered.where((item) => item.groupId == groupFilter).toList();
    }

    return Column(
      children: [
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _statuses.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final status = _statuses[index];
              final isActive = status == statusFilter;
              return FilterChip(
                label: Text(bankTitle(status)),
                selected: isActive,
                onSelected: (_) => onStatusFilterChanged(status),
                backgroundColor: colors.chipBackground,
                selectedColor: colors.chipSelectedBackground,
                labelStyle: theme.textTheme.bodySmall?.copyWith(
                  color: isActive ? colors.primaryText : colors.secondaryText,
                  fontWeight: FontWeight.w700,
                ),
              );
            },
          ),
        ),
        if (groups.isNotEmpty) ...[
          const SizedBox(height: CoolSpace.x2),
          DropdownButtonFormField<String?>(
            initialValue: groupFilter,
            decoration: InputDecoration(
              labelText: 'Filter by group',
              labelStyle: theme.textTheme.bodySmall?.copyWith(
                color: colors.tertiaryText,
                fontWeight: FontWeight.w700,
              ),
              filled: true,
              fillColor: colors.inputSurface,
              border: _bankContributionFilterBorder(colors),
              enabledBorder: _bankContributionFilterBorder(colors),
              focusedBorder: _bankContributionFilterBorder(
                colors,
                borderColor: colors.accent,
                width: 1.4,
              ),
              isDense: true,
            ),
            dropdownColor: colors.inputSurface,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w600,
            ),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(context.l10n.allGroups),
              ),
              ...groups.map(
                (group) => DropdownMenuItem<String?>(
                  value: group.id,
                  child: Text(group.group.name),
                ),
              ),
            ],
            onChanged: onGroupFilterChanged,
          ),
        ],
        const SizedBox(height: CoolSpace.x3),
        if (filtered.isEmpty)
          const Expanded(
            child: CoolEmptyView(
              message: 'No contributions match the selected filters',
              compact: true,
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const SizedBox(height: CoolSpace.x3),
              itemBuilder: (context, index) {
                final contribution = filtered[index];
                final confirmed = bankIsConfirmedContributionStatus(
                  contribution.status,
                );
                return CoolCard(
                  backgroundColor: colors.operationalSurface,
                  useGradient: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              contribution.contributorName,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: colors.primaryText,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          BankStatusTag(
                            label: bankTitle(contribution.status),
                            backgroundColor: confirmed
                                ? colors.success.withValues(alpha: 0.12)
                                : colors.warning.withValues(alpha: 0.12),
                            foregroundColor: confirmed
                                ? colors.success
                                : colors.warning,
                          ),
                        ],
                      ),
                      const SizedBox(height: CoolSpace.x1),
                      Text(
                        contribution.groupName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.tertiaryText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: CoolSpace.x2),
                      Text(
                        '${moneyFormat.format(contribution.amount)} RWF',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: colors.primaryText,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: CoolSpace.x1),
                      Text(
                        dateFormat.format(contribution.createdAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.secondaryText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if ((contribution.reference?.trim().isNotEmpty ??
                          false)) ...[
                        const SizedBox(height: CoolSpace.x1),
                        Text(
                          'Reference: ${contribution.reference}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.secondaryText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
