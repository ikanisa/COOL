import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/money_formatters.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_icon_box.dart';
import '../../../shared/widgets/core_detail_scaffold.dart';
import '../../../shared/widgets/transaction_status_chip.dart';

import '../../momo/models/momo_statement.dart';
import '../widgets/transaction_allocation_sheet.dart';

// ═══════════════════════════════════════════════════════════════
// Statements button
// ═══════════════════════════════════════════════════════════════

/// CTA button that navigates to full statements list.
class GroupStatementsButton extends StatelessWidget {
  const GroupStatementsButton({required this.groupId, super.key});

  final String groupId;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: CoolButton(
        label: context.l10n.groupsViewAllStatementsUpper,
        onTap: () => context.push(AppRoutes.groupStatementsLocation(groupId)),
        variant: CoolButtonVariant.secondary,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Ledger tile
// ═══════════════════════════════════════════════════════════════

/// Ledger tile — clean icon-led row with amount + status.
class GroupLedgerTile extends StatelessWidget {
  const GroupLedgerTile({
    required this.entry,
    this.canManageAllocations = false,
    this.groupId = '',
    super.key,
  });

  final PayeePaymentLedgerEntry entry;
  final bool canManageAllocations;
  final String groupId;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final isAllocated = entry.payerUserId.trim().isNotEmpty;
    final statusLabel = isAllocated ? 'confirmed' : 'pending_review';

    return CoolCard(
      cardPadding: CoolCardPadding.md,
      onTap: canManageAllocations
          ? () => TransactionAllocationSheet.show(
              context,
              entry: entry,
              groupId: groupId,
            )
          : null,
      child: Row(
        children: [
          const CoolIconBox(icon: CoolIcons.payment),
          const SizedBox(width: CoolSpace.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.headline(
                    Theme.of(context).textTheme.titleSmall,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.payerName} • ${entry.occurredAt.toLocal().toString().split('.').first}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text
                      .mobiLabel(color: colors.secondaryText)
                      .copyWith(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(width: CoolSpace.x3),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${formatWholeMoneyAmount(entry.amount)} ${entry.currency}',
                style: text.mono(null, color: colors.accentGold),
              ),
              const SizedBox(height: 4),
              TransactionStatusChip(status: statusLabel),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Missing group fallback
// ═══════════════════════════════════════════════════════════════

/// Fallback screen shown when a group cannot be found or loaded.
class MissingGroupState extends StatelessWidget {
  const MissingGroupState({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return CoreDetailScaffold(
      onBack: () {
        if (context.canPop()) {
          context.pop();
          return;
        }
        context.go(AppRoutes.groups);
      },
      title: Text(
        context.l10n.groupDetailTitle,
        style: context.coolText.displayCondensed(
          Theme.of(context).textTheme.headlineSmall,
          fontWeight: FontWeight.w800,
        ),
      ),
      child: Center(
        child: CoolCard(
          borderRadius: CoolRadii.xl,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: CoolSpace.x2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CoolIconBox(
                  icon: CoolIcons.groupOff,
                  size: CoolIconBoxSize.lg,
                  variant: CoolIconBoxVariant.solid,
                ),
                const SizedBox(height: CoolSpace.x5),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.secondaryText,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: CoolSpace.x6),
                CoolButton(
                  label: context.l10n.goBack,
                  variant: CoolButtonVariant.secondary,
                  onTap: () {
                    if (context.canPop()) {
                      context.pop();
                      return;
                    }
                    context.go(AppRoutes.groups);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
