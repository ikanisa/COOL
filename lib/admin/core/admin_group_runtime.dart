part of 'admin_runtime.dart';

class _AdminGroupWorkspaceActions extends ConsumerWidget {
  const _AdminGroupWorkspaceActions({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(adminIdentityProvider).valueOrNull;
    final canCreatePublic =
        _adminHasPermission(identity, 'collections.moderate') &&
        _adminHasPermission(identity, 'receivers.manage');
    final canCreateAssisted =
        _adminHasPermission(identity, 'collections.moderate') &&
        _adminHasPermission(identity, 'users.read');
    if (!canCreatePublic && !canCreateAssisted) {
      return const SizedBox.shrink();
    }
    return Semantics(
      button: true,
      label: 'Create group',
      hint:
          'Create a public Collect-sponsored group or a private assisted group with reviewed members.',
      child: PopupMenuButton<String>(
        tooltip: 'Create group',
        icon: const Icon(Icons.create_new_folder_outlined),
        onSelected: (value) {
          if (value == 'assisted') {
            createAdminAssistedGroup(context, ref, onDone: onDone);
          } else if (value == 'public') {
            createAdminPublicGroup(context, ref, onDone: onDone);
          }
        },
        itemBuilder: (_) => [
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

class _AssistedGroupDraft {
  const _AssistedGroupDraft({
    required this.title,
    required this.reason,
    required this.rows,
  });

  final String title;
  final String reason;
  final List<Map<String, dynamic>> rows;
}

Future<void> createAdminAssistedGroup(
  BuildContext context,
  WidgetRef ref, {
  required VoidCallback onDone,
}) async {
  final formKey = GlobalKey<FormState>();
  final title = TextEditingController();
  final reason = TextEditingController();
  final rosterText = TextEditingController(
    text: 'Member name,MoMo name,MoMo number\n',
  );
  PlatformFile? selectedFile;
  Map<String, dynamic>? preview;
  String? previewError;
  var preparing = false;
  var aiConsent = false;

  final draft = await showDialog<_AssistedGroupDraft>(
    context: context,
    animationStyle: CollectMotion.animationStyle(context),
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        final isAiPreview =
            preview?['processing_method'] == 'openai_structured_extraction';
        final canSubmit = preview?['can_submit'] == true && !isAiPreview;
        final readyCount = (preview?['ready_count'] as num?)?.toInt() ?? 0;
        final aiFileSelected = _isAiRosterFile(selectedFile);
        return AlertDialog(
          title: const Text('Create assisted group'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const InfoSecurityBanner(
                      title: 'Private group · review before creation',
                      message:
                          'Feature-phone members are stored as MoMo identities, not app accounts. Preparing a preview never creates a group or member. The final action creates the group, share link/QR secret and reviewed roster in one transaction.',
                      tone: CollectStatusTone.info,
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
                      controller: reason,
                      minLines: 2,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Creation and import reason',
                        helperText: 'Required for the audit trail.',
                      ),
                      validator: (value) => (value ?? '').trim().length < 8
                          ? 'Enter at least 8 characters'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Member roster',
                      style: Theme.of(dialogContext).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: rosterText,
                      minLines: 5,
                      maxLines: 10,
                      enabled: selectedFile == null && !preparing,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Paste or type members',
                        helperText:
                            'Columns: member name, registered MoMo name, full MoMo number. CSV, semicolon and tab-separated lists are accepted.',
                        alignLabelWithHint: true,
                      ),
                      onChanged: (_) => setDialogState(() {
                        preview = null;
                        previewError = null;
                      }),
                      validator: (value) =>
                          selectedFile == null && (value ?? '').trim().isEmpty
                          ? 'Paste a roster or choose a file'
                          : null,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: preparing
                              ? null
                              : () async {
                                  final picked = await FilePicker.pickFile(
                                    type: FileType.custom,
                                    allowedExtensions: const [
                                      'csv',
                                      'txt',
                                      'xlsx',
                                      'pdf',
                                      'png',
                                      'jpg',
                                      'jpeg',
                                      'webp',
                                    ],
                                  );
                                  if (picked == null ||
                                      !dialogContext.mounted) {
                                    return;
                                  }
                                  setDialogState(() {
                                    selectedFile = picked;
                                    preview = null;
                                    previewError = null;
                                    aiConsent = false;
                                  });
                                },
                          icon: const Icon(Icons.upload_file_outlined),
                          label: const Text('Choose roster file'),
                        ),
                        if (selectedFile != null) ...[
                          Chip(
                            avatar: const Icon(
                              Icons.description_outlined,
                              size: 18,
                            ),
                            label: Text(selectedFile!.name),
                          ),
                          TextButton(
                            onPressed: preparing
                                ? null
                                : () => setDialogState(() {
                                    selectedFile = null;
                                    preview = null;
                                    previewError = null;
                                    aiConsent = false;
                                  }),
                            child: const Text('Use pasted list'),
                          ),
                        ],
                      ],
                    ),
                    if (aiFileSelected) ...[
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: aiConsent,
                        onChanged: preparing
                            ? null
                            : (value) => setDialogState(() {
                                aiConsent = value == true;
                                preview = null;
                                previewError = null;
                              }),
                        title: const Text('Use OpenAI for this file'),
                        subtitle: const Text(
                          'Send this PDF/image to the configured server-side OpenAI account for structured extraction. The response is not stored by Collect and must be moved into the editor and reviewed before creation.',
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ],
                    if (previewError != null) ...[
                      const SizedBox(height: 8),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          previewError!,
                          style: Theme.of(dialogContext).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  dialogContext,
                                ).colorScheme.error,
                              ),
                        ),
                      ),
                    ],
                    if (preview != null) ...[
                      const SizedBox(height: 16),
                      _RosterImportPreview(preview: preview!),
                      if (isAiPreview) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: preparing
                              ? null
                              : () => setDialogState(() {
                                  rosterText.text = _previewRowsAsRosterText(
                                    preview!,
                                  );
                                  selectedFile = null;
                                  aiConsent = false;
                                  preview = null;
                                  previewError = null;
                                }),
                          icon: const Icon(Icons.edit_note_outlined),
                          label: const Text('Move extraction to editor'),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Review and correct every extracted row, then prepare a deterministic preview before creating the group.',
                          style: Theme.of(dialogContext).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: preparing ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            OutlinedButton.icon(
              onPressed: preparing
                  ? null
                  : () async {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      setDialogState(() {
                        preparing = true;
                        preview = null;
                        previewError = null;
                      });
                      try {
                        if (aiFileSelected && !aiConsent) {
                          throw StateError(
                            'Confirm OpenAI extraction for this PDF or image.',
                          );
                        }
                        final body = await _rosterPreviewRequest(
                          selectedFile: selectedFile,
                          rosterText: rosterText.text,
                          aiConsent: aiConsent,
                        );
                        final result = await ref
                            .read(adminRepositoryProvider)
                            .prepareRosterImport(body);
                        if (!dialogContext.mounted) return;
                        setDialogState(() => preview = result);
                      } catch (error) {
                        if (!dialogContext.mounted) return;
                        setDialogState(
                          () => previewError = _adminActionErrorMessage(error),
                        );
                      } finally {
                        if (dialogContext.mounted) {
                          setDialogState(() => preparing = false);
                        }
                      }
                    },
              icon: preparing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.fact_check_outlined),
              label: Text(preparing ? 'Preparing…' : 'Prepare preview'),
            ),
            FilledButton.icon(
              onPressed: canSubmit && !preparing
                  ? () {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      final rawRows = preview?['normalized_rows'];
                      if (rawRows is! List || rawRows.isEmpty) return;
                      Navigator.pop(
                        dialogContext,
                        _AssistedGroupDraft(
                          title: title.text.trim(),
                          reason: reason.text.trim(),
                          rows: [
                            for (final row in rawRows)
                              Map<String, dynamic>.from(row as Map),
                          ],
                        ),
                      );
                    }
                  : null,
              icon: const Icon(Icons.group_add_outlined),
              label: Text(
                canSubmit
                    ? 'Create group and add $readyCount members'
                    : 'Review roster first',
              ),
            ),
          ],
        );
      },
    ),
  );

  title.dispose();
  reason.dispose();
  rosterText.dispose();
  if (draft == null) return;

  try {
    final result = await ref
        .read(adminRepositoryProvider)
        .action('admin_create_assisted_group_with_roster', {
          'p_title': draft.title,
          'p_rows': draft.rows,
          'p_reason': draft.reason,
          'p_group_request_id': const Uuid().v4(),
          'p_roster_request_id': const Uuid().v4(),
        });
    onDone();
    ref.read(adminRealtimeTickProvider.notifier).state += 1;
    if (!context.mounted) return;
    final count =
        (result['roster_count'] as num?)?.toInt() ?? draft.rows.length;
    final shareReady = result['share_code_ready'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Assisted group created with $count members${shareReady ? ' · share link and QR ready' : ''}',
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

class _RosterImportPreview extends StatelessWidget {
  const _RosterImportPreview({required this.preview});

  final Map<String, dynamic> preview;

  @override
  Widget build(BuildContext context) {
    final rows = preview['rows'] is List ? preview['rows'] as List : const [];
    final ready = (preview['ready_count'] as num?)?.toInt() ?? 0;
    final errors = (preview['error_count'] as num?)?.toInt() ?? 0;
    final isAi = preview['processing_method'] == 'openai_structured_extraction';
    final method = isAi
        ? 'OpenAI structured extraction · human review required'
        : 'Deterministic parsing';
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Roster preview: $ready ready, $errors requiring correction',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: errors == 0 ? colors.outlineVariant : colors.error,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$ready ready · $errors requiring correction',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 2),
            Text(method, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            for (final raw in rows.take(25))
              _RosterPreviewRow(row: Map<String, dynamic>.from(raw as Map)),
            if (rows.length > 25)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('${rows.length - 25} more rows are included.'),
              ),
          ],
        ),
      ),
    );
  }
}

class _RosterPreviewRow extends StatelessWidget {
  const _RosterPreviewRow({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final issues = row['issues'] is List ? row['issues'] as List : const [];
    final ready = row['ready'] == true;
    final sourceRow = row['source_row'] ?? '?';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ready ? Icons.check_circle_outline : Icons.error_outline,
            size: 20,
            color: ready
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Row $sourceRow · ${row['member_name'] ?? 'Missing member'}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  '${row['momo_name'] ?? ''} · ${row['momo_number'] ?? ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (issues.isNotEmpty)
                  Text(
                    issues.join(' · '),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<Map<String, dynamic>> _rosterPreviewRequest({
  required PlatformFile? selectedFile,
  required String rosterText,
  required bool aiConsent,
}) async {
  if (selectedFile == null) {
    return {'source_type': 'text', 'content': rosterText.trim()};
  }
  final bytes = await selectedFile.readAsBytes();
  if (bytes.isEmpty) {
    throw StateError('The selected roster file could not be read.');
  }
  final extension = (selectedFile.extension ?? '').toLowerCase();
  if (bytes.length > 5 * 1024 * 1024) {
    throw StateError('Choose a roster file no larger than 5 MB.');
  }
  if (extension == 'xlsx') {
    return {'source_type': 'text', 'content': decodeRosterXlsx(bytes)};
  }
  if (extension == 'csv' || extension == 'txt') {
    return {
      'source_type': extension == 'csv' ? 'csv' : 'text',
      'content': utf8.decode(bytes),
    };
  }
  const mimeTypes = {
    'pdf': 'application/pdf',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'webp': 'image/webp',
  };
  final mimeType = mimeTypes[extension];
  if (mimeType == null) {
    throw StateError('Choose a CSV, TXT, XLSX, PDF, PNG, JPEG or WebP file.');
  }
  return {
    'source_type': extension == 'pdf' ? 'pdf' : 'image',
    'filename': selectedFile.name,
    'mime_type': mimeType,
    'content_base64': base64Encode(bytes),
    'ai_consent': aiConsent,
  };
}

bool _isAiRosterFile(PlatformFile? file) {
  final extension = (file?.extension ?? '').toLowerCase();
  return const {'pdf', 'png', 'jpg', 'jpeg', 'webp'}.contains(extension);
}

String _previewRowsAsRosterText(Map<String, dynamic> preview) {
  final rawRows = preview['rows'];
  if (rawRows is! List || rawRows.isEmpty) {
    throw StateError('The extraction did not return editable rows.');
  }
  String clean(Object? value) =>
      '${value ?? ''}'.replaceAll(RegExp(r'[\t\r\n]+'), ' ').trim();
  return [
    'Member name\tMoMo name\tMoMo number',
    for (final raw in rawRows)
      if (raw is Map)
        [
          clean(raw['member_name']),
          clean(raw['momo_name']),
          clean(raw['momo_number']),
        ].join('\t'),
  ].join('\n');
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
