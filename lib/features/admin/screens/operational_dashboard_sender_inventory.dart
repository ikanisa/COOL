part of 'operational_dashboard_screen.dart';

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
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'This keeps the raw SMS history unchanged, but marks $senderDisplay as reviewed legacy unsupported sender history.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.secondaryText,
            fontWeight: FontWeight.w400,
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
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'This records the visible unsupported senders as reviewed legacy history without altering raw SMS records.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.secondaryText,
            fontWeight: FontWeight.w400,
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
                      fontWeight: FontWeight.w600,
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
