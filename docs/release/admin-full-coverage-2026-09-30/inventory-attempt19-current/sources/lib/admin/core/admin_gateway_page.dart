part of 'admin_runtime.dart';

String _gatewayTime(DateTime value) =>
    '${adminKigaliDate(value)} · ${adminKigaliTime(value)}:${value.second.toString().padLeft(2, '0')} · Africa/Kigali';

class AdminGatewayPage extends ConsumerStatefulWidget {
  const AdminGatewayPage({this.pageSize = 20, super.key});
  final int pageSize;
  @override
  ConsumerState<AdminGatewayPage> createState() => _AdminGatewayPageState();
}

class _AdminGatewayPageState extends ConsumerState<AdminGatewayPage> {
  late AdminGatewayQuery _query = AdminGatewayQuery(limit: widget.pageSize);
  final _previous = <AdminGatewayQuery>[];
  final _requestController = TextEditingController();
  Timer? _timer;
  Object? _scope;
  bool _busy = false, _saving = false, _storageFailed = false;
  String? _message, _requestId, _lookupError, _ownerDigest;
  AdminGatewayCheckpoint? _checkpoint;
  AdminGatewayActionReceipt? _receipt;
  Map<String, dynamic>? _document;

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
    _requestController.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _previous.clear();
      _query = AdminGatewayQuery(limit: widget.pageSize);
    });
    ref.invalidate(adminGatewayDevicesProvider(_query));
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(adminAuthSessionScopeProvider);
    final store = ref.watch(adminGatewayCheckpointStoreProvider);
    final currentIdentity = _adminResolvedIdentity(
      ref.watch(adminIdentityProvider),
    );
    final sessionScope = (
      session,
      ref.watch(adminRepositoryProvider),
      currentIdentity?.userId,
      store,
    );
    if (_scope != sessionScope) {
      _scope = sessionScope;
      _previous.clear();
      _query = AdminGatewayQuery(limit: widget.pageSize);
      _checkpoint = null;
      _receipt = null;
      _document = null;
      _requestId = null;
      _message = null;
      _lookupError = null;
      _storageFailed = false;
      _requestController.clear();
      _ownerDigest =
          currentIdentity != null &&
              session != null &&
              currentIdentity.userId == session.key.userId
          ? adminGatewayOwnerDigest(currentIdentity.userId)
          : null;
      if (_ownerDigest != null &&
          _gatewayCanRead(currentIdentity) &&
          store != null) {
        try {
          final saved = store.read(_ownerDigest!);
          if (saved != null) {
            _checkpoint = AdminGatewayCheckpoint.parse(saved, _ownerDigest!);
            _requestController.text = _checkpoint!.requestId;
            _message =
                'A reviewed device request was recovered from this tab. Check the original request before another device change.';
          }
        } catch (_) {
          _storageFailed = true;
          _message =
              'The recovery checkpoint could not be read. Device changes are unavailable in this tab.';
        }
      }
    }
    final identityState = ref.watch(adminIdentityProvider);
    if (identityState.isLoading) {
      return const AdminLoadingState(
        title: 'Checking gateway access',
        message: 'Checking current Admin permissions.',
      );
    }
    final identity = _adminResolvedIdentity(identityState);
    if (!_gatewayCanRead(identity)) {
      return const AdminDeniedPage(
        requiredPermission: 'notifications.read and system_health.read',
      );
    }
    final devices = ref.watch(adminGatewayDevicesProvider(_query));
    final now = ref.watch(adminClockProvider)();
    final snapshot = devices.isLoading ? null : devices.asData?.value;
    final fresh = snapshot?.isFresh(now) == true;
    final canManage =
        _gatewayCanManage(identity) &&
        fresh &&
        !_busy &&
        _checkpoint == null &&
        _ownerDigest != null &&
        store != null &&
        !_storageFailed;
    final request = _requestId == null
        ? null
        : ref.watch(adminGatewayRequestProvider(_requestId!));
    return AdminPage(
      title: 'SMS Gateway',
      subtitle:
          'Collect platform · Organization-owned Android devices · Africa/Kigali',
      trailing: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          OutlinedButton.icon(
            onPressed: devices.isLoading || _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh devices'),
          ),
          if (_gatewayCanManage(identity))
            FilledButton.icon(
              onPressed: canManage ? _enroll : null,
              icon: const Icon(Icons.phonelink_ring_outlined),
              label: const Text('Enroll device'),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const InfoSecurityBanner(
            title: 'Dispatch authority pending',
            message:
                'Device enrollment and activation establish gateway identity. SMS dispatch is unavailable in this foundation. Handset reports and OS callbacks do not establish carrier delivery.',
            tone: CollectStatusTone.warning,
          ),
          const SizedBox(height: 16),
          if (_gatewayCanManage(identity) && !canManage)
            Text(
              _checkpoint != null
                  ? 'Resolve the original request before starting another device change.'
                  : _ownerDigest == null || store == null || _storageFailed
                  ? 'A current session and verified same-tab recovery storage are required before changing a device.'
                  : !fresh
                  ? 'Refresh a current device sample before changing gateway identity.'
                  : 'A device change is in progress.',
            ),
          if (_saving) ...[
            const SizedBox(height: 8),
            Semantics(
              label: 'Recording gateway identity action',
              child: const LinearProgressIndicator(),
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 12),
            Semantics(liveRegion: true, child: Text(_message!)),
          ],
          if (_receipt != null) ...[
            const SizedBox(height: 16),
            _GatewayReceiptView(receipt: _receipt!),
          ],
          if (_document != null) ...[
            const SizedBox(height: 12),
            _GatewayEnrollmentDocument(document: _document!),
          ],
          const SizedBox(height: 24),
          _gatewayHeading(context, 'Devices'),
          const SizedBox(height: 12),
          devices.when(
            skipLoadingOnRefresh: false,
            loading: () =>
                const _GatewayLoading('Loading gateway device observations'),
            error: (error, _) => _GatewayReadError(error: error),
            data: (data) => !data.isFresh(now)
                ? const _GatewayNotice(
                    title: 'Device sample expired',
                    message:
                        'Previous states, health measurements and counts are hidden. Refresh devices for a current read.',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Checked ${_gatewayTime(data.checkedAt)}'),
                      const SizedBox(height: 8),
                      Text(
                        'This page: ${data.rows.length} of ${data.total} enrolled devices',
                      ),
                      if (data.rows.isEmpty) ...[
                        const SizedBox(height: 16),
                        const _GatewayNotice(
                          title: 'No enrolled devices',
                          message:
                              'An authorized owner can review the handset public identity and enroll a pending device.',
                        ),
                      ],
                      for (final device in data.rows) ...[
                        const SizedBox(height: 16),
                        _device(device, now, canManage),
                      ],
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: _previous.isEmpty || _busy
                                ? null
                                : () {
                                    setState(
                                      () => _query = _previous.removeLast(),
                                    );
                                  },
                            child: const Text('Previous devices'),
                          ),
                          OutlinedButton(
                            onPressed: data.nextCursor == null || _busy
                                ? null
                                : () {
                                    final cursor = data.nextCursor!;
                                    setState(() {
                                      _previous.add(_query);
                                      _query = AdminGatewayQuery(
                                        limit: widget.pageSize,
                                        beforeEnrolledAt: cursor.enrolledAt,
                                        beforeDeviceId: cursor.deviceId,
                                      );
                                    });
                                  },
                            child: const Text('Next devices'),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 28),
          _gatewayHeading(context, 'Check a device action'),
          const SizedBox(height: 8),
          const Text(
            'Look up your original request ID after a response is interrupted. This reads immutable operation evidence without resubmitting a change.',
          ),
          if (_checkpoint != null) ...[
            const SizedBox(height: 8),
            const Text(
              'Original request retained. A new sign-in must pass current authority; recovery does not resubmit this device change.',
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _requestController,
            key: const Key('gateway-request-lookup'),
            maxLength: 36,
            autocorrect: false,
            enableSuggestions: false,
            readOnly: _checkpoint != null,
            decoration: InputDecoration(
              labelText: 'Original request ID',
              errorText: _lookupError,
            ),
            onChanged: (_) => setState(() => _lookupError = null),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: request?.isLoading == true || _busy ? null : _lookup,
              icon: const Icon(Icons.manage_search_outlined),
              label: const Text('Check original request'),
            ),
          ),
          if (request != null) ...[
            const SizedBox(height: 16),
            request.when(
              skipLoadingOnRefresh: false,
              loading: () =>
                  const _GatewayLoading('Checking original gateway request'),
              error: (error, _) => _GatewayReadError(error: error),
              data: (data) => !data.isFresh(now)
                  ? const _GatewayNotice(
                      title: 'Request read expired',
                      message:
                          'Check the original request again. No device change has been resubmitted.',
                    )
                  : !data.recorded
                  ? const _GatewayNotice(
                      title: 'Request outcome unknown',
                      message:
                          'No matching operation is recorded for this Admin at this check. An in-flight request may still commit; this is not evidence of failure. Check the same request ID again.',
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Checked ${_gatewayTime(data.checkedAt)}'),
                        const SizedBox(height: 8),
                        _GatewayReceiptView(receipt: data.receipt!),
                        if (data.action == AdminGatewayOwnerAction.enroll) ...[
                          const SizedBox(height: 12),
                          _GatewayEnrollmentDocument(
                            document: data.identity!.enrollmentDocument,
                          ),
                        ],
                        if (_checkpoint != null && _checkpoint!.matches(data))
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () => _useRecordedResult(data),
                              child: const Text(
                                'Use recorded result and refresh',
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }

  void _useRecordedResult(AdminGatewayRequestSnapshot data) {
    final checkpoint = _checkpoint;
    final identity = _adminResolvedIdentity(ref.read(adminIdentityProvider));
    final session = ref.read(adminAuthSessionScopeProvider);
    final currentRead = _requestId == null
        ? null
        : ref.read(adminGatewayRequestProvider(_requestId!));
    if (checkpoint == null ||
        !checkpoint.matches(data) ||
        !data.isFresh(ref.read(adminClockProvider)()) ||
        currentRead?.isLoading == true ||
        currentRead?.hasError == true ||
        currentRead?.asData?.value != data ||
        _ownerDigest != checkpoint.ownerDigest ||
        session == null ||
        session.key.userId != identity?.userId ||
        !_gatewayCanRead(identity)) {
      return;
    }
    try {
      final store = ref.read(adminGatewayCheckpointStoreProvider)!;
      _clearSavedCheckpoint(store, checkpoint);
    } catch (_) {
      setState(
        () => _message =
            'The recorded result is known, but its recovery checkpoint could not be cleared. The original request is retained.',
      );
      return;
    }
    setState(() {
      _checkpoint = null;
      _message =
          'Original request resolved. Refresh devices for the current identity state.';
    });
    _refresh();
  }

  void _clearSavedCheckpoint(
    AdminGatewayCheckpointStore store,
    AdminGatewayCheckpoint checkpoint,
  ) {
    final saved = store.read(checkpoint.ownerDigest);
    if (saved != null &&
        AdminGatewayCheckpoint.parse(saved, checkpoint.ownerDigest).encode() !=
            checkpoint.encode()) {
      throw const FormatException('Recovery checkpoint changed.');
    }
    store.clear(checkpoint.ownerDigest);
    if (store.read(checkpoint.ownerDigest) != null) {
      throw const FormatException('Recovery checkpoint remains stored.');
    }
  }

  void _lookup() {
    try {
      final id = gatewayUuid(_requestController.text.trim().toLowerCase());
      setState(() {
        _requestId = id;
        _lookupError = null;
      });
      ref.invalidate(adminGatewayRequestProvider(id));
    } on FormatException {
      setState(
        () => _lookupError = 'Enter the complete original request UUID.',
      );
    }
  }

  Widget _device(AdminGatewayDevice device, DateTime now, bool canManage) {
    final health = device.health;
    final freshHealth = health?.isFresh(now) == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Semantics(
                  label: 'Gateway device ${device.identity.deviceId}',
                  child: Text(
                    'Device ${device.identity.deviceId.substring(0, 8)}…${device.identity.deviceId.substring(30)}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                AdminStatusChip(
                  label: 'Identity ${device.state.name}',
                  tone: device.state == AdminGatewayDeviceState.revoked
                      ? CollectStatusTone.danger
                      : CollectStatusTone.info,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Enrolled ${_gatewayTime(device.enrolledAt)}'),
            if (device.activatedAt != null)
              Text('Activated ${_gatewayTime(device.activatedAt!)}'),
            if (device.revokedAt != null)
              Text('Revoked ${_gatewayTime(device.revokedAt!)}'),
            const SizedBox(height: 16),
            Text(
              'Handset observations',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (health == null)
              const Text(
                'No handset report recorded. Permission, network, telephony and SIM state are unknown.',
              )
            else ...[
              Align(
                alignment: Alignment.centerLeft,
                child: AdminStatusChip(
                  label: freshHealth ? 'Recent report' : 'Report expired',
                  tone: freshHealth
                      ? CollectStatusTone.info
                      : CollectStatusTone.warning,
                ),
              ),
              const SizedBox(height: 8),
              Text('Handset reported ${_gatewayTime(health.reportedAt)}'),
              Text('Backend recorded ${_gatewayTime(health.ingestedAt)}'),
              Text('Observation expires ${_gatewayTime(health.validUntil)}'),
              const SizedBox(height: 12),
              if (!freshHealth)
                const Text(
                  'Previous health values are hidden. Refreshing the list does not renew an old handset report.',
                )
              else
                Wrap(
                  spacing: 24,
                  runSpacing: 16,
                  children: [
                    _GatewayDimension(
                      'SMS permission',
                      health.smsPermission
                          ? 'Reported allowed'
                          : 'Reported denied',
                    ),
                    _GatewayDimension('Network validation', health.network),
                    _GatewayDimension('Telephony', health.telephony),
                    _GatewayDimension(
                      'SIM selection',
                      health.simSelected ? 'Selected' : 'Not selected',
                    ),
                    _GatewayDimension(
                      'Local dispatch pause',
                      health.localPause
                          ? 'Paused on handset'
                          : 'Not locally paused',
                    ),
                  ],
                ),
            ],
            const SizedBox(height: 16),
            Text(
              'OS callback observations',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '${device.callbackTotal} recorded · ${device.sentCallbacks} sent callbacks · ${device.deliveryCallbacks} delivery callbacks',
            ),
            const Text(
              'Raw OS observations only. These counts do not prove physical delivery or change payment, ledger or receipt outcomes.',
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Identity and recorded action'),
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _GatewayEvidenceField(
                      'Device ID',
                      device.identity.deviceId,
                    ),
                    _GatewayEvidenceField(
                      'Installation ID',
                      device.identity.installationId,
                    ),
                    _GatewayEvidenceField(
                      'Public key fingerprint',
                      device.identity.keySha256,
                    ),
                    _GatewayEvidenceField(
                      'Signing certificate fingerprint',
                      device.identity.signingCertificateSha256,
                    ),
                    if (device.lastOwnerAction case final evidence?)
                      _GatewayReceiptView(receipt: evidence.receipt)
                    else
                      const Text(
                        'No owner action receipt is available in this sample.',
                      ),
                    const SizedBox(height: 12),
                    _GatewayEnrollmentDocument(
                      document: device.identity.enrollmentDocument,
                    ),
                  ],
                ),
              ],
            ),
            if (_gatewayCanManage(
                  _adminResolvedIdentity(ref.watch(adminIdentityProvider)),
                ) &&
                device.state != AdminGatewayDeviceState.revoked) ...[
              const SizedBox(height: 16),
              if (device.state == AdminGatewayDeviceState.pending &&
                  !freshHealth)
                const Text(
                  'Activation requires a recent key-possession report for this identity.',
                ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (device.state == AdminGatewayDeviceState.pending)
                    OutlinedButton(
                      onPressed: canManage && freshHealth
                          ? () => _changeDevice(
                              device,
                              AdminGatewayOwnerAction.activate,
                            )
                          : null,
                      child: const Text('Activate identity'),
                    ),
                  OutlinedButton(
                    onPressed: canManage
                        ? () => _changeDevice(
                            device,
                            AdminGatewayOwnerAction.revoke,
                          )
                        : null,
                    child: const Text('Revoke identity'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _enroll() => _reviewAndPerform(
    (scope) => _showAdminFormDialog<AdminGatewayOwnerIntent>(
      context: context,
      builder: (_) => _GatewayEnrollmentDialog(scope: scope),
    ),
  );

  Future<void> _changeDevice(
    AdminGatewayDevice device,
    AdminGatewayOwnerAction action,
  ) => _reviewAndPerform((scope) {
    final intent = AdminGatewayOwnerIntent.change(
      action: action,
      requestId: const Uuid().v4(),
      deviceId: device.identity.deviceId,
      keySha256: device.identity.keySha256,
      signingCertificateSha256: device.identity.signingCertificateSha256,
    );
    return _showAdminFormDialog<AdminGatewayOwnerIntent>(
      context: context,
      builder: (dialogContext) => _AdminSessionDialog(
        scope: scope,
        child: AlertDialog(
          title: Text(
            action == AdminGatewayOwnerAction.activate
                ? 'Activate gateway identity'
                : 'Revoke gateway identity',
          ),
          scrollable: true,
          content: SizedBox(
            width: 640,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action == AdminGatewayOwnerAction.activate
                      ? 'Activation accepts this enrolled identity after recent key possession. Dispatch authority remains pending.'
                      : 'Revocation blocks new device heartbeats and future authority. It cannot recall a message already handed off; retained callback observations remain evidence.',
                ),
                const SizedBox(height: 16),
                _GatewayEvidenceField('Device ID', intent.deviceId!),
                _GatewayEvidenceField(
                  'Public key fingerprint',
                  intent.keySha256,
                ),
                _GatewayEvidenceField(
                  'Signing certificate fingerprint',
                  intent.signingCertificateSha256,
                ),
                _GatewayEvidenceField('Request ID', intent.requestId),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (scope.isCurrent) Navigator.pop(dialogContext, intent);
              },
              child: Text(
                action == AdminGatewayOwnerAction.activate
                    ? 'Activate identity'
                    : 'Revoke identity',
              ),
            ),
          ],
        ),
      ),
    );
  });

  Future<void> _reviewAndPerform(
    Future<AdminGatewayOwnerIntent?> Function(_AdminActionScope) review,
  ) async {
    if (_busy ||
        _checkpoint != null ||
        _ownerDigest == null ||
        _storageFailed ||
        !_gatewayCanManage(
          _adminResolvedIdentity(ref.read(adminIdentityProvider)),
        )) {
      return;
    }
    final scope = _AdminActionScope(ref);
    final ownerDigest = _ownerDigest!;
    final store = ref.read(adminGatewayCheckpointStoreProvider);
    if (store == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    AdminGatewayOwnerIntent? intent;
    var submitted = false;
    try {
      intent = await review(scope);
      if (!mounted || intent == null || !scope.isCurrent) return;
      final actor = await scope.repository.currentIdentity();
      if (!mounted || !scope.isCurrent) return;
      if (actor?.userId != scope.actorId || !_gatewayCanManage(actor)) {
        throw const AdminGatewayDenied();
      }
      final data = ref.read(adminGatewayDevicesProvider(_query));
      if (data.isLoading ||
          data.hasError ||
          data.asData?.value.isFresh(ref.read(adminClockProvider)()) != true) {
        throw const FormatException('Current gateway sample required.');
      }
      final devices = data.asData!.value.rows;
      final currentDevice = intent.deviceId == null
          ? null
          : devices
                .where((device) => device.identity.deviceId == intent!.deviceId)
                .firstOrNull;
      if (intent.deviceId != null &&
          (currentDevice == null ||
              currentDevice.identity.keySha256 != intent.keySha256 ||
              currentDevice.identity.signingCertificateSha256 !=
                  intent.signingCertificateSha256)) {
        throw const FormatException('Reviewed gateway identity changed.');
      }
      final checkpoint = AdminGatewayCheckpoint(
        ownerDigest: ownerDigest,
        action: intent.action,
        requestId: intent.requestId,
        installationId:
            intent.publicIdentity?.installationId ??
            currentDevice!.identity.installationId,
        deviceId: intent.deviceId,
        keySha256: intent.keySha256,
        signingCertificateSha256: intent.signingCertificateSha256,
      );
      try {
        store.write(ownerDigest, checkpoint.encode());
        final saved = store.read(ownerDigest);
        if (saved == null ||
            AdminGatewayCheckpoint.parse(saved, ownerDigest).encode() !=
                checkpoint.encode()) {
          throw const FormatException('Recovery checkpoint not acknowledged.');
        }
      } catch (_) {
        _storageFailed = true;
        rethrow;
      }
      if (!mounted ||
          !scope.isCurrent ||
          _ownerDigest != ownerDigest ||
          ref.read(adminGatewayCheckpointStoreProvider) != store) {
        return;
      }
      setState(() {
        _checkpoint = checkpoint;
        _requestController.text = checkpoint.requestId;
        _saving = true;
      });
      submitted = true;
      final receipt = await scope.repository.gatewayOwnerAction(intent);
      if (!mounted ||
          !scope.isCurrent ||
          _ownerDigest != ownerDigest ||
          ref.read(adminGatewayCheckpointStoreProvider) != store) {
        return;
      }
      _clearSavedCheckpoint(store, checkpoint);
      setState(() {
        _checkpoint = null;
        _receipt = receipt;
        _document = intent!.publicIdentity?.enrollmentDocument(
          receipt.deviceId,
        );
        _message =
            'Device action recorded. Its receipt describes the action time. Refreshing the current device state.';
      });
      _refresh();
    } catch (error) {
      if (!mounted ||
          !scope.isCurrent ||
          _ownerDigest != ownerDigest ||
          ref.read(adminGatewayCheckpointStoreProvider) != store)
        return;
      final refused =
          !submitted ||
          error is AdminGatewayDenied ||
          error is UnsupportedError ||
          error is PostgrestException &&
              {'42501', '22023', '55000'}.contains(error.code);
      if (refused && _checkpoint != null) {
        try {
          _clearSavedCheckpoint(store, _checkpoint!);
          if (store.read(ownerDigest) == null) _checkpoint = null;
        } catch (_) {
          // A refused action is known, but a failed storage clear stays recoverable.
        }
      }
      setState(() {
        _message = refused
            ? error is PostgrestException && error.code == '55000'
                  ? 'Device change refused. Refresh its state and obtain a recent handset report before activation.'
                  : error is UnsupportedError
                  ? 'Device changes are unavailable from this service.'
                  : 'Device change refused or current authority unavailable. Refresh devices and check your current approval and permissions.'
            : 'Device action outcome unconfirmed. Keep the original request ID and check it before another change.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _saving = false;
        });
      }
    }
  }
}

Widget _gatewayHeading(BuildContext context, String title) => Semantics(
  header: true,
  child: Text(title, style: Theme.of(context).textTheme.titleLarge),
);

class _GatewayDimension extends StatelessWidget {
  const _GatewayDimension(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(value),
      ],
    ),
  );
}

class _GatewayReceiptView extends StatelessWidget {
  const _GatewayReceiptView({required this.receipt});
  final AdminGatewayActionReceipt receipt;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Immutable action receipt',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      _GatewayEvidenceField('Request ID', receipt.requestId),
      _GatewayEvidenceField('Device ID', receipt.deviceId),
      Text('State at action: ${receipt.stateAtAction.name}'),
      Text('Recorded ${_gatewayTime(receipt.recordedAt)}'),
      Text(
        receipt.replay
            ? 'Original result returned on replay.'
            : 'Persisted original action result.',
      ),
      const Text(
        'This historical result does not establish the current identity state or dispatch availability.',
      ),
    ],
  );
}

class _GatewayEnrollmentDocument extends StatelessWidget {
  const _GatewayEnrollmentDocument({required this.document});
  final Map<String, dynamic> document;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Handset enrollment document',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      const Text(
        'Check the current identity state, then apply this public document on the matching handset. It pairs retained identity only and cannot authorize sending.',
      ),
      const SizedBox(height: 8),
      SelectableText(const JsonEncoder.withIndent('  ').convert(document)),
    ],
  );
}

class _GatewayNotice extends StatelessWidget {
  const _GatewayNotice({required this.title, required this.message});
  final String title, message;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        liveRegion: true,
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      const SizedBox(height: 8),
      Text(message),
    ],
  );
}

class _GatewayReadError extends StatelessWidget {
  const _GatewayReadError({required this.error});
  final Object error;
  @override
  Widget build(BuildContext context) => _GatewayNotice(
    title: error is AdminGatewayDenied
        ? 'Gateway read denied'
        : error is UnsupportedError
        ? 'Gateway service unavailable'
        : error is AdminSessionChanged
        ? 'Admin session changed'
        : 'Gateway read failed',
    message: error is AdminGatewayDenied
        ? 'A current approved platform owner with notification and system-health read permissions is required.'
        : error is UnsupportedError
        ? 'This service does not expose the versioned gateway reads. No device state is assumed.'
        : error is AdminSessionChanged
        ? 'Reopen the page under your current sign-in.'
        : 'Gateway evidence could not be loaded or validated. Refresh the read; device changes are not resubmitted.',
  );
}

class _GatewayLoading extends StatelessWidget {
  const _GatewayLoading(this.label);
  final String label;
  @override
  Widget build(BuildContext context) =>
      Semantics(label: label, child: const LinearProgressIndicator());
}
