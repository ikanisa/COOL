import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/collect_colors.dart';
import '../../app/theme/collect_universal_tokens.dart';
import '../shared/components/admin_page.dart';
import 'admin_account_api.dart';
import 'admin_burimunsi_api.dart';
import 'admin_pending_attempt_store.dart';

/// Quiet utility/settings adaptation of the selected Revolut web references.
/// Uses Collect's shared semantic theme and existing account/session boundary.
class AdminBuriMunsiPage extends ConsumerStatefulWidget {
  const AdminBuriMunsiPage({
    required this.onBack,
    required this.onVerify,
    super.key,
  });
  final VoidCallback onBack, onVerify;
  @override
  ConsumerState<AdminBuriMunsiPage> createState() => _BuriPageState();
}

class _BuriPageState extends ConsumerState<AdminBuriMunsiPage> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  BuriOperatorDirectory? _directory;
  BuriApprovalCoordinator? _coordinator;
  BuriSharedOperator? _selected;
  BuriOperatorApproval? _existing;
  Object? _loadedFence;
  String _role = 'staff';
  Set<String> _capabilities = {'records.read'};
  bool _active = true, _busy = false;
  String? _error, _status, _absentRequest;
  AdminBuriMunsiApi? get _api {
    final api = ref.read(adminAccountApiProvider);
    return api is AdminBuriMunsiApi ? api as AdminBuriMunsiApi : null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      await operation();
    } on AdminAccountException catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } on FormatException catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Access could not be confirmed. Check the original request before trying again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() {
    setState(() {
      _loadedFence = null;
      _directory = null;
      _coordinator = null;
    });
    return _run(_read);
  }

  Future<void> _read() async {
    final api = _api;
    if (api == null || !api.buriAvailable || !api.buriAuthorized) return;
    final fence = api.buriAuthorityFence;
    final directory = await api.loadBuriDirectory();
    if (!mounted ||
        !identical(api, _api) ||
        fence != api.buriAuthorityFence ||
        !api.buriAuthorized) {
      return;
    }
    final coordinator = BuriApprovalCoordinator(
      api: api,
      store: ref.read(adminPendingAttemptStoreProvider),
      collectionId: directory.collectionId,
    );
    final selectedId = _selected?.principalId;
    setState(() {
      _directory = directory;
      _loadedFence = fence;
      _coordinator = coordinator;
      _selected = null;
      _existing = null;
      _absentRequest = null;
      final choices = _choices(directory);
      final selection =
          choices.where((v) => v.principalId == selectedId).firstOrNull ??
          choices.firstOrNull;
      if (selection != null) _select(selection);
    });
  }

  List<BuriSharedOperator> _choices(BuriOperatorDirectory directory) => {
    for (final row in directory.approvals)
      row.operator.principalId: row.operator,
    for (final row in directory.team) row.principalId: row,
  }.values.toList();
  void _select(BuriSharedOperator operator) {
    _selected = operator;
    _existing = _directory?.approvals
        .where((v) => v.operator.principalId == operator.principalId)
        .firstOrNull;
    _phone.text = _existing?.phone ?? '';
    _role = _existing?.role ?? 'staff';
    _active = _existing?.active ?? true;
    _capabilities = {
      ...?_existing?.capabilities,
      if (_existing == null) 'records.read',
    };
  }

  Future<void> _save() async {
    final selected = _selected, coordinator = _coordinator;
    if (selected == null ||
        coordinator == null ||
        _form.currentState?.validate() != true) {
      return;
    }
    await _run(() async {
      final intent = BuriApprovalIntent(
        collectionId: coordinator.collectionId,
        operator: selected,
        phone: _phone.text,
        role: _role,
        capabilities: _capabilities.toList(),
        active: _active,
        expectedVersion: _existing?.version ?? 0,
      );
      await coordinator.submit(intent);
      await _read();
      if (mounted) setState(() => _status = 'BuriMunsi access saved.');
    });
  }

  Future<void> _check(BuriApprovalIntent intent) => _run(() async {
    final coordinator = _coordinator;
    if (coordinator == null) return;
    final found = await coordinator.check(intent);
    if (!mounted) return;
    if (found) {
      await _read();
      if (mounted) {
        setState(() => _status = 'The original approval is confirmed.');
      }
    } else {
      setState(() {
        _absentRequest = intent.requestId;
        _status = 'No receipt was found for this original request.';
      });
    }
  });
  Future<void> _resubmit(BuriApprovalIntent intent) => _run(() async {
    final coordinator = _coordinator;
    if (coordinator == null || _absentRequest != intent.requestId) return;
    await coordinator.submit(intent);
    await _read();
    if (mounted) {
      setState(() => _status = 'The original approval is confirmed.');
    }
  });

  Widget _surface(Widget child) => Material(
    color: context.collectColors.surfaceReadable,
    borderRadius: BorderRadius.circular(
      context.collectUniversalTokens.cardRadius,
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: const EdgeInsets.all(20), child: child),
  );
  @override
  Widget build(BuildContext context) {
    final api = _api, store = ref.watch(adminPendingAttemptStoreProvider);
    final authorized = api?.buriAuthorized == true;
    final directory = authorized && _loadedFence == api?.buriAuthorityFence
        ? _directory
        : null;
    final pending = directory == null
        ? const <BuriApprovalIntent>[]
        : _coordinator?.pending ?? const <BuriApprovalIntent>[];
    final editable =
        !_busy &&
        directory?.configured == true &&
        pending.isEmpty &&
        store.storageAvailable;
    final compact = MediaQuery.sizeOf(context).width < 600;
    final back = IconButton(
      tooltip: 'Back to team access',
      onPressed: widget.onBack,
      icon: const Icon(Icons.arrow_back),
    );
    final refresh = IconButton(
      tooltip: 'Refresh BuriMunsi access',
      onPressed: _busy || !authorized ? null : _load,
      icon: const Icon(Icons.refresh),
    );
    return AdminPage(
      title: 'BuriMunsi access',
      subtitle: 'Approve staff and admin access.',
      leading: compact ? null : back,
      trailing: compact ? Wrap(spacing: 8, children: [back, refresh]) : refresh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_busy)
            const LinearProgressIndicator(
              semanticsLabel: 'Checking BuriMunsi access',
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: context.collectColors.dangerForeground,
                  ),
                ),
              ),
            ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Semantics(liveRegion: true, child: Text(_status!)),
            ),
          if (api?.buriAvailable != true)
            const Text('BuriMunsi access is not available in this workspace.')
          else if (!authorized)
            _surface(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Verify your current owner email to manage BuriMunsi access.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: widget.onVerify,
                    icon: const Icon(Icons.mark_email_read_outlined),
                    label: const Text('Verify email'),
                  ),
                ],
              ),
            )
          else ...[
            if (!store.storageAvailable)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(store.storageMessage),
              ),
            for (final intent in pending)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: _surface(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Approval needs confirmation',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Check the original request before changing access again.',
                      ),
                      SelectableText(intent.requestId),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton.icon(
                            onPressed: _busy ? null : () => _check(intent),
                            icon: const Icon(Icons.manage_search),
                            label: const Text('Check original request'),
                          ),
                          if (_absentRequest == intent.requestId)
                            OutlinedButton(
                              onPressed: _busy ? null : () => _resubmit(intent),
                              child: const Text('Submit original request'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (directory != null && !directory.configured)
              const Text(
                'The BuriMunsi group and receiving account need to be configured before approving access.',
              ),
            if (directory?.configured == true)
              LayoutBuilder(
                builder: (context, constraints) {
                  final people = _people(directory!, editable);
                  final form = _editor(editable);
                  if (constraints.maxWidth < 1000 ||
                      MediaQuery.textScalerOf(context).scale(16) > 24) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [people, const SizedBox(height: 20), form],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: people),
                      const SizedBox(width: 24),
                      Expanded(flex: 3, child: form),
                    ],
                  );
                },
              ),
          ],
        ],
      ),
    );
  }

  Widget _people(BuriOperatorDirectory directory, bool editable) {
    final choices = _choices(directory);
    if (choices.isEmpty) {
      return _surface(
        const Text(
          'Add and activate a Collect teammate before approving BuriMunsi access.',
        ),
      );
    }
    return _surface(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Collect accounts',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          for (final operator in choices)
            ListTile(
              contentPadding: EdgeInsets.zero,
              selected: _selected?.principalId == operator.principalId,
              leading: const Icon(Icons.person_outline),
              title: Text(
                operator.name.isEmpty ? operator.email : operator.name,
              ),
              subtitle: Text(operator.email),
              trailing: _selected?.principalId == operator.principalId
                  ? const Icon(Icons.check_circle_outline)
                  : null,
              onTap: editable ? () => setState(() => _select(operator)) : null,
            ),
        ],
      ),
    );
  }

  Widget _editor(bool editable) {
    final selected = _selected;
    if (selected == null) return const SizedBox.shrink();
    final canBeAdmin =
        const {'owner', 'admin'}.contains(selected.role) || _role == 'admin';
    return _surface(
      Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              selected.name.isEmpty ? selected.email : selected.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(selected.email),
            if (_existing?.sharedStatus case final status?
                when status != 'active')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Collect access: $status'),
              ),
            const SizedBox(height: 20),
            TextFormField(
              key: const Key('buri-login-phone'),
              controller: _phone,
              enabled: editable,
              keyboardType: TextInputType.phone,
              maxLength: 40,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[+0-9 ()-]')),
              ],
              decoration: const InputDecoration(
                labelText: 'BuriMunsi login phone',
                hintText: '078…',
              ),
              validator: (value) {
                try {
                  buriLoginPhone(value ?? '');
                  return null;
                } on FormatException catch (e) {
                  return e.message;
                }
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('buri-role-${selected.principalId}-$_role'),
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'BuriMunsi role'),
              items: [
                const DropdownMenuItem(value: 'staff', child: Text('Staff')),
                if (canBeAdmin)
                  const DropdownMenuItem(value: 'admin', child: Text('Admin')),
              ],
              onChanged: editable && _existing == null
                  ? (role) => setState(() {
                      _role = role!;
                      _capabilities = {'records.read'};
                    })
                  : null,
            ),
            const SizedBox(height: 16),
            for (final entry in buriCapabilities.entries)
              if (_role == 'admin' ||
                  const {
                    'records.read',
                    'members.enroll',
                    'payments.allocate',
                  }.contains(entry.key))
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.value),
                  value: _capabilities.contains(entry.key),
                  onChanged: editable && entry.key != 'records.read'
                      ? (value) => setState(() {
                          if (value == true) {
                            _capabilities.add(entry.key);
                          } else {
                            _capabilities.remove(entry.key);
                          }
                        })
                      : null,
                ),
            if (_existing != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('BuriMunsi access enabled'),
                value: _active,
                onChanged: editable
                    ? (value) => setState(() => _active = value)
                    : null,
              ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('buri-save-access'),
              onPressed: editable ? _save : null,
              icon: const Icon(Icons.verified_user_outlined),
              label: Text(_existing == null ? 'Approve access' : 'Save access'),
            ),
          ],
        ),
      ),
    );
  }
}
