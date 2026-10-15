import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../shared/components/admin_data_table.dart';
import '../shared/components/admin_loading_state.dart';
import '../shared/components/admin_page.dart';
import 'admin_account_api.dart';
import 'admin_display_formatters.dart';
import 'admin_pending_attempt_store.dart';
import 'admin_repository_base.dart';
import 'cloudflare_admin_gateway_pages.dart';
import 'cloudflare_admin_receiver_api.dart';
import 'cloudflare_admin_repository.dart';
import 'cloudflare_admin_session.dart';

AdminTableRowData _row(Map<String, dynamic> values) => AdminTableRowData(
  id: '${values['id'] ?? values['request_id'] ?? 'review'}',
  title: '${values['device_label'] ?? values['id'] ?? 'Capture grant'}',
  subtitle: '',
  status: '',
  amount: '',
  extra: values,
);
String _value(String field, Object? value) => value == null
    ? '—'
    : value is bool
    ? (value ? 'Yes' : 'No')
    : field.endsWith('_at') && value is String
    ? adminKigaliDateTime(DateTime.tryParse(value))
    : '$value';
AdminTableColumn _column(String field, String label) => AdminTableColumn(
  label: label,
  selectable: true,
  value: (row) => _value(field, row.extra[field]),
);
final _grantColumns = [
  _column('device_label', 'Device'),
  _column('payee_label', 'Payee'),
  _column('payee_momo_number_or_code', 'Payee MoMo'),
  _column('status', 'Status'),
  _column('created_at', 'Created'),
  _column('revoked_at', 'Revoked'),
  _column('version', 'Version'),
  _column('capture_authority', 'Receipt capture'),
  _column('send_authority', 'Sending authority'),
  _column('financial_authority', 'Financial authority'),
  _column('id', 'Grant ID'),
];

class CloudflareReceiverGrantListPage extends ConsumerStatefulWidget {
  const CloudflareReceiverGrantListPage({super.key});
  @override
  ConsumerState<CloudflareReceiverGrantListPage> createState() =>
      _GrantListState();
}

class _GrantListState extends ConsumerState<CloudflareReceiverGrantListPage> {
  int _offset = 0;
  String _status = '';
  late Future<({List<ReceiverCaptureGrant> rows, int total})> _future;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = ref
        .read(cloudflareAdminReceiverApiProvider)
        .grants(status: _status, offset: _offset);
  }

  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Receiver capture grants',
    subtitle:
        'An active grant links one enrolled device to one recorded payee for incoming receipt evidence.',
    leading: IconButton(
      tooltip: 'Back to gateway devices',
      onPressed: () => context.go('/admin/gateway'),
      icon: const Icon(Icons.arrow_back),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Capture does not grant SMS sending, payment confirmation or allocation authority.',
        ),
        if (ref.watch(cloudflareAdminReceiverApiProvider).canManage) ...[
          const SizedBox(height: 16),
          CloudflareReceiverGrantForm(onSaved: () => setState(_load)),
          const SizedBox(height: 24),
        ],
        DropdownButtonFormField<String>(
          initialValue: _status,
          decoration: const InputDecoration(labelText: 'Capture grant status'),
          items: const [
            DropdownMenuItem(value: '', child: Text('All statuses')),
            DropdownMenuItem(value: 'active', child: Text('Active')),
            DropdownMenuItem(value: 'revoked', child: Text('Revoked')),
          ],
          onChanged: (v) => setState(() {
            _status = v ?? '';
            _offset = 0;
            _load();
          }),
        ),
        const SizedBox(height: 16),
        FutureBuilder<({List<ReceiverCaptureGrant> rows, int total})>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const AdminLoadingState(title: 'Loading capture grants');
            }
            if (snapshot.hasError) {
              return GatewayMessage(
                gatewayErrorMessage(snapshot.error!),
                error: true,
              );
            }
            final data = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (data.rows.isEmpty)
                  const Text('No capture grants match this page.'),
                AdminDataTable(
                  tableLabel: 'Receiver capture grants',
                  rows: [for (final grant in data.rows) _row(grant.values)],
                  columns: _grantColumns,
                  onOpen: (row) =>
                      context.push('/admin/gateway/receiver-grants/${row.id}'),
                ),
                _Paging(
                  offset: _offset,
                  total: data.total,
                  count: data.rows.length,
                  onChange: (v) => setState(() {
                    _offset = v;
                    _load();
                  }),
                ),
                TextButton.icon(
                  onPressed: () => setState(_load),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh capture grants'),
                ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _Paging extends StatelessWidget {
  const _Paging({
    required this.offset,
    required this.total,
    required this.count,
    required this.onChange,
  });
  final int offset, total, count;
  final ValueChanged<int> onChange;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text('${count == 0 ? 0 : offset + 1}–${offset + count} of $total'),
      OutlinedButton(
        onPressed: offset == 0
            ? null
            : () => onChange((offset - 25).clamp(0, 2147483647)),
        child: const Text('Previous'),
      ),
      OutlinedButton(
        onPressed: offset + count >= total ? null : () => onChange(offset + 25),
        child: const Text('Next'),
      ),
    ],
  );
}

class CloudflareReceiverGrantDetailPage extends ConsumerStatefulWidget {
  const CloudflareReceiverGrantDetailPage({required this.id, super.key});
  final String id;
  @override
  ConsumerState<CloudflareReceiverGrantDetailPage> createState() =>
      _GrantDetailState();
}

class _GrantDetailState
    extends ConsumerState<CloudflareReceiverGrantDetailPage> {
  int _offset = 0;
  late Future<ReceiverCaptureDetail> _future;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = ref
        .read(cloudflareAdminReceiverApiProvider)
        .detail(widget.id, offset: _offset);
  }

  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Receiver capture grant',
    leading: IconButton(
      tooltip: 'Back to capture grants',
      onPressed: () => context.go('/admin/gateway/receiver-grants'),
      icon: const Icon(Icons.arrow_back),
    ),
    child: FutureBuilder<ReceiverCaptureDetail>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const AdminLoadingState(title: 'Loading capture grant');
        }
        if (snapshot.hasError) {
          return GatewayMessage(
            gatewayErrorMessage(snapshot.error!),
            error: true,
          );
        }
        final detail = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminDataTable(
              tableLabel: 'Capture grant facts',
              rows: [_row(detail.grant.values)],
              columns: [
                ..._grantColumns,
                _column('installation_id', 'Installation ID'),
                _column('key_sha256', 'Public key SHA-256'),
                _column('created_by_admin_id', 'Created by'),
                _column('revoked_by_admin_id', 'Revoked by'),
              ],
            ),
            if (detail.canManage &&
                (detail.grant.active ||
                    ref
                            .read(adminPendingAttemptStoreProvider)
                            .restore(
                              family: 'receiver-capture-grant',
                              resourceId: detail.grant.id,
                              schema: const AdminPendingAttemptSchema(
                                fields: {'expected_version', 'reason'},
                              ),
                            ) !=
                        null)) ...[
              const SizedBox(height: 20),
              CloudflareReceiverGrantForm(
                grant: detail.grant,
                onSaved: () => setState(_load),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              'Accepted receipt captures',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            AdminDataTable(
              tableLabel: 'Accepted receiver captures',
              rows: detail.captures.map(_row).toList(),
              columns: [
                _column('client_sms_id', 'Handset receipt ID'),
                _column('issued_at', 'Signed time'),
                _column('source_received_at', 'Handset received'),
                _column('accepted_at', 'Accepted'),
                _column('payload_sha256', 'Payload SHA-256'),
                _column('metadata_accepted', 'Metadata accepted'),
                _column('provider_confirmation', 'Provider confirmation'),
                _column('request_id', 'Request ID'),
              ],
            ),
            _Paging(
              offset: _offset,
              total: detail.total,
              count: detail.captures.length,
              onChange: (v) => setState(() {
                _offset = v;
                _load();
              }),
            ),
            TextButton.icon(
              onPressed: () => setState(_load),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh capture grant'),
            ),
          ],
        );
      },
    ),
  );
}

class CloudflareReceiverGrantForm extends ConsumerStatefulWidget {
  const CloudflareReceiverGrantForm({
    this.grant,
    required this.onSaved,
    super.key,
  });
  final ReceiverCaptureGrant? grant;
  final VoidCallback onSaved;
  @override
  ConsumerState<CloudflareReceiverGrantForm> createState() => _GrantFormState();
}

class _GrantFormState extends ConsumerState<CloudflareReceiverGrantForm> {
  final _reason = TextEditingController();
  Map<String, dynamic>? _device, _payee, _intent;
  String? _key, _message;
  bool _busy = false, _unknown = false, _retry = false;
  Object? _authority;
  String get _resource => widget.grant?.id ?? 'new';
  static const _family = 'receiver-capture-grant';
  AdminPendingAttemptSchema get _schema => AdminPendingAttemptSchema(
    fields: widget.grant == null
        ? {
            'device_id',
            'expected_device_version',
            'payee_id',
            'expected_payee_version',
            'reason',
          }
        : {'expected_version', 'reason'},
  );
  @override
  void initState() {
    super.initState();
    _authority = ref
        .read(cloudflareAdminSessionProvider)
        .asData
        ?.value
        ?.authorityKey;
    final saved = ref
        .read(adminPendingAttemptStoreProvider)
        .restore(family: _family, resourceId: _resource, schema: _schema);
    if (saved != null) {
      _key = saved.requestKey;
      _intent = Map.from(saved.intent);
      _unknown = true;
      _reason.text = '${saved.intent['reason']}';
      _message =
          'A previous capture request needs recovery. Check its original receipt before continuing.';
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _current =>
      mounted &&
      _authority != null &&
      ref.read(cloudflareAdminSessionProvider).asData?.value?.authorityKey ==
          _authority;
  bool get _locked => _busy || _unknown;
  bool _validPayeeReview(Map<String, dynamic> payee) {
    final label = payee['label'], route = payee['momo_number_or_code'];
    return label is String &&
        label.trim().length >= 2 &&
        label.length <= 120 &&
        !RegExp(r'[\x00-\x1f\x7f]').hasMatch(label) &&
        route is String &&
        RegExp(r'^[0-9]{4,12}$').hasMatch(route);
  }

  void _clear() {
    ref
        .read(adminPendingAttemptStoreProvider)
        .clear(family: _family, resourceId: _resource);
  }

  Future<void> _choose(bool device) async {
    final selected = await showDialog<AdminTableRowData>(
      context: context,
      builder: (_) => _CapturePicker(device: device),
    );
    if (!_current || selected == null) return;
    try {
      if (device) {
        setState(() => _device = selected.extra);
      } else {
        final repo =
            ref.read(adminRepositoryProvider) as CloudflareAdminRepository;
        final detail = await repo.operatingDetail('payees', selected.id);
        if (!_current) return;
        if (detail.resource['status'] != 'active' ||
            !_validPayeeReview(detail.resource)) {
          throw const AdminAccountException(
            'Select an active payee with a recorded name and numeric MoMo number or code.',
          );
        }
        setState(() => _payee = detail.resource);
      }
    } catch (error) {
      if (_current) setState(() => _message = gatewayErrorMessage(error));
    }
  }

  Future<void> _confirm() async {
    if (_busy || _unknown && !_retry) return;
    final body =
        _intent ??
        (widget.grant == null
            ? {
                'device_id': _device?['id'],
                'expected_device_version': _device?['version'],
                'payee_id': _payee?['id'],
                'expected_payee_version': _payee?['version'],
                'reason': _reason.text.trim(),
              }
            : {
                'expected_version': widget.grant!.version,
                'reason': _reason.text.trim(),
              });
    if ((body['reason'] as String).runes.length < 8 ||
        (body['reason'] as String).runes.length > 1000 ||
        widget.grant == null &&
            (body['device_id'] == null || body['payee_id'] == null)) {
      setState(
        () => _message =
            'Select the device and payee, and provide a reason of 8–1000 characters.',
      );
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          widget.grant == null
              ? 'Review receiver capture access'
              : 'Review capture revocation',
        ),
        content: SizedBox(
          width: 700,
          height: MediaQuery.sizeOf(context).height * .5,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.grant == null
                      ? 'This device may submit incoming receipt evidence for the selected payee. Sending and financial authority are excluded.'
                      : 'The grant will stop accepting new captures. Accepted evidence remains available.',
                ),
                const SizedBox(height: 12),
                AdminDataTable(
                  tableLabel: 'Capture request review',
                  rows: [
                    _row({
                      ...body,
                      'device':
                          _device?['label'] ??
                          widget.grant?.values['device_label'],
                      'payee':
                          _payee?['label'] ??
                          widget.grant?.values['payee_label'],
                      'payee_momo':
                          _payee?['momo_number_or_code'] ??
                          widget.grant?.values['payee_momo_number_or_code'],
                    }),
                  ],
                  columns: [
                    _column('device', 'Device'),
                    _column('payee', 'Payee'),
                    _column('payee_momo', 'Payee MoMo'),
                    for (final field in body.keys)
                      _column(field, field.replaceAll('_', ' ')),
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
            child: Text(
              _unknown ? 'Confirm identical retry' : 'Confirm capture change',
            ),
          ),
        ],
      ),
    );
    if (accepted != true || !_current) return;
    await _send(body, _key ?? const Uuid().v4());
  }

  Future<void> _send(Map<String, dynamic> body, String key) async {
    try {
      final store = ref.read(adminPendingAttemptStoreProvider);
      store.retain(
        family: _family,
        resourceId: _resource,
        requestKey: key,
        permission: 'gateway.manage',
        intent: body,
        schema: _schema,
      );
      _intent = Map.from(body);
      _key = key;
      setState(() {
        _busy = true;
        _retry = false;
        _message = store.storageMessage;
      });
      final receipt = await ref
          .read(cloudflareAdminReceiverApiProvider)
          .submit(key: key, body: body, revokeId: widget.grant?.id);
      if (!_current) return;
      _clear();
      setState(() {
        _key = null;
        _intent = null;
        _unknown = false;
        _message = 'Capture change saved. Request ${receipt.requestId}';
      });
      widget.onSaved();
    } catch (error) {
      if (!_current) return;
      final unknown =
          error is CloudflareAdminRequestException &&
              (error.outcomeUnknown || error.code == 'request_pending') ||
          error is FormatException;
      setState(() {
        _unknown = unknown;
        _message = unknown
            ? 'Outcome unconfirmed. Check original request $_key before another change.'
            : gatewayErrorMessage(error);
      });
      if (!unknown) {
        _clear();
        _key = null;
        _intent = null;
      }
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  Future<void> _recover() async {
    if (_busy || _key == null) return;
    setState(() {
      _busy = true;
      _retry = false;
    });
    try {
      final receipt = await ref
          .read(cloudflareAdminReceiverApiProvider)
          .lookup(_key!, revokeId: widget.grant?.id);
      if (!_current) return;
      if (receipt == null) {
        if (widget.grant == null) {
          final intent = _intent!;
          final repo =
              ref.read(adminRepositoryProvider) as CloudflareAdminRepository;
          final device = await repo.gatewayDevice(
            intent['device_id'] as String,
          );
          if (!_current) return;
          final payee = await repo.operatingDetail(
            'payees',
            intent['payee_id'] as String,
          );
          if (!_current) return;
          if (!_validPayeeReview(payee.resource)) {
            throw const AdminAccountException(
              'The original payee name and MoMo route could not be verified. The request remains locked; check its original receipt before another change.',
            );
          }
          if (device.device.state != 'active' ||
              device.device.values['version'] !=
                  intent['expected_device_version'] ||
              payee.resource['status'] != 'active' ||
              payee.resource['version'] != intent['expected_payee_version']) {
            throw const AdminAccountException(
              'The original device or payee has changed. The request remains locked; check its original receipt before another change.',
            );
          }
          _device = device.device.values;
          _payee = payee.resource;
        }
        setState(() {
          _retry = true;
          _message =
              'The original request has no recorded receipt. Review before retrying the same key and unchanged intent.';
        });
      } else {
        _clear();
        setState(() {
          _unknown = false;
          _intent = null;
          _key = null;
          _message = 'Capture change saved. Request ${receipt.requestId}';
        });
        widget.onSaved();
      }
    } catch (error) {
      if (_current) setState(() => _message = gatewayErrorMessage(error));
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.grant == null)
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: _locked ? null : () => _choose(true),
              child: Text(
                _device == null
                    ? 'Select active device'
                    : 'Device: ${_device!['label']}',
              ),
            ),
            OutlinedButton(
              onPressed: _locked ? null : () => _choose(false),
              child: Text(
                _payee == null
                    ? 'Select active payee'
                    : 'Payee: ${_payee!['label']} · ${_payee!['momo_number_or_code']}',
              ),
            ),
          ],
        ),
      const SizedBox(height: 12),
      TextField(
        controller: _reason,
        enabled: !_locked,
        maxLength: 1000,
        decoration: const InputDecoration(
          labelText: 'Capture access review reason',
        ),
      ),
      if (_message != null) GatewayMessage(_message!, error: _unknown),
      if (_key != null) SelectableText('Original request: $_key'),
      if (!ref.watch(adminPendingAttemptStoreProvider).storageAvailable)
        GatewayMessage(
          ref.read(adminPendingAttemptStoreProvider).storageMessage,
          error: true,
        ),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          if (!_unknown)
            FilledButton(
              onPressed: _busy ? null : _confirm,
              child: Text(
                widget.grant == null
                    ? 'Review capture grant'
                    : 'Review revocation',
              ),
            ),
          if (_unknown)
            OutlinedButton(
              onPressed: _busy ? null : _recover,
              child: const Text('Check original receipt'),
            ),
          if (_unknown && _retry)
            FilledButton(
              onPressed: _busy ? null : _confirm,
              child: const Text('Review identical retry'),
            ),
        ],
      ),
    ],
  );
}

class _CapturePicker extends ConsumerStatefulWidget {
  const _CapturePicker({required this.device});
  final bool device;
  @override
  ConsumerState<_CapturePicker> createState() => _PickerState();
}

class _PickerState extends ConsumerState<_CapturePicker> {
  int _offset = 0;
  String _search = '';
  late Future<AdminListResult> _future;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final repo = ref.read(adminRepositoryProvider) as CloudflareAdminRepository;
    _future = widget.device
        ? repo
              .gatewayDeviceList(state: 'active', offset: _offset)
              .then(
                (p) => AdminListResult(
                  total: p.total,
                  rows: [
                    for (final d in p.rows)
                      AdminTableRowData(
                        id: d.id,
                        title: '${d.values['label']}',
                        subtitle: '',
                        status: d.state,
                        amount: '',
                        extra: d.values,
                      ),
                  ],
                ),
              )
        : repo.list(
            'admin_list_collect_payees',
            status: 'active',
            search: _search,
            offset: _offset,
            limit: 25,
          );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.device ? 'Select active device' : 'Select active payee'),
    content: SizedBox(
      width: 900,
      height: 440,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.device)
            TextField(
              decoration: const InputDecoration(
                labelText: 'Find payee or MoMo route',
              ),
              onSubmitted: (v) => setState(() {
                _search = v;
                _offset = 0;
                _load();
              }),
            ),
          Expanded(
            child: SingleChildScrollView(
              child: FutureBuilder<AdminListResult>(
                future: _future,
                builder: (context, s) {
                  if (s.connectionState != ConnectionState.done) {
                    return const AdminLoadingState(title: 'Loading selection');
                  }
                  if (s.hasError) {
                    return GatewayMessage(
                      gatewayErrorMessage(s.error!),
                      error: true,
                    );
                  }
                  final p = s.data!;
                  return Column(
                    children: [
                      AdminDataTable(
                        tableLabel: widget.device
                            ? 'Active devices'
                            : 'Active payees',
                        rows: p.rows,
                        columns: [
                          AdminTableColumn(
                            label: widget.device ? 'Device' : 'Payee',
                            value: (r) => r.title,
                          ),
                          if (widget.device) _column('app_id', 'App ID'),
                          if (!widget.device)
                            _column(
                              'momo_number_or_code',
                              'MoMo number or code',
                            ),
                        ],
                        onOpen: (r) => Navigator.pop(context, r),
                      ),
                      _Paging(
                        offset: _offset,
                        total: p.total!,
                        count: p.rows.length,
                        onChange: (v) => setState(() {
                          _offset = v;
                          _load();
                        }),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  );
}
