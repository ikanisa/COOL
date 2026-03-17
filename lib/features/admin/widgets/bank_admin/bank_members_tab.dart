import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_empty_view.dart';
import '../../models/bank_admin_models.dart';
import 'bank_admin_helpers.dart';
import '../../../../core/l10n/l10n.dart';

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
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final member = members[index];
        return CoolCard(
          backgroundColor: AppColors.surface,
          borderColor: AppColors.border,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.displayName,
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      member.groupName,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Contribution total: ${moneyFormat.format(member.contributionAmount)} RWF',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text2,
                      ),
                    ),
                    Text(
                      member.joinedAt == null
                          ? 'Joined: -'
                          : 'Joined: ${dateFormat.format(member.joinedAt!)}',
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
                BankStatusTag(
                  label: context.l10n.admin,
                  backgroundColor: AppColors.rsBlueGlow,
                  foregroundColor: AppColors.rsWhite,
                ),
            ],
          ),
        );
      },
    );
  }
}