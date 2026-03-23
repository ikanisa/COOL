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
    required this.driverUsers,
    required this.verifiedUsers,
    required this.momoUsers,
    required this.mockBatches,
  });

  final int totalUsers;
  final int mockUsers;
  final int adminUsers;
  final int driverUsers;
  final int verifiedUsers;
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
        border: Border.all(color: colors.border),
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
                      label: 'Drivers',
                      value: driverUsers.toString(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CoolSpace.x2),
              Row(
                children: [
                  Expanded(
                    child: _MetricChip(
                      label: 'Verified',
                      value: verifiedUsers.toString(),
                    ),
                  ),
                  const SizedBox(width: CoolSpace.x2),
                  Expanded(
                    child: _MetricChip(
                      label: 'MoMo',
                      value: momoUsers.toString(),
                    ),
                  ),
                ],
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
        border: Border.all(color: colors.border),
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

class _UserTile extends ConsumerWidget {
  const _UserTile({required this.user, required this.onEdit});

  final Map<String, dynamic> user;
  final VoidCallback onEdit;

  Future<void> _toggleAdmin(BuildContext context, WidgetRef ref) async {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final userId = user['id']?.toString();
    if (userId == null || userId.isEmpty) return;

    final isAdmin = user['is_admin'] == true;
    final action = isAdmin ? 'Remove admin' : 'Make admin';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.overlaySurface,
        title: Text(
          '$action?',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.primaryText,
          ),
        ),
        content: Text(
          'This will ${isAdmin ? "remove" : "grant"} platform admin access for this user.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.tertiaryText,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(adminRepositoryProvider).toggleUserAdmin(userId, !isAdmin);
      ref.invalidate(adminUsersProvider);
      if (context.mounted) {
        CoolToast.success(
          context,
          isAdmin ? 'Admin access removed' : 'Admin access granted',
        );
      }
    } catch (e) {
      if (context.mounted) {
        CoolToast.error(context, 'Failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final publicUserId = PublicUserIdentity.resolve(
      publicUserId: user['public_user_id']?.toString(),
      userId: user['id']?.toString(),
      phone: user['phone']?.toString(),
    );
    final momoProvider = user['momo_provider']?.toString().trim() ?? '';
    final momoNumber = user['momo_number']?.toString().trim() ?? '';
    final vehicleType = user['vehicle_type']?.toString().trim() ?? '';
    final createdAt = user['created_at']?.toString().trim() ?? '';
    final kycStatus = user['kyc_status']?.toString().trim() ?? '';
    final isMock = user['is_mock'] == true;
    final isAdmin = user['is_admin'] == true;
    final isDriver = user['is_driver'] == true;
    final mockBatch = user['mock_batch']?.toString().trim() ?? '';

    return Semantics(
      button: true,
      hint: isAdmin
          ? 'Long press to remove admin access'
          : 'Long press to grant admin access',
      child: GestureDetector(
        onLongPress: () {
          HapticFeedback.mediumImpact();
          _toggleAdmin(context, ref);
        },
        child: Container(
          padding: _manageUsersCardPadding(),
          decoration: BoxDecoration(
            color: colors.operationalSurface,
            borderRadius: _manageUsersCardRadius,
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          publicUserId,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.primaryText,
                          ),
                        ),
                        if (user['phone']?.toString().isNotEmpty ?? false) ...[
                          const SizedBox(height: CoolSpace.x1),
                          Text(
                            user['phone'].toString(),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colors.secondaryText,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (isMock)
                        _MarkerChip(label: 'Mock', color: colors.warning),
                      if (isAdmin) ...[
                        if (isMock) const SizedBox(height: CoolSpace.x2),
                        _MarkerChip(label: 'Admin', color: colors.success),
                      ],
                      if (isDriver) ...[
                        if (isMock || isAdmin)
                          const SizedBox(height: CoolSpace.x2),
                        _MarkerChip(label: 'Driver', color: colors.info),
                      ],
                      if (kycStatus == 'verified') ...[
                        const SizedBox(height: CoolSpace.x2),
                        _MarkerChip(label: 'KYC ✓', color: colors.accent),
                      ] else if (kycStatus == 'pending_review') ...[
                        const SizedBox(height: CoolSpace.x2),
                        _MarkerChip(label: 'KYC ⏳', color: colors.warning),
                      ],
                      if (momoNumber.isNotEmpty) ...[
                        const SizedBox(height: CoolSpace.x2),
                        _MarkerChip(label: 'MoMo', color: colors.info),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: CoolSpace.x3),
              Text(
                '${AppMarket.country.name} · ${AppMarket.languageCode.toUpperCase()} · '
                '${momoProvider.isEmpty ? 'momo' : momoProvider}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.tertiaryText,
                ),
              ),
              if (vehicleType.isNotEmpty) ...[
                const SizedBox(height: CoolSpace.x1),
                Text(
                  'Vehicle: $vehicleType',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.tertiaryText,
                  ),
                ),
              ],
              if (isMock && mockBatch.isNotEmpty) ...[
                const SizedBox(height: CoolSpace.x2),
                Text(
                  'Batch: $mockBatch',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.warning,
                  ),
                ),
              ],
              if (createdAt.isNotEmpty) ...[
                const SizedBox(height: CoolSpace.x2),
                Text(
                  'Created: $createdAt',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.tertiaryText,
                  ),
                ),
              ],
              const SizedBox(height: CoolSpace.x3),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: CoolSpace.x3,
                runSpacing: CoolSpace.x3,
                children: [
                  OutlinedButton(
                    onPressed: () => _toggleAdmin(context, ref),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isAdmin ? colors.danger : colors.accent,
                      side: BorderSide(
                        color: isAdmin ? colors.danger : colors.accent,
                      ),
                      minimumSize: _manageUsersActionMinSize,
                      padding: _manageUsersActionPadding(),
                    ),
                    child: Text(isAdmin ? 'Remove Admin' : 'Make Admin'),
                  ),
                  TextButton(
                    onPressed: onEdit,
                    style: TextButton.styleFrom(
                      foregroundColor: colors.accent,
                      minimumSize: _manageUsersActionMinSize,
                      padding: _manageUsersActionPadding(),
                      textStyle: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: const Text('Edit'),
                  ),
                ],
              ),
            ],
          ),
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
          .read(adminRepositoryProvider)
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
