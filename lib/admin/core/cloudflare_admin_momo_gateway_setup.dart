part of 'cloudflare_admin_momo_page.dart';

const _gatewaySchema = AdminPendingAttemptSchema(
  fields: {
    'provider',
    'public_code',
    'recipient_name',
    'receiving_account_id',
    'subscription_id',
    'reason',
  },
);

class _GatewaySetupDialog extends ConsumerStatefulWidget {
  const _GatewaySetupDialog();
  @override
  ConsumerState<_GatewaySetupDialog> createState() => _GatewaySetupState();
}

class _GatewaySetupState extends ConsumerState<_GatewaySetupDialog> {
  final _code = TextEditingController(),
      _name = TextEditingController(),
      _reason = TextEditingController(),
      _subscription = TextEditingController();
  late final Object _openingFence = ref
      .read(cloudflareAdminSessionProvider.notifier)
      .authorityFence;
  String _provider = 'mtn_momo', _kind = 'account';
  String? _account, _pairingCode, _errorValue;
  List<Map<String, dynamic>> _accounts = [];
  AdminPendingAttemptCheckpoint? _pending;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _openingFence;
    final store = ref.read(adminPendingAttemptStoreProvider);
    for (final kind in ['account', 'pair']) {
      final pending = store.restore(
        family: 'momo-gateway-$kind',
        resourceId: 'gateway',
        schema: _gatewaySchema,
      );
      if (pending != null) {
        _kind = kind;
        _pending = pending;
        break;
      }
    }
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _reason.dispose();
    _subscription.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await ref
          .read(momoAdminApiProvider)
          .read('accounts', 'receivers.read');
      if (data['rows'] is! List) _invalid();
      final rows = [for (final value in data['rows'] as List) _map(value)];
      for (final row in rows) {
        _identifier(row['id']);
        _text(row['recipient_name']);
        _text(row['public_code']);
      }

      if (mounted) setState(() => _accounts = rows);
    } catch (error) {
      if (mounted) setState(() => _errorValue = _error(error));
    }
  }

  Future<void> _save(String kind) async {
    setState(() {
      _busy = true;
      _errorValue = null;
    });
    try {
      final api = ref.read(momoAdminApiProvider);
      if (_openingFence != api.fence) {
        throw const AdminAccountException(
          'Reopen this view with the current authorized account.',
        );
      }
      api.require('receivers.manage', fresh: true);
      final authorizedUser = api.session.user;
      final store = ref.read(adminPendingAttemptStoreProvider);
      if (_pending == null && !store.storageAvailable) {
        // A failed initial load may hide another unresolved family. Do not
        // overwrite that durable journal with a new in-memory-only claim.
        throw const AdminAccountException(
          'Recovery storage is unavailable. Restore it and reopen this view before starting a request.',
        );
      }
      final body =
          _pending?.intent ??
          (kind == 'account'
              ? {
                  'provider': _provider,
                  'public_code': _code.text.trim(),
                  'recipient_name': _name.text.trim(),
                  'reason': _reason.text.trim(),
                }
              : {
                  'receiving_account_id': _account,
                  'subscription_id': _subscription.text.trim().isEmpty
                      ? null
                      : int.parse(_subscription.text.trim()),
                  'reason': _reason.text.trim(),
                });
      _kind = kind;
      _pending = store.retain(
        family: 'momo-gateway-$kind',
        resourceId: 'gateway',
        requestKey: _pending?.requestKey ?? const Uuid().v4(),
        permission: 'receivers.manage',
        intent: body,
        schema: _gatewaySchema,
      );
      if (!store.storageAvailable) {
        // The shared store intentionally keeps its warning sticky. Verify a
        // retry with its canonical decoder rather than resetting that warning
        // or sending an in-memory-only request after a failed durable save.
        final proof = AdminPendingAttemptStore(storage: store.storage);
        try {
          proof.bind(authorizedUser);
          final retained = proof.restore(
            family: 'momo-gateway-$kind',
            resourceId: 'gateway',
            schema: _gatewaySchema,
          );
          if (!proof.storageAvailable ||
              retained == null ||
              retained.permission != 'receivers.manage' ||
              retained.family != 'momo-gateway-$kind' ||
              retained.resourceId != 'gateway' ||
              retained.requestKey != _pending!.requestKey ||
              jsonEncode(retained.intent) != jsonEncode(_pending!.intent)) {
            throw const AdminAccountException(
              'Recovery storage is unavailable. Keep this view open and retry the original request.',
            );
          }
        } finally {
          proof.dispose();
        }
      }
      api.require('receivers.manage', fresh: true);
      final result = await api.session.request(
        kind == 'account' ? 'momo/accounts' : 'momo/bindings',
        authenticated: true,
        body: _pending!.intent,
        idempotencyKey: _pending!.requestKey,
      );
      api.require('receivers.manage');
      if (kind == 'account') {
        _identifier(result['id']);
        if (result['profile_status'] != 'unverified') {
          _invalid();
        }
      } else {
        _identifier(result['binding_id']);
        if (result['pairing_code'] is! String ||
            (result['pairing_code'] as String).length < 16 ||
            result['expires_in_seconds'] != 600) {
          _invalid();
        }
      }
      store.clear(family: 'momo-gateway-$kind', resourceId: 'gateway');
      if (mounted) {
        setState(() {
          _pending = null;
          if (kind == 'account') {
            _account = result['id'] as String;
          } else {
            _pairingCode = result['pairing_code'] as String;
          }
        });
      }
      if (kind == 'account') {
        await _load();
      }
    } catch (error) {
      if (error is CloudflareAdminRequestException &&
          !error.outcomeUnknown &&
          error.statusCode != null) {
        ref
            .read(adminPendingAttemptStoreProvider)
            .clear(family: 'momo-gateway-$kind', resourceId: 'gateway');
        _pending = null;
      }
      if (mounted) {
        setState(() => _errorValue = _error(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => _Scope(
    fence: _openingFence,
    child: AlertDialog(
      title: const Text('Gateway setup'),
      content: SizedBox(
        width: 650,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Pair the dedicated receiving phone with its actual MoMo account. Ordinary members do not need SMS access.',
              ),
              const _Note(
                'Automatic extraction requires a provider source profile reviewed against real messages. No sample profile is enabled by this setup.',
              ),
              if (_pending != null) ...[
                SelectableText(
                  'Unresolved original request ${_pending!.requestKey}\n${_pending!.intent}',
                ),
                FilledButton(
                  onPressed: _busy ? null : () => _save(_kind),
                  child: const Text('Retry original request'),
                ),
              ] else ...[
                ExpansionTile(
                  title: const Text('Add receiving account'),
                  children: [
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _provider,
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
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _provider = value!),
                    ),
                    TextField(
                      controller: _code,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Actual MoMo number or payment code',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    TextField(
                      controller: _name,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Recipient name shown by MoMo',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    TextButton(
                      onPressed:
                          _busy ||
                              _code.text.trim().isEmpty ||
                              _name.text.trim().isEmpty ||
                              _reason.text.trim().length < 8
                          ? null
                          : () => _save('account'),
                      child: const Text('Create receiving account'),
                    ),
                  ],
                ),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _account,
                  key: ValueKey(
                    'gateway-account-$_account:${_accounts.length}',
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Receiving account',
                  ),
                  items: [
                    for (final row in _accounts)
                      DropdownMenuItem(
                        value: row['id'] as String,
                        child: Text(
                          '${row['recipient_name']} · ${row['public_code']} · ${row['profile_status']}',
                        ),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _account = value),
                ),
                TextField(
                  controller: _subscription,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Receiving SIM subscription ID (optional)',
                    helperText:
                        'Use the Android subscription ID; this is not the phone number.',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                TextField(
                  controller: _reason,
                  enabled: !_busy,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Account ownership and pairing reason',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                FilledButton(
                  onPressed:
                      _busy ||
                          _account == null ||
                          _reason.text.trim().length < 8 ||
                          (_subscription.text.trim().isNotEmpty &&
                              int.tryParse(_subscription.text.trim()) == null)
                      ? null
                      : () => _save('pair'),
                  child: const Text('Create phone pairing code'),
                ),
              ],
              if (_pairingCode != null) ...[
                const _Note(
                  'Single-use pairing code · expires in 10 minutes. Enter it only on the dedicated receiving phone.',
                ),
                SelectableText(_pairingCode!),
                TextButton.icon(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: _pairingCode!)),
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copy pairing code'),
                ),
              ],
              if (_errorValue != null) _Note(_errorValue!, error: true),
              if (_busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
