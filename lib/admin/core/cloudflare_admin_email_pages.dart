import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../shared/components/admin_empty_state.dart';
import '../shared/components/admin_loading_state.dart';
import '../shared/components/admin_page.dart';
import '../shared/components/admin_data_table.dart';
import 'admin_account_api.dart';
import 'admin_display_formatters.dart';
import 'admin_models.dart';
import 'admin_repository_base.dart' show adminRepositoryProvider;
import 'cloudflare_admin_gateway_pages.dart' show GatewayMessage;
import 'cloudflare_admin_operating_pages.dart';
import 'cloudflare_admin_repository.dart';
import 'cloudflare_admin_session.dart';

String emailStatusLabel(String status) => switch (status) {
  'queued' => 'Queued',
  'leased' => 'Reserved for sending',
  'send_started' => 'Sending started',
  'accepted' => 'Provider accepted',
  'delivered' => 'Delivered',
  'failed_no_send' => 'Failed before send',
  'uncertain' => 'Outcome uncertain',
  'suppressed' => 'Suppressed',
  _ => status,
};
String _emailError(Object error) =>
    error is CloudflareAdminRequestException &&
        error.code == 'email_unavailable'
    ? 'Cloudflare email sending is not available. Review the service configuration before dispatching.'
    : error is AdminAccountException
    ? error.message
    : 'Email status could not be verified. Refresh and try again.';
CloudflareAdminRepository _emailRepository(WidgetRef ref) =>
    ref.read(adminRepositoryProvider) as CloudflareAdminRepository;
String _emailDate(Object? value) => value is int
    ? adminKigaliDateTime(
        DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true),
      )
    : 'Not recorded';

AdminTableRowData _emailRow(Map<String, dynamic> row) => AdminTableRowData(
  id: row['id'] as String,
  title: operatingLabel(row['notification_type'] as String),
  subtitle: '',
  status: row['status'] as String,
  amount: '',
  extra: row,
);

AdminTableColumn _emailColumn(
  String key,
  String label, {
  bool numeric = false,
}) => AdminTableColumn(
  label: label,
  numeric: numeric,
  selectable: true,
  value: (row) => switch (key) {
    'notification_type' => operatingLabel(row.extra[key] as String),
    'status' => emailStatusLabel(row.status),
    'created_at' ||
    'updated_at' ||
    'accepted_at' ||
    'delivered_at' => _emailDate(row.extra[key]),
    _ => '${row.extra[key] ?? 'Not recorded'}',
  },
);

class CloudflareEmailPage extends ConsumerStatefulWidget {
  const CloudflareEmailPage({super.key});
  @override
  ConsumerState<CloudflareEmailPage> createState() => _EmailPageState();
}

class _EmailPageState extends ConsumerState<CloudflareEmailPage> {
  String _status = '';
  int _page = 0;
  late Future<({List<Map<String, dynamic>> rows, int total})> _future;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = _emailRepository(
      ref,
    ).emailEvents(status: _status, offset: _page * 25);
  }

  void _refresh() => setState(() {
    _page = 0;
    _load();
  });
  Future<void> _dispatch() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
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
                        'Run queued email batch',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close dispatch',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: CloudflareEmailDispatchForm(onSaved: _refresh),
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
    final user = ref.watch(cloudflareAdminSessionProvider).asData?.value;
    final manage =
        user != null &&
        user.role != AdminAccountRole.staff &&
        user.permissions.contains('email.manage');
    return AdminPage(
      title: 'Email notifications',
      subtitle:
          'Track Collect notifications sent through Cloudflare from info@ikanisa.com.',
      trailing: manage
          ? FilledButton.icon(
              onPressed: _dispatch,
              icon: const Icon(Icons.outgoing_mail),
              label: const Text('Run queued batch'),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Queued messages are processed automatically. Provider acceptance is separate from inbox delivery; uncertain sends are not retried automatically.',
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _status,
                  isExpanded: true,
                  itemHeight: null,
                  decoration: const InputDecoration(labelText: 'Email status'),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('All statuses'),
                    ),
                    for (final state in cloudflareEmailStates)
                      DropdownMenuItem(
                        value: state,
                        child: Text(emailStatusLabel(state)),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    _status = value ?? '';
                    _page = 0;
                    _load();
                  }),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: 'Refresh email events',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FutureBuilder<({List<Map<String, dynamic>> rows, int total})>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const AdminLoadingState(title: 'Loading email events');
              }
              if (snapshot.hasError) {
                return GatewayMessage(
                  _emailError(snapshot.error!),
                  error: true,
                );
              }
              final data = snapshot.data!;
              if (data.rows.isEmpty) {
                return const AdminEmptyState(
                  title: 'No email events',
                  message:
                      'No matching notification events are recorded. Change the filter or refresh to check again.',
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AdminDataTable(
                    tableLabel: 'Email notifications',
                    rows: data.rows.map(_emailRow).toList(),
                    columns: [
                      _emailColumn('notification_type', 'Notification'),
                      _emailColumn('recipient_masked', 'Recipient'),
                      _emailColumn('status', 'Status'),
                      _emailColumn('attempt_count', 'Attempts', numeric: true),
                      _emailColumn('created_at', 'Created'),
                      _emailColumn('updated_at', 'Updated'),
                      _emailColumn('accepted_at', 'Provider accepted'),
                      _emailColumn('delivered_at', 'Delivery recorded'),
                      _emailColumn('id', 'Event ID'),
                    ],
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
}

class CloudflareEmailDispatchForm extends ConsumerStatefulWidget {
  const CloudflareEmailDispatchForm({this.onSaved, super.key});
  final VoidCallback? onSaved;
  @override
  ConsumerState<CloudflareEmailDispatchForm> createState() =>
      _EmailDispatchState();
}

class _EmailDispatchState extends ConsumerState<CloudflareEmailDispatchForm> {
  final _reason = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false, _checking = false;
  String? _key, _error;
  CloudflareOperationReceipt? _receipt;
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy || _key != null || !(_form.currentState?.validate() ?? false)) {
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Run a queued batch?'),
        content: const Text(
          'This asks Cloudflare to process up to 20 queued notifications. Provider acceptance does not prove delivery. Messages with an uncertain send outcome will not be retried.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm batch'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final key = const Uuid().v4();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final receipt = await _emailRepository(
        ref,
      ).dispatchEmails(key: key, reason: _reason.text);
      if (!mounted) return;
      setState(() => _receipt = receipt);
      widget.onSaved?.call();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _emailError(error);
          _key =
              error is! CloudflareAdminRequestException || error.outcomeUnknown
              ? key
              : null;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      final result = await _emailRepository(ref).operatingRequest(_key!);
      if (!mounted) return;
      if (result['status'] == 'succeeded') {
        final receipt = CloudflareOperationReceipt.parse(
          Map<String, dynamic>.from(result['receipt'] as Map),
        );
        if (receipt.resourceType != 'email_dispatch') {
          throw const FormatException('Unexpected receipt.');
        }
        setState(() {
          _receipt = receipt;
          _key = null;
          _error = null;
        });
        widget.onSaved?.call();
      } else {
        setState(
          () => _error =
              'The dispatch is unresolved. Review email events and check this request again. Do not retry an uncertain send.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = _emailError(error));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(cloudflareAdminSessionProvider).asData?.value;
    if (user == null ||
        user.role == AdminAccountRole.staff ||
        !user.permissions.contains('email.manage')) {
      return const GatewayMessage(
        'Only administrators can run queued email batches.',
      );
    }
    if (_receipt != null) return CloudflareReceiptView(receipt: _receipt!);
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Automatic processing runs every minute. Use this action to process the next queued batch now.',
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _reason,
            enabled: !_busy && _key == null,
            minLines: 2,
            maxLines: 4,
            maxLength: 1000,
            decoration: const InputDecoration(
              labelText: 'Reason for manual dispatch',
            ),
            validator: (value) => (value?.trim().length ?? 0) < 8
                ? 'Provide a reason of at least 8 characters.'
                : null,
          ),
          if (_error != null) GatewayMessage(_error!, error: true),
          if (_key != null) ...[
            SelectableText('Request reference: $_key'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: _checking ? null : _check,
                  child: Text(
                    _checking ? 'Checking…' : 'Check dispatch receipt',
                  ),
                ),
                TextButton(
                  onPressed: () => context.go('/admin/requests?key=$_key'),
                  child: const Text('Open request lookup'),
                ),
              ],
            ),
          ] else
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _busy ? null : _send,
                child: Text(_busy ? 'Dispatching…' : 'Review batch'),
              ),
            ),
        ],
      ),
    );
  }
}
