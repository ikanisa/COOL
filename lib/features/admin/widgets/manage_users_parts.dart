part of '../screens/manage_users_screen.dart';

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
      await ref
          .read(adminUsersRepositoryProvider)
          .toggleUserAdmin(userId, !isAdmin);
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
    final createdAt = user['created_at']?.toString().trim() ?? '';
    final isMock = user['is_mock'] == true;
    final isAdmin = user['is_admin'] == true;
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
            boxShadow: CoolShadows.ambientFloat(strength: 0.15),
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
