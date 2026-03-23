import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/admin_detail_scaffold.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/admin_section_header.dart';
import '../providers/admin_providers.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../core/l10n/l10n.dart';

part 'operational_dashboard_parts.dart';

EdgeInsets _operationalMetricChipPadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x3,
  right: CoolSpace.x3,
  top: CoolSpace.x2,
  bottom: CoolSpace.x2,
);

EdgeInsets _operationalBadgePadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x3,
  right: CoolSpace.x3,
  top: CoolSpace.x1,
  bottom: CoolSpace.x1,
);
const BorderRadius _operationalPillRadius = BorderRadius.all(
  Radius.circular(CoolRadii.pill),
);

class OperationalDashboardScreen extends ConsumerWidget {
  const OperationalDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final dashboardAsync = ref.watch(adminOperationalReleaseDashboardProvider);
    final triageAsync = ref.watch(adminOperationalTriageIssuesProvider);
    final momoSmsSummaryAsync = ref.watch(
      adminMomoSmsOperationalSummaryProvider,
    );
    final eventsAsync = ref.watch(adminRecentOperationalHealthEventsProvider);

    Future<void> refresh() async {
      ref.invalidate(adminOperationalReleaseDashboardProvider);
      ref.invalidate(adminOperationalTriageIssuesProvider);
      ref.invalidate(adminMomoSmsOperationalSummaryProvider);
      ref.invalidate(adminMomoSmsSenderInventoryProvider);
      ref.invalidate(adminMomoSmsManualReviewQueueProvider);
      ref.invalidate(adminRecentOperationalHealthEventsProvider);
    }

    return AdminDetailScaffold(
      backTooltip: context.l10n.back,
      onBack: () => Navigator.of(context).pop(),
      actions: [
        IconButton(
          tooltip: context.l10n.refresh,
          onPressed: refresh,
          icon: const Icon(Icons.refresh_rounded),
          color: colors.primaryText,
        ),
      ],
      child: RefreshIndicator(
        color: colors.accent,
        onRefresh: refresh,
        child: ListView(
          padding: CoolSpace.scaffoldPadding,
          children: [
            Text(
              'Operations',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.1,
                color: colors.primaryText,
              ),
            ),
            const SizedBox(height: CoolSpace.x6),
            AdminSectionHeader(
              title: context.l10n.releaseDashboard,
              message: 'Live health by monitored',
            ),
            const SizedBox(height: CoolSpace.x3),
            CoolAsyncView<List<Map<String, dynamic>>>(
              value: dashboardAsync,
              onRetry: refresh,
              loadingWidget: const CoolSkeletonList(itemCount: 3),
              emptyCheck: (rows) => rows.isEmpty,
              emptyWidget: const CoolEmptyView(
                message: 'No operational dashboard yet',
                icon: Icons.monitor_heart_outlined,
              ),
              builder: (rows) => Column(
                children: _spacedChildren(
                  rows,
                  (row) => _DashboardCard(row: row),
                ),
              ),
            ),
            const SizedBox(height: CoolSpace.x6),
            const AdminSectionHeader(
              title: 'Triage Queue',
              message: 'Focused on failed payment',
            ),
            const SizedBox(height: CoolSpace.x3),
            CoolAsyncView<List<Map<String, dynamic>>>(
              value: triageAsync,
              onRetry: refresh,
              loadingWidget: const CoolSkeletonList(itemCount: 3),
              emptyCheck: (rows) => rows.isEmpty,
              emptyWidget: const CoolEmptyView(
                message: 'No release-blocking operational issues',
                icon: Icons.fact_check_outlined,
              ),
              builder: (rows) => Column(
                children: _spacedChildren(
                  rows,
                  (row) => _IssueCard(row: row),
                  spacing: CoolSpace.x2,
                ),
              ),
            ),
            const SizedBox(height: CoolSpace.x6),
            const AdminSectionHeader(
              title: 'M-Money SMS',
              message:
                  'Device sync audits, parser backlog, sender backlog, migration safety, reconciliation pressure, and retention backlog.',
            ),
            const SizedBox(height: CoolSpace.x3),
            CoolAsyncView<List<Map<String, dynamic>>>(
              value: momoSmsSummaryAsync,
              onRetry: refresh,
              loadingWidget: const CoolSkeletonList(itemCount: 4),
              emptyCheck: (rows) => rows.isEmpty,
              emptyWidget: const CoolEmptyView(
                message: 'No M-Money SMS operational summary',
                icon: Icons.sms_outlined,
              ),
              builder: (rows) => Column(
                children: _spacedChildren(
                  rows,
                  (row) => _OperationalMetricCard(row: row),
                  spacing: CoolSpace.x2,
                ),
              ),
            ),
            const SizedBox(height: CoolSpace.x6),
            const AdminSectionHeader(
              title: 'Sender Inventory Audit',
              message: 'Unsupported or alias sender drift detected.',
            ),
            const SizedBox(height: CoolSpace.x3),
            const _SenderInventorySection(),
            const SizedBox(height: CoolSpace.x6),
            const AdminSectionHeader(
              title: 'Generic Manual Review',
              message: 'SMS that could not be app-linked.',
            ),
            const SizedBox(height: CoolSpace.x3),
            const _ManualReviewSection(),
            const SizedBox(height: CoolSpace.x6),
            const AdminSectionHeader(
              title: 'Recent Activity',
              message: 'Operational health stream',
            ),
            const SizedBox(height: CoolSpace.x3),
            CoolAsyncView<List<Map<String, dynamic>>>(
              value: eventsAsync,
              onRetry: refresh,
              loadingWidget: const CoolSkeletonList(itemCount: 5),
              emptyCheck: (rows) => rows.isEmpty,
              emptyWidget: const CoolEmptyView(
                message: 'No recent operational events',
                icon: Icons.history_rounded,
              ),
              builder: (rows) => Column(
                children: _spacedChildren(
                  rows,
                  (row) => _EventTile(row: row),
                  spacing: CoolSpace.x2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualReviewSection extends ConsumerStatefulWidget {
  const _ManualReviewSection();

  @override
  ConsumerState<_ManualReviewSection> createState() =>
      _ManualReviewSectionState();
}

class _ManualReviewSectionState extends ConsumerState<_ManualReviewSection> {
  static const List<(String, String)> _filters = <(String, String)>[
    ('needs_review', 'Needs Review'),
    ('unmatched_payment', 'Unmatched'),
    ('non_actionable', 'Non-actionable'),
    ('all', 'All'),
  ];

  String _filter = 'needs_review';
  String? _activeReviewId;
  bool _isBulkClosing = false;

  bool get _isBusy => _activeReviewId != null || _isBulkClosing;

  Future<void> _refreshQueue() async {
    ref.invalidate(adminMomoSmsManualReviewQueueProvider);
  }

  Future<void> _closeReview(Map<String, dynamic> row) async {
    final reviewId = _text(row['review_id']);
    if (reviewId == null || _isBusy) {
      return;
    }

    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final shouldClose = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: colors.overlaySurface,
        title: Text(
          'Close manual review?',
          style: theme.textTheme.titleLarge?.copyWith(
            color: colors.primaryText,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          'This will mark the SMS reconciliation review as not app-linked while keeping the wallet history intact.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.secondaryText,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: colors.accentForeground,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Close review'),
          ),
        ],
      ),
    );

    if (shouldClose != true || !mounted) {
      return;
    }

    setState(() => _activeReviewId = reviewId);
    try {
      await ref
          .read(adminMomoOpsRepositoryProvider)
          .rejectMomoSmsManualReview(reviewId: reviewId);
      await _refreshQueue();
      if (mounted) {
        CoolToast.success(context, 'Manual review closed.');
      }
    } catch (_) {
      if (mounted) {
        CoolToast.error(context, 'Could not close this review right now.');
      }
    } finally {
      if (mounted) {
        setState(() => _activeReviewId = null);
      }
    }
  }

  Future<void> _closeVisible(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty || _isBusy) {
      return;
    }

    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final shouldClose = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: colors.overlaySurface,
        title: Text(
          'Close ${rows.length} reviews?',
          style: theme.textTheme.titleLarge?.copyWith(
            color: colors.primaryText,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          'This bulk action closes the visible manual reviews as not app-linked. Wallet statements will remain available.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.secondaryText,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: colors.accentForeground,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Close visible'),
          ),
        ],
      ),
    );

    if (shouldClose != true || !mounted) {
      return;
    }

    final reviewIds = rows
        .map((row) => _text(row['review_id']))
        .whereType<String>()
        .toList(growable: false);
    if (reviewIds.isEmpty) {
      return;
    }

    setState(() => _isBulkClosing = true);
    try {
      final closedCount = await ref
          .read(adminMomoOpsRepositoryProvider)
          .rejectMomoSmsManualReviewBatch(reviewIds: reviewIds);
      await _refreshQueue();
      if (mounted) {
        CoolToast.success(
          context,
          closedCount > 0
              ? 'Closed $closedCount manual reviews.'
              : 'No eligible manual reviews were closed.',
        );
      }
    } catch (_) {
      if (mounted) {
        CoolToast.error(context, 'Could not close the visible reviews.');
      }
    } finally {
      if (mounted) {
        setState(() => _isBulkClosing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final queueAsync = ref.watch(adminMomoSmsManualReviewQueueProvider);
    return CoolAsyncView<List<Map<String, dynamic>>>(
      value: queueAsync,
      onRetry: _refreshQueue,
      loadingWidget: const CoolSkeletonList(itemCount: 3),
      emptyCheck: (rows) => rows.isEmpty,
      emptyWidget: const CoolEmptyView(
        message: 'No generic M-Money SMS manual reviews are open.',
        icon: Icons.task_alt_outlined,
      ),
      builder: (rows) {
        final visibleRows = _visibleManualReviews(rows, _filter);
        final totalCount = rows.isEmpty ? 0 : _count(rows.first['total_count']);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _filters.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final (value, label) = _filters[index];
                  final count = value == 'all'
                      ? rows.length
                      : rows
                            .where((row) => _manualReviewKind(row) == value)
                            .length;
                  final selected = _filter == value;
                  return FilterChip(
                    label: Text('$label${count > 0 ? ' ($count)' : ''}'),
                    selected: selected,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    backgroundColor: colors.inputSurface,
                    selectedColor: colors.accent.withValues(alpha: 0.16),
                    labelStyle: theme.textTheme.labelLarge?.copyWith(
                      color: selected ? colors.accent : colors.secondaryText,
                      fontWeight: FontWeight.w700,
                    ),
                    side: BorderSide(
                      color: selected ? colors.accent : colors.border,
                    ),
                    onSelected: (_) => setState(() => _filter = value),
                    visualDensity: VisualDensity.compact,
                  );
                },
              ),
            ),
            const SizedBox(height: CoolSpace.x3),
            if (visibleRows.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _isBusy ? null : () => _closeVisible(visibleRows),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: colors.accentForeground,
                    minimumSize: const Size(0, CoolTapTargets.minimum),
                  ),
                  icon: _isBulkClosing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.task_alt_outlined, size: 16),
                  label: Text(
                    _isBulkClosing
                        ? 'Closing...'
                        : 'Close visible (${visibleRows.length})',
                  ),
                ),
              ),
            if (visibleRows.isNotEmpty) const SizedBox(height: CoolSpace.x3),
            if (visibleRows.isEmpty)
              CoolEmptyView(
                compact: true,
                message: _filter == 'all'
                    ? 'No manual reviews matched the current filter.'
                    : 'No ${_reviewKindLabel(_filter).toLowerCase()} reviews are open.',
                icon: Icons.inbox_outlined,
              )
            else
              Column(
                children: [
                  ..._spacedChildren(
                    visibleRows,
                    (row) => _ManualReviewCard(
                      row: row,
                      isBusy:
                          _activeReviewId == _text(row['review_id']) ||
                          _isBulkClosing,
                      onClose: () => _closeReview(row),
                    ),
                  ),
                  if (totalCount > visibleRows.length)
                    Column(
                      children: [
                        const SizedBox(height: CoolSpace.x1),
                        Text(
                          '${visibleRows.length}/$totalCount shown',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.tertiaryText,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}



class _SenderInventorySection extends ConsumerStatefulWidget {
  const _SenderInventorySection();

  @override
  ConsumerState<_SenderInventorySection> createState() =>
      _SenderInventorySectionState();
}

class _SenderInventorySectionState
    extends ConsumerState<_SenderInventorySection> {
  static const List<(String, String)> _filters = <(String, String)>[
    ('unresolved', 'Unresolved'),
    ('acknowledged', 'Acknowledged'),
    ('all', 'All'),
  ];

  String? _activeSenderToken;
  String _filter = 'unresolved';
  bool _isBulkAcknowledging = false;

  Future<void> _refreshInventory() async {
    ref.invalidate(adminMomoSmsSenderInventoryProvider);
  }

  Future<void> _acknowledgeSender(Map<String, dynamic> row) async {
    final senderToken = _text(row['sender_token']);
    final senderDisplay = _text(row['sender']) ?? 'this sender';
    if (senderToken == null ||
        _activeSenderToken != null ||
        _isBulkAcknowledging) {
      return;
    }

    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final shouldAcknowledge = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: colors.overlaySurface,
        title: Text(
          'Acknowledge legacy sender?',
          style: theme.textTheme.titleLarge?.copyWith(
            color: colors.primaryText,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          'This keeps the raw SMS history unchanged, but marks $senderDisplay as reviewed legacy unsupported sender history.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.secondaryText,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: colors.accentForeground,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Acknowledge'),
          ),
        ],
      ),
    );

    if (shouldAcknowledge != true || !mounted) {
      return;
    }

    setState(() => _activeSenderToken = senderToken);
    try {
      await ref
          .read(adminMomoOpsRepositoryProvider)
          .acknowledgeMomoSmsSenderInventory(senderToken: senderToken);
      await _refreshInventory();
      if (mounted) {
        CoolToast.success(context, 'Legacy sender acknowledged.');
      }
    } catch (_) {
      if (mounted) {
        CoolToast.error(
          context,
          'Could not acknowledge this sender right now.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _activeSenderToken = null);
      }
    }
  }

  Future<void> _acknowledgeVisible(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty || _activeSenderToken != null || _isBulkAcknowledging) {
      return;
    }

    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final shouldAcknowledge = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: colors.overlaySurface,
        title: Text(
          'Acknowledge ${rows.length} senders?',
          style: theme.textTheme.titleLarge?.copyWith(
            color: colors.primaryText,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          'This records the visible unsupported senders as reviewed legacy history without altering raw SMS records.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.secondaryText,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: colors.accentForeground,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Acknowledge visible'),
          ),
        ],
      ),
    );

    if (shouldAcknowledge != true || !mounted) {
      return;
    }

    final senderTokens = rows
        .map((row) => _text(row['sender_token']))
        .whereType<String>()
        .toList(growable: false);
    if (senderTokens.isEmpty) {
      return;
    }

    setState(() => _isBulkAcknowledging = true);
    try {
      final acknowledgedCount = await ref
          .read(adminMomoOpsRepositoryProvider)
          .acknowledgeMomoSmsSenderInventoryBatch(senderTokens: senderTokens);
      await _refreshInventory();
      if (mounted) {
        CoolToast.success(
          context,
          acknowledgedCount > 0
              ? 'Acknowledged $acknowledgedCount sender backlogs.'
              : 'No sender backlogs needed acknowledgement.',
        );
      }
    } catch (_) {
      if (mounted) {
        CoolToast.error(
          context,
          'Could not acknowledge the visible senders right now.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isBulkAcknowledging = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final inventoryAsync = ref.watch(adminMomoSmsSenderInventoryProvider);
    return CoolAsyncView<List<Map<String, dynamic>>>(
      value: inventoryAsync,
      onRetry: _refreshInventory,
      loadingWidget: const CoolSkeletonList(itemCount: 2),
      emptyCheck: (rows) => rows.isEmpty,
      emptyWidget: const CoolEmptyView(
        message: 'No unsupported M-Money SMS senders are currently stored.',
        icon: Icons.verified_user_outlined,
      ),
      builder: (rows) {
        final visibleRows = _visibleSenderInventoryRows(rows, _filter);
        final acknowledgeableRows = visibleRows
            .where((row) => _text(row['resolution_status']) == null)
            .toList(growable: false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _filters.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final (value, label) = _filters[index];
                  final count = rows
                      .where((row) => _senderInventoryMatchesFilter(row, value))
                      .length;
                  final selected = _filter == value;
                  return FilterChip(
                    label: Text('$label${count > 0 ? ' ($count)' : ''}'),
                    selected: selected,
                    labelStyle: theme.textTheme.labelMedium?.copyWith(
                      color: selected ? colors.accent : colors.secondaryText,
                      fontWeight: FontWeight.w700,
                    ),
                    side: BorderSide(
                      color: selected ? colors.accent : colors.border,
                    ),
                    onSelected: (_) => setState(() => _filter = value),
                    visualDensity: VisualDensity.compact,
                  );
                },
              ),
            ),
            const SizedBox(height: CoolSpace.x3),
            if (acknowledgeableRows.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed:
                      (_activeSenderToken != null || _isBulkAcknowledging)
                      ? null
                      : () => _acknowledgeVisible(acknowledgeableRows),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: colors.accentForeground,
                    minimumSize: const Size(0, CoolTapTargets.minimum),
                  ),
                  icon: _isBulkAcknowledging
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.fact_check_outlined, size: 16),
                  label: Text(
                    _isBulkAcknowledging
                        ? 'Saving...'
                        : 'Acknowledge visible (${acknowledgeableRows.length})',
                  ),
                ),
              ),
            if (acknowledgeableRows.isNotEmpty)
              const SizedBox(height: CoolSpace.x3),
            if (visibleRows.isEmpty)
              CoolEmptyView(
                compact: true,
                message: _senderInventoryEmptyMessage(rows, _filter),
                icon: Icons.fact_check_outlined,
              )
            else
              Column(
                children: _spacedChildren(
                  visibleRows,
                  (row) => _SenderInventoryCard(
                    row: row,
                    isBusy: _activeSenderToken == _text(row['sender_token']),
                    onAcknowledge: () => _acknowledgeSender(row),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
