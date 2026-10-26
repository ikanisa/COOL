import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../app/theme/collect_motion.dart';
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

CloudflareAdminRepository _receiptRepository(WidgetRef ref) =>
    ref.read(adminRepositoryProvider) as CloudflareAdminRepository;
String _receiptError(Object error, {bool capture = false}) =>
    error is AdminAccountException
    ? error.message
    : error is FormatException
    ? capture
          ? 'The receipt metadata could not be verified. Please refresh.'
          : 'The submitted content or response could not be verified. Check the request receipt before another classification.'
    : 'The receipt service could not be reached. Please refresh.';

AdminTableRowData _receiptRow(Map<String, dynamic> values, {String? id}) =>
    AdminTableRowData(
      id: id ?? values['id'] as String,
      title: '${values['public_id'] ?? values['id']}',
      subtitle: '',
      status: '${values['status'] ?? ''}',
      amount: '',
      extra: values,
    );

String _receiptValue(String key, Object? value) {
  if (value == null || '$value'.trim().isEmpty) return 'Not recorded';
  if (key.endsWith('_at') && value is String) {
    return adminKigaliDateTime(DateTime.tryParse(value));
  }
  if ({'status', 'outcome', 'evidence_level'}.contains(key)) {
    return operatingLabel('$value');
  }
  // Preserve source text and its line boundaries in one table cell. The
  // original content is unchanged; arrows represent recorded line breaks.
  return '$value'.replaceAll(RegExp(r'\r\n?|\n'), ' ↵ ');
}

AdminTableColumn _receiptColumn(
  String key,
  String label, {
  bool numeric = false,
}) => AdminTableColumn(
  label: label,
  numeric: numeric,
  selectable: true,
  value: (row) => _receiptValue(key, row.extra[key]),
);

List<AdminTableColumn> _receiptColumns({bool capture = false}) => [
  _receiptColumn('public_id', 'Member ID', numeric: true),
  _receiptColumn('display_name', 'Member name'),
  _receiptColumn('status', capture ? 'Receipt status' : 'Review status'),
  if (capture) _receiptColumn('received_at_device', 'Device time (source)'),
  if (capture) _receiptColumn('evidence_level', 'Evidence level'),
  _receiptColumn('received_at', 'Received'),
  _receiptColumn('created_at', 'Created'),
  _receiptColumn('reviewed_at', 'Reviewed'),
  _receiptColumn('transaction_id', 'Attached transaction ID'),
  _receiptColumn('version', 'Version', numeric: true),
  _receiptColumn('id', 'Submission ID'),
  _receiptColumn('user_id', 'User record ID'),
  _receiptColumn('body_sha256', 'Source SHA-256'),
];

class CloudflareMemberReceiptListPage extends ConsumerStatefulWidget {
  const CloudflareMemberReceiptListPage({super.key});
  @override
  ConsumerState<CloudflareMemberReceiptListPage> createState() =>
      _ReceiptListState();
}

class _ReceiptListState extends ConsumerState<CloudflareMemberReceiptListPage> {
  bool get _canonical =>
      _receiptRepository(ref).session.user?.usesCanonicalEvidence == true;
  String _status = 'needs_review';
  int _page = 0;
  late Future<({List<CloudflareMemberReceipt> rows, int total})> _future;
  @override
  void initState() {
    super.initState();
    if (_canonical) _status = '';
    _load();
  }

  void _load() {
    _future = _receiptRepository(
      ref,
    ).memberReceiptList(status: _status, offset: _page * 25);
  }

  void _refresh() => setState(() {
    _page = 0;
    _load();
  });
  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Member receipts',
    subtitle: _canonical
        ? 'View recorded receipt metadata.'
        : 'Review submitted payment material before attaching evidence to a transaction.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _canonical
              ? 'Captured receipts do not confirm a payment or provider settlement.'
              : 'Member submissions are claims to review. They do not confirm a payment or provider settlement.',
        ),
        if (_canonical) ...[
          const SizedBox(height: 8),
          const Text('Source review is unavailable for this captured receipt'),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _status,
                isExpanded: true,
                itemHeight: null,
                decoration: InputDecoration(
                  labelText: _canonical ? 'Receipt status' : 'Review status',
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('All statuses'),
                  ),
                  for (final value
                      in (_canonical
                          ? ['received', 'under_review', 'rejected', 'linked']
                          : ['needs_review', 'reviewed', 'rejected']))
                    DropdownMenuItem(
                      value: value,
                      child: Text(operatingLabel(value)),
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
              tooltip: 'Refresh member receipts',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 20),
        FutureBuilder<({List<CloudflareMemberReceipt> rows, int total})>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const AdminLoadingState(title: 'Loading member receipts');
            }
            if (snapshot.hasError) {
              return GatewayMessage(
                _receiptError(snapshot.error!, capture: _canonical),
                error: true,
              );
            }
            final data = snapshot.data!;
            if (data.rows.isEmpty) {
              return const AdminEmptyState(
                title: 'No matching receipts',
                message:
                    'No receipts match this status. Refresh or choose another status.',
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AdminDataTable(
                  tableLabel: 'Member receipts',
                  rows: [for (final row in data.rows) _receiptRow(row.values)],
                  columns: _receiptColumns(capture: _canonical),
                  onOpen: (row) async {
                    await context.push('/admin/member-receipts/${row.id}');
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

class CloudflareMemberReceiptDetailPage extends ConsumerStatefulWidget {
  const CloudflareMemberReceiptDetailPage({required this.id, super.key});
  final String id;
  @override
  ConsumerState<CloudflareMemberReceiptDetailPage> createState() =>
      _ReceiptDetailState();
}

class _ReceiptDetailState
    extends ConsumerState<CloudflareMemberReceiptDetailPage> {
  late Future<CloudflareMemberReceiptDetail> _future;
  final _reason = TextEditingController();
  final _search = TextEditingController();
  Map<String, String>? _content;
  List<Map<String, dynamic>> _transactions = [];
  String? _transaction, _error, _unknownKey;
  String _outcome = 'reviewed';
  bool _revealing = false,
      _searching = false,
      _saving = false,
      _checking = false,
      _retryAllowed = false;
  CloudflareOperationReceipt? _saved;
  Map<String, dynamic>? _pending;
  int? _pendingVersion;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _future = _receiptRepository(ref).memberReceiptDetail(widget.id);
  }

  @override
  void didUpdateWidget(covariant CloudflareMemberReceiptDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _clear();
      _future = _receiptRepository(ref).memberReceiptDetail(widget.id);
    }
  }

  void _clear() {
    _generation++;
    _content = null;
    _transactions = [];
    _transaction = null;
    _error = null;
    _saved = null;
    _unknownKey = null;
    _pending = null;
    _pendingVersion = null;
    _revealing = _searching = _saving = _checking = _retryAllowed = false;
    _reason.clear();
    _search.clear();
  }

  @override
  void dispose() {
    _content = null;
    _pending = null;
    _reason.dispose();
    _search.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {
    _generation++;
    _content = null;
    _transactions = [];
    _transaction = null;
    _future = _receiptRepository(ref).memberReceiptDetail(widget.id);
  });
  bool get _locked => _saving || _unknownKey != null || _saved != null;
  Future<void> _reveal(CloudflareMemberReceipt receipt) async {
    final generation = _generation;
    if (_reason.text.trim().length < 8) {
      setState(
        () => _error =
            'Provide an audit reason of at least 8 characters before viewing the submission.',
      );
      return;
    }
    setState(() {
      _revealing = true;
      _error = null;
    });
    try {
      final content = await _receiptRepository(
        ref,
      ).memberReceiptContent(receipt, reason: _reason.text);
      if (mounted && generation == _generation) {
        setState(() => _content = content);
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _content = null;
          _error = _receiptError(error);
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _revealing = false);
      }
    }
  }

  Future<void> _lookup() async {
    final generation = _generation;
    setState(() => _searching = true);
    try {
      final rows = await _receiptRepository(
        ref,
      ).memberReceiptTransactions(widget.id, search: _search.text);
      if (mounted && generation == _generation) {
        setState(() {
          _transactions = rows;
          if (!rows.any((row) => row['id'] == _transaction)) {
            _transaction = null;
          }
        });
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = _receiptError(error));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _review(CloudflareMemberReceipt receipt) async {
    final generation = _generation;
    if (_locked || _content == null) return;
    if (_reason.text.trim().length < 8) {
      setState(
        () => _error =
            'Provide a classification reason of at least 8 characters.',
      );
      return;
    }
    final transaction = _outcome == 'reviewed' ? _transaction : null;
    final accepted = await showDialog<bool>(
      context: context,
      animationStyle: CollectMotion.animationStyle(context),
      builder: (context) => AlertDialog(
        title: Text('Mark receipt $_outcome?'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'This classification is permanent. Any attached evidence remains member-submitted material; the transaction stays pending until a separate verification.',
                ),
                const SizedBox(height: 12),
                AdminDataTable(
                  tableLabel: 'Receipt classification confirmation',
                  rows: [
                    _receiptRow({
                      'id': receipt.id,
                      'version': receipt.version,
                      'outcome': _outcome,
                      'transaction_id': transaction ?? 'No attachment',
                      'reason': _reason.text.trim(),
                    }),
                  ],
                  columns: [
                    _receiptColumn('id', 'Receipt'),
                    _receiptColumn('version', 'Version', numeric: true),
                    _receiptColumn('outcome', 'Classification'),
                    _receiptColumn('transaction_id', 'Transaction'),
                    _receiptColumn('reason', 'Reason'),
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
            child: const Text('Confirm classification'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted && generation == _generation) {
      final body = {
        'outcome': _outcome,
        'transaction_id': transaction,
        'reason': _reason.text.trim(),
      };
      await _send(receipt, body, const Uuid().v4());
    }
  }

  Future<void> _send(
    CloudflareMemberReceipt receipt,
    Map<String, dynamic> body,
    String key,
  ) async {
    final generation = _generation;
    setState(() {
      _saving = true;
      _error = null;
      _retryAllowed = false;
    });
    _pending = body;
    _pendingVersion = receipt.version + 1;
    try {
      final saved = await _receiptRepository(ref).reviewMemberReceipt(
        receipt,
        key: key,
        outcome: body['outcome'] as String,
        transactionId: body['transaction_id'] as String?,
        reason: body['reason'] as String,
      );
      if (mounted && generation == _generation) {
        setState(() {
          _saved = saved;
          _unknownKey = null;
          _content = null;
        });
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = _receiptError(error);
          _unknownKey =
              error is! CloudflareAdminRequestException || error.outcomeUnknown
              ? key
              : null;
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _check() async {
    final generation = _generation;
    setState(() => _checking = true);
    try {
      final result = await _receiptRepository(
        ref,
      ).operatingRequest(_unknownKey!);
      if (!mounted || generation != _generation) return;
      if (result['status'] == 'succeeded') {
        final saved = CloudflareOperationReceipt.parse(
          Map<String, dynamic>.from(result['receipt'] as Map),
        );
        if (saved.resourceType != 'member_receipts' ||
            saved.resourceId != widget.id ||
            saved.version != _pendingVersion) {
          throw const FormatException('Unexpected receipt.');
        }
        setState(() {
          _saved = saved;
          _unknownKey = null;
          _content = null;
          _error = null;
        });
      } else {
        setState(() {
          _retryAllowed = result['status'] == 'not_found';
          _error = result['status'] == 'not_found'
              ? 'The request was not found. Check again, or retry the identical classification with its original reference.'
              : 'The request is unresolved. Check again before another classification.';
        });
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = _receiptError(error));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _checking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(cloudflareAdminSessionProvider).asData?.value;
    final manage =
        user != null &&
        user.role != AdminAccountRole.staff &&
        user.permissions.contains('payments.manage');
    ref.listen(cloudflareAdminSessionProvider, (_, next) {
      if (next.asData?.value?.role == AdminAccountRole.staff ||
          next.asData?.value?.permissions.contains('payments.manage') != true) {
        _generation++;
        _content = null;
      }
    });
    return AdminPage(
      title: user?.usesCanonicalEvidence == true
          ? 'Member receipt'
          : 'Member receipt review',
      subtitle: user?.usesCanonicalEvidence == true
          ? 'View recorded receipt metadata.'
          : 'Inspect the submission and record its classification.',
      leading: IconButton(
        tooltip: 'Back to member receipts',
        onPressed: () => context.canPop()
            ? context.pop()
            : context.go('/admin/member-receipts'),
        icon: const Icon(Icons.arrow_back),
      ),
      trailing: IconButton(
        tooltip: 'Refresh submission',
        onPressed: _revealing || _saving || _unknownKey != null
            ? null
            : _refresh,
        icon: const Icon(Icons.refresh),
      ),
      child: FutureBuilder<CloudflareMemberReceiptDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const AdminLoadingState(title: 'Loading submission');
          }
          if (snapshot.hasError) {
            return GatewayMessage(
              _receiptError(
                snapshot.error!,
                capture: user?.usesCanonicalEvidence == true,
              ),
              error: true,
            );
          }
          final detail = snapshot.data!, receipt = detail.receipt;
          if (_saved != null) return CloudflareReceiptView(receipt: _saved!);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminDataTable(
                tableLabel: 'Member receipt details',
                rows: [_receiptRow(receipt.values)],
                columns: _receiptColumns(capture: receipt.isCapture),
              ),
              if (receipt.values['transaction_id'] != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => context.push(
                      '/admin/transactions/${receipt.values['transaction_id']}',
                    ),
                    child: const Text('Open attached transaction'),
                  ),
                ),
              const SizedBox(height: 20),
              if (receipt.isCapture)
                const Text(
                  'Source review is unavailable for this captured receipt',
                )
              else if (manage && detail.canManage) ...[
                TextFormField(
                  controller: _reason,
                  enabled: !_locked && !_revealing,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 1000,
                  decoration: const InputDecoration(
                    labelText: 'Audit reason for access and review',
                    helperText:
                        '8–1000 characters. Viewing source content is recorded.',
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: _revealing || _locked
                          ? null
                          : () => _reveal(receipt),
                      child: Text(
                        _revealing
                            ? 'Checking content…'
                            : 'Reveal submitted content',
                      ),
                    ),
                    if (_content != null)
                      OutlinedButton(
                        onPressed: _revealing
                            ? null
                            : () => setState(() => _content = null),
                        child: const Text('Hide submitted content'),
                      ),
                  ],
                ),
                if (_content != null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Stored hash verified · Member-submitted evidence',
                  ),
                  const SizedBox(height: 12),
                  AdminDataTable(
                    tableLabel: 'Revealed submission source',
                    rows: [_receiptRow(_content!, id: receipt.id)],
                    columns: [
                      _receiptColumn('raw_sender', 'Source sender'),
                      _receiptColumn('raw_body', 'Submitted content'),
                      _receiptColumn('body_sha256', 'Verified SHA-256'),
                      _receiptColumn('evidence_level', 'Evidence level'),
                    ],
                  ),
                  if (receipt.status == 'needs_review') ...[
                    const SizedBox(height: 24),
                    DropdownButtonFormField<String>(
                      initialValue: _outcome,
                      decoration: const InputDecoration(
                        labelText: 'Classification',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'reviewed',
                          child: Text('Reviewed'),
                        ),
                        DropdownMenuItem(
                          value: 'rejected',
                          child: Text('Rejected'),
                        ),
                      ],
                      onChanged: _locked
                          ? null
                          : (value) => setState(() {
                              _outcome = value ?? 'reviewed';
                              if (_outcome == 'rejected') _transaction = null;
                            }),
                    ),
                    if (_outcome == 'reviewed') ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: _search,
                        enabled: !_locked,
                        decoration: const InputDecoration(
                          labelText: 'Search pending transactions',
                          helperText:
                              'Only transactions in this member’s active groups can be attached.',
                        ),
                        onSubmitted: (_) => _locked ? null : _lookup(),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _searching || _locked ? null : _lookup,
                          icon: const Icon(Icons.search),
                          label: Text(
                            _searching
                                ? 'Searching…'
                                : 'Find eligible transactions',
                          ),
                        ),
                      ),
                      DropdownButtonFormField<String>(
                        key: ValueKey(_transaction),
                        initialValue: _transaction,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Attach to transaction (optional)',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('No attachment'),
                          ),
                          for (final row in _transactions)
                            DropdownMenuItem(
                              value: row['id'] as String,
                              child: Text(
                                '${row['label']} · ${adminFormatWholeAmount(row['amount_rwf'])}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _locked
                            ? null
                            : (value) => setState(
                                () => _transaction = value == '' ? null : value,
                              ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (_unknownKey == null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed: _locked ? null : () => _review(receipt),
                          child: Text(
                            _saving ? 'Saving…' : 'Review classification',
                          ),
                        ),
                      ),
                  ],
                ],
              ] else
                const GatewayMessage(
                  'Your account can view submission metadata. Source content and classification require administrator access.',
                ),
              if (_error != null) GatewayMessage(_error!, error: true),
              if (_unknownKey != null) ...[
                SelectableText('Request reference: $_unknownKey'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: _checking || _saving ? null : _check,
                      child: Text(
                        _checking
                            ? 'Checking…'
                            : 'Check classification receipt',
                      ),
                    ),
                    if (_retryAllowed)
                      OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => _send(receipt, _pending!, _unknownKey!),
                        child: const Text('Retry identical classification'),
                      ),
                    TextButton(
                      onPressed: () =>
                          context.go('/admin/requests?key=$_unknownKey'),
                      child: const Text('Open request lookup'),
                    ),
                  ],
                ),
              ],
              if (!receipt.isCapture) ...[
                const SizedBox(height: 24),
                Text(
                  'Review history',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                if (detail.reviews.isEmpty)
                  const Text('No classification recorded.')
                else
                  AdminDataTable(
                    tableLabel: 'Receipt review history',
                    rows: [
                      for (final review in detail.reviews) _receiptRow(review),
                    ],
                    columns: [
                      _receiptColumn('outcome', 'Classification'),
                      _receiptColumn('reviewed_at', 'Reviewed'),
                      _receiptColumn('actor_admin_id', 'Administrator ID'),
                      _receiptColumn('reason', 'Reason'),
                      _receiptColumn(
                        'transaction_id',
                        'Attached transaction ID',
                      ),
                      _receiptColumn('evidence_id', 'Evidence ID'),
                      _receiptColumn('id', 'Review ID'),
                    ],
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}
