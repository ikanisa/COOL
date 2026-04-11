part of '../screens/manage_admin_roles_screen.dart';

EdgeInsets _adminRoleInputPadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x3,
  right: CoolSpace.x3,
  top: CoolSpace.x3,
  bottom: CoolSpace.x3,
);

EdgeInsets _adminRoleBadgePadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x2,
  right: CoolSpace.x2,
  top: CoolSpace.x1,
  bottom: CoolSpace.x1,
);

EdgeInsets _adminRoleActionPadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x3,
  right: CoolSpace.x3,
  top: CoolSpace.x2,
  bottom: CoolSpace.x2,
);

EdgeInsets _adminRoleScopePadding() => CoolSpace.sectionPadding.copyWith(
  left: 0,
  right: 0,
  top: 0,
  bottom: CoolSpace.x1,
);

EdgeInsets _adminRoleSheetInsets(BuildContext context) {
  final space = context.coolSpace;
  return CoolSpace.pagePadding.copyWith(
    top: space.x4,
    bottom: MediaQuery.of(context).viewInsets.bottom + space.x6,
  );
}

const BorderRadius _adminRoleFieldRadius = BorderRadius.all(
  Radius.circular(CoolRadii.xs),
);
const BorderRadius _adminRoleBadgeRadius = BorderRadius.all(
  Radius.circular(CoolRadii.pill),
);
const BorderRadius _adminRoleSheetRadius = BorderRadius.vertical(
  top: Radius.circular(CoolRadii.lg),
);

OutlineInputBorder _adminRoleInputBorder(
  BuildContext context, {
  Color? color,
  double width = 1,
}) {
  final colors = context.coolSemanticColors;
  return OutlineInputBorder(
    borderRadius: _adminRoleFieldRadius,
    borderSide: BorderSide(color: color ?? colors.border, width: width),
  );
}

Color _adminRoleColor(BuildContext context, AdminRole role) {
  final colors = context.coolSemanticColors;
  return switch (role) {
    AdminRole.admin => colors.success,
    AdminRole.bank => colors.accent,
  };
}

InputDecoration _roleInputDecoration(
  BuildContext context, {
  required String label,
  String? hintText,
  Widget? suffixIcon,
}) {
  final colors = context.coolSemanticColors;
  final theme = Theme.of(context);
  return InputDecoration(
    labelText: label,
    hintText: hintText,
    labelStyle: theme.textTheme.bodySmall?.copyWith(
      color: colors.tertiaryText,
      fontWeight: FontWeight.w600,
    ),
    hintStyle: theme.textTheme.bodySmall?.copyWith(color: colors.tertiaryText),
    filled: true,
    fillColor: colors.inputSurface,
    contentPadding: _adminRoleInputPadding(),
    suffixIcon: suffixIcon,
    border: _adminRoleInputBorder(context),
    enabledBorder: _adminRoleInputBorder(context),
    focusedBorder: _adminRoleInputBorder(
      context,
      color: colors.accent,
      width: 1.4,
    ),
  );
}

class _RoleAssignmentTile extends ConsumerStatefulWidget {
  const _RoleAssignmentTile({required this.assignment});

  final AdminRoleAssignment assignment;

  @override
  ConsumerState<_RoleAssignmentTile> createState() =>
      _RoleAssignmentTileState();
}

class _RoleAssignmentTileState extends ConsumerState<_RoleAssignmentTile> {
  bool _isRevoking = false;

  Color get _roleColor => _adminRoleColor(context, widget.assignment.role);

  Future<void> _revoke() async {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: colors.overlaySurface,
        title: Text(
          'Revoke Role',
          style: theme.textTheme.titleLarge?.copyWith(
            color: colors.primaryText,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          'Remove ${widget.assignment.role.label}'
          '${widget.assignment.bankName != null ? ' for ${widget.assignment.bankName}' : ''}?'
          ' This user can be assigned again later.',
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
              backgroundColor: colors.danger,
              foregroundColor: colors.accentForeground,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.revoke),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isRevoking = true);
    try {
      final repo = ref.read(adminRoleRepositoryProvider);
      await repo.revokeRole(assignmentId: widget.assignment.id);
      ref.invalidate(adminRoleAssignmentsProvider);
      if (!mounted) return;
      CoolToast.success(context, 'Role revoked.');
    } catch (error) {
      if (!mounted) return;
      CoolToast.error(context, 'Failed: $error');
    } finally {
      if (mounted) {
        setState(() => _isRevoking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final assignment = widget.assignment;
    final displayName =
        assignment.userName ?? assignment.userPhone ?? assignment.userId;
    final grantedDate =
        '${assignment.grantedAt.day}/${assignment.grantedAt.month}/${assignment.grantedAt.year}';

    return CoolCard(
      backgroundColor: colors.operationalSurface,
      useGradient: false,
      semanticsLabel: '$displayName. ${assignment.role.label}.',
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
                      displayName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.primaryText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (assignment.userPhone != null &&
                        assignment.userName != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        assignment.userPhone!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.tertiaryText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: _roleColor.withValues(alpha: 0.14),
                  borderRadius: _adminRoleBadgeRadius,
                ),
                child: Padding(
                  padding: _adminRoleBadgePadding(),
                  child: Text(
                    assignment.role.label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: _roleColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (assignment.bankName != null)
            Padding(
              padding: _adminRoleScopePadding(),
              child: Text(
                '${assignment.role == AdminRole.bank ? 'Bank' : 'Scope'}: ${assignment.bankName}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.secondaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          Text(
            'Granted: $grantedDate',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.tertiaryText,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (assignment.notes != null && assignment.notes!.isNotEmpty) ...[
            const SizedBox(height: CoolSpace.x1),
            Text(
              assignment.notes!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.tertiaryText,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: CoolSpace.x3),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _isRevoking ? null : _revoke,
              icon: _isRevoking
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CupertinoActivityIndicator(radius: 7),
                    )
                  : const Icon(CoolIcons.removeCircle, size: 16),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.danger,
                side: BorderSide(color: colors.danger.withValues(alpha: 0.7)),
                minimumSize: const Size(0, CoolTapTargets.minimum),
                padding: _adminRoleActionPadding(),
              ),
              label: Text(
                'Revoke',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
