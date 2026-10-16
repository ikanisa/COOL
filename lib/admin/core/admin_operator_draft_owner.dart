part of 'admin_runtime.dart';

class AdminOperatorDraftOwnerPanel extends ConsumerStatefulWidget {
  const AdminOperatorDraftOwnerPanel({
    required this.collectionId,
    required this.markedDraft,
    super.key,
  });

  final String collectionId;
  final bool markedDraft;

  @override
  ConsumerState<AdminOperatorDraftOwnerPanel> createState() =>
      _AdminOperatorDraftOwnerPanelState();
}

class _AdminOperatorDraftOwnerPanelState
    extends ConsumerState<AdminOperatorDraftOwnerPanel> {
  final _id = TextEditingController();
  final _revision = ValueNotifier(0);
  AdminTableRowData? _candidate;
  _AdminActionScope? _candidateScope;
  String? _candidateId, _attemptedOwner, _message;
  bool _busy = false, _uncertain = false, _resolved = false, _assigned = false;
  int _request = 0;

  @override
  void didUpdateWidget(covariant AdminOperatorDraftOwnerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collectionId != widget.collectionId) {
      _request++;
      _notifyTargetChange();
      _id.clear();
      _candidate = null;
      _candidateScope = null;
      _candidateId = null;
      _attemptedOwner = null;
      _message = null;
      _busy = _uncertain = _resolved = _assigned = false;
    } else if (oldWidget.markedDraft != widget.markedDraft) {
      _request++;
      _notifyTargetChange();
      _candidate = null;
    }
  }

  void _notifyTargetChange() {
    // An open dialog is outside this widget's ancestor tree. Notify it after
    // the parent update frame, while synchronous request fences already refuse
    // every action for the previous target.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _revision.value++;
    });
  }

  @override
  void dispose() {
    _id.dispose();
    _revision.dispose();
    super.dispose();
  }

  bool _current(_AdminActionScope scope, String target, int request) =>
      mounted &&
      widget.collectionId == target &&
      widget.markedDraft &&
      request == _request &&
      scope.isCurrent;

  Future<void> _lookup() async {
    if (_busy || _uncertain || _resolved) return;
    final publicId = _id.text.trim();
    if (!RegExp(r'^[0-9]{6}$').hasMatch(publicId)) {
      setState(() => _message = 'Enter a six-digit Collect ID.');
      return;
    }
    final scope = _AdminActionScope(ref);
    if (!_authorized(scope)) return;
    final target = widget.collectionId, request = ++_request;
    setState(() {
      _busy = true;
      _candidate = null;
      _candidateScope = null;
      _message = null;
    });
    try {
      final result = await scope.repository.list(
        'admin_list_users',
        search: publicId,
        status: 'app',
        limit: 25,
        offset: 0,
      );
      if (!_current(scope, target, request) || _id.text.trim() != publicId) {
        return;
      }
      final matches = result.rows
          .where(
            (row) =>
                row.extra['public_id'] == publicId &&
                row.extra['user_type'] == 'App' &&
                row.extra['record_type'] == 'auth' &&
                RegExp(
                  r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$',
                ).hasMatch(row.id),
          )
          .toList();
      // A truncated search cannot prove that an exact ID is unique.
      if (matches.length != 1 || result.total != result.rows.length) {
        setState(
          () => _message = matches.isEmpty
              ? 'No exact App user found for this Collect ID.'
              : 'The exact App user could not be verified. Search again.',
        );
        return;
      }
      setState(() {
        _candidate = matches.single;
        _candidateScope = scope;
        _candidateId = publicId;
      });
    } catch (_) {
      if (_current(scope, target, request)) {
        setState(() => _message = 'User lookup failed. Search again.');
      }
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  bool _authorized(_AdminActionScope scope) =>
      scope.isCurrent &&
      scope.roles.any(const {'admin', 'platform_owner'}.contains) &&
      scope.permissions.contains('collections.moderate') &&
      scope.permissions.contains('users.read');

  Future<void> _assign() async {
    final candidate = _candidate, scope = _candidateScope;
    final publicId = _candidateId;
    if (_busy ||
        _uncertain ||
        _resolved ||
        candidate == null ||
        scope == null ||
        publicId == null ||
        !_authorized(scope) ||
        _id.text.trim() != publicId) {
      return;
    }
    final target = widget.collectionId, request = _request;
    final reason = TextEditingController();
    final form = GlobalKey<FormState>();
    final confirmed = await _showAdminFormDialog<bool>(
      context: context,
      builder: (dialogContext) => _AdminSessionDialog(
        scope: scope,
        child: ValueListenableBuilder<int>(
          valueListenable: _revision,
          builder: (context, _, _) {
            if (!_current(scope, target, request) ||
                _id.text.trim() != publicId) {
              final route = ModalRoute.of(context);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (route?.isActive == true) {
                  route!.navigator?.removeRoute(route);
                }
              });
              return const SizedBox.shrink();
            }
            return AlertDialog(
              title: const Text('Assign group owner'),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Form(
                    key: form,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ..._candidateFields(candidate, publicId),
                        const SizedBox(height: 16),
                        const Text(
                          'This App user will own the group and manage its member and MoMo receiver setup.',
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: reason,
                          decoration: const InputDecoration(
                            labelText: 'Reason',
                          ),
                          maxLength: 500,
                          maxLines: 3,
                          validator: (value) =>
                              value == null || value.trim().length < 8
                              ? 'Enter a reason of at least 8 characters'
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    if (form.currentState!.validate()) {
                      Navigator.pop(dialogContext, true);
                    }
                  },
                  child: const Text('Confirm owner'),
                ),
              ],
            );
          },
        ),
      ),
    );
    final reasonText = reason.text.trim();
    reason.dispose();
    if (confirmed != true ||
        !_current(scope, target, request) ||
        _id.text.trim() != publicId) {
      return;
    }
    setState(() {
      _busy = true;
      _uncertain = true;
      _attemptedOwner = candidate.id;
      _message = null;
    });
    try {
      await scope.repository.assignOperatorDraftOwner(
        collectionId: target,
        ownerCollectId: publicId,
        reason: reasonText,
      );
      if (!_current(scope, target, request)) return;
      // SQL void/null is not proof of the resulting group ownership.
      await _readOutcome(scope, target, request, mayUnlock: false);
    } catch (_) {
      if (_current(scope, target, request)) {
        setState(
          () => _message =
              'Ownership is not yet confirmed. Refresh group status before trying again.',
        );
      }
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  Future<void> _readOutcome(
    _AdminActionScope scope,
    String target,
    int request, {
    required bool mayUnlock,
  }) async {
    final row = await scope.repository.detail('admin_get_collection', target);
    if (!_current(scope, target, request)) return;
    if (row['id'] != target || row['admin_operator_draft'] is! bool) {
      throw const FormatException('Group status unavailable');
    }
    if (row['admin_operator_draft'] == false) {
      final assigned = row['creator_user_id'] == _attemptedOwner;
      setState(() {
        _resolved = true;
        _uncertain = false;
        _assigned = assigned;
        _message = assigned
            ? 'Group owner assigned.'
            : 'This group now has a different owner. Refresh the group details.';
      });
      ref.read(adminRealtimeTickProvider.notifier).state++;
    } else {
      setState(() {
        _uncertain = !mayUnlock;
        _message = mayUnlock
            ? 'The group is still a draft. Review the owner before trying again.'
            : 'Ownership is not yet confirmed. Refresh group status before trying again.';
      });
    }
  }

  Future<void> _refresh() async {
    if (_busy || !_uncertain) return;
    final scope = _AdminActionScope(ref);
    if (!_authorized(scope)) return;
    final target = widget.collectionId, request = ++_request;
    setState(() => _busy = true);
    try {
      await _readOutcome(scope, target, request, mayUnlock: true);
    } catch (_) {
      if (_current(scope, target, request)) {
        setState(
          () => _message = 'Group status could not be verified. Refresh again.',
        );
      }
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  List<Widget> _candidateFields(AdminTableRowData candidate, String publicId) {
    String? stored(String key) {
      final value = candidate.extra[key];
      return value is String && value.trim().isNotEmpty ? value : null;
    }

    return [
      AdminDataFieldRow(
        label: 'Name',
        value:
            stored('momo_registered_name') ??
            stored('display_name') ??
            'Name not recorded',
      ),
      AdminDataFieldRow(label: 'Collect ID', value: publicId),
      if (stored('whatsapp_phone') case final phone?)
        AdminDataFieldRow(label: 'WhatsApp', value: phone),
      if (stored('momo_number') case final number?)
        AdminDataFieldRow(label: 'MoMo number', value: number),
      if (stored('momo_pay_code') case final code?)
        AdminDataFieldRow(label: 'MoMo code', value: code),
    ];
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(adminAuthSessionScopeProvider);
    ref.watch(adminRepositoryProvider);
    ref.watch(_adminIdentityRevisionProvider);
    final identity = _adminResolvedIdentity(ref.watch(adminIdentityProvider));
    if (!widget.markedDraft ||
        identity == null ||
        !identity.roles.any(const {'admin', 'platform_owner'}.contains) ||
        !_adminHasPermission(identity, 'collections.moderate') ||
        !_adminHasPermission(identity, 'users.read')) {
      return const SizedBox.shrink();
    }
    final candidate =
        _candidateScope?.isCurrent == true && _candidateId == _id.text.trim()
        ? _candidate
        : null;
    return AdminDataSection(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Assign group owner',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'An Admin must assign this private draft to a real App user before member and MoMo receiver setup.',
            ),
            if (!_resolved) ...[
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('draft-owner-id'),
                controller: _id,
                enabled: !_uncertain,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'Owner Collect ID',
                  hintText: 'Six digits',
                ),
                onChanged: (_) => setState(() {
                  _request++;
                  _revision.value++;
                  _candidate = null;
                  _candidateScope = null;
                  _message = null;
                  _busy = false;
                }),
                onSubmitted: (_) => _lookup(),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy || _uncertain ? null : _lookup,
                icon: const Icon(Icons.person_search_outlined),
                label: const Text('Find App user'),
              ),
              if (candidate != null) ...[
                const SizedBox(height: 16),
                ..._candidateFields(candidate, _candidateId!),
                const SizedBox(height: 12),
                FilledButton(
                  key: const ValueKey('draft-owner-assign'),
                  onPressed: _busy || _uncertain ? null : _assign,
                  child: const Text('Assign owner'),
                ),
              ],
              if (_uncertain) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _busy ? null : _refresh,
                  child: const Text('Refresh group status'),
                ),
              ],
            ],
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _message!,
                    style: _assigned
                        ? Theme.of(context).textTheme.titleMedium
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
