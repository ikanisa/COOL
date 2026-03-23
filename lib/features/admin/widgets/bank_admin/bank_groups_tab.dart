import 'package:cool_app/core/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/cool_foundations.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_empty_view.dart';
import '../../models/bank_admin_models.dart';
import 'bank_admin_helpers.dart';

EdgeInsets _bankGroupsSearchPadding() => CoolSpace.sectionPadding.copyWith(
  left: 0,
  right: 0,
  top: 0,
  bottom: CoolSpace.x3,
);

EdgeInsets _bankGroupsSearchContentPadding() =>
    CoolSpace.sectionPadding.copyWith(
      left: CoolSpace.x3,
      right: CoolSpace.x3,
      top: CoolSpace.x2,
      bottom: CoolSpace.x2,
    );

EdgeInsets _bankGroupsSheetInsets(BuildContext context) {
  final space = context.coolSpace;
  return CoolSpace.pagePadding.copyWith(
    top: space.x5,
    bottom: MediaQuery.of(context).viewInsets.bottom + space.x5,
  );
}

EdgeInsets _bankGroupsRecordPadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x3,
  right: CoolSpace.x3,
  top: CoolSpace.x3,
  bottom: CoolSpace.x3,
);

EdgeInsets _bankGroupsRecordSpacing() => CoolSpace.sectionPadding.copyWith(
  left: 0,
  right: 0,
  top: 0,
  bottom: CoolSpace.x2,
);

const BorderRadius _bankGroupsSearchRadius = BorderRadius.all(
  Radius.circular(CoolRadii.lg),
);
const BorderRadius _bankGroupsSheetHandleRadius = BorderRadius.all(
  Radius.circular(CoolRadii.pill),
);
const BorderRadius _bankGroupsRecordRadius = BorderRadius.all(
  Radius.circular(CoolRadii.xs),
);

OutlineInputBorder _bankGroupsSearchBorder(
  BuildContext context, {
  Color? color,
  double width = 1,
}) {
  final colors = context.coolSemanticColors;
  return OutlineInputBorder(
    borderRadius: _bankGroupsSearchRadius,
    borderSide: BorderSide(color: color ?? colors.border, width: width),
  );
}

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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final moneyFormat = NumberFormat.decimalPattern('en_US');
    final dateFormat = DateFormat('dd MMM yyyy');
    final lowerSearch = search.toLowerCase();
    final filtered = search.isEmpty
        ? groups
        : groups
              .where(
                (group) => group.group.name.toLowerCase().contains(lowerSearch),
              )
              .toList(growable: false);

    return Column(
      children: [
        Padding(
          padding: _bankGroupsSearchPadding(),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search groups...',
              hintStyle: theme.textTheme.bodySmall?.copyWith(
                color: colors.tertiaryText,
                fontWeight: FontWeight.w600,
              ),
              prefixIcon: Icon(
                Icons.search,
                size: 20,
                color: colors.tertiaryText,
              ),
              filled: true,
              fillColor: colors.inputSurface,
              border: _bankGroupsSearchBorder(context),
              enabledBorder: _bankGroupsSearchBorder(context),
              focusedBorder: _bankGroupsSearchBorder(
                context,
                color: colors.accent,
                width: 1.4,
              ),
              isDense: true,
              contentPadding: _bankGroupsSearchContentPadding(),
            ),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w600,
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
                  backgroundColor: colors.operationalSurface,
                  useGradient: false,
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
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: colors.primaryText,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${bankTitle(item.group.type)} · ${bankTitle(item.group.visibility)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.tertiaryText,
                                    fontWeight: FontWeight.w700,
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
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.secondaryText,
                            fontWeight: FontWeight.w600,
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
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.tertiaryText,
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final moneyFormat = NumberFormat.decimalPattern('en_US');
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

    return SafeArea(
      top: false,
      child: Padding(
        padding: _bankGroupsSheetInsets(context),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.border,
                    borderRadius: _bankGroupsSheetHandleRadius,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                group.group.name,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Linked group profile active',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.secondaryText,
                  fontWeight: FontWeight.w600,
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
                    value: '${moneyFormat.format(group.contributionTotal)} RWF',
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
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w800,
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
                    padding: _bankGroupsRecordSpacing(),
                    child: Container(
                      padding: _bankGroupsRecordPadding(),
                      decoration: BoxDecoration(
                        color: colors.operationalSurface,
                        borderRadius: _bankGroupsRecordRadius,
                        border: Border.all(color: colors.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  member.displayName,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: colors.primaryText,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${moneyFormat.format(member.contributionAmount)} RWF contributed',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.secondaryText,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (member.isAdmin)
                            BankStatusTag(
                              label: 'Admin',
                              backgroundColor: colors.info.withValues(
                                alpha: 0.14,
                              ),
                              foregroundColor: colors.info,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                'Recent contributions',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w800,
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
                    padding: _bankGroupsRecordSpacing(),
                    child: Container(
                      padding: _bankGroupsRecordPadding(),
                      decoration: BoxDecoration(
                        color: colors.operationalSurface,
                        borderRadius: _bankGroupsRecordRadius,
                        border: Border.all(color: colors.border),
                      ),
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
                                backgroundColor:
                                    bankIsConfirmedContributionStatus(
                                      contribution.status,
                                    )
                                    ? colors.success.withValues(alpha: 0.12)
                                    : colors.warning.withValues(alpha: 0.12),
                                foregroundColor:
                                    bankIsConfirmedContributionStatus(
                                      contribution.status,
                                    )
                                    ? colors.success
                                    : colors.warning,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${moneyFormat.format(contribution.amount)} RWF',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: colors.primaryText,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            dateFormat.format(contribution.createdAt),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.secondaryText,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if ((contribution.reference?.trim().isNotEmpty ??
                              false)) ...[
                            const SizedBox(height: 4),
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
