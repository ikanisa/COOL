part of 'admin_runtime.dart';

/// Actual v2 policy controls; a policy is never proof of a sender or delivery.
class AdminReceiptOperationsCard extends ConsumerStatefulWidget {
  const AdminReceiptOperationsCard({super.key});
  @override
  ConsumerState<AdminReceiptOperationsCard> createState() =>
      _AdminReceiptOperationsCardState();
}

class _AdminReceiptOperationsCardState
    extends ConsumerState<AdminReceiptOperationsCard> {
  final _principals = TextEditingController(),
      _collections = TextEditingController(),
      _devices = TextEditingController(),
      _hours = TextEditingController();
  final _caps = {
    for (final name in AdminReceiptOperationsCaps.names)
      name: TextEditingController(),
  };
  AdminReceiptOperationsMode _mode = AdminReceiptOperationsMode.paused;
  bool _stop = true, _catchup = false;
  int? _revision, _draftIdentityRevision;
  AdminSessionScope? _draftScope;
  String? _error;
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
    for (final controller in [
      _principals,
      _collections,
      _devices,
      _hours,
      ..._caps.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _load(AdminReceiptOperationsPolicy policy, AdminSessionScope scope) {
    _revision = policy.revision;
    _draftScope = scope;
    _draftIdentityRevision = ref.read(_adminIdentityRevisionProvider);
    _mode = policy.mode;
    _stop = policy.emergencyStop;
    _catchup = policy.catchupEnabled;
    _principals.text = policy.principalIds.join('\n');
    _collections.text = policy.collectionIds.join('\n');
    _devices.text = policy.deviceIds.join('\n');
    _hours.text = '${policy.catchupHours}';
    for (final name in _caps.keys) {
      _caps[name]!.text = '${policy.caps.values[name]}';
    }
    _error = null;
  }

  void _clearDraft() {
    _revision = null;
    _draftScope = null;
    _draftIdentityRevision = null;
    _mode = AdminReceiptOperationsMode.paused;
    _stop = true;
    _catchup = false;
    _error = null;
    for (final controller in [
      _principals,
      _collections,
      _devices,
      _hours,
      ..._caps.values,
    ]) {
      controller.clear();
    }
  }

  List<String> _ids(String value) =>
      value.trim().isEmpty ? [] : value.trim().split(RegExp(r'[\s,]+'));
  int _integer(String value) {
    if (!RegExp(r'^(0|[1-9][0-9]{0,6})$').hasMatch(value.trim())) {
      operationsInvalid();
    }
    return int.parse(value.trim());
  }

  static const _senderQuery = AdminGatewayQuery(limit: 50);

  bool _senderEvidenceReady(DateTime now) {
    final ids = _ids(_devices.text);
    if (ids.isEmpty) return true;
    final read = ref.read(adminGatewayDevicesProvider(_senderQuery));
    if (read.isLoading || read.hasError) return false;
    return AdminSenderPicker(
      deviceIds: ids,
      snapshot: read.asData?.value,
      now: now,
      enabled: false,
      onChanged: (_) {},
    ).evidenceReady;
  }

  Future<void> _act(
    AdminReceiptOperationsPolicy policy,
    AdminSessionScope scope, {
    required bool stop,
  }) async {
    final actionScope = _AdminActionScope(ref);
    final now = ref.read(adminClockProvider)();
    if (!actionScope.isCurrent ||
        !policy.isFresh(now) ||
        ref.read(adminAuthSessionScopeProvider) != scope ||
        (!stop && (_revision != policy.revision || _draftScope != scope))) {
      return;
    }
    if (!stop && !_senderEvidenceReady(now)) {
      setState(
        () => _error =
            'Refresh current gateway evidence for every allowed device before applying policy.',
      );
      return;
    }
    try {
      // Validate the draft before requesting a reason; this does not send it.
      if (!stop) {
        AdminReceiptOperationsIntent.configure(
          requestId: const Uuid().v4(),
          expectedRevision: policy.revision,
          createdAt: now,
          expiresAt: now.add(const Duration(seconds: 90)),
          reason: 'Draft validation only',
          mode: _mode,
          emergencyStop: _mode == AdminReceiptOperationsMode.paused || _stop,
          principalIds: _ids(_principals.text),
          collectionIds: _ids(_collections.text),
          deviceIds: _ids(_devices.text),
          caps: AdminReceiptOperationsCaps.parse({
            for (final entry in _caps.entries)
              entry.key: _integer(entry.value.text),
          }),
          catchupEnabled: _catchup,
          catchupHours: _integer(_hours.text),
        );
      }
    } catch (_) {
      setState(
        () => _error =
            'Check canonical IDs, positive limits and catch-up hours (1–168). '
            'Live modes require an active gateway device; Live-limited allows at most 10 run actions and 20 run SMS segments.',
      );
      return;
    }
    final reason = await showAdminReasonDialog(
      context,
      title: stop
          ? 'Stop receipt operations'
          : 'Apply receipt operations policy',
      actionLabel: stop ? 'Record emergency stop' : 'Apply reviewed policy',
      minLength: 8,
      maxLength: 500,
      dialogWrapper: (_, child) =>
          _AdminSessionDialog(scope: actionScope, child: child),
    );
    if (!mounted ||
        reason == null ||
        !actionScope.isCurrent ||
        ref.read(adminAuthSessionScopeProvider) != scope ||
        !adminReceiptOperationsCanManage(
          _adminResolvedIdentity(ref.read(adminIdentityProvider)),
        )) {
      return;
    }
    final currentNow = ref.read(adminClockProvider)();
    if (!stop &&
        (_draftScope != scope ||
            _revision != policy.revision ||
            _draftIdentityRevision !=
                ref.read(_adminIdentityRevisionProvider) ||
            !_senderEvidenceReady(currentNow))) {
      setState(
        () => _error =
            'Sender evidence or draft authority changed. Refresh and review the original draft.',
      );
      return;
    }
    if (!policy.isFresh(currentNow)) {
      setState(
        () => _error =
            'Policy observation expired. Refresh and review current policy before applying.',
      );
      return;
    }
    try {
      final created = currentNow.toUtc();
      final intent = stop
          ? AdminReceiptOperationsIntent.stop(
              requestId: const Uuid().v4(),
              expectedRevision: policy.revision,
              createdAt: created,
              expiresAt: created.add(const Duration(seconds: 90)),
              reason: reason,
            )
          : AdminReceiptOperationsIntent.configure(
              requestId: const Uuid().v4(),
              expectedRevision: policy.revision,
              createdAt: created,
              expiresAt: created.add(const Duration(seconds: 90)),
              reason: reason,
              mode: _mode,
              emergencyStop:
                  _mode == AdminReceiptOperationsMode.paused || _stop,
              principalIds: _ids(_principals.text),
              collectionIds: _ids(_collections.text),
              deviceIds: _ids(_devices.text),
              caps: AdminReceiptOperationsCaps.parse({
                for (final entry in _caps.entries)
                  entry.key: _integer(entry.value.text),
              }),
              catchupEnabled: _catchup,
              catchupHours: _integer(_hours.text),
            );
      await ref
          .read(adminReceiptOperationsControllerProvider.notifier)
          .submit(intent);
      if (mounted && ref.read(adminAuthSessionScopeProvider) == scope) {
        ref.invalidate(adminReceiptOperationsPolicyProvider);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Policy action could not be prepared. Refresh and review the current values.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final identity = _adminResolvedIdentity(ref.watch(adminIdentityProvider));
    final scope = ref.watch(adminAuthSessionScopeProvider);
    final identityRevision = ref.watch(_adminIdentityRevisionProvider);
    if (_draftIdentityRevision != null &&
        _draftIdentityRevision != identityRevision) {
      _clearDraft();
    }
    if (scope == null ||
        identity?.userId != scope.key.userId ||
        !adminReceiptOperationsCanManage(identity)) {
      _clearDraft();
      return const Text(
        'Current platform owner access with user administration, notifications management '
        'and system health permissions is required for receipt operations policy.',
      );
    }
    final control = ref.watch(adminReceiptOperationsControllerProvider);
    final now = ref.watch(adminClockProvider)();
    final policy = ref.watch(adminReceiptOperationsPolicyProvider);
    final senderRead = ref.watch(adminGatewayDevicesProvider(_senderQuery));
    void refresh() => ref.invalidate(adminReceiptOperationsPolicyProvider);
    final children = <Widget>[
      Semantics(
        header: true,
        child: Text(
          'Receipt operations policy',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'The signed runner derives receipts from committed evidence under this policy. '
        'These controls do not enroll an identity, schedule runs or enable an SMS sender. '
        'A live mode is not proof of a working gateway, carrier delivery or payment settlement.',
      ),
      const SizedBox(height: 12),
      if (control.message case final message?)
        Semantics(liveRegion: true, child: Text(message)),
      if (control.storageBlocked)
        OutlinedButton(
          onPressed: control.busy
              ? null
              : () => ref
                    .read(adminReceiptOperationsControllerProvider.notifier)
                    .reload(),
          child: const Text('Check recovery storage'),
        ),
      for (final checkpoint in control.pending)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Original ${checkpoint.action} request · ${checkpoint.requestId}',
              ),
              Text(
                'Original deadline · ${adminKigaliDate(checkpoint.expiresAt)} · ${adminKigaliTime(checkpoint.expiresAt)} · Africa/Kigali',
              ),
              OutlinedButton(
                onPressed: control.busy
                    ? null
                    : () async {
                        await ref
                            .read(
                              adminReceiptOperationsControllerProvider.notifier,
                            )
                            .reconcile(checkpoint);
                        if (mounted &&
                            ref.read(adminAuthSessionScopeProvider) == scope) {
                          refresh();
                        }
                      },
                child: const Text('Check original request'),
              ),
            ],
          ),
        ),
      if (_error case final error?)
        Semantics(liveRegion: true, child: Text(error)),
    ];
    children.add(
      policy.when(
        skipLoadingOnRefresh: false,
        loading: () => Semantics(
          liveRegion: true,
          child: const Text('Checking receipt operations policy…'),
        ),
        error: (error, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              error is AdminReceiptOperationsDenied
                  ? 'Current email owner authority could not be verified. Sign in again.'
                  : error is UnsupportedError
                  ? 'Receipt operations policy service is unavailable.'
                  : 'Receipt operations policy could not be verified.',
            ),
            OutlinedButton.icon(
              onPressed: refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh policy'),
            ),
          ],
        ),
        data: (value) {
          final fresh = value.isFresh(now);
          if (_draftScope != scope || _revision == null) _load(value, scope);
          final canEdit =
              fresh &&
              !control.busy &&
              !control.storageBlocked &&
              control.pending.isEmpty &&
              _revision == value.revision;
          Widget field(
            String label,
            TextEditingController controller, {
            bool number = false,
            int lines = 1,
          }) => TextField(
            controller: controller,
            enabled: canEdit,
            keyboardType: number
                ? TextInputType.number
                : TextInputType.multiline,
            minLines: lines,
            maxLines: lines == 1 ? 1 : 4,
            decoration: InputDecoration(labelText: label),
            onChanged: identical(controller, _devices)
                ? (_) => setState(() {})
                : null,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  AdminStatusChip(
                    label: fresh
                        ? value.mode.label
                        : 'Policy observation expired',
                  ),
                  AdminStatusChip(
                    label: !fresh
                        ? 'Emergency stop unverified'
                        : value.emergencyStop
                        ? 'Emergency stop set'
                        : 'Emergency stop clear',
                    tone: value.emergencyStop
                        ? CollectStatusTone.warning
                        : CollectStatusTone.info,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Policy revision ${value.revision} · Checked ${adminKigaliDate(value.checkedAt)} · ${adminKigaliTime(value.checkedAt)} · Africa/Kigali',
              ),
              if (!fresh)
                const Text(
                  'Refresh the expired observation before relying on policy or taking an action.',
                ),
              if (_revision != value.revision)
                const Text(
                  'Policy changed since this draft. Load the current values before applying.',
                ),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: control.busy ? null : refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh policy'),
                  ),
                  OutlinedButton(
                    onPressed: fresh && !control.busy && control.pending.isEmpty
                        ? () => setState(() => _load(value, scope))
                        : null,
                    child: const Text('Load current values'),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        fresh &&
                            !control.busy &&
                            !control.storageBlocked &&
                            !control.pendingStop
                        ? () => _act(value, scope, stop: true)
                        : null,
                    icon: const Icon(Icons.pause_circle_outline),
                    label: const Text('Emergency stop'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<AdminReceiptOperationsMode>(
                key: ValueKey('operations-mode-$_revision-${scope.generation}'),
                initialValue: _mode,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Operating mode'),
                items: [
                  for (final mode in AdminReceiptOperationsMode.values)
                    DropdownMenuItem(value: mode, child: Text(mode.label)),
                ],
                onChanged: canEdit
                    ? (mode) {
                        if (mode != null) {
                          setState(() {
                            _mode = mode;
                            if (mode == AdminReceiptOperationsMode.paused) {
                              _stop = true;
                            }
                          });
                        }
                      }
                    : null,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Emergency stop'),
                subtitle: const Text(
                  'Stop new receipt operations under this policy.',
                ),
                value: _stop,
                onChanged: canEdit && _mode != AdminReceiptOperationsMode.paused
                    ? (v) => setState(() => _stop = v)
                    : null,
              ),
              field('Principal IDs (one per line)', _principals, lines: 2),
              const SizedBox(height: 12),
              field('Collection IDs (one per line)', _collections, lines: 2),
              const SizedBox(height: 12),
              field('Gateway device IDs (one per line)', _devices, lines: 2),
              const SizedBox(height: 12),
              if (senderRead.isLoading)
                const Text('Checking current Android sender evidence…'),
              if (senderRead.hasError)
                const Text(
                  'Gateway evidence is unavailable under current access. Existing IDs are retained.',
                ),
              AdminSenderPicker(
                deviceIds: _ids(_devices.text),
                snapshot: senderRead.isLoading || senderRead.hasError
                    ? null
                    : senderRead.asData?.value,
                now: now,
                enabled: canEdit,
                onChanged: (ids) {
                  if (!canEdit ||
                      _draftScope != ref.read(adminAuthSessionScopeProvider) ||
                      _draftIdentityRevision !=
                          ref.read(_adminIdentityRevisionProvider) ||
                      !value.isFresh(ref.read(adminClockProvider)()) ||
                      !_senderEvidenceReady(ref.read(adminClockProvider)()) ||
                      ids.length != _ids(_devices.text).length ||
                      ids.toSet().length != ids.length ||
                      ids
                          .toSet()
                          .difference(_ids(_devices.text).toSet())
                          .isNotEmpty ||
                      _ids(
                        _devices.text,
                      ).toSet().difference(ids.toSet()).isNotEmpty) {
                    return;
                  }
                  setState(() => _devices.text = ids.join('\n'));
                },
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: control.busy
                      ? null
                      : () => ref.invalidate(
                          adminGatewayDevicesProvider(_senderQuery),
                        ),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh sender evidence'),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Action and SMS segment limits',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Text(
                'Run limits apply to each run. Collection, device and global limits apply per UTC day. '
                'Positive limits are required when configuring scope; default zeros grant no quota.',
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    for (final entry in _caps.entries)
                      SizedBox(
                        width: constraints.maxWidth >= 640
                            ? (constraints.maxWidth - 16) / 2
                            : constraints.maxWidth,
                        child: field(
                          _capLabel(entry.key),
                          entry.value,
                          number: true,
                        ),
                      ),
                  ],
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow historical catch-up'),
                subtitle: const Text(
                  'Only immutable eligible snapshots within the configured window can be considered.',
                ),
                value: _catchup,
                onChanged: canEdit ? (v) => setState(() => _catchup = v) : null,
              ),
              field('Catch-up window (hours, 1–168)', _hours, number: true),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: canEdit && _senderEvidenceReady(now)
                      ? () => _act(value, scope, stop: false)
                      : null,
                  child: const Text('Review and apply policy'),
                ),
              ),
            ],
          );
        },
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

String _capLabel(String name) => switch (name) {
  'run_actions' => 'Actions per run',
  'group_actions' => 'Collection actions per UTC day',
  'device_actions' => 'Device actions per UTC day',
  'global_actions' => 'Global actions per UTC day',
  'run_sms_segments' => 'SMS segments per run',
  'group_sms_segments' => 'Collection SMS segments per UTC day',
  'device_sms_segments' => 'Device SMS segments per UTC day',
  _ => 'Global SMS segments per UTC day',
};
