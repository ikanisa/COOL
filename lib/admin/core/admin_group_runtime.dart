part of 'admin_runtime.dart';

class _AdminGroupWorkspaceActions extends ConsumerWidget {
  const _AdminGroupWorkspaceActions({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(adminIdentityProvider).valueOrNull;
    final canManage =
        _adminHasPermission(identity, 'collections.moderate') &&
        _adminHasPermission(identity, 'receivers.manage');
    if (!canManage) return const SizedBox.shrink();
    return Semantics(
      button: true,
      label: 'Group management',
      hint:
          'Create a Collect-sponsored public group. Member-created groups remain private and Android-only.',
      child: IconButton.filled(
        tooltip: 'Create public group',
        onPressed: () => createAdminPublicGroup(context, ref, onDone: onDone),
        icon: const Icon(Icons.create_new_folder_outlined),
      ),
    );
  }
}

Future<void> createAdminPublicGroup(
  BuildContext context,
  WidgetRef ref, {
  required VoidCallback onDone,
}) async {
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

  final submitted = await showDialog<bool>(
    context: context,
    animationStyle: CollectMotion.animationStyle(context),
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
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
                    decoration: const InputDecoration(labelText: 'Group name'),
                    validator: (value) => (value ?? '').trim().length < 3
                        ? 'Enter at least 3 characters'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: description,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Description'),
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
                      DropdownMenuItem(value: 'church', child: Text('Church')),
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
  );

  if (submitted != true) {
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
    await ref
        .read(adminRepositoryProvider)
        .action('admin_create_platform_public_group', {
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
    onDone();
    ref.read(adminRealtimeTickProvider.notifier).state += 1;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Public group created and activated')),
    );
  } catch (error) {
    if (!context.mounted) return;
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
