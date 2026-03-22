import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/cool_palette.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_empty_view.dart';
import '../../models/bank_admin_models.dart';
import 'bank_admin_helpers.dart';

class BankAllocationsTab extends StatelessWidget {
  const BankAllocationsTab({
    required this.items,
    required this.totalCount,
    required this.activeReviewId,
    required this.activeAction,
    required this.statusFilter,
    required this.onStatusFilterChanged,
    required this.onAllocate,
    required this.onReject,
    required this.onAcceptSuggestion,
    required this.onTriggerAi,
    required this.isAiRunning,
    super.key,
  });

  final List<BankAdminAllocationReviewItem> items;
  final int totalCount;
  final String? activeReviewId;
  final String? activeAction;
  final String statusFilter;
  final ValueChanged<String> onStatusFilterChanged;
  final ValueChanged<BankAdminAllocationReviewItem> onAllocate;
  final ValueChanged<BankAdminAllocationReviewItem> onReject;
  final ValueChanged<BankAdminAllocationReviewItem> onAcceptSuggestion;
  final VoidCallback onTriggerAi;
  final bool isAiRunning;

  static const _filters = [
    ('all', 'All'),
    ('suggested', 'Suggested'),
    ('manual_review', 'Manual'),
    ('pending_review', 'Pending'),
    ('rejected', 'Rejected'),
  ];

  Color _statusColor(String status) {
    switch (status) {
      case 'suggested':
        return const Color(0xFF6366F1);
      case 'manual_review':
        return AppColors.orange;
      case 'pending_review':
        return AppColors.yellow;
      case 'rejected':
        return AppColors.red;
      case 'matched':
        return AppColors.accent;
      default:
        return AppColors.text3;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final moneyFormat = NumberFormat.decimalPattern('en_US');
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

    final filtered = statusFilter == 'all'
        ? items
        : items.where((i) => i.matchStatus == statusFilter).toList();

    return Stack(
      children: [
        Column(
          children: [
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                itemCount: _filters.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final (value, label) = _filters[index];
                  final selected = statusFilter == value;
                  final count = value == 'all'
                      ? items.length
                      : items
                            .where((i) => i.matchStatus == value)
                            .length;
                  return FilterChip(
                    label: Text(
                      '$label${count > 0 ? ' ($count)' : ''}',
                    ),
                    selected: selected,
                    onSelected: (_) => onStatusFilterChanged(value),
                    backgroundColor: palette.surface,
                    selectedColor:
                        palette.accent.withValues(alpha: 0.12),
                    labelStyle: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      color:
                          selected ? palette.accent : palette.text2,
                    ),
                    side: BorderSide(
                      color:
                          selected ? palette.accent : palette.border,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    visualDensity: VisualDensity.compact,
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? CoolEmptyView(
                      message: statusFilter == 'all'
                          ? 'No unresolved allocations. Tap the AI button to run auto-matching.'
                          : 'No ${statusFilter.replaceAll('_', ' ')} allocations.',
                      compact: true,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        final isActive =
                            activeReviewId == item.reviewId;
                        final color =
                            _statusColor(item.matchStatus);

                        return CoolCard(
                          backgroundColor: palette.surface,
                          borderColor: item.isSuggested
                              ? const Color(0xFF6366F1)
                                  .withValues(alpha: 0.3)
                              : palette.border,
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.groupName,
                                      style: GoogleFonts.dmSans(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: palette.text,
                                      ),
                                    ),
                                  ),
                                  BankStatusTag(
                                    label: bankTitle(
                                      item.matchStatus,
                                    ),
                                    backgroundColor: color
                                        .withValues(alpha: 0.12),
                                    foregroundColor: color,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                item.payerName,
                                style: GoogleFonts.dmSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: palette.text2,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${moneyFormat.format(item.amount)} RWF',
                                style: GoogleFonts.dmSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: palette.text,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Reason: ${bankTitle(item.reason)}',
                                style: GoogleFonts.dmSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: palette.text2,
                                ),
                              ),
                              if ((item.reference
                                      ?.trim()
                                      .isNotEmpty ??
                                  false))
                                Text(
                                  'Reference: ${item.reference}',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: palette.text2,
                                  ),
                                ),
                              if ((item.payeeDigits
                                      ?.trim()
                                      .isNotEmpty ??
                                  false))
                                Text(
                                  'Payee: ${item.payeeDigits}',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: palette.text2,
                                  ),
                                ),
                              if (item.isSuggested) ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding:
                                      const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF6366F1)
                                        .withValues(alpha: 0.06),
                                    borderRadius:
                                        BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.auto_awesome,
                                        size: 16,
                                        color: Color(0xFF6366F1),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          '→ ${item.suggestedMemberName ?? 'Suggested member'} · ${(item.suggestedConfidence ?? 0).toStringAsFixed(0)}%',
                                          style:
                                              GoogleFonts.dmSans(
                                            fontSize: 12,
                                            fontWeight:
                                                FontWeight.w600,
                                            color: const Color(
                                              0xFF6366F1,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (item.aiReasoning !=
                                    null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    item.aiReasoning!,
                                    style: GoogleFonts.dmSans(
                                      fontSize: 11,
                                      color: palette.text3,
                                    ),
                                    maxLines: 2,
                                    overflow:
                                        TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (item.isSuggested)
                                    FilledButton.icon(
                                      onPressed: isActive
                                          ? null
                                          : () =>
                                              onAcceptSuggestion(
                                                item,
                                              ),
                                      icon: isActive &&
                                              activeAction ==
                                                  'accept'
                                          ? const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child:
                                                  CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color:
                                                    Colors.white,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.check,
                                              size: 16,
                                            ),
                                      label: Text(
                                        isActive &&
                                                activeAction ==
                                                    'accept'
                                            ? 'Accepting...'
                                            : 'Accept',
                                      ),
                                      style:
                                          FilledButton.styleFrom(
                                        backgroundColor:
                                            const Color(
                                          0xFF6366F1,
                                        ),
                                        textStyle:
                                            GoogleFonts.dmSans(
                                          fontSize: 12,
                                          fontWeight:
                                              FontWeight.w600,
                                        ),
                                        visualDensity:
                                            VisualDensity
                                                .compact,
                                      ),
                                    ),
                                  OutlinedButton(
                                    onPressed: isActive
                                        ? null
                                        : () =>
                                            onAllocate(item),
                                    child: Text(
                                      isActive &&
                                              activeAction ==
                                                  'allocate'
                                          ? 'Allocating...'
                                          : item.isSuggested
                                              ? 'Override'
                                              : 'Allocate',
                                    ),
                                  ),
                                  if (item.matchStatus !=
                                      'rejected')
                                    TextButton(
                                      onPressed: isActive
                                          ? null
                                          : () =>
                                              onReject(item),
                                      child: Text(
                                        isActive &&
                                                activeAction ==
                                                    'reject'
                                            ? 'Rejecting...'
                                            : 'Reject',
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Updated ${dateFormat.format(item.updatedAt)}',
                                style: GoogleFonts.dmSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: palette.text3,
                                ),
                              ),
                              if (index == 0 &&
                                  totalCount >
                                      filtered.length) ...[
                                const SizedBox(height: 10),
                                Text(
                                  '${filtered.length}/$totalCount shown',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: palette.text3,
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
        ),
        Positioned(
          right: 12,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'ai_allocation',
            onPressed: isAiRunning ? null : onTriggerAi,
            backgroundColor: const Color(0xFF6366F1),
            icon: isAiRunning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(
                    Icons.auto_awesome,
                    size: 18,
                    color: Colors.white,
                  ),
            label: Text(
              isAiRunning ? 'Running...' : 'Run AI',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
