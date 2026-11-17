import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/collect_colors.dart';
import '../../app/theme/collect_universal_tokens.dart';
import '../shared/components/admin_page.dart';
import 'admin_account_api.dart';
import 'admin_burimunsi_api.dart';
import 'admin_pending_attempt_store.dart';
import 'cloudflare_admin_momo_page.dart' show showMomoGatewaySetup;

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

class _BuriPageState extends ConsumerState<AdminBuriMunsiPage>
    with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _pin = _ProtectedNativeTextController(),
      _pinConfirm = _ProtectedNativeTextController();
  final _installation = TextEditingController();
  BuriOperatorDirectory? _directory;
  BuriApprovalCoordinator? _coordinator;
  BuriProvisioningDirectory? _provisioning;
  BuriProvisioningCoordinator? _provisioner;
  String? _provisioningError;
  String _profile = 'staff';
  BuriSharedOperator? _selected;
  BuriOperatorApproval? _existing;
  Object? _loadedFence;
  String _role = 'staff';
  Set<String> _capabilities = {'records.read'};
  bool _active = true, _busy = false;
  String? _error, _status, _absentRequest;
  List<BuriScopeChoice> _scopes = [];
  String? _collectionId;
  AdminBuriMunsiApi? get _api {
    final api = ref.read(adminAccountApiProvider);
    return api is AdminBuriMunsiApi ? api as AdminBuriMunsiApi : null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    _phone.dispose();
    _pin.dispose();
    _pinConfirm.dispose();
    _installation.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _pin.clear();
      _pinConfirm.clear();
    }
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
      _provisioning = null;
      _provisioner = null;
      _provisioningError = null;
    });
    return _run(_read);
  }

  Future<void> _read() async {
    final api = _api;
    if (api == null || !api.buriAvailable || !api.buriAuthorized) return;
    final fence = api.buriAuthorityFence;
    if (api is AdminBuriMunsiScopeApi) {
      final choices = await api.loadBuriScopes();
      if (!mounted || fence != api.buriAuthorityFence) return;
      setState(() => _scopes = choices);
      if (_collectionId == null) {
        final store = ref.read(adminPendingAttemptStoreProvider);
        final retained = [
          ...store.restoreFamily(
            family: BuriApprovalCoordinator.family,
            permission: BuriApprovalCoordinator.permission,
            schema: BuriApprovalCoordinator.schema,
          ),
          ...store.restoreFamily(
            family: BuriProvisioningCoordinator.family,
            permission: BuriProvisioningCoordinator.permission,
            schema: BuriProvisioningCoordinator.schema,
          ),
        ];
        for (final entry in retained) {
          final group = entry.intent['collectionId'];
          if (choices.any((choice) => choice.id == group)) {
            _collectionId = group as String;
            break;
          }
        }
      }
      if (_collectionId == null && choices.length == 1) {
        _collectionId = choices.single.id;
      }
      if (_collectionId == null || !choices.any((s) => s.id == _collectionId)) {
        return;
      }
    }
    final directory = await api.loadBuriDirectory(collectionId: _collectionId);
    BuriProvisioningDirectory? provisioning;
    String? provisioningError;
    if (api is AdminBuriMunsiProvisioningApi) {
      try {
        provisioning = await (api).loadBuriProvisioning(
          collectionId: directory.collectionId,
        );
        if (provisioning.collectionId != directory.collectionId) {
          throw const FormatException(
            'The native setup group changed. Refresh this workspace.',
          );
        }
      } catch (_) {
        provisioningError =
            'Native setup is temporarily unavailable. Refresh or contact the service administrator.';
      }
    }
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
    final provisioner =
        provisioning != null && api is AdminBuriMunsiProvisioningApi
        ? BuriProvisioningCoordinator(
            api: api,
            store: ref.read(adminPendingAttemptStoreProvider),
            collectionId: directory.collectionId,
          )
        : null;
    final selectedId = _selected?.principalId;
    setState(() {
      _directory = directory;
      _loadedFence = fence;
      _coordinator = coordinator;
      _provisioning = provisioning;
      _provisioner = provisioner;
      _provisioningError = provisioningError;
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
    _pin.clear();
    _pinConfirm.clear();
    _installation.clear();
    _profile = 'staff';
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
    final nativePending = directory == null
        ? const <BuriProvisioningIntent>[]
        : _provisioner?.pending ?? const <BuriProvisioningIntent>[];
    final editable =
        !_busy &&
        directory?.configured == true &&
        pending.isEmpty &&
        nativePending.isEmpty &&
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
      subtitle: 'Manage staff and native app access.',
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
            if (api is AdminBuriMunsiScopeApi) ...[
              DropdownButtonFormField<String>(
                key: ValueKey('buri-scope-$_collectionId:${_scopes.length}'),
                initialValue: _scopes.any((s) => s.id == _collectionId)
                    ? _collectionId
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'BuriMunsi group'),
                items: [
                  for (final scope in _scopes)
                    DropdownMenuItem(value: scope.id, child: Text(scope.title)),
                ],
                onChanged:
                    _busy || pending.isNotEmpty || nativePending.isNotEmpty
                    ? null
                    : (value) {
                        setState(() => _collectionId = value);
                        _load();
                      },
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          await showMomoGatewaySetup(
                            context,
                            collectionId: _collectionId,
                          );
                          if (mounted) _load();
                        },
                  icon: const Icon(Icons.phonelink_setup_outlined, size: 28),
                  label: const Text('Receiving phone setup'),
                ),
              ),
              if (_scopes.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Prepare an existing Collect group in receiving phone setup before approving native access.',
                  ),
                ),
              const SizedBox(height: 20),
            ],
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
            for (final intent in nativePending) _nativePending(intent),
            if (_provisioningError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_provisioningError!),
              ),
            if (directory != null && !directory.configured)
              const Text(
                'The BuriMunsi group and receiving account need to be configured before approving access.',
              ),
            if (directory?.configured == true && nativePending.isEmpty)
              LayoutBuilder(
                builder: (context, constraints) {
                  final people = _people(directory!, editable);
                  final form = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _editor(editable),
                      if (_provisioning != null) ...[
                        const SizedBox(height: 20),
                        _nativeSetup(editable),
                      ],
                    ],
                  );
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

  BuriNativeAccount? get _nativeAccount => _provisioning?.accounts
      .where((a) => a.principalId == _selected?.principalId)
      .firstOrNull;
  BuriNativeGrant? get _nativeGrant => _provisioning?.grants
      .where((g) => g.installationId == _installation.text.trim())
      .firstOrNull;

  Future<void> _setPin() async {
    final account = _nativeAccount,
        directory = _provisioning,
        coordinator = _provisioner;
    if (account == null ||
        directory?.scopeVersion == null ||
        coordinator == null ||
        !coordinator.current) {
      return;
    }
    _pin.clear();
    _pinConfirm.clear();
    final form = GlobalKey<FormState>();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          account.accountId == null ? 'Set native PIN' : 'Reset native PIN',
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${account.name}\n${account.phone}'),
                const SizedBox(height: 16),
                const Text(
                  'Existing native sign-ins for this account will end. Deliver the PIN privately to this approved teammate.',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('buri-native-pin'),
                  controller: _pin,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Four-digit PIN',
                  ),
                  validator: (v) => RegExp(r'^\d{4}$').hasMatch(v ?? '')
                      ? null
                      : 'Enter four digits.',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('buri-native-pin-confirm'),
                  controller: _pinConfirm,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: const InputDecoration(labelText: 'Confirm PIN'),
                  validator: (v) => v == _pin.text && v?.length == 4
                      ? null
                      : 'The PINs must match.',
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
              if (form.currentState?.validate() == true) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Set PIN'),
          ),
        ],
      ),
    );
    final pin = accepted == true ? _pin.text : null;
    _pin.clear();
    _pinConfirm.clear();
    if (pin == null || !mounted || !coordinator.current) return;
    await _run(() async {
      await coordinator.submit(
        BuriProvisioningIntent(
          collectionId: directory!.collectionId,
          principalId: account.principalId,
          scopeVersion: directory.scopeVersion!,
          approvalVersion: account.approvalVersion,
          expectedAccountVersion: account.version,
          accountId: account.accountId,
          operation: 'set_pin',
          reason: 'Owner approved native PIN setup',
        ),
        pin: pin,
      );
      await _read();
      if (mounted) {
        setState(
          () => _status = 'Native PIN set. Previous native sign-ins ended.',
        );
      }
    });
  }

  Future<void> _grantInstallation({bool revoke = false}) async {
    final account = _nativeAccount,
        directory = _provisioning,
        coordinator = _provisioner,
        grant = _nativeGrant;
    if (account?.accountId == null ||
        directory?.scopeVersion == null ||
        coordinator == null ||
        !coordinator.current) {
      return;
    }
    await _run(() async {
      if (grant != null &&
          (grant.accountId != account!.accountId ||
              grant.profile != _profile)) {
        throw const AdminAccountException(
          'This installation already belongs to a different custodian or app profile.',
        );
      }
      final intent = BuriProvisioningIntent(
        collectionId: directory!.collectionId,
        principalId: account!.principalId,
        scopeVersion: directory.scopeVersion!,
        approvalVersion: account.approvalVersion,
        expectedAccountVersion: account.version,
        accountId: account.accountId,
        operation: revoke ? 'revoke_installation' : 'grant_installation',
        installationId: _installation.text.trim(),
        profile: _profile,
        grantId: grant?.id,
        expectedGrantVersion: grant?.version ?? 0,
        reason: revoke
            ? 'Owner revoked native installation'
            : 'Owner approved managed installation',
      );
      // Confirmation is waiting for the owner, not an active server request.
      if (mounted) setState(() => _busy = false);
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            revoke
                ? 'Revoke native access?'
                : grant == null
                ? 'Grant native access?'
                : 'Rotate native grant?',
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(account.name),
                const SizedBox(height: 8),
                SelectableText(intent.installationId!),
                Text(_profile == 'staff' ? 'Staff' : 'Receiving phone'),
                const SizedBox(height: 16),
                Text(
                  revoke
                      ? 'This installation’s native sign-ins will end.'
                      : 'Deliver the new token through approved device management. Existing native sign-ins for this grant will end.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Wallet/SIM pairing and captured payment evidence are managed separately.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(revoke ? 'Revoke access' : 'Confirm grant'),
            ),
          ],
        ),
      );
      if (accepted != true || !coordinator.current) return;
      if (mounted) setState(() => _busy = true);
      await coordinator.submit(intent);
      // Keep the original grant checkpoint until its protected delivery is closed.
      if (revoke) await _read();
      if (mounted) {
        setState(
          () => _status = revoke
              ? 'Native installation access revoked.'
              : 'Native grant confirmed. Open its protected delivery.',
        );
      }
    });
  }

  Widget _nativeSetup(bool editable) {
    final account = _nativeAccount,
        directory = _provisioning,
        grant = _nativeGrant;
    if (account == null || directory == null) return const SizedBox.shrink();
    final ready =
        editable &&
        directory.configured &&
        account.approved &&
        !account.removed;
    final canGrant = ready && account.accountId != null && account.active;
    return _surface(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Native app setup',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Text(
            account.accountId == null
                ? 'PIN not issued'
                : 'Native account · version ${account.version}',
          ),
          if (!directory.scopeEnabled)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Native operations remain disabled for this group.'),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('buri-set-native-pin'),
            onPressed: ready ? _setPin : null,
            icon: const Icon(Icons.pin_outlined, size: 28),
            label: Text(
              account.accountId == null ? 'Set native PIN' : 'Reset native PIN',
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            key: const Key('buri-installation-id'),
            controller: _installation,
            enabled: editable,
            onChanged: (_) => setState(() {}),
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Installation ID',
              helperText: 'Copy the exact ID from the installed native app.',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('buri-native-profile-$_profile'),
            initialValue: _profile,
            decoration: const InputDecoration(labelText: 'Native app profile'),
            items: [
              const DropdownMenuItem(value: 'staff', child: Text('Staff')),
              if (account.role == 'admin')
                const DropdownMenuItem(
                  value: 'internal_receiver',
                  child: Text('Receiving phone'),
                ),
            ],
            onChanged: editable
                ? (value) => setState(() => _profile = value!)
                : null,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('buri-grant-installation'),
            onPressed: canGrant ? _grantInstallation : null,
            icon: const Icon(Icons.phonelink_lock_outlined, size: 28),
            label: Text(
              grant == null ? 'Grant installation' : 'Rotate native grant',
            ),
          ),
          if (grant?.active == true)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                onPressed: editable && grant?.accountId == account.accountId
                    ? () => _grantInstallation(revoke: true)
                    : null,
                icon: const Icon(Icons.phonelink_erase_outlined, size: 28),
                label: const Text('Revoke native grant'),
              ),
            ),
          const SizedBox(height: 12),
          const Text('Wallet/SIM pairing stays separate.'),
        ],
      ),
    );
  }

  Widget _nativePending(BuriProvisioningIntent intent) {
    final coordinator = _provisioner;
    final receipt = coordinator?.receipt(intent);
    final confirmedGrant = receipt?['operation'] == 'grant_installation';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: _surface(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              confirmedGrant
                  ? 'Native grant delivery'
                  : 'Native setup needs confirmation',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SelectableText(intent.requestId),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          final found = await coordinator!.check(intent);
                          if (!mounted) return;
                          if (found && coordinator.pending.isEmpty) {
                            await _read();
                          }
                          if (mounted) {
                            setState(
                              () => _status = found
                                  ? 'The original native request is confirmed.'
                                  : 'No receipt found. Cancel the original request before starting again.',
                            );
                          }
                        }),
                  icon: const Icon(Icons.manage_search),
                  label: const Text('Check original request'),
                ),
                if (!confirmedGrant)
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await coordinator!.cancel(intent);
                            if (coordinator.pending.isEmpty) await _read();
                            if (mounted) {
                              setState(
                                () => _status =
                                    'The original request is settled. Check the current account before continuing.',
                              );
                            }
                          }),
                    child: const Text('Cancel if not applied'),
                  ),
                if (confirmedGrant) ...[
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            final delivery = await coordinator!.delivery(
                              intent,
                            );
                            if (!mounted || !coordinator.current) return;
                            setState(() => _busy = false);
                            await showDialog<void>(
                              context: context,
                              builder: (_) => _NativeDeliveryDialog(
                                delivery: delivery,
                                intent: intent,
                                current: () => coordinator.current,
                              ),
                            );
                          }),
                    icon: const Icon(Icons.lock_outline, size: 28),
                    label: const Text('Open protected delivery'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            coordinator!.closeDelivery(intent);
                            await _read();
                          }),
                    child: const Text('Close delivery'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NativeDeliveryDialog extends StatefulWidget {
  const _NativeDeliveryDialog({
    required this.delivery,
    required this.intent,
    required this.current,
  });
  final BuriNativeDelivery delivery;
  final BuriProvisioningIntent intent;
  final bool Function() current;
  @override
  State<_NativeDeliveryDialog> createState() => _NativeDeliveryDialogState();
}

class _NativeDeliveryDialogState extends State<_NativeDeliveryDialog>
    with WidgetsBindingObserver {
  late final TextEditingController _secret;
  late final Timer _guard;
  bool _revealed = false, _closed = false;
  @override
  void initState() {
    super.initState();
    _secret = _ProtectedNativeTextController(
      text: widget.delivery.installationToken,
    );
    WidgetsBinding.instance.addObserver(this);
    _guard = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!widget.current() ||
          !widget.delivery.expiresAt.isAfter(DateTime.now())) {
        _close();
      }
    });
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    _secret.clear();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _close();
  }

  @override
  void dispose() {
    _guard.cancel();
    _secret.clear();
    _secret.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Protected installation delivery'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Use approved device management for this exact installation. This token is not a login PIN or wallet pairing credential.',
            ),
            const SizedBox(height: 16),
            SelectableText(widget.intent.installationId!),
            Text(widget.intent.profile!),
            const SizedBox(height: 16),
            TextField(
              controller: _secret,
              readOnly: true,
              obscureText: !_revealed,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Installation token',
                suffixIcon: IconButton(
                  tooltip: _revealed
                      ? 'Hide installation token'
                      : 'Reveal installation token',
                  onPressed: () {
                    if (widget.current()) {
                      setState(() => _revealed = !_revealed);
                    } else {
                      _close();
                    }
                  },
                  icon: Icon(
                    _revealed
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Delivery expires after 15 minutes or when its account, approval, scope or grant changes.',
            ),
          ],
        ),
      ),
    ),
    actions: [TextButton(onPressed: _close, child: const Text('Close'))],
  );
}

class _ProtectedNativeTextController extends TextEditingController {
  _ProtectedNativeTextController({super.text});
  @override
  String toString() => 'ProtectedNativeTextController(redacted)';
}
