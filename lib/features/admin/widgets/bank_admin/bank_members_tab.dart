import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_empty_view.dart';
import '../../models/bank_admin_models.dart';
import 'bank_admin_helpers.dart';

class BankMembersTab extends StatelessWidget {
  const BankMembersTab({
    required this.members,
    required this.totalCount,
    super.key,
  });

  final List<BankAdminMemberRecord> members;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final moneyFormat = NumberFormat.decimalPattern('en_US');
    final dateFormat = DateFormat('dd MMM yyyy');

    if (members.isEmpty) {
      return const CoolEmptyView(
        message: 'No members are visible',
        compact: true,
      );
    }

    return ListView.separated(
      itemCount: members.length,
      separatorBuilder: (_, _) => const SizedBox(height: CoolSpace.x3),
      itemBuilder: (context, index) {
        final member = members[index];
        return CoolCard(
          backgroundColor: colors.operationalSurface,
          useGradient: false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                    const SizedBox(height: CoolSpace.x1),
                    Text(
                      member.groupName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.tertiaryText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x2),
                    Text(
                      'Contribution total: ${moneyFormat.format(member.contributionAmount)} RWF',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.secondaryText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      member.joinedAt == null
                          ? 'Joined: -'
                          : 'Joined: ${dateFormat.format(member.joinedAt!)}',
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
                  label: context.l10n.admin,
                  backgroundColor: colors.info.withValues(alpha: 0.14),
                  foregroundColor: colors.info,
                ),
            ],
          ),
        );
      },
    );
  }
}
