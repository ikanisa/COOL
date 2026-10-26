part of 'admin_runtime.dart';

class _AdminCollectionStatusActions extends ConsumerWidget {
  const _AdminCollectionStatusActions({
    required this.collectionId,
    required this.currentStatus,
    required this.operatorDraft,
  });

  final String collectionId;
  final String currentStatus;
  final bool operatorDraft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = _adminResolvedIdentity(ref.watch(adminIdentityProvider));
    final canPublish =
        !operatorDraft &&
        identity != null &&
        identity.roles.any(const {'admin', 'platform_owner'}.contains) &&
        _adminHasPermission(identity, 'collections.moderate') &&
        _adminHasPermission(identity, 'public_requests.review');
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Group lifecycle actions',
      hint: 'Activates or deactivates the group with an audited reason.',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (canPublish &&
              {'private', 'public_rejected'}.contains(currentStatus))
            _AdminCollectionStatusButton(
              collectionId: collectionId,
              status: 'public_approved',
              label: 'Make public',
              icon: Icons.public_rounded,
            ),
          if (canPublish && currentStatus == 'public_requested') ...[
            _AdminCollectionStatusButton(
              collectionId: collectionId,
              status: 'public_approved',
              label: 'Approve public',
              icon: Icons.public_rounded,
            ),
            _AdminCollectionStatusButton(
              collectionId: collectionId,
              status: 'public_rejected',
              label: 'Reject public',
              icon: Icons.block_outlined,
            ),
          ],
          if (currentStatus == 'archived' || currentStatus == 'inactive')
            _AdminCollectionStatusButton(
              collectionId: collectionId,
              status: 'active',
              label: 'Activate',
              icon: Icons.play_circle_outline,
            )
          else
            _AdminCollectionStatusButton(
              collectionId: collectionId,
              status: 'inactive',
              label: 'Deactivate',
              icon: Icons.pause_circle_outline,
              destructive: true,
            ),
        ],
      ),
    );
  }
}

class _AdminCollectionStatusButton extends ConsumerStatefulWidget {
  const _AdminCollectionStatusButton({
    required this.collectionId,
    required this.status,
    required this.label,
    required this.icon,
    this.destructive = false,
  });

  final String collectionId;
  final String status;
  final String label;
  final IconData icon;
  final bool destructive;

  @override
  ConsumerState<_AdminCollectionStatusButton> createState() =>
      _AdminCollectionStatusButtonState();
}

class _AdminCollectionStatusButtonState
    extends ConsumerState<_AdminCollectionStatusButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final button = IconButton.outlined(
      tooltip: widget.label,
      onPressed: _busy ? null : _updateStatus,
      icon: Icon(widget.icon),
      style: widget.destructive
          ? IconButton.styleFrom(foregroundColor: colors.danger)
          : null,
    );
    return Semantics(
      button: true,
      label: '${widget.label} group support status',
      hint: 'Opens a reason dialog before updating the group status.',
      child: button,
    );
  }

  Future<void> _updateStatus() async {
    if (_busy) return;
    final scope = _AdminActionScope(ref);
    final target = widget.collectionId;
    final status = widget.status;
    final label = widget.label;
    final lifecycleAction = status == 'active' || status == 'inactive';
    bool current() =>
        mounted &&
        widget.collectionId == target &&
        widget.status == status &&
        scope.isCurrent;
    setState(() => _busy = true);
    try {
      final reason = await showAdminReasonDialog(
        context,
        minLength: 8,
        maxLength: lifecycleAction ? 1000 : 500,
        dialogWrapper: (_, child) =>
            _AdminSessionDialog(scope: scope, child: child),
        title: '$label group',
        actionLabel: label,
      );
      if (reason == null || !current()) return;
      await scope.repository.action(
        lifecycleAction
            ? 'admin_set_group_active'
            : 'admin_update_collection_support_status',
        lifecycleAction
            ? {
                'p_collection_id': target,
                'p_active': status == 'active',
                'p_reason': reason,
              }
            : {
                'p_collection_id': target,
                'p_status': status,
                'p_reason': reason,
              },
      );
      if (!current()) return;
      ref.read(adminRealtimeTickProvider.notifier).state += 1;
      if (!mounted || !current()) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Group updated: $label')));
    } catch (error) {
      if (!mounted || !current()) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_adminActionErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _AdminPlatformPublicGroupEditor extends ConsumerStatefulWidget {
  const _AdminPlatformPublicGroupEditor({
    required this.collectionId,
    required this.data,
  });

  final String collectionId;
  final Map<String, dynamic> data;

  @override
  ConsumerState<_AdminPlatformPublicGroupEditor> createState() =>
      _AdminPlatformPublicGroupEditorState();
}

class _AdminPlatformPublicGroupEditorState
    extends ConsumerState<_AdminPlatformPublicGroupEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _categorySubtype;
  late final TextEditingController _purposeLabel;
  late final TextEditingController _receiverLabel;
  late String _collectionType;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: '${widget.data['title'] ?? ''}');
    _description = TextEditingController(
      text: '${widget.data['description'] ?? ''}',
    );
    _categorySubtype = TextEditingController(
      text: '${widget.data['category_subtype'] ?? ''}',
    );
    _purposeLabel = TextEditingController(
      text: '${widget.data['purpose_label'] ?? ''}',
    );
    _receiverLabel = TextEditingController(
      text: '${widget.data['receiver_display_label'] ?? ''}',
    );
    final type = '${widget.data['collection_type'] ?? 'other'}';
    _collectionType =
        const {'ikimina', 'sport', 'church', 'wedding', 'other'}.contains(type)
        ? type
        : 'other';
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _categorySubtype.dispose();
    _purposeLabel.dispose();
    _receiverLabel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Edit database-managed public group',
      hint:
          'Updates public group catalogue metadata. The payee MoMo route remains locked.',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceMuted.withValues(alpha: 0.84),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.borderAccent),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Edit group',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: CollectTypography.weightBold,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _publicGroupTextField(
                      controller: _title,
                      label: 'Group name',
                      validator: (value) => (value ?? '').trim().length < 3
                          ? 'Enter at least 3 characters'
                          : null,
                    ),
                    _publicGroupTextField(
                      controller: _description,
                      label: 'Description',
                      maxLines: 2,
                    ),
                    _publicGroupDropdown(
                      label: 'Collection type',
                      value: _collectionType,
                      items: const {
                        'ikimina': 'Group savings',
                        'sport': 'Sport',
                        'church': 'Church',
                        'wedding': 'Wedding',
                        'other': 'Other',
                      },
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _collectionType = value);
                        }
                      },
                    ),
                    _publicGroupTextField(
                      controller: _purposeLabel,
                      label: 'Purpose label',
                    ),
                    _publicGroupTextField(
                      controller: _receiverLabel,
                      label: 'Receiver name',
                      validator: (value) => (value ?? '').trim().isEmpty
                          ? 'Receiver name is required'
                          : null,
                    ),
                    _AdminImmutablePayeeRoute(data: widget.data),
                  ],
                ),
                const SizedBox(height: 14),
                IconButton.filled(
                  tooltip: 'Save group changes',
                  onPressed: _working ? null : _save,
                  icon: _working
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _publicGroupTextField({
    required TextEditingController controller,
    required String label,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return SizedBox(
      width: 300,
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        maxLines: maxLines,
        keyboardType: keyboardType,
        validator: validator,
      ),
    );
  }

  Widget _publicGroupDropdown({
    required String label,
    required String value,
    required Map<String, String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return SizedBox(
      width: 300,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final item in items.entries)
            DropdownMenuItem(value: item.key, child: Text(item.value)),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Future<void> _save() async {
    final scope = _AdminActionScope(ref);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final reason = await showAdminReasonDialog(
      context,
      dialogWrapper: (_, child) =>
          _AdminSessionDialog(scope: scope, child: child),
      title: 'Update public group',
      actionLabel: 'Save changes',
    );
    if (reason == null || !mounted || !scope.isCurrent) return;
    setState(() => _working = true);
    try {
      await scope.repository
          .action('admin_update_platform_public_group_metadata', {
            'p_collection_id': widget.collectionId,
            'p_title': _title.text.trim(),
            'p_description': _description.text.trim(),
            'p_collection_type': _collectionType,
            'p_category_subtype': _categorySubtype.text.trim(),
            'p_purpose_label': _purposeLabel.text.trim(),
            'p_receiver_label': _receiverLabel.text.trim(),
            'p_reason': reason,
          });
      if (!context.mounted || !scope.isCurrent) return;
      ref.read(adminRealtimeTickProvider.notifier).state += 1;
      if (!mounted || !scope.isCurrent) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Public group updated')));
    } catch (error) {
      if (!mounted || !scope.isCurrent) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_adminActionErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}

class _AdminImmutablePayeeRoute extends StatelessWidget {
  const _AdminImmutablePayeeRoute({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final code = '${data['receiver_momo_code'] ?? 'Not configured'}';
    final network = '${data['receiver_network'] ?? 'Not configured'}';
    return Semantics(
      container: true,
      readOnly: true,
      label: 'Immutable payee route. MoMo code $code. Network $network.',
      child: SizedBox(
        width: 300,
        child: InputDecorator(
          decoration: const InputDecoration(
            labelText: 'MoMo route (locked)',
            helperText: 'The MoMo number or code can never be edited.',
          ),
          child: Text('$network · $code'),
        ),
      ),
    );
  }
}
