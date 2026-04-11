part of 'operational_dashboard_screen.dart';

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
            fontWeight: FontWeight.w500,
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
            fontWeight: FontWeight.w500,
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
        icon: CoolIcons.taskComplete,
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
                      : const Icon(CoolIcons.taskComplete, size: 16),
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
                icon: CoolIcons.inbox,
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
                            fontWeight: FontWeight.w500,
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
