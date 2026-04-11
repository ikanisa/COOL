part of '../screens/manage_users_screen.dart';

class _UserTile extends ConsumerWidget {
  const _UserTile({required this.user, required this.onEdit});

  final Map<String, dynamic> user;
  final VoidCallback onEdit;

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
      hint: 'Tap Edit to update user details',
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
                    fontWeight: FontWeight.w500,
                    color: colors.warning,
                  ),
                ),
              ],
              if (createdAt.isNotEmpty) ...[
                const SizedBox(height: CoolSpace.x2),
                Text(
                  'Created: $createdAt',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colors.tertiaryText,
                  ),
                ),
              ],
              const SizedBox(height: CoolSpace.x3),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
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
              ),
            ],
          ),
      ),
    );
  }
}
