part of '../screens/manage_admin_roles_screen.dart';

EdgeInsets _adminRoleInputPadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x3,
  right: CoolSpace.x3,
  top: CoolSpace.x3,
  bottom: CoolSpace.x3,
);

EdgeInsets _adminRoleMetricPadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x3,
  right: CoolSpace.x3,
  top: CoolSpace.x2,
  bottom: CoolSpace.x2,
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
  switch (role) {
    case AdminRole.admin:
      return colors.success;
    case AdminRole.bank:
      return colors.info;
    case AdminRole.rayonSport:
      return colors.accent;
  }
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

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.totalAssignments,
    required this.adminCount,
    required this.bankCount,
    required this.rayonCount,
  });

  final int totalAssignments;
  final int adminCount;
  final int bankCount;
  final int rayonCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return CoolCard(
      backgroundColor: colors.operationalSurface,
      useGradient: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Role Summary',
            style: theme.textTheme.titleLarge?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricChip(
                label: context.l10n.total,
                value: totalAssignments.toString(),
                color: colors.primaryText,
              ),
              _MetricChip(
                label: context.l10n.admin,
                value: adminCount.toString(),
                color: colors.success,
              ),
              _MetricChip(
                label: context.l10n.bank,
                value: bankCount.toString(),
                color: colors.info,
              ),
              _MetricChip(
                label: context.l10n.rayon,
                value: rayonCount.toString(),
                color: colors.accent,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.inputSurface,
        borderRadius: _adminRoleFieldRadius,
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: _adminRoleMetricPadding(),
        child: RichText(
          text: TextSpan(
            style: theme.textTheme.labelLarge?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w700,
            ),
            children: [
              TextSpan(
                text: '$value ',
                style: TextStyle(color: color),
              ),
              TextSpan(
                text: label,
                style: TextStyle(color: colors.tertiaryText),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
          '${widget.assignment.partnerName != null ? ' for ${widget.assignment.partnerName}' : ''}?'
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
                  border: Border.all(color: _roleColor.withValues(alpha: 0.24)),
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
          if (assignment.partnerName != null)
            Padding(
              padding: _adminRoleScopePadding(),
              child: Text(
                'Scope: ${assignment.partnerName}',
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
            const SizedBox(height: 4),
            Text(
              assignment.notes!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.tertiaryText,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 12),
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
                  : const Icon(Icons.remove_circle_outline_rounded, size: 16),
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

class _AssignRoleSheet extends ConsumerStatefulWidget {
  const _AssignRoleSheet({required this.ref});

  final WidgetRef ref;

  @override
  ConsumerState<_AssignRoleSheet> createState() => _AssignRoleSheetState();
}

class _AssignRoleSheetState extends ConsumerState<_AssignRoleSheet> {
  final _userIdController = TextEditingController();
  AdminRole _selectedRole = AdminRole.admin;
  String? _selectedPartnerId;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _userIdController.addListener(_handleInputChanged);
  }

  @override
  void dispose() {
    _userIdController.removeListener(_handleInputChanged);
    _userIdController.dispose();
    super.dispose();
  }

  void _handleInputChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  bool get _needsPartnerScope =>
      _selectedRole == AdminRole.bank || _selectedRole == AdminRole.rayonSport;

  bool get _canSubmit =>
      _userIdController.text.trim().isNotEmpty &&
      (!_needsPartnerScope ||
          (_selectedPartnerId != null && _selectedPartnerId!.isNotEmpty));

  Future<void> _submit() async {
    final userId = _userIdController.text.trim();
    if (userId.isEmpty) {
      CoolToast.error(context, 'Enter a user ID.');
      return;
    }
    if (_needsPartnerScope &&
        (_selectedPartnerId == null || _selectedPartnerId!.isEmpty)) {
      CoolToast.error(context, 'Select partner scope.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(adminRoleRepositoryProvider);
      await repo.assignRole(
        targetUserId: userId,
        role: _selectedRole,
        partnerScopeId: _needsPartnerScope ? _selectedPartnerId : null,
      );
      ref.invalidate(adminRoleAssignmentsProvider);
      if (!mounted) return;
      CoolToast.success(context, '${_selectedRole.label} assigned.');
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      CoolToast.error(context, 'Failed: $error');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final partnersAsync = ref.watch(adminPartnersProvider);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.overlaySurface,
        borderRadius: _adminRoleSheetRadius,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: _adminRoleSheetInsets(context),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.border,
                      borderRadius: _adminRoleBadgeRadius,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Assign Admin Role',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _userIdController,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: _roleInputDecoration(
                    context,
                    label: 'User ID',
                    hintText: 'Paste user UUID',
                    suffixIcon: IconButton(
                      tooltip: 'Paste user ID',
                      icon: Icon(
                        Icons.paste_rounded,
                        size: 18,
                        color: colors.tertiaryText,
                      ),
                      onPressed: () async {
                        final clipboard = await Clipboard.getData('text/plain');
                        if (clipboard?.text != null) {
                          _userIdController.text = clipboard!.text!;
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Role',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: AdminRole.values
                      .map((role) {
                        final isSelected = role == _selectedRole;
                        final tone = _adminRoleColor(context, role);
                        return ChoiceChip(
                          label: Text(role.label),
                          selected: isSelected,
                          onSelected: (_) => setState(() {
                            _selectedRole = role;
                            if (!_needsPartnerScope) {
                              _selectedPartnerId = null;
                            }
                          }),
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                          backgroundColor: colors.inputSurface,
                          selectedColor: tone.withValues(alpha: 0.18),
                          labelStyle: theme.textTheme.labelLarge?.copyWith(
                            color: isSelected ? tone : colors.secondaryText,
                            fontWeight: FontWeight.w700,
                          ),
                          side: BorderSide(
                            color: isSelected ? tone : colors.border,
                          ),
                        );
                      })
                      .toList(growable: false),
                ),
                const SizedBox(height: 20),
                if (_needsPartnerScope) ...[
                  Text(
                    'Partner Scope',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.primaryText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  partnersAsync.when(
                    data: (partners) {
                      final filtered = _selectedRole == AdminRole.bank
                          ? partners
                                .where(
                                  (p) => p['category']?.toString() == 'bank',
                                )
                                .toList(growable: false)
                          : partners
                                .where(
                                  (p) =>
                                      p['category']?.toString() == 'football',
                                )
                                .toList(growable: false);
                      return DropdownButtonFormField<String>(
                        initialValue: _selectedPartnerId,
                        decoration: _roleInputDecoration(
                          context,
                          label: 'Partner Scope',
                        ),
                        dropdownColor: colors.overlaySurface,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: colors.primaryText,
                          fontWeight: FontWeight.w700,
                        ),
                        hint: Text(
                          'Select partner',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.tertiaryText,
                          ),
                        ),
                        items: filtered
                            .map(
                              (partner) => DropdownMenuItem<String>(
                                value: partner['id']?.toString(),
                                child: Text(
                                  partner['name']?.toString() ?? 'Unknown',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colors.primaryText,
                                  ),
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) =>
                            setState(() => _selectedPartnerId = value),
                      );
                    },
                    loading: () => const Center(
                      child: CupertinoActivityIndicator(radius: 10),
                    ),
                    error: (e, _) => Text(
                      'Failed to load partners',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.danger,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                SizedBox(
                  width: double.infinity,
                  child: CoolButton(
                    label: 'Assign Role',
                    onTap: _submit,
                    isLoading: _isSubmitting,
                    isDisabled: !_canSubmit,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
