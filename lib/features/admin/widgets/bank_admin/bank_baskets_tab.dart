import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/cool_palette.dart';
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

  static const _statuses = ['all', 'active', 'completed', 'closed'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.coolPalette;
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
              final s = _statuses[index];
              final active = s == statusFilter;
              return FilterChip(
                label: Text(bankTitle(s)),
                selected: active,
                onSelected: (_) => onStatusFilterChanged(s),
                backgroundColor: palette.surface2,
                selectedColor: palette.accent.withValues(alpha: 0.15),
                labelStyle: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? palette.accent : palette.text2,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: basketsAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(context.l10n.genericErrorText(e.toString()))),
            data: (baskets) {
              final filtered = statusFilter == 'all'
                  ? baskets
                  : baskets
                        .where(
                          (b) =>
                              (b['status']?.toString() ?? '') ==
                              statusFilter,
                        )
                        .toList();
              if (filtered.isEmpty) {
                return const CoolEmptyView(
                  message: 'No baskets match filter',
                  compact: true,
                );
              }
              return ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final basket = filtered[index];
                  final name =
                      basket['name']?.toString() ?? 'Basket';
                  final groupName =
                      basket['group_name']?.toString() ?? '—';
                  final targetAmount =
                      (basket['target_amount'] as num?)
                          ?.toDouble() ??
                      0;
                  final currentAmount =
                      (basket['current_amount'] as num?)
                          ?.toDouble() ??
                      0;
                  final progressPct =
                      (basket['progress_pct'] as num?)
                          ?.toDouble() ??
                      0;
                  final status =
                      basket['status']?.toString() ?? 'active';

                  return CoolCard(
                    backgroundColor: palette.surface,
                    borderColor: palette.border,
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: GoogleFonts.dmSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: palette.text,
                                ),
                              ),
                            ),
                            BankStatusTag(
                              label: bankTitle(status),
                              backgroundColor:
                                  status == 'completed'
                                      ? Colors.green
                                          .withValues(alpha: 0.15)
                                      : palette.surface2,
                              foregroundColor:
                                  status == 'completed'
                                      ? Colors.green
                                      : palette.text3,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          groupName,
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            color: palette.text3,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius:
                              BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: (progressPct / 100)
                                .clamp(0.0, 1.0),
                            backgroundColor:
                                palette.surface2,
                            color: progressPct >= 100
                                ? Colors.green
                                : palette.blue,
                            minHeight: 8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment
                                  .spaceBetween,
                          children: [
                            Text(
                              '${moneyFmt.format(currentAmount)} / ${moneyFmt.format(targetAmount)} RWF',
                              style: GoogleFonts.dmSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: palette.text2,
                              ),
                            ),
                            Text(
                              '${progressPct.toStringAsFixed(1)}%',
                              style: GoogleFonts.dmSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: progressPct >= 100
                                    ? Colors.green
                                    : palette.text,
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
