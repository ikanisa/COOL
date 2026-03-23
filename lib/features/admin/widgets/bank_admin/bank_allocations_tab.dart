import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/cool_foundations.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_empty_view.dart';
import '../../models/bank_admin_models.dart';
import 'bank_admin_helpers.dart';

EdgeInsets _bankAllocationFilterPadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x1,
  right: CoolSpace.x1,
  top: 0,
  bottom: 0,
);

EdgeInsets _bankAllocationListPadding() =>
    CoolSpace.scaffoldPadding.copyWith(left: 0, right: 0, top: 0);

EdgeInsets _bankAllocationSuggestionPadding() =>
    CoolSpace.sectionPadding.copyWith(
      left: CoolSpace.x3,
      right: CoolSpace.x3,
      top: CoolSpace.x2,
      bottom: CoolSpace.x2,
    );

const BorderRadius _bankAllocationChipRadius = BorderRadius.all(
  Radius.circular(CoolRadii.pill),
);

const BorderRadius _bankAllocationSuggestionRadius = BorderRadius.all(
  Radius.circular(CoolRadii.xs),
);

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

  static const List<(String, String)> _filters = <(String, String)>[
    ('all', 'All'),
    ('suggested', 'Suggested'),
    ('manual_review', 'Manual'),
    ('pending_review', 'Pending'),
    ('rejected', 'Rejected'),
  ];

  Color _statusColor(BuildContext context, String status) {
    final colors = context.coolSemanticColors;
    switch (status) {
      case 'suggested':
        return colors.info;
      case 'manual_review':
        return colors.warning;
      case 'pending_review':
        return colors.neutral;
      case 'rejected':
        return colors.danger;
      case 'matched':
        return colors.success;
      default:
        return colors.tertiaryText;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final moneyFormat = NumberFormat.decimalPattern('en_US');
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');
    final filtered = statusFilter == 'all'
        ? items
        : items.where((item) => item.matchStatus == statusFilter).toList();

    return Stack(
      children: [
        Column(
          children: [
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: _bankAllocationFilterPadding(),
                itemCount: _filters.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final (value, label) = _filters[index];
                  final selected = statusFilter == value;
                  final count = value == 'all'
                      ? items.length
                      : items.where((item) => item.matchStatus == value).length;
                  return FilterChip(
                    label: Text('$label${count > 0 ? ' ($count)' : ''}'),
                    selected: selected,
                    onSelected: (_) => onStatusFilterChanged(value),
                    backgroundColor: colors.chipBackground,
                    selectedColor: colors.chipSelectedBackground,
                    labelStyle: theme.textTheme.bodySmall?.copyWith(
                      color: selected
                          ? colors.primaryText
                          : colors.secondaryText,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                    side: BorderSide(
                      color: selected ? colors.accent : colors.border,
                    ),
                    shape: const RoundedRectangleBorder(
                      borderRadius: _bankAllocationChipRadius,
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
                      padding: _bankAllocationListPadding(),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        final isActive = activeReviewId == item.reviewId;
                        final color = _statusColor(context, item.matchStatus);

                        return CoolCard(
                          backgroundColor: colors.operationalSurface,
                          borderColor: item.isSuggested
                              ? colors.info.withValues(alpha: 0.3)
                              : colors.border,
                          useGradient: false,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.groupName,
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            color: colors.primaryText,
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  ),
                                  BankStatusTag(
                                    label: bankTitle(item.matchStatus),
                                    backgroundColor: color.withValues(
                                      alpha: 0.12,
                                    ),
                                    foregroundColor: color,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                item.payerName,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colors.secondaryText,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${moneyFormat.format(item.amount)} RWF',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: colors.primaryText,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Reason: ${bankTitle(item.reason)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.secondaryText,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if ((item.reference?.trim().isNotEmpty ?? false))
                                Text(
                                  'Reference: ${item.reference}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.secondaryText,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              if ((item.payeeDigits?.trim().isNotEmpty ??
                                  false))
                                Text(
                                  'Payee: ${item.payeeDigits}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.secondaryText,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              if (item.isSuggested) ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding: _bankAllocationSuggestionPadding(),
                                  decoration: BoxDecoration(
                                    color: colors.info.withValues(alpha: 0.08),
                                    borderRadius:
                                        _bankAllocationSuggestionRadius,
                                    border: Border.all(
                                      color: colors.info.withValues(
                                        alpha: 0.22,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.auto_awesome,
                                        size: 16,
                                        color: colors.info,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          '→ ${item.suggestedMemberName ?? 'Suggested member'} · ${(item.suggestedConfidence ?? 0).toStringAsFixed(0)}%',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: colors.info,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (item.aiReasoning != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    item.aiReasoning!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.tertiaryText,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
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
                                          : () => onAcceptSuggestion(item),
                                      icon: isActive && activeAction == 'accept'
                                          ? SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: colors.accentForeground,
                                              ),
                                            )
                                          : const Icon(Icons.check, size: 16),
                                      label: Text(
                                        isActive && activeAction == 'accept'
                                            ? 'Accepting...'
                                            : 'Accept',
                                      ),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: colors.info,
                                        foregroundColor:
                                            colors.accentForeground,
                                        textStyle: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ),
                                  OutlinedButton(
                                    onPressed: isActive
                                        ? null
                                        : () => onAllocate(item),
                                    child: Text(
                                      isActive && activeAction == 'allocate'
                                          ? 'Allocating...'
                                          : item.isSuggested
                                          ? 'Override'
                                          : 'Allocate',
                                    ),
                                  ),
                                  if (item.matchStatus != 'rejected')
                                    TextButton(
                                      onPressed: isActive
                                          ? null
                                          : () => onReject(item),
                                      child: Text(
                                        isActive && activeAction == 'reject'
                                            ? 'Rejecting...'
                                            : 'Reject',
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Updated ${dateFormat.format(item.updatedAt)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.tertiaryText,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (index == 0 &&
                                  totalCount > filtered.length) ...[
                                const SizedBox(height: 10),
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
        ),
        Positioned(
          right: 12,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'ai_allocation',
            onPressed: isAiRunning ? null : onTriggerAi,
            backgroundColor: colors.info,
            foregroundColor: colors.accentForeground,
            icon: isAiRunning
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.accentForeground,
                    ),
                  )
                : const Icon(Icons.auto_awesome, size: 18),
            label: Text(
              isAiRunning ? 'Running...' : 'Run AI',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.accentForeground,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
