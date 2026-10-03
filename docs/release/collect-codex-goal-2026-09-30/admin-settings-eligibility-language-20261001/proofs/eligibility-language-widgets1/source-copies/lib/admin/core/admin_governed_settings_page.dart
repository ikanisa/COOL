part of 'admin_runtime.dart';

class AdminGovernedSettingsPage extends ConsumerStatefulWidget {
  const AdminGovernedSettingsPage({
    this.initialFamily,
    this.initialIdentity,
    super.key,
  });
  final String? initialFamily;
  final Map<String, Object?>? initialIdentity;
  @override
  ConsumerState<AdminGovernedSettingsPage> createState() =>
      _AdminGovernedSettingsPageState();
}

class _AdminGovernedSettingsPageState
    extends ConsumerState<AdminGovernedSettingsPage> {
  String? _familyKey, _selectedIdentity, _after;
  final List<String?> _catalogPrevious = [];
  AdminSessionScope? _renderedScope;
  int? _renderedVersion;
  final Map<String, TextEditingController> _ids = {};
  String? _identityError;
  @override
  void initState() {
    super.initState();
    if (widget.initialFamily != null) {
      try {
        final f = AdminSettingsFamily.parse(widget.initialFamily);
        _familyKey = f.key;
        if (widget.initialIdentity != null) {
          _selectedIdentity = jsonEncode(f.identity(widget.initialIdentity));
        }
      } catch (_) {
        _identityError = 'The requested setting identity is invalid.';
      }
    }
  }

  @override
  void dispose() {
    for (final c in _ids.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _chooseFamily(String key) {
    _familyKey = key;
    _selectedIdentity = null;
    _after = null;
    _catalogPrevious.clear();
    _identityError = null;
    for (final c in _ids.values) {
      c.dispose();
    }
    _ids.clear();
  }

  Widget _notice(String message) => Semantics(
    liveRegion: true,
    child: Padding(padding: const EdgeInsets.all(16), child: Text(message)),
  );
  Widget _panel(Widget child) => Card(
    child: Padding(padding: const EdgeInsets.all(18), child: child),
  );
  void _openIdentity(AdminSettingsFamily family) {
    try {
      final identity = <String, Object?>{};
      for (final field in family.identityFields) {
        identity[field] = family.fieldTypes[field] == 'boolean'
            ? true
            : _ids[field]?.text;
      }
      setState(() {
        _selectedIdentity = jsonEncode(family.identity(identity));
        _identityError = null;
      });
    } catch (_) {
      setState(
        () => _identityError =
            'Enter the complete setting identity using the displayed fields.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(adminAuthSessionScopeProvider),
        version = ref.watch(_adminIdentityRevisionProvider),
        identity = _adminResolvedIdentity(ref.watch(adminIdentityProvider));
    if (_renderedScope != scope || _renderedVersion != version) {
      if (_renderedScope != null) {
        _selectedIdentity = null;
        _after = null;
        _catalogPrevious.clear();
        for (final c in _ids.values) {
          c.clear();
        }
      }
      _renderedScope = scope;
      _renderedVersion = version;
    }
    if (scope == null ||
        identity?.userId != scope.key.userId ||
        identity?.roles.contains('platform_owner') != true) {
      return const AdminDeniedPage();
    }
    final families = AdminSettingsFamily.values
        .where((f) => f.canRead(identity) || f.canAudit(identity))
        .toList();
    if (families.isEmpty) {
      return const AdminDeniedPage(requiredPermission: 'settings.read');
    }
    final family = families.firstWhere(
      (f) => f.key == _familyKey,
      orElse: () => families.first,
    );
    if (_familyKey != family.key) _chooseFamily(family.key);
    final action = ref.watch(adminSettingsControllerProvider);
    final q = (family: family.key, after: _after);
    final catalog = ref.watch(adminSettingsCatalogProvider(q));
    return AdminPage(
      title: 'Settings',
      subtitle:
          'Inspect governed controls, review a change, and check its original result.',
      trailing: TextButton.icon(
        onPressed: () => ref.invalidate(adminSettingsCatalogProvider(q)),
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh settings'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _panel(
            DropdownButtonFormField<String>(
              initialValue: family.key,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Settings family'),
              items: families
                  .map(
                    (f) => DropdownMenuItem(value: f.key, child: Text(f.label)),
                  )
                  .toList(),
              onChanged: action.busy
                  ? null
                  : (value) {
                      if (value != null) setState(() => _chooseFamily(value));
                    },
            ),
          ),
          if (family.key.startsWith('notification_template'))
            _notice(
              'SMS receipt wording is reviewed through its separate receipt policy.',
            ),
          if (action.storageBlocked || action.message != null)
            _notice(
              action.message ??
                  'Recovery storage is unavailable. Restore storage before saving a setting.',
            ),
          if (action.pending.isNotEmpty)
            _panel(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Original requests to investigate'),
                  for (final original in action.pending)
                    ListTile(
                      title: Text(original.family.label),
                      subtitle: SelectableText(
                        'Request ${original.requestId}\nOriginal deadline ${settingsUtc(original.expiresAt)}',
                      ),
                      trailing: TextButton(
                        onPressed:
                            action.busy || !original.family.canRead(identity)
                            ? null
                            : () => ref
                                  .read(
                                    adminSettingsControllerProvider.notifier,
                                  )
                                  .reconcile(original),
                        child: const Text('Check original'),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, box) {
              final listing = _panel(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Controls',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    catalog.when(
                      skipLoadingOnRefresh: false,
                      data: (page) => Column(
                        children: [
                          if (page.rows.isEmpty)
                            const AdminEmptyState(
                              title: 'No controls in this family',
                              message:
                                  'Open an identity to inspect whether a control can be created.',
                            ),
                          for (final row in page.rows)
                            ListTile(
                              title: Text(
                                row.identity.entries
                                    .map((e) => '${e.key}: ${e.value}')
                                    .join(' · '),
                              ),
                              subtitle: Text(
                                'Revision ${row.revision}${row.redacted ? ' · Restricted value' : ''}',
                              ),
                              selected:
                                  _selectedIdentity == jsonEncode(row.identity),
                              onTap: () => setState(
                                () => _selectedIdentity = jsonEncode(
                                  row.identity,
                                ),
                              ),
                            ),
                          Wrap(
                            spacing: 8,
                            children: [
                              if (_catalogPrevious.isNotEmpty)
                                TextButton(
                                  onPressed: () {
                                    setState(
                                      () => _after = _catalogPrevious
                                          .removeLast(),
                                    );
                                  },
                                  child: const Text('Previous controls'),
                                ),
                              if (page.nextCursor != null)
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _catalogPrevious.add(_after);
                                      _after = jsonEncode(page.nextCursor);
                                    });
                                  },
                                  child: const Text('Next controls'),
                                ),
                            ],
                          ),
                        ],
                      ),
                      loading: () => const AdminLoadingState(
                        title: 'Loading settings',
                        message: 'Checking the current controls.',
                      ),
                      error: (_, _) => _notice(
                        family.canRead(identity)
                            ? 'Settings could not be verified. Refresh or sign in again.'
                            : 'This family requires separate read permission. You can inspect change history for a known identity.',
                      ),
                    ),
                    const Divider(height: 24),
                    Text(
                      'Open a control',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    for (final field in family.identityFields)
                      if (family.fieldTypes[field] != 'boolean')
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: TextField(
                            key: ValueKey('settings-identity-$field'),
                            controller: _ids.putIfAbsent(
                              field,
                              TextEditingController.new,
                            ),
                            decoration: InputDecoration(
                              labelText: field,
                              errorText: _identityError,
                            ),
                            onSubmitted: (_) => _openIdentity(family),
                          ),
                        ),
                    if (family.identityFields.any(
                      (f) => family.fieldTypes[f] == 'boolean',
                    ))
                      const Text('This family has one control.'),
                    TextButton(
                      onPressed: () => _openIdentity(family),
                      child: const Text('Open identity'),
                    ),
                  ],
                ),
              );
              final detail = _selectedIdentity == null
                  ? _panel(
                      const Text(
                        'Select a control to inspect its current value and change history.',
                      ),
                    )
                  : _AdminSettingsDetailPane(
                      query: (family: family.key, identity: _selectedIdentity!),
                    );
              return box.maxWidth >= 1050
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 330, child: listing),
                        const SizedBox(width: 18),
                        Expanded(child: detail),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [listing, const SizedBox(height: 12), detail],
                    );
            },
          ),
        ],
      ),
    );
  }
}

class _AdminSettingsDetailPane extends ConsumerWidget {
  const _AdminSettingsDetailPane({required this.query});
  final AdminSettingsControlQuery query;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final family = AdminSettingsFamily.parse(query.family),
        identity = _adminResolvedIdentity(ref.watch(adminIdentityProvider));
    final detail = ref.watch(adminSettingsControlProvider(query));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        detail.when(
          skipLoadingOnRefresh: false,
          data: (control) => _AdminSettingsEditor(
            key: ValueKey(
              '${query.family}:${query.identity}:${control.revision}',
            ),
            control: control,
          ),
          loading: () =>
              const AdminLoadingState(title: 'Loading current setting'),
          error: (_, _) => const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'The current value could not be verified. Refresh or check your read permission.',
              ),
            ),
          ),
        ),
        TextButton.icon(
          onPressed: () => ref.invalidate(adminSettingsControlProvider(query)),
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh current value'),
        ),
        if (family.canAudit(identity))
          _AdminSettingsHistoryPane(query: query)
        else
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text('Change history requires Audit read permission.'),
            ),
          ),
      ],
    );
  }
}

class _AdminSettingsEditor extends ConsumerStatefulWidget {
  const _AdminSettingsEditor({required this.control, super.key});
  final AdminSettingsControl control;
  @override
  ConsumerState<_AdminSettingsEditor> createState() =>
      _AdminSettingsEditorState();
}

class _AdminSettingsEditorState extends ConsumerState<_AdminSettingsEditor> {
  final _reason = TextEditingController();
  final _fields = <String, TextEditingController>{};
  final _changed = <String>{}, _clear = <String>{};
  final _bools = <String, bool>{};
  String? _error;
  AdminSettingsEligibility? _eligibility;
  bool _checking = false;
  AdminSessionScope? _draftScope;
  int? _draftVersion;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    for (final field in widget.control.family.writableFields) {
      final value = widget.control.value[field];
      _fields[field] = TextEditingController(
        text: value == null
            ? ''
            : value is String
            ? value
            : jsonEncode(value),
      );
      _bools[field] = value == true;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _reason.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, Object?> _patch() {
    final family = widget.control.family, patch = <String, Object?>{};
    for (final field in _changed) {
      if (_clear.contains(field)) {
        patch[field] = null;
        continue;
      }
      final text = _fields[field]!.text;
      patch[field] = switch (family.fieldTypes[field]) {
        'boolean' => _bools[field],
        'integer' || 'bigint' =>
          RegExp(r'^-?(0|[1-9][0-9]*)$').hasMatch(text)
              ? exactJsonInteger(text, field: field, allowDigitString: true)
              : governedSettingsInvalid('$field integer'),
        'jsonb' => jsonDecode(text),
        _ => text,
      };
    }
    return family.patch(patch);
  }

  bool _editable(String field) {
    final control = widget.control;
    if (!AdminSettingsEligibility.requiredFor(control.family))
      return control.editableField(field);
    if (!control.exists &&
        const {'policy_document_id', 'template_key'}.contains(field))
      return true;
    final eligibility = _eligibility;
    return eligibility != null &&
        eligibility.canManage &&
        eligibility.sample.fresh(ref.read(adminClockProvider)()) &&
        eligibility.permittedFields.contains(field);
  }

  List<String> get _statuses =>
      _eligibility?.permittedStatuses.isNotEmpty == true
      ? _eligibility!.permittedStatuses
      : widget.control.permittedStatuses;
  Future<AdminSettingsEligibility?> _checkEligibility(String raw) async {
    final fence = _AdminActionScope(ref), control = widget.control;
    if (!fence.isCurrent ||
        !control.family.canManage(
          _adminResolvedIdentity(ref.read(adminIdentityProvider)),
        ))
      return null;
    if (mounted)
      setState(() {
        _checking = true;
        _error = null;
      });
    try {
      final value = await ref
          .read(adminRepositoryProvider)
          .governedSettings
          .eligibility(control, raw);
      if (!mounted ||
          !fence.isCurrent ||
          _draftScope != ref.read(adminAuthSessionScopeProvider) ||
          _draftVersion != ref.read(_adminIdentityRevisionProvider) ||
          !control.family.canManage(
            _adminResolvedIdentity(ref.read(adminIdentityProvider)),
          ))
        return null;
      setState(() => _eligibility = value);
      return value;
    } finally {
      if (mounted && fence.isCurrent) setState(() => _checking = false);
    }
  }

  Future<void> _refreshEligibility() async {
    try {
      final raw = _changed.isEmpty ? '{}' : jsonEncode(_patch());
      final result = await _checkEligibility(raw);
      if (mounted && result?.blocker != null)
        setState(
          () => _error =
              'This draft is not eligible: ${result!.blocker!.split('_').join(' ')}.',
        );
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Eligibility could not be checked. Refresh the current setting.',
        );
    }
  }

  Future<void> _review() async {
    final fence = _AdminActionScope(ref),
        control = widget.control,
        scope = ref.read(adminAuthSessionScopeProvider);
    if (scope == null ||
        !fence.isCurrent ||
        _draftScope != scope ||
        _draftVersion != ref.read(_adminIdentityRevisionProvider) ||
        !control.family.canManage(
          _adminResolvedIdentity(ref.read(adminIdentityProvider)),
        )) {
      return;
    }
    try {
      final patch = _patch(), raw = jsonEncode(_patch()), reason = _reason.text;
      final eligibility = AdminSettingsEligibility.requiredFor(control.family)
          ? await _checkEligibility(raw)
          : null;
      if (!mounted ||
          !fence.isCurrent ||
          reason != _reason.text ||
          raw != jsonEncode(_patch()))
        return;
      if (AdminSettingsEligibility.requiredFor(control.family) &&
          eligibility == null)
        return;
      final intent = AdminSettingsPreparedUpdate.prepare(
        requestId: const Uuid().v4(),
        control: control,
        patch: patch,
        reason: reason,
        now: ref.read(adminClockProvider)(),
        eligibility: eligibility,
        scope: scope,
      );
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => _AdminSessionDialog(
          scope: fence,
          child: _AdminSettingsReviewDialog(intent: intent, scope: fence),
        ),
      );
      if (!mounted ||
          approved != true ||
          !fence.isCurrent ||
          !intent.current(
            ref.read(adminAuthSessionScopeProvider),
            ref.read(adminClockProvider)(),
          )) {
        return;
      }
      await ref.read(adminSettingsControllerProvider.notifier).submit(intent);
      if (!mounted || !fence.isCurrent) return;
      final result = ref.read(adminSettingsControllerProvider);
      if (result.receipt != null) {
        _reason.clear();
        _changed.clear();
        ref.invalidate(
          adminSettingsControlProvider((
            family: control.family.key,
            identity: jsonEncode(control.identity),
          )),
        );
      }
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The change could not be prepared. Refresh the current setting.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final control = widget.control,
        family = control.family,
        scope = ref.watch(adminAuthSessionScopeProvider),
        version = ref.watch(_adminIdentityRevisionProvider),
        identity = _adminResolvedIdentity(ref.watch(adminIdentityProvider));
    if (AdminSettingsEligibility.requiredFor(family)) {
      final observation = ref.watch(
        adminSettingsEligibilityProvider((
          family: family.key,
          identity: jsonEncode(control.identity),
          revision: control.revision,
          patch: '{}',
        )),
      );
      _eligibility ??= observation.asData?.value;
    }
    final action = ref.watch(adminSettingsControllerProvider),
        now = ref.read(adminClockProvider)();
    _draftScope ??= scope;
    _draftVersion ??= version;
    final fresh = control.sample?.fresh(now) == true,
        owned = scope == _draftScope && version == _draftVersion;
    final manage =
        fresh &&
        owned &&
        scope != null &&
        family.canManage(identity) &&
        control.canManage &&
        !control.redacted &&
        !_checking &&
        !action.busy &&
        !action.storageBlocked &&
        action.pending.isEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Current setting',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              control.identity.entries
                  .map((e) => '${e.key}: ${e.value}')
                  .join('\n'),
            ),
            Text(
              'Revision ${control.revision}${control.exists ? '' : ' · No control yet'}',
            ),
            if (!fresh)
              const Text(
                'This view expired. Refresh the current value before preparing a change.',
              ),
            if (!owned)
              const Text(
                'Your session or access changed. Refresh to open a new editor.',
              ),
            if (control.redacted)
              const Text(
                'This value is restricted. It cannot be changed through this workspace.',
              ),
            if (!control.exists && !family.createAllowed)
              const Text(
                'Creating this control requires its dedicated owner workflow.',
              ),
            if (AdminSettingsEligibility.requiredFor(family)) ...[
              const Text(
                'Draft edits and publication require current parent and version eligibility. Saving checks the exact draft again.',
              ),
              if (_eligibility?.blocker != null)
                Text(
                  'Eligibility: ${_eligibility!.blocker!.split('_').join(' ')}.',
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: manage ? _refreshEligibility : null,
                  child: const Text('Check draft eligibility'),
                ),
              ),
            ],
            const SizedBox(height: 14),
            for (final field in family.writableFields)
              _field(field, manage && _editable(field)),
            const SizedBox(height: 16),
            TextField(
              key: const Key('settings-reason'),
              controller: _reason,
              enabled: manage,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason',
                helperText:
                    '8–500 characters, retained as an audit fingerprint.',
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            if (_error != null)
              Semantics(liveRegion: true, child: Text(_error!)),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: manage && _changed.isNotEmpty ? _review : null,
                child: const Text('Review change'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String field, bool enabled) {
    final family = widget.control.family,
        type = family.fieldTypes[field],
        changed = _changed.contains(field),
        cleared = _clear.contains(field);
    final label = field.split('_').join(' ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckboxListTile(
            key: ValueKey('settings-change-$field'),
            contentPadding: EdgeInsets.zero,
            value: changed,
            onChanged: enabled
                ? (v) => setState(() {
                    v == true ? _changed.add(field) : _changed.remove(field);
                    _error = null;
                  })
                : null,
            title: Text('Change $label'),
            subtitle: !_editable(field)
                ? const Text('Immutable for this current control.')
                : null,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          if (family.nullableFields.contains(field))
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: cleared,
              onChanged: enabled && changed
                  ? (v) => setState(() {
                      v ? _clear.add(field) : _clear.remove(field);
                    })
                  : null,
              title: Text('Clear $label'),
            ),
          if (type == 'boolean')
            SwitchListTile(
              key: ValueKey('settings-field-$field'),
              contentPadding: EdgeInsets.zero,
              value: _bools[field]!,
              onChanged: enabled && changed && !cleared
                  ? (v) => setState(() => _bools[field] = v)
                  : null,
              title: Text(label),
            )
          else if (field == 'receipt_language' &&
              family.key == 'sms_receipt_policies')
            DropdownButtonFormField<String>(
              key: ValueKey('settings-field-$field'),
              initialValue:
                  const {'rw', 'en', 'fr'}.contains(_fields[field]!.text)
                  ? _fields[field]!.text
                  : null,
              decoration: const InputDecoration(
                labelText: 'Receipt language',
                helperText:
                    'New receipts capture this language in their original evidence.',
              ),
              items: const [
                DropdownMenuItem(value: 'rw', child: Text('Kinyarwanda')),
                DropdownMenuItem(value: 'en', child: Text('English')),
                DropdownMenuItem(value: 'fr', child: Text('Français')),
              ],
              onChanged: enabled && changed && !cleared
                  ? (value) {
                      if (value != null) {
                        setState(() {
                          _fields[field]!.text = value;
                          _error = null;
                        });
                      }
                    }
                  : null,
            )
          else if (field == 'status' &&
              {
                'policy_documents',
                'notification_template_versions',
              }.contains(family.key))
            DropdownButtonFormField<String>(
              key: ValueKey('settings-field-$field'),
              initialValue: _statuses.contains(_fields[field]!.text)
                  ? _fields[field]!.text
                  : _statuses.first,
              decoration: InputDecoration(labelText: label),
              items: _statuses
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: enabled && changed && !cleared
                  ? (v) {
                      if (v != null) setState(() => _fields[field]!.text = v);
                    }
                  : null,
            )
          else
            TextField(
              key: ValueKey('settings-field-$field'),
              controller: _fields[field],
              enabled: enabled && changed && !cleared,
              minLines: type == 'jsonb' || field.contains('body') ? 3 : 1,
              maxLines: type == 'jsonb' || field.contains('body') ? 8 : 3,
              decoration: InputDecoration(
                labelText: label,
                helperText: type == 'jsonb'
                    ? 'JSON object, array or scalar; up to 65,536 bytes.'
                    : type == 'timestamp with time zone'
                    ? 'Use an explicit time zone.'
                    : null,
              ),
              onChanged: (_) => setState(() {
                _error = null;
                if (const {
                  'policy_document_id',
                  'template_key',
                }.contains(field))
                  _eligibility = null;
              }),
            ),
        ],
      ),
    );
  }
}

class _AdminSettingsReviewDialog extends ConsumerStatefulWidget {
  const _AdminSettingsReviewDialog({required this.intent, required this.scope});
  final AdminSettingsPreparedUpdate intent;
  final _AdminActionScope scope;
  @override
  ConsumerState<_AdminSettingsReviewDialog> createState() =>
      _AdminSettingsReviewDialogState();
}

class _AdminSettingsReviewDialogState
    extends ConsumerState<_AdminSettingsReviewDialog> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(adminAuthSessionScopeProvider);
    ref.watch(adminIdentityProvider);
    ref.watch(_adminIdentityRevisionProvider);
    final current =
        widget.scope.isCurrent &&
        widget.intent.current(
          ref.read(adminAuthSessionScopeProvider),
          ref.read(adminClockProvider)(),
        );
    return AlertDialog(
      scrollable: true,
      title: const Text('Review setting change'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.intent.family.label),
          Text('Expected revision ${widget.intent.expectedRevision}'),
          const SizedBox(height: 12),
          SelectableText(
            const JsonEncoder.withIndent(
              '  ',
            ).convert(jsonDecode(widget.intent.patchJson)),
          ),
          const SizedBox(height: 12),
          Text('Reason: ${widget.intent.reason}'),
          SelectableText('Request ${widget.intent.requestId}'),
          Text('Deadline ${settingsUtc(widget.intent.expiresAt)}'),
          if (!current)
            const Text(
              'This original request expired or your session changed. Close and refresh.',
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: current ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Save original request'),
        ),
      ],
    );
  }
}

class _AdminSettingsHistoryPane extends ConsumerStatefulWidget {
  const _AdminSettingsHistoryPane({required this.query});
  final AdminSettingsControlQuery query;
  @override
  ConsumerState<_AdminSettingsHistoryPane> createState() =>
      _AdminSettingsHistoryPaneState();
}

class _AdminSettingsHistoryPaneState
    extends ConsumerState<_AdminSettingsHistoryPane> {
  AdminSettingsHistoryCursor? _before;
  final List<AdminSettingsHistoryCursor?> _previous = [];
  @override
  void didUpdateWidget(covariant _AdminSettingsHistoryPane old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) {
      _before = null;
      _previous.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = (
          family: widget.query.family,
          identity: widget.query.identity,
          beforeAt: _before == null ? null : settingsUtc(_before!.recordedAt),
          beforeId: _before?.eventId,
        ),
        history = ref.watch(adminSettingsHistoryProvider(q));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Change history',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Text(
              'Changes only. Earlier history may be incomplete. No-op results are available through their original request.',
            ),
            const SizedBox(height: 12),
            history.when(
              skipLoadingOnRefresh: false,
              loading: () =>
                  const AdminLoadingState(title: 'Loading change history'),
              error: (_, _) => const Text(
                'Change history could not be verified. Refresh or check Audit read permission.',
              ),
              data: (page) => Column(
                children: [
                  if (page.events.isEmpty)
                    const Text('No recorded changes in this page.'),
                  for (final event in page.events)
                    ExpansionTile(
                      key: ValueKey('settings-history-${event.eventId}'),
                      title: Text(
                        '${event.operation} · Revision ${event.previousRevision} → ${event.revision}',
                      ),
                      subtitle: Text(settingsUtc(event.recordedAt)),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: SelectableText(
                            'Event ${event.eventId}\nActor ${event.actorId ?? 'Database owner'}\nAuthority ${event.authority}\n${event.requestId == null ? 'Original request association unavailable' : 'Request ${event.requestId}'}\nChanged fields: ${event.changedFields.join(', ')}\n${event.redacted ? 'Content hashes redacted' : 'Previous hash ${event.oldHash ?? 'none'}\nCurrent hash ${event.newHash ?? 'none'}'}\nReason fingerprint ${event.reasonHash}\nReason length ${event.reasonCharacters}',
                          ),
                        ),
                      ],
                    ),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (_previous.isNotEmpty)
                        TextButton(
                          onPressed: () =>
                              setState(() => _before = _previous.removeLast()),
                          child: const Text('Newer changes'),
                        ),
                      if (page.nextCursor != null)
                        TextButton(
                          onPressed: () => setState(() {
                            _previous.add(_before);
                            _before = page.nextCursor;
                          }),
                          child: const Text('Older changes'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => ref.invalidate(adminSettingsHistoryProvider(q)),
              child: const Text('Refresh history'),
            ),
          ],
        ),
      ),
    );
  }
}
