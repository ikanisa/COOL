import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_empty_view.dart';
import '../../models/bank_admin_models.dart';
import 'bank_admin_helpers.dart';
import 'package:cool_app/core/l10n/l10n.dart';

class BankGroupsTab extends StatelessWidget {
  const BankGroupsTab({
    required this.groups,
    required this.totalCount,
    required this.onOpenGroup,
    required this.onOpenLedger,
    required this.search,
    required this.onSearchChanged,
    super.key,
  });

  final List<BankAdminGroupSummary> groups;
  final int totalCount;
  final ValueChanged<BankAdminGroupSummary> onOpenGroup;
  final ValueChanged<String> onOpenLedger;
  final String search;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) {
    final moneyFormat = NumberFormat.decimalPattern('en_US');
    final dateFormat = DateFormat('dd MMM yyyy');
    final lowerSearch = search.toLowerCase();
    final filtered = search.isEmpty
        ? groups
        : groups
              .where(
                (g) => g.group.name.toLowerCase().contains(lowerSearch),
              )
              .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search groups...',
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            onChanged: onSearchChanged,
          ),
        ),
        if (filtered.isEmpty)
          const Expanded(
            child: CoolEmptyView(
              message: 'No custodial groups found',
              compact: true,
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = filtered[index];
                return CoolCard(
                  backgroundColor: AppColors.surface,
                  borderColor: AppColors.border,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.group.name,
                                  style: GoogleFonts.dmSans(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.text,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${bankTitle(item.group.type)} · ${bankTitle(item.group.visibility)}',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.text3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if ((item.group.description?.trim().isNotEmpty ??
                          false)) ...[
                        const SizedBox(height: 8),
                        Text(
                          item.group.description!.trim(),
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.text2,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          BankInfoPill(
                            label: 'Balance',
                            value:
                                '${moneyFormat.format(item.group.amount)} RWF',
                          ),
                          BankInfoPill(
                            label: 'Members',
                            value: item.group.memberCount.toString(),
                          ),
                          BankInfoPill(
                            label: 'Admins',
                            value: item.adminCount.toString(),
                          ),
                          BankInfoPill(
                            label: 'Contributions',
                            value: item.contributionCount.toString(),
                          ),
                          BankInfoPill(
                            label: 'Monthly',
                            value: item.group.monthlyContribution == null
                                ? '-'
                                : '${moneyFormat.format(item.group.monthlyContribution)} RWF',
                          ),
                          BankInfoPill(
                            label: 'Last activity',
                            value: item.lastContributionAt == null
                                ? '-'
                                : dateFormat.format(item.lastContributionAt!),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: () => onOpenGroup(item),
                            child: Text(context.l10n.viewDetails),
                          ),
                          TextButton(
                            onPressed: item.id.isEmpty
                                ? null
                                : () => onOpenLedger(item.id),
                            child: Text(context.l10n.viewLedger),
                          ),
                        ],
                      ),
                      if (index == 0 && totalCount > filtered.length) ...[
                        const SizedBox(height: 12),
                        Text(
                          '${filtered.length}/$totalCount shown',
                          style: GoogleFonts.dmSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text3,
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

class BankGroupDetailSheet extends StatelessWidget {
  const BankGroupDetailSheet({
    required this.group,
    required this.members,
    required this.contributions,
    this.onOpenLedger,
    super.key,
  });

  final BankAdminGroupSummary group;
  final List<BankAdminMemberRecord> members;
  final List<BankAdminContributionRecord> contributions;
  final VoidCallback? onOpenLedger;

  @override
  Widget build(BuildContext context) {
    final moneyFormat = NumberFormat.decimalPattern('en_US');
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                group.group.name,
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Linked group profile active',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text2,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  BankInfoPill(
                    label: 'Balance',
                    value: '${moneyFormat.format(group.group.amount)} RWF',
                  ),
                  BankInfoPill(
                    label: 'Members',
                    value: members.length.toString(),
                  ),
                  BankInfoPill(
                    label: 'Contributions',
                    value: contributions.length.toString(),
                  ),
                  BankInfoPill(
                    label: 'Raised',
                    value:
                        '${moneyFormat.format(group.contributionTotal)} RWF',
                  ),
                ],
              ),
              if (onOpenLedger != null) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: onOpenLedger,
                    child: Text(context.l10n.openLedger),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                'Members',
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 10),
              if (members.isEmpty)
                const CoolEmptyView(
                  message: 'No member records are',
                  compact: true,
                )
              else
                ...members.map(
                  (member) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  member.displayName,
                                  style: GoogleFonts.dmSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.text,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${moneyFormat.format(member.contributionAmount)} RWF contributed',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.text2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (member.isAdmin)
                            const BankStatusTag(
                              label: 'Admin',
                              backgroundColor: AppColors.rsBlueGlow,
                              foregroundColor: AppColors.rsWhite,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                'Recent contributions',
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 10),
              if (contributions.isEmpty)
                const CoolEmptyView(
                  message: 'No contribution records are',
                  compact: true,
                )
              else
                ...contributions.map(
                  (contribution) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  contribution.contributorName,
                                  style: GoogleFonts.dmSans(
                                    fontSize: 13,
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
                          const SizedBox(height: 6),
                          Text(
                            '${moneyFormat.format(contribution.amount)} RWF',
                            style: GoogleFonts.dmSans(
                              fontSize: 14,
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
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}