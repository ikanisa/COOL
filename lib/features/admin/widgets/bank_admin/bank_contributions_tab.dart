import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_empty_view.dart';
import '../../models/bank_admin_models.dart';
import 'bank_admin_helpers.dart';
import '../../../../core/l10n/l10n.dart';

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

  static const _statuses = ['all', 'confirmed', 'pending'];

  @override
  Widget build(BuildContext context) {
    final moneyFormat = NumberFormat.decimalPattern('en_US');
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

    var filtered = contributions;
    if (statusFilter != 'all') {
      filtered = filtered.where((c) => c.status == statusFilter).toList();
    }
    if (groupFilter != null && groupFilter!.isNotEmpty) {
      filtered = filtered.where((c) => c.groupId == groupFilter).toList();
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
                backgroundColor: AppColors.surface2,
                selectedColor: AppColors.accent.withValues(alpha: 0.15),
                labelStyle: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isActive ? AppColors.accent : AppColors.text2,
                ),
              );
            },
          ),
        ),
        if (groups.isNotEmpty) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            initialValue: groupFilter,
            decoration: const InputDecoration(
              labelText: 'Filter by group',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(context.l10n.allGroups),
              ),
              ...groups.map(
                (g) => DropdownMenuItem<String?>(
                  value: g.id,
                  child: Text(g.group.name),
                ),
              ),
            ],
            onChanged: onGroupFilterChanged,
          ),
        ],
        const SizedBox(height: 12),
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
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final contribution = filtered[index];
                return CoolCard(
                  backgroundColor: AppColors.surface,
                  borderColor: AppColors.border,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              contribution.contributorName,
                              style: GoogleFonts.dmSans(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.text,
                              ),
                            ),
                          ),
                          BankStatusTag(
                            label: bankTitle(contribution.status),
                            backgroundColor:
                                contribution.status == 'confirmed'
                                    ? AppColors.accent
                                        .withValues(alpha: 0.12)
                                    : AppColors.orange
                                        .withValues(alpha: 0.12),
                            foregroundColor:
                                contribution.status == 'confirmed'
                                    ? AppColors.accent
                                    : AppColors.orange,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        contribution.groupName,
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${moneyFormat.format(contribution.amount)} RWF',
                        style: GoogleFonts.dmSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dateFormat.format(contribution.createdAt),
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text2,
                        ),
                      ),
                      if ((contribution.reference?.trim().isNotEmpty ??
                          false)) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Reference: ${contribution.reference}',
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.text2,
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