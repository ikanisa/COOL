part of '../screens/manage_admin_roles_screen.dart';

class _AssignRoleSheet extends ConsumerStatefulWidget {
  const _AssignRoleSheet({required this.ref});

  final WidgetRef ref;

  @override
  ConsumerState<_AssignRoleSheet> createState() => _AssignRoleSheetState();
}

class _AssignRoleSheetState extends ConsumerState<_AssignRoleSheet> {
  final _userIdController = TextEditingController();
  AdminRole _selectedRole = AdminRole.admin;
  String? _selectedBankScopeId;
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

  bool get _requiresBankScope => _selectedRole == AdminRole.bank;

  bool get _canSubmit =>
      _userIdController.text.trim().isNotEmpty &&
      (!_requiresBankScope || _selectedBankScopeId != null);

  void _selectRole(AdminRole role) {
    if (_selectedRole == role) {
      return;
    }

    setState(() {
      _selectedRole = role;
      _selectedBankScopeId = null;
    });
  }

  Future<void> _submit() async {
    final userId = _userIdController.text.trim();
    if (userId.isEmpty) {
      CoolToast.error(context, 'Enter a user ID.');
      return;
    }
    if (_requiresBankScope && _selectedBankScopeId == null) {
      CoolToast.error(context, 'Select a bank scope.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(adminRoleRepositoryProvider);
      await repo.assignRole(
        targetUserId: userId,
        role: _selectedRole,
        bankId: _selectedBankScopeId,
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

    List<Map<String, dynamic>> bankScopeOptions(
      List<Map<String, dynamic>> partners,
    ) {
      return partners
          .where((partner) {
            final category = partner['category']?.toString() ?? '';
            return switch (_selectedRole) {
              AdminRole.admin => false,
              AdminRole.bank => category == 'bank',
            };
          })
          .toList(growable: false);
    }

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
                const SizedBox(height: CoolSpace.x5),
                Text(
                  'Assign Admin Role',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: CoolSpace.x4),
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
                const SizedBox(height: CoolSpace.x4),
                Text(
                  'Role',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.tertiaryText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: CoolSpace.x2),
                Wrap(
                  spacing: CoolSpace.x2,
                  runSpacing: CoolSpace.x2,
                  children: [
                    for (final role in AdminRole.values)
                      ChoiceChip(
                        label: Text(role.label),
                        selected: _selectedRole == role,
                        onSelected: (_) => _selectRole(role),
                      ),
                  ],
                ),
                if (_requiresBankScope) ...[
                  const SizedBox(height: CoolSpace.x4),
                  partnersAsync.when(
                    data: (partners) {
                      final options = bankScopeOptions(partners);
                      return DropdownButtonFormField<String>(
                        initialValue: _selectedBankScopeId,
                        decoration: _roleInputDecoration(
                          context,
                          label: 'Bank Scope',
                        ),
                        items: [
                          for (final partner in options)
                            DropdownMenuItem<String>(
                              value: partner['id']?.toString(),
                              child: Text(partner['name']?.toString() ?? ''),
                            ),
                        ],
                        onChanged: (value) {
                          setState(() => _selectedBankScopeId = value);
                        },
                      );
                    },
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: CoolSpace.x2),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                    error: (error, stackTrace) => Text(
                      'Failed to load bank scopes.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.danger,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: CoolSpace.x5),
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
