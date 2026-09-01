part of 'admin_runtime.dart';

class _AdminPayeeWorkspaceActions extends ConsumerWidget {
  const _AdminPayeeWorkspaceActions({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(adminIdentityProvider).valueOrNull;
    final canManage = _adminHasPermission(identity, 'receivers.manage');
    if (!canManage) return const SizedBox.shrink();
    return Semantics(
      button: true,
      label: 'Official payee management',
      hint:
          'Create an official payee. The MoMo route is immutable after creation.',
      child: IconButton.filled(
        tooltip: 'Create payee',
        onPressed: () => createAdminPayee(context, ref, onDone: onDone),
        icon: const Icon(Icons.person_add_alt_1_outlined),
      ),
    );
  }
}

Future<void> createAdminPayee(
  BuildContext context,
  WidgetRef ref, {
  required VoidCallback onDone,
}) async {
  final repository = ref.read(adminRepositoryProvider);
  late final AdminListResult candidateResult;
  try {
    candidateResult = await repository.list(
      'admin_list_platform_payee_candidates',
      status: 'eligible',
      limit: 100,
      offset: 0,
      sortBy: 'created_at_asc',
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_adminActionErrorMessage(error))));
    return;
  }
  if (!context.mounted) return;
  if (candidateResult.rows.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Every current platform-sponsored public group already has a payee.',
        ),
      ),
    );
    return;
  }

  final formKey = GlobalKey<FormState>();
  final label = TextEditingController();
  final momoCode = TextEditingController();
  final reason = TextEditingController();
  var collectionId = candidateResult.rows.first.id;
  var network = 'mtn_momo';
  final submitted = await showDialog<bool>(
    context: context,
    animationStyle: CollectMotion.animationStyle(context),
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Create official payee'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const InfoSecurityBanner(
                    title: 'Route becomes immutable',
                    message:
                        'Confirm the MoMo number or code and provider before creating the payee. They can never be edited afterward; deactivate the payee if it must no longer receive contributions.',
                    tone: CollectStatusTone.warning,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: collectionId,
                    decoration: const InputDecoration(
                      labelText: 'Platform public group',
                    ),
                    items: [
                      for (final candidate in candidateResult.rows)
                        DropdownMenuItem(
                          value: candidate.id,
                          child: Text(candidate.title),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => collectionId = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: label,
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
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Create payee'),
          ),
        ],
      ),
    ),
  );
  if (submitted != true) {
    label.dispose();
    momoCode.dispose();
    reason.dispose();
    return;
  }
  try {
    await repository.action('admin_create_collect_payee', {
      'p_collection_id': collectionId,
      'p_label': label.text.trim(),
      'p_momo_code': momoCode.text.trim(),
      'p_network': network,
      'p_reason': reason.text.trim(),
    });
    onDone();
    ref.read(adminRealtimeTickProvider.notifier).state += 1;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Official payee created and activated')),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_adminActionErrorMessage(error))));
  } finally {
    label.dispose();
    momoCode.dispose();
    reason.dispose();
  }
}

Future<void> editAdminPayee(
  BuildContext context,
  WidgetRef ref, {
  required AdminTableRowData row,
  required VoidCallback onDone,
}) async {
  final formKey = GlobalKey<FormState>();
  final label = TextEditingController(text: row.title);
  final reason = TextEditingController();
  final submitted = await showDialog<bool>(
    context: context,
    animationStyle: CollectMotion.animationStyle(context),
    builder: (dialogContext) => AlertDialog(
      title: const Text('Edit official payee'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoSecurityBanner(
                title: 'MoMo route is locked',
                message:
                    '${row.subtitle}. Only the official payee name can be edited.',
                tone: CollectStatusTone.privacy,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: label,
                decoration: const InputDecoration(
                  labelText: 'Official payee name',
                ),
                validator: (value) => (value ?? '').trim().length < 2
                    ? 'Enter the official payee name'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: reason,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Change reason',
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState?.validate() ?? false) {
              Navigator.pop(dialogContext, true);
            }
          },
          child: const Text('Save name'),
        ),
      ],
    ),
  );
  if (submitted != true) {
    label.dispose();
    reason.dispose();
    return;
  }
  try {
    await ref
        .read(adminRepositoryProvider)
        .action('admin_update_collect_payee', {
          'p_payee_id': _adminPayeeUuid(row.id),
          'p_label': label.text.trim(),
          'p_reason': reason.text.trim(),
        });
    onDone();
    ref.read(adminRealtimeTickProvider.notifier).state += 1;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Official payee name updated')),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_adminActionErrorMessage(error))));
  } finally {
    label.dispose();
    reason.dispose();
  }
}

Future<void> setAdminPayeeActive(
  BuildContext context,
  WidgetRef ref, {
  required AdminTableRowData row,
  required bool active,
  required VoidCallback onDone,
}) async {
  final reason = await showAdminReasonDialog(
    context,
    title: active ? 'Activate official payee' : 'Deactivate official payee',
    actionLabel: active ? 'Activate payee' : 'Deactivate payee',
  );
  if (reason == null) return;
  try {
    await ref.read(adminRepositoryProvider).action(
      'admin_set_collect_payee_status',
      {
        'p_payee_id': _adminPayeeUuid(row.id),
        'p_active': active,
        'p_reason': reason,
      },
    );
    onDone();
    ref.read(adminRealtimeTickProvider.notifier).state += 1;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          active ? 'Official payee activated' : 'Official payee deactivated',
        ),
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_adminActionErrorMessage(error))));
  }
}

String _adminPayeeUuid(String id) {
  final value = id.trim();
  return value.startsWith('momo:') ? value.substring('momo:'.length) : value;
}
