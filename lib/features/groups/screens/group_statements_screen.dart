import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/user_error.dart';
import '../../../shared/widgets/core_detail_scaffold.dart';
import '../../momo/models/momo_statement.dart';
import '../../momo/providers/momo_statement_providers.dart';
import '../providers/groups_provider.dart';

/// Full-page statements screen filtered to a specific group.
/// Accessed from GroupDetailScreen → "VIEW ALL STATEMENTS".
class GroupStatementsScreen extends ConsumerWidget {
  const GroupStatementsScreen({required this.groupId, super.key});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final bottomPad = MediaQuery.viewPaddingOf(context).bottom;
    final groupAsync = ref.watch(groupDetailProvider(groupId));

    final ledgerAsync = ref.watch(
      groupPaymentLedgerProvider(
        GroupPaymentLedgerQuery(
          groupId: groupId,
          statementQuery: const MomoStatementQuery(limit: 100),
        ),
      ),
    );

    return CoreDetailScaffold(
      title: Text(
        'STATEMENTS',
        style: context.coolText.displayCondensed(
          Theme.of(context).textTheme.headlineSmall,
          fontWeight: FontWeight.w900,
        ),
      ),
      subtitle: Text(
        groupAsync.when(
          data: (g) => g?.name.toUpperCase() ?? 'GROUP LEDGER',
          loading: () => 'LOADING',
          error: (_, stackTrace) => 'GROUP LEDGER',
        ),
        style: context.coolText.mono(
          Theme.of(context).textTheme.labelSmall,
          fontWeight: FontWeight.w700,
          color: colors.secondaryText,
          letterSpacing: 1.0,
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: CoolSpace.x4),
          child: IgnorePointer(
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.receipt_long_rounded,
                color: colors.accent,
                size: 22,
              ),
            ),
          ),
        ),
      ],
      child: ledgerAsync.when(
        data: (page) {
          if (page.entries.isEmpty) {
            return ListView(
              padding: EdgeInsets.only(bottom: CoolSpace.x8 + bottomPad),
              children: [_EmptyState(colors)],
            );
          }
          return ListView.builder(
            padding: EdgeInsets.only(bottom: CoolSpace.x8 + bottomPad),
            itemCount: page.entries.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: CoolSpace.x3),
                child: _StatementTile(entry: page.entries[index]),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ListView(
          padding: EdgeInsets.only(bottom: CoolSpace.x8 + bottomPad),
          children: [_ErrorState(colors: colors, message: describeUserFacingError(error))],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(this.colors);

  final CoolSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(CoolSpace.x6),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(CoolRadii.xl),
        boxShadow: CoolShadows.ambientFloat(strength: 0.3),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.receipt_long_rounded,
              color: colors.accent,
              size: 32,
            ),
          ),
          const SizedBox(height: CoolSpace.x4),
          Text(
            'NO TRANSACTIONS YET',
            style: context.coolText.displayCondensed(
              Theme.of(context).textTheme.titleLarge,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            'Contributions will appear here as members make payments to this group.',
            textAlign: TextAlign.center,
            style: context.coolText.mono(
              Theme.of(context).textTheme.bodySmall,
              fontWeight: FontWeight.w600,
              color: colors.secondaryText,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.colors, required this.message});

  final CoolSemanticColors colors;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(CoolSpace.x5),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(CoolRadii.xl),
        boxShadow: CoolShadows.ambientFloat(strength: 0.3),
      ),
      child: Text(
        'Could not load statements.',
        style: context.coolText.mono(
          Theme.of(context).textTheme.bodyMedium,
          fontWeight: FontWeight.w600,
          color: colors.secondaryText,
        ),
      ),
    );
  }
}

class _StatementTile extends StatelessWidget {
  const _StatementTile({required this.entry});

  final PayeePaymentLedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;

    return Container(
      padding: const EdgeInsets.all(CoolSpace.x4),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(CoolRadii.xl),
        boxShadow: CoolShadows.ambientFloat(strength: 0.3),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(CoolRadii.md),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.arrow_downward_rounded,
              color: colors.accent,
              size: 20,
            ),
          ),
          const SizedBox(width: CoolSpace.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.label,
                  style: context.coolText.mono(
                    Theme.of(context).textTheme.titleSmall,
                    fontWeight: FontWeight.w800,
                    color: colors.primaryText,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.payerName} • ${_formatDate(entry.occurredAt)}',
                  style: context.coolText.mono(
                    Theme.of(context).textTheme.labelSmall,
                    fontWeight: FontWeight.w600,
                    color: colors.secondaryText,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            '${entry.amount} ${entry.currency}',
            style: context.coolText.mono(
              Theme.of(context).textTheme.titleSmall,
              fontWeight: FontWeight.w800,
              color: colors.accentGold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day}/${local.month}/${local.year}';
  }
}
