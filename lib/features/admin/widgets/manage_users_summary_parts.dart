part of '../screens/manage_users_screen.dart';

EdgeInsets _manageUsersActionPadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x3,
  right: CoolSpace.x3,
  top: CoolSpace.x2,
  bottom: CoolSpace.x2,
);

const Size _manageUsersActionMinSize = Size(0, CoolTapTargets.minimum);

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
              fontWeight: FontWeight.w500,
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
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
