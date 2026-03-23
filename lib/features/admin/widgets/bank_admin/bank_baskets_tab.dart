import 'package:cool_app/core/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/cool_foundations.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_empty_view.dart';
import '../../providers/bank_admin_providers.dart';
import 'bank_admin_helpers.dart';

class BankBasketsTab extends ConsumerWidget {
  const BankBasketsTab({
    required this.partnerId,
    required this.statusFilter,
    required this.onStatusFilterChanged,
    super.key,
  });

  final String partnerId;
  final String statusFilter;
  final ValueChanged<String> onStatusFilterChanged;

  static const List<String> _statuses = <String>[
    'all',
    'active',
    'completed',
    'closed',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final basketsAsync = ref.watch(bankBasketsProvider(partnerId));
    final moneyFmt = NumberFormat.decimalPattern('en_US');

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
              final active = status == statusFilter;
              return FilterChip(
                label: Text(bankTitle(status)),
                selected: active,
                onSelected: (_) => onStatusFilterChanged(status),
                backgroundColor: colors.chipBackground,
                selectedColor: colors.chipSelectedBackground,
                labelStyle: theme.textTheme.bodySmall?.copyWith(
                  color: active ? colors.primaryText : colors.secondaryText,
                  fontWeight: FontWeight.w700,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: CoolSpace.x3),
        Expanded(
          child: basketsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Text(context.l10n.genericErrorText(error.toString())),
            ),
            data: (baskets) {
              final filtered = statusFilter == 'all'
                  ? baskets
                  : baskets.where((basket) {
                      return (basket['status']?.toString() ?? '') ==
                          statusFilter;
                    }).toList();

              if (filtered.isEmpty) {
                return const CoolEmptyView(
                  message: 'No baskets match filter',
                  compact: true,
                );
              }

              return ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final basket = filtered[index];
                  final name = basket['name']?.toString() ?? 'Basket';
                  final groupName = basket['group_name']?.toString() ?? '—';
                  final targetAmount =
                      (basket['target_amount'] as num?)?.toDouble() ?? 0;
                  final currentAmount =
                      (basket['current_amount'] as num?)?.toDouble() ?? 0;
                  final progressPct =
                      (basket['progress_pct'] as num?)?.toDouble() ?? 0;
                  final status = basket['status']?.toString() ?? 'active';
                  final completed = status == 'completed';

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
                                name,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: colors.primaryText,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            BankStatusTag(
                              label: bankTitle(status),
                              backgroundColor: completed
                                  ? colors.success.withValues(alpha: 0.15)
                                  : colors.cardSurfaceStrong,
                              foregroundColor: completed
                                  ? colors.success
                                  : colors.tertiaryText,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          groupName,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.tertiaryText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: CoolSpace.x3),
                        ClipRRect(
                          borderRadius: const BorderRadius.all(
                            Radius.circular(CoolSpace.x1 + 2),
                          ),
                          child: LinearProgressIndicator(
                            value: (progressPct / 100).clamp(0.0, 1.0),
                            backgroundColor: colors.cardSurfaceStrong,
                            color: completed ? colors.success : colors.info,
                            minHeight: 8,
                          ),
                        ),
                        const SizedBox(height: CoolSpace.x2),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${moneyFmt.format(currentAmount)} / ${moneyFmt.format(targetAmount)} RWF',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.secondaryText,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${progressPct.toStringAsFixed(1)}%',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: completed
                                    ? colors.success
                                    : colors.primaryText,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
