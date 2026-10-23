import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../app/theme/collect_motion.dart';
import '../../app/theme/collect_colors.dart';
import '../../app/theme/collect_radius.dart';
import '../shared/components/admin_empty_state.dart';
import '../shared/components/admin_loading_state.dart';
import '../shared/components/admin_page.dart';
import '../shared/components/admin_data_table.dart';
import 'admin_account_api.dart';
import 'admin_display_formatters.dart';
import 'admin_models.dart';
import 'admin_repository_base.dart' show adminRepositoryProvider;
import 'cloudflare_admin_operating_pages.dart';
import 'cloudflare_admin_repository.dart';
import 'cloudflare_admin_session.dart';

CloudflareAdminRepository _gatewayRepository(WidgetRef ref) =>
    ref.read(adminRepositoryProvider) as CloudflareAdminRepository;
bool _gatewayManage(WidgetRef ref) {
  final user = ref.watch(cloudflareAdminSessionProvider).asData?.value;
  return user != null &&
      user.role != AdminAccountRole.staff &&
      user.permissions.contains('gateway.manage');
}

String gatewayErrorMessage(Object error) {
  if (error is CloudflareAdminRequestException) {
    if (error.code == 'gateway_identity_policy_unavailable') {
      return 'Gateway identity policy is not configured on the server. Enrollment and activation require an approved app and signing certificate. Contact the workspace operator to configure the policy.';
    }
    if (error.code == 'gateway_identity_not_allowed') {
      return 'This app or signing certificate is not approved by the server identity policy. Review the device identity before continuing.';
    }
  }
  return error is AdminAccountException
      ? error.message
      : error is FormatException
      ? 'The device response could not be verified. Refresh before continuing.'
      : 'The device service could not be reached. Please try again.';
}

class GatewayPanel extends StatelessWidget {
  const GatewayPanel({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    color: context.collectColors.surfaceReadable,
    shape: RoundedRectangleBorder(
      side: BorderSide(color: context.collectColors.border),
      borderRadius: CollectRadius.cardBorder,
    ),
    child: Padding(padding: const EdgeInsets.all(20), child: child),
  );
}

class GatewayMessage extends StatelessWidget {
  const GatewayMessage(this.message, {this.error = false, super.key});
  final String message;
  final bool error;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: error ? Theme.of(context).colorScheme.error : null,
        ),
      ),
    ),
  );
}

AdminTableRowData _gatewayRow(
  Map<String, dynamic> values, {
  String? id,
  String? title,
}) => AdminTableRowData(
  id: id ?? values['id'] as String,
  title: title ?? '${values['label'] ?? values['id']}',
  subtitle: '',
  status: '${values['state'] ?? ''}',
  amount: '',
  extra: values,
);

String _gatewayValue(String key, Object? value) {
  if (value == null) return 'Not recorded';
  if (key.endsWith('_at') && value is String) {
    return adminKigaliDateTime(DateTime.tryParse(value));
  }
  if (value is bool) return value ? 'Yes' : 'No';
  if ({'state', 'network', 'telephony'}.contains(key)) {
    return operatingLabel('$value');
  }
  return '$value';
}

AdminTableColumn _gatewayColumn(
  String key,
  String label, {
  bool numeric = false,
}) => AdminTableColumn(
  label: label,
  numeric: numeric,
  selectable: true,
  value: (row) => _gatewayValue(key, row.extra[key]),
);

class CloudflareGatewayListPage extends ConsumerStatefulWidget {
  const CloudflareGatewayListPage({super.key});
  @override
  ConsumerState<CloudflareGatewayListPage> createState() => _GatewayListState();
}

class _GatewayListState extends ConsumerState<CloudflareGatewayListPage> {
  String _state = '';
  int _page = 0;
  late Future<({List<CloudflareGatewayDevice> rows, int total})> _future;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = _gatewayRepository(
      ref,
    ).gatewayDeviceList(state: _state, offset: _page * 25);
  }

  void _refresh() => setState(() {
    _page = 0;
    _load();
  });
  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Gateway devices',
    subtitle: 'Manage device identity for incoming MoMo payment evidence.',
    trailing: _gatewayManage(ref)
        ? FilledButton.icon(
            onPressed: () async {
              await context.push('/admin/gateway/new');
              if (mounted) _refresh();
            },
            icon: const Icon(Icons.add),
            label: const Text('Enroll device'),
          )
        : null,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => context.push('/admin/gateway/receiver-grants'),
            icon: const Icon(Icons.sms_outlined),
            label: const Text('Receiver capture grants'),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Trusted identity does not establish carrier delivery or grant SMS sending authority.',
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _state,
                isExpanded: true,
                itemHeight: null,
                decoration: const InputDecoration(labelText: 'Device state'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('All states')),
                  for (final state in ['pending', 'active', 'revoked'])
                    DropdownMenuItem(
                      value: state,
                      child: Text(operatingLabel(state)),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _state = value ?? '';
                  _page = 0;
                  _load();
                }),
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              tooltip: 'Refresh devices',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 20),
        FutureBuilder<({List<CloudflareGatewayDevice> rows, int total})>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const AdminLoadingState(title: 'Loading gateway devices');
            }
            if (snapshot.hasError) {
              return GatewayMessage(
                gatewayErrorMessage(snapshot.error!),
                error: true,
              );
            }
            final data = snapshot.data!;
            if (data.rows.isEmpty) {
              return AdminEmptyState(
                title: _state.isEmpty
                    ? 'No enrolled devices'
                    : 'No matching devices',
                message:
                    'Enroll an approved device or change the state filter and refresh.',
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AdminDataTable(
                  tableLabel: 'Gateway devices',
                  rows: [
                    for (final device in data.rows) _gatewayRow(device.values),
                  ],
                  columns: [
                    _gatewayColumn('label', 'Device'),
                    _gatewayColumn('state', 'State'),
                    _gatewayColumn('app_id', 'App ID'),
                    _gatewayColumn('last_heartbeat_at', 'Last heartbeat'),
                    _gatewayColumn('created_at', 'Created'),
                    _gatewayColumn('activated_at', 'Activated'),
                    _gatewayColumn('revoked_at', 'Revoked'),
                    _gatewayColumn('version', 'Version', numeric: true),
                    _gatewayColumn('id', 'Device ID'),
                  ],
                  onOpen: (row) async {
                    await context.push('/admin/gateway/${row.id}');
                    if (mounted) setState(_load);
                  },
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${_page * 25 + 1}–${_page * 25 + data.rows.length} of ${data.total}',
                    ),
                    OutlinedButton(
                      onPressed: _page == 0
                          ? null
                          : () => setState(() {
                              _page--;
                              _load();
                            }),
                      child: const Text('Previous'),
                    ),
                    OutlinedButton(
                      onPressed: (_page + 1) * 25 >= data.total
                          ? null
                          : () => setState(() {
                              _page++;
                              _load();
                            }),
                      child: const Text('Next'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class CloudflareGatewayEnrollPage extends StatelessWidget {
  const CloudflareGatewayEnrollPage({super.key});
  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Enroll gateway device',
    subtitle:
        'Use the public identity exported by the handset. Keep its private key on the device.',
    leading: IconButton(
      tooltip: 'Back to devices',
      onPressed: () =>
          context.canPop() ? context.pop() : context.go('/admin/gateway'),
      icon: const Icon(Icons.arrow_back),
    ),
    child: Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: const CloudflareGatewayActionForm(
          action: CloudflareGatewayAction.enroll,
        ),
      ),
    ),
  );
}

class CloudflareGatewayDetailPage extends ConsumerStatefulWidget {
  const CloudflareGatewayDetailPage({required this.id, super.key});
  final String id;
  @override
  ConsumerState<CloudflareGatewayDetailPage> createState() =>
      _GatewayDetailState();
}

class _GatewayDetailState extends ConsumerState<CloudflareGatewayDetailPage> {
  late Future<CloudflareGatewayDetail> _future;
  @override
  void initState() {
    super.initState();
    _future = _gatewayRepository(ref).gatewayDevice(widget.id);
  }

  @override
  void didUpdateWidget(covariant CloudflareGatewayDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _future = _gatewayRepository(ref).gatewayDevice(widget.id);
    }
  }

  void _refresh() => setState(
    () => _future = _gatewayRepository(ref).gatewayDevice(widget.id),
  );
  Future<void> _act(
    CloudflareGatewayAction action,
    CloudflareGatewayDetail detail,
  ) async {
    await showDialog<void>(
      context: context,
      animationStyle: CollectMotion.animationStyle(context),
      barrierDismissible: false,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        action == CloudflareGatewayAction.activate
                            ? 'Activate device'
                            : 'Revoke device',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close action',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: CloudflareGatewayActionForm(
                      action: action,
                      detail: detail,
                      onSaved: _refresh,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final manage = _gatewayManage(ref);
    return AdminPage(
      title: 'Gateway identity',
      subtitle:
          'Review the app, installation and signing fingerprints before changing trust.',
      leading: IconButton(
        tooltip: 'Back to devices',
        onPressed: () =>
            context.canPop() ? context.pop() : context.go('/admin/gateway'),
        icon: const Icon(Icons.arrow_back),
      ),
      trailing: IconButton(
        tooltip: 'Refresh device',
        onPressed: _refresh,
        icon: const Icon(Icons.refresh),
      ),
      child: FutureBuilder<CloudflareGatewayDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const AdminLoadingState(title: 'Loading device identity');
          }
          if (snapshot.hasError) {
            return GatewayMessage(
              gatewayErrorMessage(snapshot.error!),
              error: true,
            );
          }
          final detail = snapshot.data!, device = detail.device;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminDataTable(
                tableLabel: 'Gateway identity',
                rows: [_gatewayRow(device.values)],
                columns: [
                  _gatewayColumn('label', 'Device'),
                  _gatewayColumn('state', 'State'),
                  _gatewayColumn('version', 'Version', numeric: true),
                  _gatewayColumn('id', 'Device ID'),
                  _gatewayColumn('app_id', 'App ID'),
                  _gatewayColumn('installation_id', 'Installation ID'),
                  _gatewayColumn('key_sha256', 'Key SHA-256'),
                  _gatewayColumn(
                    'signing_certificate_sha256',
                    'Signing certificate SHA-256',
                  ),
                  _gatewayColumn('public_key_spki_base64', 'Public key'),
                  _gatewayColumn('created_at', 'Created'),
                  _gatewayColumn('activated_at', 'Activated'),
                  _gatewayColumn('revoked_at', 'Revoked'),
                  _gatewayColumn('last_heartbeat_at', 'Last heartbeat'),
                  _gatewayColumn('carrier_proof', 'Carrier delivery proven'),
                  _gatewayColumn('send_authority', 'SMS sending authority'),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Carrier delivery is unproven. SMS sending authority is not granted by this device state.',
              ),
              const SizedBox(height: 16),
              if (manage && detail.canManage && device.state != 'revoked')
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    if (device.state == 'pending')
                      FilledButton(
                        onPressed: () =>
                            _act(CloudflareGatewayAction.activate, detail),
                        child: const Text('Activate device'),
                      ),
                    OutlinedButton(
                      onPressed: () =>
                          _act(CloudflareGatewayAction.revoke, detail),
                      child: const Text('Revoke device'),
                    ),
                  ],
                ),
              if (device.state == 'revoked')
                const GatewayMessage(
                  'Revocation is permanent. Enroll a new installation to establish a new identity.',
                ),
              const SizedBox(height: 24),
              Text(
                'Enrollment response',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              AdminDataTable(
                tableLabel: 'Enrollment response',
                rows: [
                  _gatewayRow(
                    detail.enrollment,
                    id: device.id,
                    title: device.label,
                  ),
                ],
                columns: [
                  _gatewayColumn(
                    'contract_version',
                    'Contract version',
                    numeric: true,
                  ),
                  _gatewayColumn('device_id', 'Device ID'),
                  _gatewayColumn('installation_id', 'Installation ID'),
                  _gatewayColumn('key_sha256', 'Key SHA-256'),
                  _gatewayColumn(
                    'signing_certificate_sha256',
                    'Signing certificate SHA-256',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Recent heartbeats',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (detail.heartbeats.isEmpty)
                const GatewayMessage('No heartbeat evidence recorded.')
              else
                GatewayMessage(
                  '${detail.heartbeats.length} heartbeat records returned. Last recorded: ${device.values['last_heartbeat_at'] ?? 'Not recorded'}. Heartbeats do not establish payment settlement or carrier delivery.',
                ),
              if (detail.truncated)
                const GatewayMessage('Showing the latest 100 observations.'),
              if (detail.heartbeats.isNotEmpty)
                AdminDataTable(
                  tableLabel: 'Recent heartbeats',
                  rows: [
                    for (final heartbeat in detail.heartbeats)
                      _gatewayRow(
                        heartbeat,
                        id: heartbeat['observation_id'] as String,
                        title: 'Heartbeat observation',
                      ),
                  ],
                  columns: [
                    _gatewayColumn('reported_at', 'Reported'),
                    _gatewayColumn('issued_at', 'Issued'),
                    _gatewayColumn('ingested_at', 'Ingested'),
                    _gatewayColumn('network', 'Network'),
                    _gatewayColumn('telephony', 'Telephony'),
                    _gatewayColumn('sms_permission', 'SMS permission observed'),
                    _gatewayColumn('sim_selected', 'SIM selected'),
                    _gatewayColumn(
                      'sim_revision_sha256',
                      'SIM revision SHA-256',
                    ),
                    _gatewayColumn('local_pause', 'Locally paused'),
                    _gatewayColumn('carrier_proof', 'Carrier delivery proven'),
                    _gatewayColumn('send_authority', 'SMS sending authority'),
                    _gatewayColumn('observation_id', 'Observation ID'),
                    _gatewayColumn('request_id', 'Request ID'),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

class CloudflareGatewayActionForm extends ConsumerStatefulWidget {
  const CloudflareGatewayActionForm({
    required this.action,
    this.detail,
    this.onSaved,
    super.key,
  });
  final CloudflareGatewayAction action;
  final CloudflareGatewayDetail? detail;
  final VoidCallback? onSaved;
  @override
  ConsumerState<CloudflareGatewayActionForm> createState() =>
      _GatewayActionState();
}

class _GatewayActionState extends ConsumerState<CloudflareGatewayActionForm> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  final _fields = {
    for (final key in [
      'label',
      'app_id',
      'installation_id',
      'public_key_spki_base64',
      'key_sha256',
      'signing_certificate_sha256',
    ])
      key: TextEditingController(),
  };
  bool _busy = false,
      _checking = false,
      _confirmed = false,
      _retryAllowed = false;
  String? _error, _unknownKey;
  Map<String, dynamic>? _pending;
  CloudflareOperationReceipt? _receipt;
  bool get _enroll => widget.action == CloudflareGatewayAction.enroll;
  bool get _locked => _busy || _unknownKey != null || _receipt != null;
  @override
  void dispose() {
    _reason.dispose();
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  String? _validate(String key, String? input) {
    final value = input?.trim() ?? '';
    if (value.isEmpty) return 'Enter ${operatingLabel(key).toLowerCase()}.';
    if (key == 'label' && (value.length < 2 || value.length > 120)) {
      return 'Use 2–120 characters.';
    }
    if (key == 'app_id' &&
        (value.length > 160 ||
            !RegExp(
              r'^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$',
            ).hasMatch(value))) {
      return 'Use the Android package identifier from the device.';
    }
    if (key == 'installation_id' &&
        !RegExp(
          r'^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$',
        ).hasMatch(value)) {
      return 'Use the lowercase installation UUID from the device.';
    }
    if (key.endsWith('sha256') && !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
      return 'Use 64 lowercase hexadecimal characters.';
    }
    if (key == 'public_key_spki_base64' && value.length != 124) {
      return 'Use the canonical Base64 P-256 public key exported by the device.';
    }
    return null;
  }

  Future<void> _review() async {
    if (_locked || !(_form.currentState?.validate() ?? false)) return;
    if (!_enroll && !_confirmed) {
      setState(
        () => _error =
            'Compare the key and certificate fingerprints, then confirm your review.',
      );
      return;
    }
    final values = widget.detail?.device.values;
    final body = <String, dynamic>{
      'reason': _reason.text.trim(),
      if (_enroll)
        for (final entry in _fields.entries) entry.key: entry.value.text.trim(),
      if (!_enroll) ...{
        'expected_version': widget.detail!.device.version,
        'expected_key_sha256': values!['key_sha256'],
        'expected_signing_certificate_sha256':
            values['signing_certificate_sha256'],
      },
    };
    if (_enroll &&
        !validCloudflareGatewayKey(
          body['public_key_spki_base64'],
          body['key_sha256'],
        )) {
      setState(
        () => _error =
            'The public key does not match its SHA-256 fingerprint. Copy the matching public identity from the device.',
      );
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      animationStyle: CollectMotion.animationStyle(context),
      builder: (context) => AlertDialog(
        title: Text('${operatingLabel(widget.action.name)} device?'),
        content: SizedBox(
          width: 580,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.action == CloudflareGatewayAction.revoke
                      ? 'Revocation permanently removes this installation’s trusted status.'
                      : 'This records device trust for incoming evidence. It does not grant SMS sending authority.',
                ),
                const SizedBox(height: 16),
                AdminDataTable(
                  tableLabel: 'Device change confirmation',
                  rows: [_gatewayRow(body, id: 'confirmation')],
                  columns: [
                    for (final key in body.keys.where(
                      (key) => key != 'public_key_spki_base64',
                    ))
                      AdminTableColumn(
                        label: operatingLabel(key),
                        selectable: true,
                        value: (row) => _gatewayValue(key, row.extra[key]),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back to review'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm device change'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) await _send(body, const Uuid().v4());
  }

  Future<void> _send(Map<String, dynamic> body, String key) async {
    setState(() {
      _busy = true;
      _error = null;
      _retryAllowed = false;
    });
    _pending = body;
    try {
      final receipt = await _gatewayRepository(ref).gatewayAction(
        widget.action,
        id: widget.detail?.device.id,
        key: key,
        body: body,
      );
      if (!mounted) return;
      setState(() {
        _receipt = receipt;
        _unknownKey = null;
      });
      widget.onSaved?.call();
    } catch (error) {
      if (mounted) {
        final unknown =
            error is! CloudflareAdminRequestException || error.outcomeUnknown;
        setState(() {
          _error = gatewayErrorMessage(error);
          _unknownKey = unknown ? key : null;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      final result = await _gatewayRepository(
        ref,
      ).operatingRequest(_unknownKey!);
      if (!mounted) return;
      if (result['status'] == 'succeeded') {
        final receipt = CloudflareOperationReceipt.parse(
          Map<String, dynamic>.from(result['receipt'] as Map),
        );
        if (receipt.resourceType != 'gateway_devices' ||
            receipt.version !=
                (_enroll ? 1 : widget.detail!.device.version + 1) ||
            !_enroll && receipt.resourceId != widget.detail!.device.id) {
          throw const FormatException('Unexpected receipt.');
        }
        setState(() {
          _receipt = receipt;
          _unknownKey = null;
          _error = null;
        });
        widget.onSaved?.call();
      } else {
        setState(() {
          _retryAllowed = result['status'] == 'not_found';
          _error = result['status'] == 'not_found'
              ? 'No request is recorded. Check again, or explicitly retry the same device request after resolving its cause.'
              : 'The request is still unresolved. Check again before changing the device.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = gatewayErrorMessage(error));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_gatewayManage(ref) || widget.detail?.canManage == false) {
      return const GatewayMessage(
        'Your account can view device identities but cannot change them.',
      );
    }
    if (_receipt != null) return CloudflareReceiptView(receipt: _receipt!);
    return GatewayPanel(
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_enroll)
              for (final entry in _fields.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: TextFormField(
                    controller: entry.value,
                    enabled: !_locked,
                    minLines: entry.key == 'public_key_spki_base64' ? 3 : 1,
                    maxLines: entry.key == 'public_key_spki_base64' ? 4 : 2,
                    decoration: InputDecoration(
                      labelText: switch (entry.key) {
                        'app_id' => 'Android app ID',
                        'installation_id' => 'Installation ID',
                        'public_key_spki_base64' => 'Public key (SPKI Base64)',
                        'key_sha256' => 'Public key SHA-256',
                        'signing_certificate_sha256' =>
                          'Signing certificate SHA-256',
                        _ => 'Device label',
                      },
                    ),
                    validator: (value) => _validate(entry.key, value),
                  ),
                ),
            if (!_enroll) ...[
              Text(
                widget.detail!.device.label,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              const Text('Public key SHA-256'),
              SelectableText(
                widget.detail!.device.values['key_sha256'] as String,
              ),
              const SizedBox(height: 12),
              const Text('Signing certificate SHA-256'),
              SelectableText(
                widget.detail!.device.values['signing_certificate_sha256']
                    as String,
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _confirmed,
                onChanged: _locked
                    ? null
                    : (value) => setState(() => _confirmed = value ?? false),
                title: const Text(
                  'I compared both fingerprints with the device and confirmed this installation.',
                ),
              ),
            ],
            TextFormField(
              controller: _reason,
              enabled: !_locked,
              minLines: 2,
              maxLines: 4,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'Reason for device change',
              ),
              validator: (value) => (value?.trim().length ?? 0) < 8
                  ? 'Provide a reason of at least 8 characters.'
                  : null,
            ),
            if (_error != null) GatewayMessage(_error!, error: true),
            if (_unknownKey != null) ...[
              const GatewayMessage(
                'The outcome is unconfirmed. Check the server receipt before another change.',
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
                  if (_retryAllowed)
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _send(_pending!, _unknownKey!),
                      child: const Text('Retry identical request'),
                    ),
                  TextButton(
                    onPressed: () =>
                        context.go('/admin/requests?key=$_unknownKey'),
                    child: const Text('Open request lookup'),
                  ),
                ],
              ),
            ] else
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _locked ? null : _review,
                  child: Text(_busy ? 'Saving…' : 'Review device change'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
