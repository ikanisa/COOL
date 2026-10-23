part of 'cloudflare_admin_operating_pages.dart';

// The form and an existing-record recovery entry point must accept the same
// retained intent. Recovery never reconstructs a newer version or write body.
AdminPendingAttemptSchema _operatingRecoverySchema(
  CloudflareOperation operation,
) => AdminPendingAttemptSchema(
  fields: {
    'reason',
    'expected_version',
    for (final field in _fieldsFor(operation)) field.key,
    if (operation == CloudflareOperation.createGroup) ...{
      'owner_user_id',
      'receiver_label',
      'receiver_network',
      'receiver_route',
      'visibility',
      'is_platform_sponsored',
    },
    if (operation == CloudflareOperation.createTransaction) 'source_fact_id',
    if (operation == CloudflareOperation.createTransaction) 'payer_name',
    'receiver',
    'evidence',
    'entries',
  },
  nestedFields: const {
    'receiver': {'label', 'network', 'momo_number_or_code'},
    'evidence': {'kind', 'reference', 'sha256'},
    'entries[]': {'account_id', 'debit_rwf', 'credit_rwf', 'description'},
  },
);

class CloudflareOperatingForm extends ConsumerStatefulWidget {
  const CloudflareOperatingForm({
    required this.operation,
    this.detail,
    this.targetId,
    this.initial = const {},
    this.fixed = const {},
    this.onSaved,
    super.key,
  });
  final CloudflareOperation operation;
  final CloudflareOperatingDetail? detail;
  final String? targetId;
  final Map<String, dynamic> initial, fixed;
  final VoidCallback? onSaved;
  @override
  ConsumerState<CloudflareOperatingForm> createState() => _OperatingFormState();
}

class _OperatingFormState extends ConsumerState<CloudflareOperatingForm> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  final _recoveryEvidence = TextEditingController();
  final _controllers = <String, TextEditingController>{};
  final _values = <String, String?>{};
  final _lookups = <String, List<Map<String, dynamic>>>{};
  final _lookupErrors = <String, String>{};
  final _lookupLoading = <String>{};
  final _lines = <_JournalLine>[];
  final _lookupEpoch = <String, int>{};
  bool _busy = false, _checking = false, _reviewing = false;
  String? _error, _unknownKey;
  CloudflareOperationReceipt? _receipt;
  Object? _authority;
  String get _recoveryFamily =>
      'operating-${widget.operation.name.toLowerCase()}';
  String? get _target =>
      widget.targetId ??
      (widget.operation.needsVersion ? widget.detail?.id : null);
  String get _recoveryResource => (_target ?? 'new').replaceAll('/', ':');
  String get _permission => widget.operation == CloudflareOperation.createGroup
      ? 'collections.create'
      : widget.operation.permission;
  bool get _current {
    if (!mounted || _authority == null) return false;
    final user = ref.read(cloudflareAdminSessionProvider).asData?.value;
    return user != null &&
        user.authorityKey == _authority &&
        user.expiresAt.isAfter(DateTime.now()) &&
        user.permissions.contains(_permission) &&
        (user.role != AdminAccountRole.staff ||
            widget.operation == CloudflareOperation.createGroup);
  }

  AdminPendingAttemptSchema get _recoverySchema =>
      _operatingRecoverySchema(widget.operation);
  void _forgetAttempt() => ref
      .read(adminPendingAttemptStoreProvider)
      .clear(family: _recoveryFamily, resourceId: _recoveryResource);
  late final List<_Field> _fields;
  bool get _canonical =>
      widget.detail?.usesCanonicalEvidence == true ||
      ref
              .read(cloudflareAdminSessionProvider)
              .asData
              ?.value
              ?.usesCanonicalEvidence ==
          true;
  bool get _freshVerification {
    final user = ref.read(cloudflareAdminSessionProvider).asData?.value;
    return !_canonical || user?.hasRecentSensitiveVerification() == true;
  }

  bool get _hasEvidence =>
      !_canonical &&
      (widget.operation == CloudflareOperation.createTransaction ||
          widget.operation == CloudflareOperation.addEvidence);
  bool get _hasJournal =>
      widget.operation == CloudflareOperation.createJournal ||
      widget.operation == CloudflareOperation.updateJournal;
  String? get _groupId =>
      widget.fixed['group_id'] as String? ??
      _values['group_id'] ??
      widget.detail?.resource['group_id'] as String?;
  bool get _locked => _busy || _unknownKey != null || _receipt != null;
  bool get _canPublishGroup {
    final user = ref.read(cloudflareAdminSessionProvider).asData?.value;
    return user != null &&
        {AdminAccountRole.owner, AdminAccountRole.admin}.contains(user.role) &&
        user.permissions.contains('collections.manage') &&
        user.permissions.contains('receivers.manage') &&
        (widget.operation != CloudflareOperation.createGroup ||
            user.permissions.contains('collections.create'));
  }

  bool get _publicGroupRequested =>
      _canPublishGroup && _values['visibility'] == 'public_approved';

  bool get _groupReceiverLocked =>
      widget.detail?.resource['visibility'] == 'public_approved' ||
      const [
        true,
        1,
      ].contains(widget.detail?.resource['is_platform_sponsored']);

  void _openPayeeGroup() {
    final path = _payeeGroupPath(widget.detail);
    if (widget.operation != CloudflareOperation.updatePayee ||
        path == null ||
        !_current ||
        _locked ||
        ref
                .read(cloudflareAdminSessionProvider)
                .asData
                ?.value
                ?.permissions
                .contains('collections.read') !=
            true) {
      return;
    }
    context.go(path);
  }

  @override
  void initState() {
    super.initState();
    _authority = ref
        .read(cloudflareAdminSessionProvider)
        .asData
        ?.value
        ?.authorityKey;
    _fields = [
      ...(_canonical
              ? _canonicalFieldsFor(widget.operation)
              : _fieldsFor(widget.operation))
          .where((field) {
            if (_canonical && field.key == 'visibility') {
              return _canPublishGroup &&
                  (widget.operation == CloudflareOperation.createGroup ||
                      const [
                        'private',
                        'public_pending',
                      ].contains(widget.detail?.resource['visibility']));
            }
            return !(widget.operation == CloudflareOperation.createGroup &&
                ref.read(cloudflareAdminSessionProvider).asData?.value?.role ==
                    AdminAccountRole.staff &&
                {'visibility', 'is_platform_sponsored'}.contains(field.key));
          }),
      if (widget.operation == CloudflareOperation.createGroup) ...[
        _Field(
          'owner_user_id',
          'Group owner',
          required: _canonical,
          lookup: 'users',
        ),
        _Field(
          'receiver_label',
          'Receiver name on MoMo',
          required: _canonical,
          maximum: 120,
        ),
        _Field(
          'receiver_network',
          'Receiver MoMo provider',
          required: _canonical,
          choices: ['mtn_momo', 'airtel_money'],
        ),
        _Field(
          'receiver_route',
          _canonical && !_canPublishGroup
              ? 'Receiver MoMo number'
              : 'Receiver MoMo number or code',
          required: _canonical,
          minimum: 4,
          maximum: _canonical ? 13 : 12,
          hint: _canonical && _canPublishGroup
              ? 'Private groups need a Rwanda MoMo number. Public groups may use a numeric merchant code.'
              : null,
        ),
      ],
      if (!_canonical &&
          widget.operation == CloudflareOperation.createTransaction)
        const _Field(
          'source_fact_id',
          'Preserved SMS facts (optional)',
          required: false,
          optionalNull: true,
          lookup: 'sms_facts',
          hint:
              'Select extracted receiver facts; they are checked against the payee and amount. Member receipts are linked after review.',
        ),
      if (_canonical &&
          widget.operation == CloudflareOperation.createTransaction)
        const _Field(
          'evidence_text',
          'Exact evidence text',
          multiline: true,
          minimum: 8,
          maximum: 4000,
          hint:
              'Retained encrypted with the payment. Raw evidence is not saved in browser recovery storage.',
        ),
      if (_hasEvidence) ...const [
        _Field('evidence_kind', 'Evidence type', choices: _evidenceKinds),
        _Field(
          'evidence_reference',
          'Evidence reference',
          minimum: 8,
          maximum: 500,
        ),
        _Field(
          'evidence_sha256',
          'Artifact SHA-256',
          minimum: 64,
          maximum: 64,
          hint: '64 lowercase hexadecimal characters',
        ),
      ],
    ];
    final source = {
      if (widget.operation.needsVersion) ...?widget.detail?.resource,
      ...widget.initial,
      ...widget.fixed,
    };
    for (final field in _fields) {
      var initial = source[field.key];
      if (_canonical && field.key == 'visibility') {
        initial =
            widget.operation == CloudflareOperation.createGroup &&
                initial == 'public_approved'
            ? 'public_approved'
            : 'private';
      }
      if (field.key == 'is_platform_sponsored' && initial is int) {
        initial = initial == 1;
      }
      if (field.key == 'role' && initial == null) initial = 'member';
      if (field.choices != null || field.lookup != null) {
        _values[field.key] =
            initial?.toString() ??
            (field.required && field.choices != null
                ? field.choices!.first
                : null);
      } else {
        _controllers[field.key] = TextEditingController(
          text: initial?.toString() ?? '',
        );
      }
    }
    if (_hasJournal) {
      final entries = widget.detail?.related['entries'] ?? [];
      for (final entry in entries) {
        _lines.add(
          _JournalLine(
            accountId: entry['account_id'] as String?,
            debit: entry['debit_rwf'] as int? ?? 0,
            credit: entry['credit_rwf'] as int? ?? 0,
            description: entry['description'] as String? ?? '',
          ),
        );
      }
      if (_lines.isEmpty) {
        _lines.addAll([_JournalLine(), _JournalLine()]);
      }
    }
    final saved = ref
        .read(adminPendingAttemptStoreProvider)
        .restore(
          family: _recoveryFamily,
          resourceId: _recoveryResource,
          schema: _recoverySchema,
        );
    if (saved != null) {
      _pendingBody = Map.from(saved.intent);
      _unknownKey = saved.requestKey;
      _reason.text = '${saved.intent['reason'] ?? ''}';
      _error =
          'A previous change needs recovery. Check its original request before continuing.';
      for (final field in _fields) {
        final value = saved.intent[field.key];
        if (field.lookup != null || field.choices != null) {
          _values[field.key] = value?.toString();
        } else if (value != null) {
          _controllers[field.key]?.text = '$value';
        }
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(cloudflareAdminSessionProvider).asData?.value;
      final permission = widget.operation == CloudflareOperation.createGroup
          ? 'collections.create'
          : widget.operation.permission;
      if (mounted &&
          (!_canonical ||
              _canonicalWritableOperations.contains(widget.operation)) &&
          user != null &&
          user.permissions.contains(permission) &&
          (user.role != AdminAccountRole.staff ||
              widget.operation == CloudflareOperation.createGroup)) {
        _reloadLookups();
      }
    });
  }

  @override
  void dispose() {
    _recoveryEvidence.dispose();
    _reason.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _loadLookup(String kind, {String search = ''}) async {
    final epoch = (_lookupEpoch[kind] ?? 0) + 1;
    _lookupEpoch[kind] = epoch;
    if ({'payees', 'accounts', 'members'}.contains(kind) && _groupId == null) {
      setState(() => _lookups[kind] = []);
      return;
    }
    setState(() {
      _lookupLoading.add(kind);
      _lookupErrors.remove(kind);
    });
    try {
      final repo = _repository(ref);
      List<Map<String, dynamic>> rows;
      if (kind == 'sms_facts') {
        final page = await ref
            .read(cloudflareAdminSmsApiProvider)
            .receipts(
              search: search,
              sourceKind: 'receiver',
              extractionStatus: 'parsed',
              limit: 100,
            );
        rows = [
          for (final source in page.rows)
            if (source.values['is_payment'] == 1 &&
                source.values['direction'] == 'incoming')
              {
                ...source.values,
                'id': source.values['source_fact_id'],
                'label':
                    '${source.values['payer_name'] ?? 'Unknown payer'} · ${source.values['momo_transaction_reference']} · ${adminFormatWholeAmount(source.values['amount_rwf'])}',
              },
        ];
      } else if (kind == 'evidence') {
        rows = [
          for (final row
              in widget.detail?.related['evidence'] ?? <Map<String, dynamic>>[])
            if (row['recorded_by_admin_id'] != widget.detail?.actorId)
              {
                ...row,
                'label':
                    '${operatingLabel(row['kind'] as String)} · ${row['reference']}',
              },
        ];
      } else if (kind == 'allocations') {
        rows = [
          for (final row
              in widget.detail?.related['allocations'] ??
                  <Map<String, dynamic>>[])
            {
              ...row,
              'label':
                  'RWF ${row['amount_rwf']} · ${row['member_user_id'] ?? 'Unattributed'}',
            },
        ];
      } else {
        rows = await repo.operatingLookups(
          kind,
          groupId: {'payees', 'accounts', 'members'}.contains(kind)
              ? _groupId
              : null,
          search: search,
        );
      }
      if (!mounted || _lookupEpoch[kind] != epoch) return;
      setState(() => _lookups[kind] = rows);
    } catch (error) {
      if (mounted && _lookupEpoch[kind] == epoch) {
        setState(() => _lookupErrors[kind] = _safeOperatingError(error));
      }
    } finally {
      if (mounted && _lookupEpoch[kind] == epoch) {
        setState(() => _lookupLoading.remove(kind));
      }
    }
  }

  void _reloadLookups() {
    for (final kind in {
      ..._fields
          .where(
            (field) =>
                field.lookup != null && !widget.fixed.containsKey(field.key),
          )
          .map((field) => field.lookup!),
      if (_hasJournal) 'accounts',
    }) {
      _loadLookup(kind);
    }
  }

  void _changedGroup(String? value) {
    setState(() {
      _values['group_id'] = value;
      _values['payee_id'] = null;
      _values['member_user_id'] = null;
      for (final line in _lines) {
        line.accountId = null;
      }
      for (final kind in ['payees', 'accounts', 'members']) {
        _lookups.remove(kind);
      }
    });
    _reloadLookups();
  }

  String? _validate(_Field field, String? input) {
    final value = input?.trim() ?? '';
    if (value.isEmpty) {
      return field.required ? 'Enter ${field.label.toLowerCase()}.' : null;
    }
    if (field.money && parseOperatingRwf(value) == null) {
      return 'Enter a whole RWF amount from 1 to 9007199254740991.';
    }
    if (!field.money &&
        (value.runes.length < field.minimum ||
            value.runes.length > field.maximum)) {
      return 'Use ${field.minimum}–${field.maximum} characters.';
    }
    if (field.key == 'slug' &&
        !RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(value)) {
      return 'Use lowercase letters, digits and hyphens.';
    }
    if (field.key == 'email' && !RegExp(r'^[^\s@]+@[^\s@]+$').hasMatch(value)) {
      return 'Enter a valid email address.';
    }
    if (field.key == 'phone_e164' &&
        !RegExp(r'^\+2507[2389][0-9]{7}$').hasMatch(value)) {
      return 'Use a Rwanda mobile number such as +25078…';
    }
    if ({'momo_number_or_code', 'receiver_route'}.contains(field.key) &&
        !(_canonical
                ? field.key == 'receiver_route' && _publicGroupRequested
                      ? RegExp(
                          r'^(?:07[2389][0-9]{7}|\+?2507[2389][0-9]{7}|[0-9]{4,12})$',
                        )
                      : RegExp(r'^(?:07[2389][0-9]{7}|\+?2507[2389][0-9]{7})$')
                : RegExp(r'^[0-9]{4,12}$'))
            .hasMatch(value)) {
      return _canonical
          ? field.key == 'receiver_route' && _publicGroupRequested
                ? 'Enter a Rwanda MoMo number or a 4–12 digit merchant code.'
                : 'Enter the recorded Rwanda MoMo number.'
          : 'Use 4–12 digits.';
    }
    if (field.key == 'momo_number' &&
        !RegExp(r'^07[2389][0-9]{7}$').hasMatch(value)) {
      return 'Enter the recorded Rwanda MoMo number.';
    }
    if (field.key == 'momo_pay_code' &&
        !RegExp(r'^[0-9]{4,9}$').hasMatch(value)) {
      return 'Use 4–9 digits and preserve leading zeros.';
    }
    if (field.key == 'evidence_sha256' &&
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
      return 'Use the 64 lowercase hexadecimal characters of the artifact digest.';
    }
    if (field.key == 'observed_at') {
      final date = DateTime.tryParse(value);
      if (!value.endsWith('Z') ||
          date == null ||
          date.millisecondsSinceEpoch <= 0 ||
          date.isAfter(DateTime.now().add(const Duration(seconds: 60)))) {
        return 'Enter a valid UTC time ending in Z that is not in the future.';
      }
    }
    return null;
  }

  Map<String, dynamic> _body() {
    final body = <String, dynamic>{'reason': _reason.text.trim()};
    if (widget.operation.needsVersion) {
      body['expected_version'] =
          widget.initial['version'] ?? widget.detail!.version;
    }
    for (final field in _fields) {
      if (field.key.startsWith('evidence_')) continue;
      final value =
          widget.fixed[field.key]?.toString() ??
          _values[field.key] ??
          _controllers[field.key]?.text.trim() ??
          '';
      body[field.key] = value.isEmpty && field.optionalNull
          ? null
          : field.money && value.isNotEmpty
          ? parseOperatingRwf(value)
          : field.key == 'is_platform_sponsored'
          ? value == 'true'
          : field.key == 'observed_at'
          ? _canonical
                ? DateTime.fromMillisecondsSinceEpoch(
                    DateTime.parse(value).millisecondsSinceEpoch,
                    isUtc: true,
                  ).toIso8601String()
                : DateTime.parse(value).millisecondsSinceEpoch ~/ 1000
          : field.key == 'email'
          ? value.toLowerCase()
          : value;
    }
    if (widget.operation == CloudflareOperation.createGroup) {
      final label = body.remove('receiver_label') as String? ?? '';
      final network = body.remove('receiver_network') as String? ?? '';
      final route = body.remove('receiver_route') as String? ?? '';
      if (label.isNotEmpty || network.isNotEmpty || route.isNotEmpty) {
        body['receiver'] = {
          'label': label,
          'network': network,
          'momo_number_or_code': route,
        };
      }
      if ((body['owner_user_id'] as String?)?.isEmpty ?? true) {
        body.remove('owner_user_id');
      }
      if (_canonical) {
        body['visibility'] = _publicGroupRequested
            ? 'public_approved'
            : 'private';
        body['is_platform_sponsored'] = _publicGroupRequested;
      } else if (ref.read(cloudflareAdminSessionProvider).asData?.value?.role ==
          AdminAccountRole.staff) {
        body['visibility'] = 'private';
        body['is_platform_sponsored'] = false;
      }
    }
    if (_canonical && widget.operation == CloudflareOperation.updateGroup) {
      body.remove('visibility');
      body.remove('is_platform_sponsored');
      if (_publicGroupRequested &&
          widget.detail?.resource['visibility'] != 'public_approved') {
        body['visibility'] = 'public_approved';
        body['is_platform_sponsored'] = true;
      }
    }
    if (body['member_type'] == 'direct') body.remove('phone_e164');
    if (body['source_fact_id'] == null) body.remove('source_fact_id');
    if (_hasEvidence) {
      body['evidence'] = {
        'kind': _values['evidence_kind'],
        'reference': _controllers['evidence_reference']!.text.trim(),
        'sha256': _controllers['evidence_sha256']!.text.trim(),
      };
    }
    if (_canonical &&
        widget.operation == CloudflareOperation.createTransaction) {
      body['evidence'] = _controllers['evidence_text']!.text.trim();
    }
    if (_hasJournal) {
      body['entries'] = [
        for (final line in _lines)
          {
            'account_id': line.accountId,
            'debit_rwf': line.debit.text.trim().isEmpty
                ? 0
                : parseOperatingRwf(line.debit.text, allowZero: true),
            'credit_rwf': line.credit.text.trim().isEmpty
                ? 0
                : parseOperatingRwf(line.credit.text, allowZero: true),
            'description': line.description.text.trim(),
          },
      ];
    }
    return body;
  }

  String? _crossFieldError(Map<String, dynamic> body) {
    if (_canonical && (body['reason'] as String).runes.length > 500) {
      return 'Use at most 500 characters for the recorded reason.';
    }
    if (widget.operation == CloudflareOperation.createGroup &&
        body['status'] == 'active' &&
        (body['owner_user_id'] == null || body['receiver'] == null)) {
      return 'Select the group owner and recorded receiver before creating an active group.';
    }
    if (_canonical &&
        widget.operation == CloudflareOperation.updateGroup &&
        body['visibility'] == 'public_approved' &&
        (widget.detail?.resource['owner_user_id'] == null ||
            !(widget.detail?.related['payees'] ?? []).any(
              (receiver) =>
                  receiver['status'] == 'active' &&
                  const [
                    'mtn_momo',
                    'airtel_money',
                  ].contains(receiver['network']) &&
                  RegExp(
                    r'^(?:07[2389][0-9]{7}|\+?2507[2389][0-9]{7}|[0-9]{4,12})$',
                  ).hasMatch('${receiver['momo_number_or_code'] ?? ''}'),
            ))) {
      return 'Refresh the recorded group owner and active MoMo receiver before publishing.';
    }
    if (body['member_type'] == 'direct' &&
        (body['momo_number'] as String? ?? '').isEmpty) {
      return 'A Direct member needs their recorded MoMo number.';
    }
    if ({
          CloudflareOperation.createUser,
          CloudflareOperation.updateUser,
        }.contains(widget.operation) &&
        body['email'] == null &&
        body['phone_e164'] == null &&
        body['member_type'] != 'direct') {
      return 'Provide an email or Rwanda mobile number.';
    }
    if (widget.operation == CloudflareOperation.verifyTransaction &&
        body['outcome'] == 'confirmation_recorded') {
      final evidence = widget.detail?.related['evidence']
          ?.where((row) => row['id'] == body['evidence_id'])
          .firstOrNull;
      if (evidence == null ||
          !{
            'receiver_statement',
            'provider_statement',
          }.contains(evidence['kind'])) {
        return 'Confirmation requires a receiver statement or provider statement.';
      }
      if (widget.detail?.resource['recorded_by_admin_id'] ==
          widget.detail?.actorId) {
        return 'A different administrator must confirm the payment you recorded.';
      }
    }
    if (widget.operation == CloudflareOperation.allocateTransaction) {
      final amount = widget.detail?.resource['amount_rwf'];
      final allocated = widget.detail?.resource['allocated_amount_rwf'];
      if (amount is int &&
          allocated is int &&
          (body['amount_rwf'] as int) > amount - allocated) {
        return 'The allocation exceeds the remaining RWF ${amount - allocated}.';
      }
    }
    if (_hasJournal) {
      var debits = BigInt.zero, credits = BigInt.zero;
      for (final entry in body['entries'] as List) {
        final debit = entry['debit_rwf'], credit = entry['credit_rwf'];
        if (debit is! int || credit is! int || ((debit > 0) == (credit > 0))) {
          return 'Each journal line needs an amount on exactly one side.';
        }
        debits += BigInt.from(debit);
        credits += BigInt.from(credit);
      }
      if (debits == BigInt.zero || debits != credits) {
        return 'Total debits and credits must be equal and positive.';
      }
      if (debits > BigInt.from(9007199254740991)) {
        return 'Journal totals exceed the exact RWF limit.';
      }
    }
    return null;
  }

  Future<_JournalPostingContext?> _postingContext(Map<String, dynamic> body) =>
      widget.operation == CloudflareOperation.postJournal
      ? _loadJournalPostingContext(
          _repository(ref),
          widget.detail,
          _target,
          body,
        )
      : Future.value(null);

  Future<void> _submit() async {
    if (!_current ||
        !_freshVerification ||
        _locked ||
        !(_form.currentState?.validate() ?? false)) {
      return;
    }
    final body = _body(), target = _target;
    final problem = _crossFieldError(body);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _reviewing = true;
      _error = null;
    });
    try {
      final journal = await _postingContext(body);
      bool canConfirm() =>
          _current &&
          _freshVerification &&
          _target == target &&
          _unknownKey == null &&
          _receipt == null &&
          (journal?.matches(widget.detail, _target, body) ?? true);
      if (!mounted || !canConfirm()) return;
      final confirmed = await _reviewOperatingConfirmation(
        context: context,
        operation: widget.operation,
        body: body,
        accountLabel: _accountLabel,
        journal: journal,
        canConfirm: canConfirm,
        explanation: _canonical
            ? _canonicalActionExplanation(widget.operation)
            : null,
      );
      if (confirmed != true || !canConfirm()) return;
      setState(() => _reviewing = false);
      await _send(body, const Uuid().v4());
    } catch (error) {
      if (_current) setState(() => _error = _safeOperatingError(error));
    } finally {
      if (_current) {
        setState(() {
          _busy = false;
          _reviewing = false;
        });
      }
    }
  }

  Map<String, dynamic>? _pendingBody;
  bool _canRetryIdentical = false;
  Future<void> _send(Map<String, dynamic> body, String key) async {
    if (!_current || !_freshVerification) return;
    try {
      if (_canonical) body = _recoverySchema.canonical(body);
      ref
          .read(adminPendingAttemptStoreProvider)
          .retain(
            family: _recoveryFamily,
            resourceId: _recoveryResource,
            requestKey: key,
            permission: _permission,
            intent: _operatingRecoveryIntent(body),
            schema: _recoverySchema,
          );
    } catch (error) {
      if (_current) setState(() => _error = _safeOperatingError(error));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _canRetryIdentical = false;
    });
    _pendingBody = body;
    try {
      final receipt = await _repository(
        ref,
      ).operate(widget.operation, id: _target, key: key, body: body);
      if (!_current) return;
      _forgetAttempt();
      setState(() {
        _receipt = receipt;
        _unknownKey = null;
      });
      widget.onSaved?.call();
    } catch (error) {
      if (!_current) return;
      final unknown =
          _canonical ||
          error is! CloudflareAdminRequestException ||
          error.outcomeUnknown ||
          error.code == 'request_pending';
      setState(() {
        _error = unknown
            ? 'The result is unconfirmed. Check this request before making another change.'
            : _safeOperatingError(error);
        _unknownKey = unknown ? key : null;
      });
      if (!unknown) _forgetAttempt();
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  Future<void> _check() async {
    if (_unknownKey == null || _checking || !_current) return;
    setState(() {
      _checking = true;
      _canRetryIdentical = false;
    });
    try {
      final result = await _repository(ref).operatingRequest(_unknownKey!);
      if (!_current) return;
      if (result['status'] == 'succeeded') {
        final receipt = CloudflareOperationReceipt.parse(
          Map<String, dynamic>.from(result['receipt'] as Map),
        );
        final originalVersion = _pendingBody?['expected_version'];
        if (receipt.resourceType != widget.operation.resource ||
            (widget.operation.needsVersion &&
                (originalVersion is! int ||
                    originalVersion < 1 ||
                    originalVersion > 9007199254740990 ||
                    receipt.resourceId != _target ||
                    receipt.version != originalVersion + 1)) ||
            (!widget.operation.needsVersion && receipt.version != 1)) {
          throw const FormatException('The original receipt does not match.');
        }
        _forgetAttempt();
        setState(() {
          _receipt = receipt;
          _unknownKey = null;
          _error = null;
        });
        widget.onSaved?.call();
      } else if (result['status'] == 'cancelled') {
        _forgetAttempt();
        setState(() {
          _unknownKey = null;
          _pendingBody = null;
          _canRetryIdentical = false;
          _error =
              'The original request is cancelled. Refresh the record before editing its current version.';
        });
      } else {
        setState(() {
          _canRetryIdentical = result['status'] == 'not_found';
          _error = switch (result['status']) {
            'not_found' =>
              'No completed request was found. Check again, or explicitly retry this exact request with its existing reference.',
            'failed' =>
              'The request failed. Keep the reference and refresh the record before making a new change.',
            _ => 'The request is still pending. Check again before continuing.',
          };
        });
      }
    } catch (error) {
      if (_current) setState(() => _error = _safeOperatingError(error));
    } finally {
      if (_current) setState(() => _checking = false);
    }
  }

  Future<void> _reviewIdenticalRetry() async {
    if (!_current ||
        !_freshVerification ||
        _busy ||
        !_canRetryIdentical ||
        _pendingBody == null ||
        _unknownKey == null) {
      return;
    }
    final retainedEvidence = _pendingBody!['evidence'];
    if (_canonical && retainedEvidence is Map) {
      final original = _recoveryEvidence.text.trim();
      if (retainedEvidence['kind'] != 'retained_operator_text' ||
          sha256.convert(utf8.encode(original)).toString() !=
              retainedEvidence['sha256']) {
        setState(
          () => _error =
              'Re-enter the exact original evidence text. Its digest must match before this request can be retried.',
        );
        return;
      }
      _pendingBody = {..._pendingBody!, 'evidence': original};
    }
    final body = _pendingBody!, key = _unknownKey!, target = _target;
    setState(() {
      _busy = true;
      _reviewing = true;
      _error = null;
    });
    try {
      final journal = await _postingContext(body);
      bool canConfirm() =>
          _current &&
          _freshVerification &&
          _target == target &&
          _unknownKey == key &&
          identical(_pendingBody, body) &&
          _canRetryIdentical &&
          _receipt == null &&
          (journal?.matches(widget.detail, _target, body) ?? true);
      if (!mounted || !canConfirm()) return;
      final accepted = await _reviewOperatingConfirmation(
        context: context,
        operation: widget.operation,
        body: body,
        accountLabel: _accountLabel,
        journal: journal,
        retryKey: key,
        canConfirm: canConfirm,
        explanation: _canonical
            ? _canonicalActionExplanation(widget.operation)
            : null,
      );
      if (accepted != true || !canConfirm()) return;
      setState(() => _reviewing = false);
      await _send(body, key);
    } catch (error) {
      if (_current) setState(() => _error = _safeOperatingError(error));
    } finally {
      if (_current) {
        setState(() {
          _busy = false;
          _reviewing = false;
        });
      }
    }
  }

  String _accountLabel(String? id) =>
      (_lookups['accounts'] ?? [])
              .where((row) => row['id'] == id)
              .firstOrNull?['label']
          as String? ??
      id ??
      'Select account';

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(cloudflareAdminSessionProvider).asData?.value;
    if (user == null ||
        widget.detail?.canManage == false ||
        widget.detail?.allows(widget.operation) == false ||
        (user.role == AdminAccountRole.staff &&
            widget.operation != CloudflareOperation.createGroup) ||
        !user.permissions.contains(
          widget.operation == CloudflareOperation.createGroup
              ? 'collections.create'
              : widget.operation.permission,
        )) {
      return const _OperatingMessage(
        'Your account can view this record but cannot perform this action.',
      );
    }
    if (_canonical &&
        !_canonicalWritableOperations.contains(widget.operation)) {
      return const _OperatingMessage(
        'This action is unavailable in the current workspace. Open a group to manage its recorded receiver; use Reconciliations for member attribution.',
      );
    }
    if (_receipt != null) return CloudflareReceiptView(receipt: _receipt!);
    return _OperatingPanel(
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_canonical && !_freshVerification) ...[
              _OperatingMessage(
                ref
                            .read(cloudflareAdminSessionProvider)
                            .asData
                            ?.value
                            ?.usesEmailVerification ==
                        true
                    ? 'Verify your email before saving this change.'
                    : 'Complete a current authenticator check before saving this change.',
              ),
              TextButton(
                onPressed: () => context.go(
                  ref
                              .read(cloudflareAdminSessionProvider)
                              .asData
                              ?.value
                              ?.usesEmailVerification ==
                          true
                      ? Uri(
                          path: '/admin/security/verify-email',
                          queryParameters: {
                            'returnTo': GoRouterState.of(
                              context,
                            ).uri.toString(),
                          },
                        ).toString()
                      : '/admin/security/authenticator',
                ),
                child: Text(
                  ref
                              .read(cloudflareAdminSessionProvider)
                              .asData
                              ?.value
                              ?.usesEmailVerification ==
                          true
                      ? 'Verify email'
                      : 'Verify authenticator',
                ),
              ),
            ],
            if (_canonical &&
                widget.operation == CloudflareOperation.updateGroup &&
                _groupReceiverLocked)
              const _OperatingMessage(
                'The recorded receiver is permanently locked for this public or platform-sponsored group.',
              ),
            if (_canonical && _publicGroupRequested)
              const _OperatingMessage(
                'Public groups are platform sponsored. Publishing permanently locks the recorded receiver; review it before confirming.',
              ),
            if (!_canonical &&
                widget.operation == CloudflareOperation.updatePayee)
              _PayeeGroupGuidance(
                detail: widget.detail,
                canReadGroup: user.permissions.contains('collections.read'),
                onOpen: _current && !_locked ? _openPayeeGroup : null,
              ),
            for (final field in _fields.where(
              (field) =>
                  !(field.key == 'phone_e164' &&
                      _values['member_type'] == 'direct'),
            ))
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: _fieldWidget(field),
              ),
            if (_hasJournal) _journalEditor(),
            TextFormField(
              controller: _reason,
              enabled: !_locked,
              minLines: 2,
              maxLines: 4,
              maxLength: _canonical ? 500 : 1000,
              decoration: InputDecoration(
                labelText: 'Reason for this change',
                helperText:
                    '8–${_canonical ? 500 : 1000} characters; included in the audit history',
              ),
              validator: (value) => (value?.trim().runes.length ?? 0) < 8
                  ? 'Explain the reason in at least 8 characters.'
                  : null,
            ),
            if (_error != null) _OperatingMessage(_error!, error: true),
            if (!ref.watch(adminPendingAttemptStoreProvider).storageAvailable)
              _OperatingMessage(
                ref.read(adminPendingAttemptStoreProvider).storageMessage,
                error: true,
              ),
            if (_unknownKey != null) ...[
              if (_canRetryIdentical &&
                  _canonical &&
                  _pendingBody?['evidence'] is Map)
                TextField(
                  controller: _recoveryEvidence,
                  minLines: 3,
                  maxLines: 8,
                  maxLength: 4000,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Re-enter original evidence text',
                    helperText:
                        'Raw evidence was not stored in the browser. Its digest must match the original request.',
                  ),
                ),
              SelectableText('Request reference: $_unknownKey'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: _checking || _busy ? null : _check,
                    child: Text(
                      _checking ? 'Checking…' : 'Check request status',
                    ),
                  ),
                  if (_canRetryIdentical)
                    OutlinedButton(
                      onPressed: _busy || !_freshVerification
                          ? null
                          : _reviewIdenticalRetry,
                      child: const Text('Retry identical request'),
                    ),
                  TextButton(
                    onPressed: () =>
                        context.go('/admin/requests?key=$_unknownKey'),
                    child: const Text('Open request lookup'),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _locked || !_freshVerification ? null : _submit,
                  icon: _busy && !_reviewing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(
                    _busy
                        ? (_reviewing ? 'Preparing review…' : 'Saving…')
                        : 'Review change',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _changeField(VoidCallback change) => setState(change);
}

String? _receiptLocation(CloudflareOperationReceipt receipt) =>
    switch (receipt.resourceType) {
      'groups' => '/admin/groups/${receipt.resourceId}',
      'users' => '/admin/users/${receipt.resourceId}',
      'memberships' => '/admin/users/${receipt.resourceId.split('/').last}',
      'payees' => '/admin/payees/${receipt.resourceId}',
      'transactions' => '/admin/transactions/${receipt.resourceId}',
      'journals' => '/admin/ledgers/${receipt.resourceId}',
      'accounts' => '/admin/ledger-accounts/${receipt.resourceId}',
      'gateway_devices' => '/admin/gateway/${receipt.resourceId}',
      'email_dispatch' => '/admin/email',
      'member_receipts' => '/admin/member-receipts/${receipt.resourceId}',
      _ => null,
    };
