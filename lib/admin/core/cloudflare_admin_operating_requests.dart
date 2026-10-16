part of 'cloudflare_admin_operating_pages.dart';

class CloudflareReceiptView extends ConsumerWidget {
  const CloudflareReceiptView({required this.receipt, super.key});
  final CloudflareOperationReceipt receipt;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.check_circle_outline),
      const SizedBox(height: 12),
      Text(
        receipt.resourceType == 'email_dispatch'
            ? 'Email batch recorded'
            : 'Change saved',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      const Text(
        'The server confirmed this change and recorded its audit receipt.',
      ),
      const SizedBox(height: 12),
      AdminDataTable(
        tableLabel: receipt.resourceType == 'email_dispatch'
            ? 'Email batch receipt'
            : 'Saved change receipt',
        rows: [
          AdminTableRowData(
            id: receipt.requestId,
            title: receipt.requestId,
            subtitle: '',
            status: 'succeeded',
            amount: '',
            extra: {
              'resource_type': receipt.resourceType,
              'resource_id': receipt.resourceId,
              'request_id': receipt.requestId,
              'version': receipt.version,
              'accepted': receipt.accepted,
              'uncertain': receipt.uncertain,
              'suppressed': receipt.suppressed,
            },
          ),
        ],
        columns: [
          AdminTableColumn(
            label: 'Resource',
            value: (row) =>
                operatingLabel(row.extra['resource_type'] as String),
          ),
          AdminTableColumn(
            label: 'Record ID',
            selectable: true,
            value: (row) => row.extra['resource_id'] as String,
          ),
          AdminTableColumn(
            label: 'Request',
            selectable: true,
            value: (row) => row.extra['request_id'] as String,
          ),
          AdminTableColumn(
            label: 'Version',
            numeric: true,
            value: (row) => '${row.extra['version']}',
          ),
          if (receipt.resourceType == 'email_dispatch')
            for (final entry in const {
              'accepted': 'Provider accepted',
              'uncertain': 'Uncertain',
              'suppressed': 'Suppressed',
            }.entries)
              AdminTableColumn(
                label: entry.value,
                numeric: true,
                value: (row) => '${row.extra[entry.key] ?? '—'}',
              ),
        ],
      ),
      if (receipt.resourceType == 'email_dispatch') ...[
        const SizedBox(height: 8),
        const Text(
          'Provider acceptance does not confirm inbox delivery. Uncertain messages are not retried automatically.',
        ),
      ],
      if (_receiptLocation(receipt) != null) ...[
        const SizedBox(height: 18),
        FilledButton(
          onPressed: () {
            // Historical receipts can outlive the currently retained detail.
            refreshCloudflareAdminData(ref);
            final router = GoRouter.of(context);
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
            router.go(_receiptLocation(receipt)!);
          },
          child: Text(
            receipt.resourceType == 'email_dispatch'
                ? 'View email events'
                : 'Open saved record',
          ),
        ),
      ],
    ],
  );
}

class _RequestReceiptView extends ConsumerWidget {
  const _RequestReceiptView(this.receipt);
  final CloudflareRequestReceipt receipt;

  @override
  Widget build(BuildContext context, WidgetRef ref) => switch (receipt) {
    CloudflareVersionedRequestReceipt(:final operation) =>
      CloudflareReceiptView(receipt: operation),
    CloudflareSmsFactsRequestReceipt() => _SmsFactsRequestReceiptView(
      receipt as CloudflareSmsFactsRequestReceipt,
    ),
    CloudflareReconciliationRequestReceipt() =>
      _ReconciliationRequestReceiptView(
        receipt as CloudflareReconciliationRequestReceipt,
        canOpen:
            ref
                .watch(cloudflareAdminSessionProvider)
                .asData
                ?.value
                ?.permissions
                .contains('reconciliations.read') ??
            false,
      ),
  };
}

class _ReconciliationRequestReceiptView extends StatelessWidget {
  const _ReconciliationRequestReceiptView(
    this.receipt, {
    required this.canOpen,
  });
  final CloudflareReconciliationRequestReceipt receipt;
  final bool canOpen;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.check_circle_outline),
      const SizedBox(height: 12),
      Text(
        'Reconciliation request recorded',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      const Text(
        'The server recorded this proposal or review. This receipt does not confirm provider settlement or ledger posting.',
      ),
      const SizedBox(height: 12),
      AdminDataTable(
        tableLabel: 'Reconciliation request receipt',
        rows: [
          AdminTableRowData(
            id: receipt.requestId,
            title: receipt.requestId,
            subtitle: '',
            status: 'succeeded',
            amount: '',
            extra: receipt.reconciliation.values,
          ),
        ],
        columns: [
          for (final entry in const {
            'request_id': 'Request',
            'resource_id': 'Proposal ID',
            'proposal_status': 'Proposal status',
            'transaction_id': 'Transaction ID',
            'version': 'Version',
            'review_id': 'Review ID',
            'allocation_id': 'Allocation ID',
            'transaction_version': 'Transaction version',
            'settlement_status': 'Settlement status',
          }.entries)
            AdminTableColumn(
              label: entry.value,
              selectable: entry.key.endsWith('_id'),
              numeric: {'version', 'transaction_version'}.contains(entry.key),
              value: (row) => _displayOperatingValue(
                entry.key.endsWith('_status') ? 'status' : entry.key,
                row.extra[entry.key],
              ),
            ),
        ],
      ),
      if (canOpen) ...[
        const SizedBox(height: 18),
        FilledButton(
          onPressed: () =>
              context.go('/admin/reconciliations/${receipt.transactionId}'),
          child: const Text('Open transaction reconciliation'),
        ),
      ],
    ],
  );
}

class _SmsFactsRequestReceiptView extends StatelessWidget {
  const _SmsFactsRequestReceiptView(this.receipt);
  final CloudflareSmsFactsRequestReceipt receipt;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.check_circle_outline),
      const SizedBox(height: 12),
      Text('SMS facts recorded', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text(
        'The server recorded facts extracted from the preserved SMS source. This receipt does not confirm a payment or provider settlement.',
      ),
      const SizedBox(height: 12),
      AdminDataTable(
        tableLabel: 'SMS extraction receipt',
        rows: [
          AdminTableRowData(
            id: receipt.requestId,
            title: receipt.requestId,
            subtitle: '',
            status: 'succeeded',
            amount: '',
            extra: {
              'resource_id': receipt.resourceId,
              'request_id': receipt.requestId,
              'source_kind': receipt.sourceKind,
              'source_id': receipt.sourceId,
              'parser_version': receipt.parserVersion,
            },
          ),
        ],
        columns: [
          AdminTableColumn(label: 'Resource', value: (_) => 'SMS facts'),
          AdminTableColumn(
            label: 'Facts ID',
            selectable: true,
            value: (row) => row.extra['resource_id'] as String,
          ),
          AdminTableColumn(
            label: 'Source kind',
            value: (row) => operatingLabel(row.extra['source_kind'] as String),
          ),
          AdminTableColumn(
            label: 'Source ID',
            selectable: true,
            value: (row) => row.extra['source_id'] as String,
          ),
          AdminTableColumn(
            label: 'Parser version',
            selectable: true,
            value: (row) => row.extra['parser_version'] as String,
          ),
          AdminTableColumn(
            label: 'Request',
            selectable: true,
            value: (row) => row.extra['request_id'] as String,
          ),
        ],
      ),
      const SizedBox(height: 18),
      FilledButton(
        onPressed: () => context.go(
          '/admin/sms-receipts/${receipt.sourceKind}/${receipt.sourceId}',
        ),
        child: const Text('Open SMS source'),
      ),
    ],
  );
}

AdminTableRowData _requestHistoryRow(Map<String, dynamic> row) =>
    AdminTableRowData(
      id: row['id'] as String,
      title: row['idempotency_key'] as String,
      subtitle: '',
      status: row['status'] as String,
      amount: '',
      extra: {
        ...row,
        'receipt_model': row['status'] == 'succeeded'
            ? CloudflareRequestReceipt.parse(
                Map<String, dynamic>.from(row['receipt'] as Map),
              )
            : null,
      },
    );

CloudflareRequestReceipt? _historyReceipt(AdminTableRowData row) =>
    row.extra['receipt_model'] as CloudflareRequestReceipt?;

Object? _reconciliationHistoryValue(AdminTableRowData row, String key) =>
    switch (_historyReceipt(row)) {
      CloudflareReconciliationRequestReceipt(:final reconciliation) =>
        reconciliation.values[key],
      _ => null,
    };

class CloudflareOperatingRequestPage extends ConsumerStatefulWidget {
  const CloudflareOperatingRequestPage({this.requestKey = '', super.key});
  final String requestKey;
  @override
  ConsumerState<CloudflareOperatingRequestPage> createState() =>
      _RequestPageState();
}

class _RequestPageState extends ConsumerState<CloudflareOperatingRequestPage> {
  late final _key = TextEditingController(text: widget.requestKey);
  bool _busy = false;
  String? _message;
  CloudflareRequestReceipt? _receipt;
  int _page = 0;
  late Future<({List<Map<String, dynamic>> rows, int total})> _recent;
  @override
  void initState() {
    super.initState();
    _recent = _repository(ref).operatingRequests();
    ref.listenManual(
      cloudflareAdminDataRevisionProvider,
      (_, _) => _loadRecent(),
    );
  }

  void _loadRecent() => setState(() {
    _recent = _repository(ref).operatingRequests(offset: _page * 25);
  });
  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (_busy) return;
    final authority = ref
        .read(cloudflareAdminSessionProvider)
        .asData
        ?.value
        ?.authorityKey;
    bool current() =>
        mounted &&
        authority != null &&
        authority ==
            ref
                .read(cloudflareAdminSessionProvider)
                .asData
                ?.value
                ?.authorityKey;
    setState(() {
      _busy = true;
      _message = null;
      _receipt = null;
    });
    try {
      final result = await _repository(ref).operatingRequest(_key.text.trim());
      if (!current()) return;
      setState(() {
        if (result['status'] == 'succeeded') {
          _receipt = CloudflareRequestReceipt.parse(
            Map<String, dynamic>.from(result['receipt'] as Map),
          );
        } else {
          _message = switch (result['status']) {
            'not_found' =>
              'No request was found for this reference and your account. An unconfirmed request should be checked again before another change.',
            'pending' =>
              'This request is still pending. Check again before continuing.',
            _ =>
              'The server recorded a failed request. Refresh the record before making another change.',
          };
        }
      });
      if (_receipt != null) refreshCloudflareAdminData(ref);
    } catch (error) {
      if (current()) setState(() => _message = _safeOperatingError(error));
    } finally {
      if (current()) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Request lookup',
    subtitle: 'Check the server receipt for a change made by your account.',
    leading: IconButton(
      tooltip: 'Back to overview',
      onPressed: () => context.go('/admin'),
      icon: const Icon(Icons.arrow_back),
    ),
    child: Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _key,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'Request reference'),
              onSubmitted: (_) => _busy ? null : _check(),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: _busy ? null : _check,
                child: Text(_busy ? 'Checking…' : 'Check request'),
              ),
            ),
            if (_message != null) _OperatingMessage(_message!),
            if (_receipt != null) ...[
              const SizedBox(height: 20),
              _RequestReceiptView(_receipt!),
            ],
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Your recent requests',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh request history',
                  onPressed: _loadRecent,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            FutureBuilder<({List<Map<String, dynamic>> rows, int total})>(
              future: _recent,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const AdminLoadingState(
                    title: 'Loading request history',
                  );
                }
                if (snapshot.hasError) {
                  return _OperatingMessage(
                    _safeOperatingError(snapshot.error!),
                    error: true,
                  );
                }
                final data = snapshot.data!;
                if (data.rows.isEmpty) {
                  return const _OperatingMessage(
                    'No requests are recorded for your account on this page.',
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AdminDataTable(
                      tableLabel: 'Your recent requests',
                      rows: [
                        for (final row in data.rows) _requestHistoryRow(row),
                      ],
                      columns: [
                        AdminTableColumn(
                          label: 'Request scope',
                          value: (row) => row.extra['scope'] as String,
                        ),
                        AdminTableColumn(
                          label: 'Status',
                          value: (row) => operatingLabel(row.status),
                        ),
                        AdminTableColumn(
                          label: 'Created',
                          value: (row) => _displayOperatingValue(
                            'created_at',
                            row.extra['created_at'],
                          ),
                        ),
                        AdminTableColumn(
                          label: 'Reference',
                          selectable: true,
                          value: (row) =>
                              row.extra['idempotency_key'] as String,
                        ),
                        AdminTableColumn(
                          label: 'Request ID',
                          selectable: true,
                          value: (row) => row.id,
                        ),
                        AdminTableColumn(
                          label: 'Completed',
                          value: (row) => _displayOperatingValue(
                            'completed_at',
                            row.extra['completed_at'],
                          ),
                        ),
                        AdminTableColumn(
                          label: 'Resource',
                          value: (row) => switch (_historyReceipt(row)) {
                            CloudflareSmsFactsRequestReceipt() => 'SMS facts',
                            CloudflareVersionedRequestReceipt(
                              :final operation,
                            ) =>
                              operatingLabel(operation.resourceType),
                            CloudflareReconciliationRequestReceipt() =>
                              'Reconciliation proposal',
                            null => '—',
                          },
                        ),
                        AdminTableColumn(
                          label: 'Record ID',
                          selectable: true,
                          value: (row) =>
                              _historyReceipt(row)?.resourceId ?? '—',
                        ),
                        AdminTableColumn(
                          label: 'Version',
                          numeric: true,
                          value: (row) => switch (_historyReceipt(row)) {
                            CloudflareVersionedRequestReceipt(
                              :final operation,
                            ) =>
                              '${operation.version}',
                            CloudflareReconciliationRequestReceipt(
                              :final reconciliation,
                            ) =>
                              '${reconciliation.values['version']}',
                            _ => '—',
                          },
                        ),
                        AdminTableColumn(
                          label: 'Source kind',
                          value: (row) => switch (_historyReceipt(row)) {
                            CloudflareSmsFactsRequestReceipt(
                              :final sourceKind,
                            ) =>
                              operatingLabel(sourceKind),
                            _ => '—',
                          },
                        ),
                        AdminTableColumn(
                          label: 'Source ID',
                          selectable: true,
                          value: (row) => switch (_historyReceipt(row)) {
                            CloudflareSmsFactsRequestReceipt(:final sourceId) =>
                              sourceId,
                            _ => '—',
                          },
                        ),
                        AdminTableColumn(
                          label: 'Parser version',
                          selectable: true,
                          value: (row) => switch (_historyReceipt(row)) {
                            CloudflareSmsFactsRequestReceipt(
                              :final parserVersion,
                            ) =>
                              parserVersion,
                            _ => '—',
                          },
                        ),
                        for (final entry in const {
                          'proposal_status': 'Proposal status',
                          'transaction_id': 'Transaction ID',
                          'review_id': 'Review ID',
                          'allocation_id': 'Allocation ID',
                          'transaction_version': 'Transaction version',
                        }.entries)
                          AdminTableColumn(
                            label: entry.value,
                            selectable: entry.key.endsWith('_id'),
                            numeric: entry.key == 'transaction_version',
                            value: (row) => _displayOperatingValue(
                              entry.key == 'proposal_status'
                                  ? 'status'
                                  : entry.key,
                              _reconciliationHistoryValue(row, entry.key),
                            ),
                          ),
                      ],
                      onOpen: (row) {
                        if (_busy) return;
                        _key.text = row.extra['idempotency_key'] as String;
                        _check();
                      },
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        Text(
                          '${_page * 25 + 1}–${_page * 25 + data.rows.length} of ${data.total}',
                        ),
                        OutlinedButton(
                          onPressed: _page == 0
                              ? null
                              : () {
                                  _page--;
                                  _loadRecent();
                                },
                          child: const Text('Previous'),
                        ),
                        OutlinedButton(
                          onPressed: (_page + 1) * 25 >= data.total
                              ? null
                              : () {
                                  _page++;
                                  _loadRecent();
                                },
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
      ),
    ),
  );
}
