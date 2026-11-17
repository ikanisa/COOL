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
const _nativeGatewaySchema = AdminPendingAttemptSchema(
  fields: {
    'operation',
    'requestId',
    'collectionId',
    'expectedScopeVersion',
    'receivingAccountId',
    'reason',
    'installationId',
    'grantId',
    'custodianAccountId',
    'expectedGrantVersion',
    'subscriptionId',
    'expectedBindingId',
    'expectedBindingVersion',
    'expectedReceiverKeyId',
    'handoffId',
  },
);

class _GatewaySetupDialog extends ConsumerStatefulWidget {
  const _GatewaySetupDialog({this.initialCollectionId});
  final String? initialCollectionId;
  @override
  ConsumerState<_GatewaySetupDialog> createState() => _GatewaySetupState();
}

class _GatewaySetupState extends ConsumerState<_GatewaySetupDialog>
    with WidgetsBindingObserver {
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
  String? _collection, _grant;
  List<Map<String, dynamic>> _groups = [], _scopes = [], _devices = [];
  AdminPendingAttemptCheckpoint? _nativePending;
  Map<String, dynamic>? _nativeReceipt;
  bool _nativeAbsent = false;
  bool _lostOldPhone = false;
  int _disclosureEpoch = 0;
  bool _foreground = false;
  bool _currentDisclosure(int epoch) =>
      mounted && _foreground && epoch == _disclosureEpoch;
  Map<String, dynamic>? get _scope =>
      _scopes.where((s) => s['collectionId'] == _collection).firstOrNull;
  String _deviceKey(Map<String, dynamic> device) =>
      '${device['grantId']}:${device['custodianAccountId']}';
  Map<String, dynamic>? get _device =>
      _devices.where((d) => _deviceKey(d) == _grant).firstOrNull;
  Map<String, dynamic>? get _replacement => _scope?['pendingReplacement'] is Map
      ? _map(_scope!['pendingReplacement'])
      : null;
  String? _codePhase;
  String _route(String value) => value.startsWith('07') && value.length == 10
      ? '250${value.substring(1)}'
      : value.replaceFirst(RegExp(r'^\+'), '');
  List<Map<String, dynamic>> get _choices {
    if (_collection == null) return _accounts;
    final group = _groups.where((g) => g['id'] == _collection).firstOrNull;
    if (group == null) return [];
    return _accounts
        .where(
          (a) =>
              a['provider'] == group['receiverNetwork'] &&
              _route('${a['public_code']}') ==
                  _route('${group['receiverNumber'] ?? ''}'),
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _collection = widget.initialCollectionId;
    _openingFence;
    final store = ref.read(adminPendingAttemptStoreProvider);
    _nativePending = store.restore(
      family: 'momo-native-setup',
      resourceId: 'gateway',
      schema: _nativeGatewaySchema,
    );
    if (_nativePending != null) {
      _collection = _nativePending!.intent['collectionId'] as String;
    }
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
    WidgetsBinding.instance.removeObserver(this);
    _disclosureEpoch++;
    _foreground = false;
    _pairingCode = null;
    _code.dispose();
    _name.dispose();
    _reason.dispose();
    _subscription.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _disclosureEpoch++;
      if (mounted)
        setState(() {
          _pairingCode = null;
          _codePhase = null;
        });
    }
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
      final api = ref.read(momoAdminApiProvider);
      final owner = api.session.user;
      if (owner?.isCurrentOwner == true &&
          owner!.permissions.contains('admin_users.manage')) {
        final setup = await api.session.request(
          'momo/native-setup${_collection == null ? '' : '?${Uri(queryParameters: {'collectionId': _collection!}).query}'}',
          authenticated: true,
          method: 'GET',
          responseCurrent: () => api.fence == _openingFence,
        );
        if (setup['contractVersion'] != 1 ||
            [
              'collections',
              'scopes',
              'installations',
            ].any((k) => setup[k] is! List)) {
          _invalid();
        }
        final groups = [for (final r in setup['collections'] as List) _map(r)];
        final scopes = [for (final r in setup['scopes'] as List) _map(r)];
        final devices = [
          for (final r in setup['installations'] as List) _map(r),
        ];
        for (final device in devices) {
          _identifier(device['grantId']);
          _identifier(device['installationId']);
          _identifier(device['custodianAccountId']);
          _text(device['custodianName']);
          exactJsonInteger(
            device['grantVersion'],
            field: 'Grant version',
            minimum: 1,
          );
          if (device['custodyAssigned'] is! bool) _invalid();
        }
        if (devices.map(_deviceKey).toSet().length != devices.length)
          _invalid();
        for (final scope in scopes) {
          _text(scope['collectionId']);
          _identifier(scope['receivingAccountId']);
          exactJsonInteger(
            scope['version'],
            field: 'Scope version',
            minimum: 1,
          );
          if (scope['enabled'] is! bool || scope['paired'] is! bool) _invalid();
          if (scope['pendingReplacement'] != null) {
            final pending = _map(scope['pendingReplacement']);
            for (final field in [
              'handoffId',
              'targetInstallationId',
              'targetGrantId',
              'targetCustodianAccountId',
              'expectedBindingId',
              'expectedReceiverKeyId',
            ])
              _identifier(pending[field]);
            for (final field in [
              'targetGrantVersion',
              'expectedScopeVersion',
              'expectedBindingVersion',
              'expiresAt',
            ])
              exactJsonInteger(pending[field], field: field, minimum: 1);
            exactJsonInteger(
              pending['subscriptionId'],
              field: 'Replacement SIM subscription',
              minimum: 0,
              maximum: 2147483646,
            );
            if (!const {'prepared', 'retired'}.contains(pending['phase']) ||
                scope['version'] !=
                    (pending['expectedScopeVersion'] as int) +
                        (pending['phase'] == 'retired' ? 1 : 0))
              _invalid();
          }
        }
        if (mounted) {
          setState(() {
            _groups = groups;
            _scopes = scopes;
            _devices = devices;
            if (!_devices.any((d) => _deviceKey(d) == _grant)) {
              _grant = _devices.length == 1
                  ? _deviceKey(_devices.single)
                  : null;
            }
            final saved = _scope?['receivingAccountId'];
            if (_collection != null &&
                !_choices.any((a) => a['id'] == _account)) {
              _account = _choices.any((a) => a['id'] == saved)
                  ? saved as String
                  : null;
            }
          });
        }
      }
    } catch (error) {
      if (mounted) setState(() => _errorValue = _error(error));
    }
  }

  Future<Map<String, dynamic>> _nativeRequest(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    String? key,
  }) async {
    final api = ref.read(momoAdminApiProvider);
    if (api.fence != _openingFence) {
      throw const AdminAccountException(
        'Reopen setup with the current authorized account.',
      );
    }
    api.require('receivers.manage', fresh: true);
    final value = await api.session.request(
      'momo/native-setup$path',
      authenticated: true,
      method: method,
      body: body,
      idempotencyKey: key,
      responseCurrent: () => api.fence == _openingFence,
    );
    api.require('receivers.manage', fresh: true);
    return value;
  }

  Future<void> _nativeRun(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _errorValue = null;
      _pairingCode = null;
      _codePhase = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _errorValue = _error(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _nativeResult(Map<String, dynamic> value) async {
    final intent = _nativePending!.intent;
    if (value['contractVersion'] == 1 &&
        value['requestId'] == _nativePending!.requestKey &&
        value['collectionId'] == intent['collectionId'] &&
        value['operation'] == 'cancelled' &&
        value['applied'] == false) {
      ref
          .read(adminPendingAttemptStoreProvider)
          .clear(family: 'momo-native-setup', resourceId: 'gateway');
      if (mounted) {
        setState(() {
          _nativePending = null;
          _nativeReceipt = null;
          _nativeAbsent = false;
        });
      }
      return;
    }
    _verifyNativeReceipt(value, intent);
    if (intent['operation'] == 'prepare') {
      ref
          .read(adminPendingAttemptStoreProvider)
          .clear(family: 'momo-native-setup', resourceId: 'gateway');
      if (mounted) {
        setState(() {
          _nativePending = null;
          _nativeReceipt = null;
        });
      }
      await _load();
    } else if (mounted) {
      setState(() => _nativeReceipt = value);
      await _load();
    }
  }

  void _verifyNativeReceipt(
    Map<String, dynamic> value,
    Map<String, dynamic> intent,
  ) {
    final operation = intent['operation'];
    const base = {
      'contractVersion',
      'requestId',
      'collectionId',
      'operation',
      'receivingAccountId',
      'scopeVersion',
      'enabled',
      'bindingId',
    };
    const target = {
      'pairingId',
      'bindingVersion',
      'installationId',
      'custodianAccountId',
      'grantId',
      'grantVersion',
      'subscriptionId',
      'deliveryExpiresAt',
    };
    final expected = <String>{
      ...base,
      if (operation == 'activate' || operation == 'prepare_replacement')
        ...target,
      if (operation == 'prepare_replacement') ...{
        'handoffId',
        'expectedBindingId',
        'expectedBindingVersion',
        'expectedReceiverKeyId',
        'retirementRequired',
      },
      if (operation == 'finalize_replacement') ...{
        'handoffId',
        'bindingVersion',
        'retirementMethod',
        'reauthenticationRequired',
      },
    };
    if (!const {
          'prepare',
          'activate',
          'prepare_replacement',
          'finalize_replacement',
        }.contains(operation) ||
        value.keys.toSet().difference(expected).isNotEmpty ||
        value.length != expected.length ||
        value['contractVersion'] != 1 ||
        value['requestId'] != intent['requestId'] ||
        value['collectionId'] != intent['collectionId'] ||
        value['receivingAccountId'] != intent['receivingAccountId'] ||
        value['operation'] != operation ||
        value['scopeVersion'] !=
            (intent['expectedScopeVersion'] as int) +
                (operation == 'prepare_replacement' ? 0 : 1) ||
        value['enabled'] != (operation != 'prepare'))
      _invalid();
    _identifier(value['requestId']);
    _identifier(value['receivingAccountId']);
    exactJsonInteger(value['scopeVersion'], field: 'Scope version', minimum: 1);
    if (operation == 'prepare') {
      if (value['bindingId'] != null) _identifier(value['bindingId']);
      return;
    }
    _identifier(value['bindingId']);
    if (exactJsonInteger(
          value['bindingVersion'],
          field: 'Binding version',
          minimum: 1,
        ) !=
        1)
      _invalid();
    if (operation == 'finalize_replacement') {
      if (value['handoffId'] != intent['handoffId'] ||
          value['retirementMethod'] != 'owner_lost' ||
          value['reauthenticationRequired'] != true)
        _invalid();
      _identifier(value['handoffId']);
      return;
    }
    _identifier(value['pairingId']);
    for (final field in [
      'installationId',
      'custodianAccountId',
      'grantId',
      'subscriptionId',
    ]) {
      if (value[field] != intent[field]) _invalid();
    }
    if (exactJsonInteger(
          value['grantVersion'],
          field: 'Grant version',
          minimum: 1,
        ) !=
        intent['expectedGrantVersion'])
      _invalid();
    for (final field in ['installationId', 'custodianAccountId', 'grantId'])
      _identifier(value[field]);
    exactJsonInteger(
      value['subscriptionId'],
      field: 'SIM subscription',
      minimum: 0,
      maximum: 2147483646,
    );
    exactJsonInteger(
      value['deliveryExpiresAt'],
      field: 'Pairing expiry',
      minimum: 1,
    );
    if (operation == 'prepare_replacement') {
      if (value['handoffId'] != intent['requestId'] ||
          value['retirementRequired'] != true ||
          value['bindingId'] == intent['expectedBindingId'])
        _invalid();
      for (final field in [
        'expectedBindingId',
        'expectedBindingVersion',
        'expectedReceiverKeyId',
      ]) {
        if (value[field] != intent[field]) _invalid();
      }
      exactJsonInteger(
        value['expectedBindingVersion'],
        field: 'Previous binding version',
        minimum: 1,
      );
    }
  }

  Future<void> _nativeSend(String operation) => _nativeRun(() async {
    final store = ref.read(adminPendingAttemptStoreProvider);
    if (_nativePending == null) {
      if (!store.storageAvailable) {
        throw const AdminAccountException(
          'Recovery storage is unavailable. Reopen setup before starting a request.',
        );
      }
      final request = const Uuid().v4(), device = _device;
      final body = <String, dynamic>{
        'operation': operation,
        'requestId': request,
        'collectionId': _collection,
        'expectedScopeVersion': _scope?['version'] ?? 0,
        'receivingAccountId': operation == 'finalize_replacement'
            ? (_scope?['receivingAccountId'])
            : _account,
        'reason': _reason.text.trim(),
        if (operation == 'activate' || operation == 'prepare_replacement') ...{
          'installationId': device?['installationId'],
          'grantId': device?['grantId'],
          'custodianAccountId': device?['custodianAccountId'],
          'expectedGrantVersion': device?['grantVersion'],
          'subscriptionId': int.tryParse(_subscription.text.trim()),
        },
        if (operation == 'prepare_replacement') ...{
          'expectedBindingId': _scope?['bindingId'],
          'expectedBindingVersion': _scope?['bindingVersion'],
          'expectedReceiverKeyId': _scope?['receiverKeyId'],
        },
        if (operation == 'finalize_replacement')
          'handoffId': _replacement?['handoffId'],
      };
      _nativePending = store.retain(
        family: 'momo-native-setup',
        resourceId: 'gateway',
        requestKey: request,
        permission: 'receivers.manage',
        intent: body,
        schema: _nativeGatewaySchema,
      );
      if (!store.storageAvailable) {
        throw const AdminAccountException(
          'The request was not saved. Keep setup open and restore recovery storage.',
        );
      }
    }
    final result = await _nativeRequest(
      '',
      method: 'POST',
      body: _nativePending!.intent,
      key: _nativePending!.requestKey,
    );
    await _nativeResult(result);
  });
  Future<void> _nativeCheck() => _nativeRun(() async {
    final p = _nativePending!,
        query = Uri(
          queryParameters: {'collectionId': p.intent['collectionId'] as String},
        ).query;
    final result = await _nativeRequest('/requests/${p.requestKey}?$query');
    if (result['contractVersion'] != 1 ||
        result['requestId'] != p.requestKey ||
        result['collectionId'] != p.intent['collectionId'] ||
        result['found'] is! bool) {
      _invalid();
    }
    if (result['found'] == true) {
      await _nativeResult(_map(result['receipt']));
    } else if (mounted) {
      setState(() => _nativeAbsent = true);
    }
  });
  Future<Map<String, dynamic>> _preparedReplacement(
    String handoff,
    String collection,
  ) async {
    final target = _replacement;
    if (target == null || target['handoffId'] != handoff) _invalid();
    final query = Uri(queryParameters: {'collectionId': collection}).query;
    final lookup = await _nativeRequest('/requests/$handoff?$query');
    if (lookup['contractVersion'] != 1 ||
        lookup['collectionId'] != collection ||
        lookup['requestId'] != handoff ||
        lookup['found'] != true)
      _invalid();
    final receipt = _map(lookup['receipt']);
    _verifyNativeReceipt(receipt, {
      'operation': 'prepare_replacement',
      'requestId': handoff,
      'collectionId': collection,
      'receivingAccountId': _scope?['receivingAccountId'],
      'expectedScopeVersion': target['expectedScopeVersion'],
      'installationId': target['targetInstallationId'],
      'grantId': target['targetGrantId'],
      'custodianAccountId': target['targetCustodianAccountId'],
      'expectedGrantVersion': target['targetGrantVersion'],
      'subscriptionId': target['subscriptionId'],
      'expectedBindingId': target['expectedBindingId'],
      'expectedBindingVersion': target['expectedBindingVersion'],
      'expectedReceiverKeyId': target['expectedReceiverKeyId'],
    });
    if (receipt['deliveryExpiresAt'] != target['expiresAt']) _invalid();
    return receipt;
  }

  Future<void> _nativeReveal() {
    final disclosureEpoch = ++_disclosureEpoch;
    return _nativeRun(() async {
      if (!_currentDisclosure(disclosureEpoch)) return;
      final p = _nativePending;
      final collection = p?.intent['collectionId'] ?? _collection;
      if (collection is! String) _invalid();
      final operation = _nativeReceipt?['operation'];
      final replacement =
          operation == 'prepare_replacement' ||
          operation == 'finalize_replacement' ||
          (p == null && _replacement != null);
      final handoff =
          _nativeReceipt?['handoffId'] ?? _replacement?['handoffId'];
      final receipt = replacement
          ? await _preparedReplacement(_identifier(handoff), collection)
          : _nativeReceipt ?? _invalid();
      final deliveryRequest = replacement
          ? handoff as String
          : p?.requestKey ?? _invalid();
      if (!_currentDisclosure(disclosureEpoch)) return;
      final result = await _nativeRequest(
        '/requests/$deliveryRequest/delivery',
        method: 'POST',
        body: {'collectionId': collection},
      );
      if (!_currentDisclosure(disclosureEpoch)) return;
      const deliveryFields = {
        'contractVersion',
        'collectionId',
        'requestId',
        'bindingId',
        'installationId',
        'subscriptionId',
        'pairingCode',
        'expiresAt',
      };
      final expectedFields = <String>{
        ...deliveryFields,
        if (replacement) ...{'handoffId', 'retirementRequired', 'phase'},
      };
      if (result.length != expectedFields.length ||
          result.keys.toSet().difference(expectedFields).isNotEmpty)
        _invalid();
      if (result['contractVersion'] != 1 ||
          result['collectionId'] != collection ||
          result['requestId'] != deliveryRequest ||
          result['bindingId'] != receipt['bindingId'] ||
          result['installationId'] != receipt['installationId'] ||
          result['subscriptionId'] != receipt['subscriptionId'] ||
          result['expiresAt'] != receipt['deliveryExpiresAt'] ||
          result['expiresAt'] is! int ||
          (result['expiresAt'] as int) <=
              DateTime.now().millisecondsSinceEpoch ||
          result['pairingCode'] is! String ||
          !RegExp(
            r'^[a-f0-9]{64}$',
          ).hasMatch(result['pairingCode'] as String)) {
        _invalid();
      }
      if (replacement &&
          (result['handoffId'] != handoff ||
              !const {'prepared', 'retired'}.contains(result['phase']) ||
              result['retirementRequired'] != (result['phase'] == 'prepared') ||
              (_replacement?['phase'] == 'retired' &&
                  result['phase'] != 'retired')))
        _invalid();
      if (_currentDisclosure(disclosureEpoch))
        setState(() {
          _pairingCode = result['pairingCode'] as String;
          _codePhase = replacement ? result['phase'] as String : 'initial';
        });
    });
  }

  void _finishNativeRequest() {
    ref
        .read(adminPendingAttemptStoreProvider)
        .clear(family: 'momo-native-setup', resourceId: 'gateway');
    setState(() {
      _nativePending = null;
      _nativeReceipt = null;
      _nativeAbsent = false;
      _pairingCode = null;
      _codePhase = null;
    });
  }

  Future<void> _finalizeReplacement() async {
    if (_busy || !_lostOldPhone || _replacement?['phase'] != 'prepared') return;
    if (_nativePending != null) {
      if (_nativeReceipt?['operation'] != 'prepare_replacement' ||
          _nativeReceipt?['handoffId'] != _replacement?['handoffId']) {
        setState(
          () => _errorValue =
              'Check the original setup before finalizing this replacement.',
        );
        return;
      }
      _finishNativeRequest();
    }
    await _nativeSend('finalize_replacement');
  }

  Future<void> _nativeCancel() => _nativeRun(() async {
    final p = _nativePending!;
    await _nativeResult(
      await _nativeRequest(
        '/requests/${p.requestKey}/cancel',
        method: 'POST',
        body: {'collectionId': p.intent['collectionId']},
        key: p.requestKey,
      ),
    );
  });

  Widget _nativeControls() {
    final scope = _scope;
    if (_nativePending != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Note(
            'Check this original setup request before changing its group, account or device.',
          ),
          SelectableText(_nativePending!.requestKey),
          OutlinedButton.icon(
            onPressed: _busy ? null : _nativeCheck,
            icon: const Icon(Icons.manage_search, size: 28),
            label: const Text('Check original setup'),
          ),
          if (_nativeAbsent)
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _nativeSend(
                      _nativePending!.intent['operation'] as String,
                    ),
              child: const Text('Submit original setup'),
            ),
          if (_nativeReceipt == null)
            TextButton(
              onPressed: _busy ? null : _nativeCancel,
              child: const Text('Cancel unapplied setup'),
            ),
          if (_nativeReceipt != null) ...[
            FilledButton.icon(
              onPressed: _busy ? null : _nativeReveal,
              icon: const Icon(Icons.key_outlined, size: 28),
              label: const Text('Show pairing code'),
            ),
            if (_nativeReceipt?['operation'] == 'prepare_replacement' &&
                _replacement?['phase'] == 'prepared')
              _lostReplacementControls(),
            TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      _finishNativeRequest();
                      _load();
                    },
              child: const Text('Finish setup'),
            ),
          ],
        ],
      );
    }
    final canPrepare =
        scope == null ||
        scope['enabled'] == false &&
            scope['bindingId'] == null &&
            scope['receivingAccountId'] != _account;
    if (_replacement != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Note(
            _replacement!['phase'] == 'prepared'
                ? 'Replacement is prepared for the selected phone. Confirm retirement of the old receiver before pairing the replacement.'
                : 'The current receiver is retired. Sign in again on the selected replacement phone, then use Pair receiver.',
          ),
          SelectableText('${_replacement!['targetInstallationId']}'),
          FilledButton.icon(
            onPressed: _busy ? null : _nativeReveal,
            icon: const Icon(Icons.key_outlined, size: 28),
            label: const Text('Show pairing code'),
          ),
          if (_replacement!['phase'] == 'prepared') _lostReplacementControls(),
        ],
      );
    }
    // A revoked credential is still receiver history. It needs an explicit
    // replacement handoff, while paired continues to mean currently active.
    if (scope?['receiverKeyId'] is String) {
      return _receivingDeviceControls(replacing: true);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canPrepare)
          FilledButton.icon(
            onPressed:
                _busy || _account == null || _reason.text.trim().length < 8
                ? null
                : () => _nativeSend('prepare'),
            icon: const Icon(Icons.settings_outlined, size: 28),
            label: const Text('Prepare native group'),
          )
        else ...[
          _receivingDeviceControls(replacing: false),
        ],
      ],
    );
  }

  Widget _receivingDeviceControls({required bool replacing}) {
    final subscription = int.tryParse(_subscription.text.trim());
    final device = _device;
    final canIssue =
        !_busy &&
        device != null &&
        _account != null &&
        _reason.text.trim().length >= 8 &&
        subscription != null &&
        subscription >= 0 &&
        subscription < 2147483647 &&
        (!replacing ||
            (_account == _scope?['receivingAccountId'] &&
                _scope?['receiverKeyId'] is String &&
                _scope?['bindingId'] is String &&
                device['installationId'] != _scope?['receiverInstallationId']));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Note(
          'Choose a phone that has signed in with its approved native Admin PIN and its current custodian. Pair receiver assigns capture custody; signing in alone does not.',
        ),
        DropdownButtonFormField<String>(
          initialValue: _grant,
          isExpanded: true,
          key: ValueKey('native-device-$_grant:${_devices.length}'),
          decoration: const InputDecoration(
            labelText: 'Approved receiving phone',
          ),
          items: [
            for (final row in _devices)
              DropdownMenuItem(
                value: _deviceKey(row),
                child: Text(
                  '${row['custodianName']} · ${row['installationId']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _busy
              ? null
              : (value) => setState(() {
                  _grant = value;
                  _lostOldPhone = false;
                }),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: canIssue
              ? () =>
                    _nativeSend(replacing ? 'prepare_replacement' : 'activate')
              : null,
          icon: const Icon(Icons.phonelink_setup_outlined, size: 28),
          label: Text(
            replacing
                ? 'Prepare phone replacement'
                : 'Issue receiving phone pairing',
          ),
        ),
      ],
    );
  }

  Widget _lostReplacementControls() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const _Note(
        'If the old phone is unavailable, its retained receipts cannot be checked here. Finalizing revokes its receiving authority without claiming its queue is empty or erasing its evidence.',
      ),
      CheckboxListTile(
        value: _lostOldPhone,
        onChanged: _busy
            ? null
            : (value) => setState(() => _lostOldPhone = value == true),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('The old receiving phone is unavailable.'),
      ),
      OutlinedButton(
        onPressed: _busy || !_lostOldPhone || _reason.text.trim().length < 8
            ? null
            : _finalizeReplacement,
        child: const Text('Finalize prepared replacement without old phone'),
      ),
    ],
  );

  Future<void> _save(String kind) async {
    final disclosureEpoch = ++_disclosureEpoch;
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
          } else if (_currentDisclosure(disclosureEpoch)) {
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
              if (_groups.isNotEmpty) ...[
                DropdownButtonFormField<String>(
                  initialValue: _groups.any((g) => g['id'] == _collection)
                      ? _collection
                      : null,
                  isExpanded: true,
                  key: ValueKey(
                    'gateway-native-group-$_collection:${_groups.length}',
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Collect group for native setup',
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Generic gateway'),
                    ),
                    for (final group in _groups)
                      DropdownMenuItem(
                        value: group['id'] as String,
                        child: Text(group['title'] as String),
                      ),
                  ],
                  onChanged: _busy || _pending != null || _nativePending != null
                      ? null
                      : (value) {
                          setState(() {
                            _collection = value;
                            _account = null;
                            _grant = null;
                            _pairingCode = null;
                            _codePhase = null;
                            _lostOldPhone = false;
                          });
                          _load();
                        },
                ),
                const SizedBox(height: 16),
              ],
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
              ] else if (_nativePending != null)
                _nativeControls()
              else ...[
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
                    for (final row in _choices)
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
                  decoration: InputDecoration(
                    labelText: _collection == null
                        ? 'Receiving SIM subscription ID (optional)'
                        : 'Receiving SIM subscription ID',
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
                if (_collection != null)
                  _nativeControls()
                else
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
                _Note(
                  _codePhase == 'prepared'
                      ? 'Enter this code on the current receiving phone in Replace receiver. After retirement, sign in again on the selected replacement phone and use Pair receiver.'
                      : _codePhase == 'retired'
                      ? 'Sign in again on the selected replacement phone, then enter this code in Pair receiver. The old phone must not use the replacement credential.'
                      : _codePhase == 'initial'
                      ? 'Pairing code expires in 10 minutes. Sign in again on the selected receiving phone, then enter it in Pair receiver.'
                      : 'Single-use pairing code · expires in 10 minutes. Enter it only on the dedicated receiving phone.',
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
