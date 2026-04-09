part of '../screens/manage_users_screen.dart';

EdgeInsets _manageUsersCardPadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x4,
  right: CoolSpace.x4,
  top: CoolSpace.x4,
  bottom: CoolSpace.x4,
);

EdgeInsets _manageUsersMetricPadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x3,
  right: CoolSpace.x3,
  top: CoolSpace.x2,
  bottom: CoolSpace.x2,
);

EdgeInsets _manageUsersActionPadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x3,
  right: CoolSpace.x3,
  top: CoolSpace.x2,
  bottom: CoolSpace.x2,
);

EdgeInsets _manageUsersMarkerPadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x2,
  right: CoolSpace.x2,
  top: CoolSpace.x1,
  bottom: CoolSpace.x1,
);
const BorderRadius _manageUsersCardRadius = BorderRadius.all(
  Radius.circular(CoolRadii.sm),
);
const BorderRadius _manageUsersElementRadius = BorderRadius.all(
  Radius.circular(CoolRadii.xs),
);
const Size _manageUsersActionMinSize = Size(0, CoolTapTargets.minimum);

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.totalUsers,
    required this.mockUsers,
    required this.adminUsers,
    required this.momoUsers,
    required this.mockBatches,
  });

  final int totalUsers;
  final int mockUsers;
  final int adminUsers;
  final int momoUsers;
  final List<String> mockBatches;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Container(
      padding: _manageUsersCardPadding(),
      decoration: BoxDecoration(
        color: colors.operationalSurface,
        borderRadius: _manageUsersCardRadius,
        boxShadow: CoolShadows.ambientFloat(strength: 0.15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'User Inventory',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            'Demo users are tagged',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.tertiaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
          Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _MetricChip(
                      label: 'Total',
                      value: totalUsers.toString(),
                    ),
                  ),
                  const SizedBox(width: CoolSpace.x2),
                  Expanded(
                    child: _MetricChip(
                      label: 'Mock',
                      value: mockUsers.toString(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CoolSpace.x2),
              Row(
                children: [
                  Expanded(
                    child: _MetricChip(
                      label: 'Admins',
                      value: adminUsers.toString(),
                    ),
                  ),
                  const SizedBox(width: CoolSpace.x2),
                  Expanded(
                    child: _MetricChip(
                      label: 'Batches',
                      value: mockBatches.length.toString(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CoolSpace.x2),
              Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: _MetricChip(
                    label: 'MoMo',
                    value: momoUsers.toString(),
                  ),
                ),
              ),
            ],
          ),
          if (mockBatches.isNotEmpty) ...[
            const SizedBox(height: CoolSpace.x4),
            Text(
              'Cleanup',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.primaryText,
              ),
            ),
            const SizedBox(height: CoolSpace.x2),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < mockBatches.length; index++) ...[
                  _BatchCleanupButton(batch: mockBatches[index]),
                  if (index < mockBatches.length - 1)
                    const SizedBox(height: CoolSpace.x2),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Container(
      padding: _manageUsersMetricPadding(),
      decoration: BoxDecoration(
        color: colors.inputSurface,
        borderRadius: _manageUsersElementRadius,
        boxShadow: CoolShadows.ambientFloat(strength: 0.15),
      ),
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.primaryText,
          ),
          children: [
            TextSpan(
              text: '$value ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(
              text: label,
              style: TextStyle(
                color: colors.tertiaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarkerChip extends StatelessWidget {
  const _MarkerChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: _manageUsersMarkerPadding(),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: _manageUsersElementRadius,
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _BatchCleanupButton extends ConsumerStatefulWidget {
  const _BatchCleanupButton({required this.batch});

  final String batch;

  @override
  ConsumerState<_BatchCleanupButton> createState() =>
      _BatchCleanupButtonState();
}

class _BatchCleanupButtonState extends ConsumerState<_BatchCleanupButton> {
  bool _isLoading = false;

  Future<void> _purgeBatch() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final colors = context.coolSemanticColors;
        final theme = Theme.of(context);
        return AlertDialog(
          backgroundColor: colors.overlaySurface,
          title: Text(
            'Remove Mock Batch?',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.primaryText,
            ),
          ),
          content: Text(
            'This deletes all rows in the batch. If your current admin account '
            'belongs to it, you may lose access immediately after cleanup.',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.tertiaryText,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colors.danger,
                foregroundColor: colors.accentForeground,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.deleteBatch),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _isLoading = true);
    try {
      final result = await ref
          .read(adminUsersRepositoryProvider)
          .purgeMockBatch(widget.batch);

      ref.invalidate(adminUsersProvider);
      ref.invalidate(adminPartnersProvider);
      ref.invalidate(adminPartnerServicesProvider(null));

      if (!mounted) {
        return;
      }

      final deleted = result['deleted'];
      final summary = deleted is Map
          ? deleted.entries
                .where((entry) {
                  final value = entry.value;
                  return value is num && value > 0;
                })
                .map((entry) => '${entry.key}: ${entry.value}')
                .take(4)
                .join(', ')
          : '';

      CoolToast.success(
        context,
        summary.isEmpty
            ? 'Removed mock batch ${widget.batch}.'
            : 'Removed ${widget.batch}. $summary',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      CoolToast.error(context, 'Cleanup failed: $error');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return OutlinedButton.icon(
      onPressed: _isLoading ? null : _purgeBatch,
      icon: _isLoading
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CupertinoActivityIndicator(radius: 7),
            )
          : const Icon(Icons.delete_outline_rounded, size: 16),
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.warning,
        side: BorderSide(color: colors.warning),
        minimumSize: _manageUsersActionMinSize,
        padding: _manageUsersActionPadding(),
      ),
      label: Text(
        widget.batch,
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
