part of 'admin_runtime.dart';

class _AdminGroupWorkspaceActions extends ConsumerStatefulWidget {
  const _AdminGroupWorkspaceActions({required this.onDone});

  final VoidCallback onDone;

  @override
  ConsumerState<_AdminGroupWorkspaceActions> createState() =>
      _AdminGroupWorkspaceActionsState();
}

class _AdminGroupWorkspaceActionsState
    extends ConsumerState<_AdminGroupWorkspaceActions> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final identity = _adminResolvedIdentity(ref.watch(adminIdentityProvider));
    final canCreatePublic =
        _adminHasPermission(identity, 'collections.moderate') &&
        _adminHasPermission(identity, 'receivers.manage');
    final canCreateAssisted =
        _adminHasPermission(identity, 'collections.moderate') &&
        _adminHasPermission(identity, 'users.read');
    final canCreatePrivate = _adminHasPermission(
      identity,
      'collections.create',
    );
    if (!canCreatePublic && !canCreateAssisted && !canCreatePrivate) {
      return const SizedBox.shrink();
    }
    return Semantics(
      button: true,
      label: 'Create group',
      hint: canCreatePublic
          ? 'Create a public or private group.'
          : 'Create a private group.',
      child: PopupMenuButton<String>(
        tooltip: 'Create group',
        enabled: !_busy,
        icon: const Icon(Icons.create_new_folder_outlined),
        onSelected: (value) async {
          if (value == 'private') {
            setState(() => _busy = true);
            try {
              await createAdminStaffGroup(context, ref, onDone: widget.onDone);
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          } else if (value == 'assisted') {
            createAdminAssistedGroup(context, ref, onDone: widget.onDone);
          } else if (value == 'public') {
            createAdminPublicGroup(context, ref, onDone: widget.onDone);
          }
        },
        itemBuilder: (_) => [
          if (canCreatePrivate)
            const PopupMenuItem(
              value: 'private',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.lock_outline),
                title: Text('Create private group'),
              ),
            ),
          if (canCreateAssisted)
            PopupMenuItem(
              value: 'assisted',
              enabled: canCreateAssisted,
              child: const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.group_add_outlined),
                title: Text('Create assisted group'),
                subtitle: Text('Private group with reviewed MoMo members'),
              ),
            ),
          if (canCreatePublic)
            PopupMenuItem(
              value: 'public',
              enabled: canCreatePublic,
              child: const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.campaign_outlined),
                title: Text('Create public group'),
                subtitle: Text('Collect-sponsored group with a locked payee'),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> createAdminAssistedGroup(
  BuildContext context,
  WidgetRef ref, {
  required VoidCallback onDone,
  String? collectionId,
}) async {
  final scope = _AdminActionScope(ref);
  try {
    if (!scope.isCurrent ||
        !scope.permissions.contains('collections.moderate') ||
        !scope.permissions.contains('users.read')) {
      return;
    }
    final gateway = scope.repository.openRosterImport();
    final result = await showAdminRosterImport(
      context,
      AdminRosterDraft(gateway, collectionId: collectionId),
      dialogWrapper: (_, child) =>
          _AdminSessionDialog(scope: scope, child: child),
    );
    // The dialog has already disposed and closed its gateway. The validated
    // result still belongs to the captured host authority, which must be current.
    if (result == null || !context.mounted || !scope.isCurrent) {
      return;
    }
    onDone();
    ref.read(adminRealtimeTickProvider.notifier).state += 1;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          collectionId == null
              ? 'Assisted group created with ${result.rosterCount} members · share link and QR ready'
              : '${result.rosterCount} reviewed members added',
        ),
      ),
    );
  } catch (error) {
    if (!context.mounted || !scope.isCurrent) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_adminActionErrorMessage(error))));
  }
}

Future<void> createAdminPublicGroup(
  BuildContext context,
  WidgetRef ref, {
  required VoidCallback onDone,
}) async {
  final scope = _AdminActionScope(ref);
  final formKey = GlobalKey<FormState>();
  final title = TextEditingController();
  final description = TextEditingController();
  final categorySubtype = TextEditingController();
  final purposeLabel = TextEditingController();
  final payeeName = TextEditingController();
  final momoCode = TextEditingController();
  final reason = TextEditingController();
  var collectionType = 'ikimina';
  var network = 'mtn_momo';

  final submitted = await _showAdminFormDialog<bool>(
    context: context,
    builder: (dialogContext) => _AdminSessionDialog(
      scope: scope,
      child: StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          scrollable: true,
          title: const Text('Create public group'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const InfoSecurityBanner(
                      title: 'Public, Collect-sponsored group',
                      message:
                          'This creates an active public group with its official MoMo payee. Confirm the route carefully: its MoMo number or code and provider are locked permanently after creation.',
                      tone: CollectStatusTone.warning,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: title,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Group name',
                      ),
                      validator: (value) => (value ?? '').trim().length < 3
                          ? 'Enter at least 3 characters'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: description,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                      ),
                      validator: (value) => (value ?? '').trim().length > 1000
                          ? 'Use 1000 characters or fewer'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: collectionType,
                      decoration: const InputDecoration(
                        labelText: 'Collection type',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'ikimina',
                          child: Text('Group savings'),
                        ),
                        DropdownMenuItem(value: 'sport', child: Text('Sport')),
                        DropdownMenuItem(
                          value: 'church',
                          child: Text('Church'),
                        ),
                        DropdownMenuItem(
                          value: 'wedding',
                          child: Text('Wedding'),
                        ),
                        DropdownMenuItem(value: 'other', child: Text('Other')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => collectionType = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: categorySubtype,
                      decoration: const InputDecoration(
                        labelText: 'Category key',
                        helperText: 'Optional internal catalogue key.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: purposeLabel,
                      decoration: const InputDecoration(
                        labelText: 'Purpose label',
                      ),
                      validator: (value) => (value ?? '').trim().length < 2
                          ? 'Enter the public purpose'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: payeeName,
                      decoration: const InputDecoration(
                        labelText: 'Official payee name',
                      ),
                      validator: (value) => (value ?? '').trim().length < 2
                          ? 'Enter the official payee name'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: network,
                      decoration: const InputDecoration(labelText: 'Provider'),
                      items: const [
                        DropdownMenuItem(
                          value: 'mtn_momo',
                          child: Text('MTN MoMo'),
                        ),
                        DropdownMenuItem(
                          value: 'airtel_money',
                          child: Text('Airtel Money'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => network = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: momoCode,
                      keyboardType: TextInputType.number,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'MoMo number or code',
                        helperText: 'Locked permanently after creation.',
                      ),
                      validator: (value) =>
                          RegExp(r'^\d{4,12}$').hasMatch((value ?? '').trim())
                          ? null
                          : 'Enter 4 to 12 digits',
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: reason,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Creation reason',
                        helperText: 'Required for the audit trail.',
                      ),
                      validator: (value) => (value ?? '').trim().length < 8
                          ? 'Enter at least 8 characters'
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.pop(dialogContext, true);
                }
              },
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Create group'),
            ),
          ],
        ),
      ),
    ),
  );

  if (submitted != true || !context.mounted || !scope.isCurrent) {
    _disposeGroupCreationControllers([
      title,
      description,
      categorySubtype,
      purposeLabel,
      payeeName,
      momoCode,
      reason,
    ]);
    return;
  }

  try {
    await scope.repository.action('admin_create_platform_public_group', {
      'p_title': title.text.trim(),
      'p_description': description.text.trim(),
      'p_collection_type': collectionType,
      'p_category_subtype': categorySubtype.text.trim(),
      'p_purpose_label': purposeLabel.text.trim(),
      'p_receiver_label': payeeName.text.trim(),
      'p_momo_code': momoCode.text.trim(),
      'p_network': network,
      'p_reason': reason.text.trim(),
    });
    if (!context.mounted || !scope.isCurrent) return;
    onDone();
    ref.read(adminRealtimeTickProvider.notifier).state += 1;
    if (!context.mounted || !scope.isCurrent) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Public group created and activated')),
    );
  } catch (error) {
    if (!context.mounted || !scope.isCurrent) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_adminActionErrorMessage(error))));
  } finally {
    _disposeGroupCreationControllers([
      title,
      description,
      categorySubtype,
      purposeLabel,
      payeeName,
      momoCode,
      reason,
    ]);
  }
}

void _disposeGroupCreationControllers(List<TextEditingController> controllers) {
  for (final controller in controllers) {
    controller.dispose();
  }
}
