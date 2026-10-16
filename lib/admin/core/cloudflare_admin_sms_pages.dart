import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/components/admin_data_table.dart';
import '../shared/components/admin_loading_state.dart';
import '../shared/components/admin_page.dart';
import 'admin_account_api.dart';
import 'admin_display_formatters.dart';
import 'admin_models.dart';
import 'admin_pending_attempt_store.dart';
import 'cloudflare_admin_data_refresh.dart';
import 'cloudflare_admin_session.dart';
import 'cloudflare_admin_sms_api.dart';

typedef _ListQuery = ({
  String search,
  String status,
  String source,
  String extraction,
  String duplicates,
  int offset,
  int limit,
});
typedef _DetailQuery = ({String kind, String id, int offset});
final _receiptsProvider = FutureProvider.autoDispose
    .family<SmsReceiptPage<SmsReceiptSource>, _ListQuery>((ref, query) {
      ref.watch(cloudflareAdminDataRevisionProvider);
      return ref
          .watch(cloudflareAdminSmsApiProvider)
          .receipts(
            search: query.search,
            status: query.status,
            sourceKind: query.source,
            extractionStatus: query.extraction,
            duplicates: query.duplicates,
            offset: query.offset,
            limit: query.limit,
          );
    });
final _detailProvider = FutureProvider.autoDispose
    .family<SmsReceiptDetail, _DetailQuery>(
      (ref, query) => ref
          .watch(cloudflareAdminSmsApiProvider)
          .detail(query.kind, query.id, offset: query.offset),
    );

/// Return only to the same listing with one bounded value per known filter.
String smsReturnLocation(String? location) {
  const fallback = '/admin/sms-receipts';
  final uri = location == null ? null : Uri.tryParse(location);
  if (uri == null ||
      location!.length > 2000 ||
      uri.hasScheme ||
      uri.hasAuthority ||
      uri.hasFragment ||
      uri.path != fallback ||
      RegExp(r'[\x00-\x20\\]').hasMatch(location) ||
      uri.queryParametersAll.entries.any(
        (entry) =>
            !{
              'search',
              'status',
              'source',
              'extraction',
              'duplicates',
              'page',
              'limit',
            }.contains(entry.key) ||
            entry.value.length != 1,
      )) {
    return fallback;
  }
  final query = uri.queryParameters,
      limit = int.tryParse(uri.queryParameters['limit'] ?? '25'),
      page = int.tryParse(uri.queryParameters['page'] ?? '1');
  if ((query['search'] ?? '').length > 200 ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(query['search'] ?? '') ||
      (query['status'] ?? '').isNotEmpty &&
          !smsReceiptStatuses.contains(query['status']) ||
      (query['source'] ?? '').isNotEmpty &&
          !smsSourceKinds.contains(query['source']) ||
      (query['extraction'] ?? '').isNotEmpty &&
          !smsExtractionStatuses.contains(query['extraction']) ||
      !{'', 'all', 'conflicting'}.contains(query['duplicates'] ?? '') ||
      limit == null ||
      limit < 1 ||
      limit > 100 ||
      page == null ||
      page < 1 ||
      (page - 1) * limit > 2147483647) {
    return fallback;
  }
  return uri.toString();
}

String _value(Object? value) => value == null || value == '' ? '—' : '$value';
String _label(Object? value) => value == null
    ? '—'
    : '$value'
          .split('_')
          .map(
            (word) => word.isEmpty
                ? word
                : '${word[0].toUpperCase()}${word.substring(1)}',
          )
          .join(' ');
String _error(Object error) => error is AdminAccountException
    ? error.message
    : error is FormatException
    ? 'The service response could not be verified. Refresh before continuing.'
    : 'The service could not be reached. Try again.';
String _time(Object? seconds) => adminKigaliDateTime(
  seconds is int
      ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true)
      : null,
);
AdminTableRowData _row(Map<String, dynamic> values) => AdminTableRowData(
  id: '${values['source_kind'] ?? ''}/${values['id'] ?? values['request_id'] ?? 'facts'}',
  title: '${values['id'] ?? 'Receipt'}',
  subtitle: '',
  status: '',
  amount: '',
  extra: values,
);
AdminTableColumn _column(
  String label,
  String field, {
  bool numeric = false,
  bool amount = false,
  bool labelValue = false,
  bool time = false,
}) => AdminTableColumn(
  label: label,
  numeric: numeric,
  selectable: true,
  value: (row) => amount
      ? adminFormatWholeAmount(row.extra[field])
      : labelValue
      ? _label(row.extra[field])
      : time
      ? _time(row.extra[field])
      : _value(row.extra[field]),
);
List<AdminTableColumn> get _sourceColumns => [
  _column('Source', 'source_kind', labelValue: true),
  _column('Source ID', 'id'),
  _column('Evidence', 'evidence_level', labelValue: true),
  _column('Source name', 'display_name'),
  _column('Status', 'status', labelValue: true),
  _column('Extraction', 'extraction_status', labelValue: true),
  _column('Payer name', 'payer_name'),
  _column('Payer phone', 'payer_phone', numeric: true),
  _column('Source masked phone', 'payer_masked_phone'),
  _column('Payer last 3', 'payer_last3', numeric: true),
  _column('Payee MoMo number', 'payee_momo_number', numeric: true),
  _column('Payee MoMo code', 'payee_momo_code', numeric: true),
  _column('MoMo transaction', 'momo_transaction_reference'),
  _column('MoMo time', 'momo_timestamp_local'),
  _column('Source timezone', 'momo_timezone_offset'),
  _column('Amount', 'amount_rwf', numeric: true, amount: true),
  _column('Wallet balance', 'wallet_balance_rwf', numeric: true, amount: true),
  _column('Network', 'network', labelValue: true),
  _column('Direction', 'direction', labelValue: true),
  _column('Transaction ID', 'transaction_reference', numeric: true),
  _column('Duplicate references', 'duplicate_reference_count', numeric: true),
  _column(
    'Conflicting references',
    'conflicting_reference_count',
    numeric: true,
  ),
  _column('Received', 'received_at', time: true),
  _column('Source SHA-256', 'source_sha256'),
];

class _Message extends StatelessWidget {
  const _Message(this.text, {this.error = false});
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        text,
        style: error
            ? TextStyle(color: Theme.of(context).colorScheme.error)
            : null,
      ),
    ),
  );
}

class _Paging extends StatelessWidget {
  const _Paging(this.page, this.onPage);
  final SmsReceiptPage<SmsReceiptSource> page;
  final ValueChanged<int> onPage;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          page.total == 0
              ? '0 records'
              : 'Showing ${page.offset + 1}–${page.offset + page.rows.length} of ${page.total}',
        ),
      ),
      IconButton(
        tooltip: 'Previous page',
        onPressed: page.offset > 0
            ? () => onPage((page.offset - page.limit).clamp(0, page.offset))
            : null,
        icon: const Icon(Icons.chevron_left),
      ),
      IconButton(
        tooltip: 'Next page',
        onPressed: page.nextOffset == null
            ? null
            : () => onPage(page.nextOffset!),
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );
}

Widget _filter(
  String label,
  String current,
  Iterable<String> choices,
  ValueChanged<String> onChange,
) => SizedBox(
  width: 245,
  child: DropdownButtonFormField<String>(
    key: ValueKey('$label-$current'),
    initialValue: current,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      DropdownMenuItem(value: '', child: Text('All ${label.toLowerCase()}')),
      for (final value in choices)
        DropdownMenuItem(value: value, child: Text(_label(value))),
    ],
    onChanged: (value) => onChange(value!),
  ),
);

class CloudflareAdminSmsReceiptsPage extends ConsumerStatefulWidget {
  const CloudflareAdminSmsReceiptsPage({super.key});
  @override
  ConsumerState<CloudflareAdminSmsReceiptsPage> createState() =>
      _ReceiptsState();
}

class _ReceiptsState extends ConsumerState<CloudflareAdminSmsReceiptsPage> {
  final _search = TextEditingController();
  String _applied = '',
      _status = '',
      _source = '',
      _extraction = '',
      _duplicates = '';
  String? _last;
  int _offset = 0, _limit = 25;
  _ListQuery get _query => (
    search: _applied,
    status: _status,
    source: _source,
    extraction: _extraction,
    duplicates: _duplicates,
    offset: _offset,
    limit: _limit,
  );
  String get _location => Uri(
    path: '/admin/sms-receipts',
    queryParameters: {
      if (_applied.isNotEmpty) 'search': _applied,
      if (_status.isNotEmpty) 'status': _status,
      if (_source.isNotEmpty) 'source': _source,
      if (_extraction.isNotEmpty) 'extraction': _extraction,
      if (_duplicates.isNotEmpty) 'duplicates': _duplicates,
      if (_offset > 0) 'page': '${_offset ~/ _limit + 1}',
      if (_limit != 25) 'limit': '$_limit',
    },
  ).toString();
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uri = GoRouterState.of(context).uri;
    if (uri.path != '/admin/sms-receipts' || uri.toString() == _last) return;
    _last = uri.toString();
    final query = Uri.parse(smsReturnLocation(uri.toString())).queryParameters;
    _applied = query['search'] ?? '';
    _search.text = _applied;
    _status = query['status'] ?? '';
    _source = query['source'] ?? '';
    _extraction = query['extraction'] ?? '';
    _duplicates = query['duplicates'] ?? '';
    _limit = int.parse(query['limit'] ?? '25');
    _offset = (int.parse(query['page'] ?? '1') - 1) * _limit;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _change(VoidCallback change) {
    setState(() {
      change();
      _offset = 0;
    });
    context.go(_location);
  }

  void _open(AdminTableRowData row) => context.go(
    Uri(
      path:
          '/admin/sms-receipts/${row.extra['source_kind']}/${row.extra['id']}',
      queryParameters: {'returnTo': _location},
    ).toString(),
  );
  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'SMS receipts',
    subtitle:
        'Preserved receipt evidence and extracted facts. Metadata acceptance and extraction do not confirm payment or settlement.',
    trailing: IconButton(
      tooltip: 'Refresh SMS receipts',
      onPressed: () => ref.invalidate(_receiptsProvider(_query)),
      icon: const Icon(Icons.refresh),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          maxLength: 200,
          decoration: const InputDecoration(
            labelText: 'Search SMS receipts',
            hintText: 'Source name, payer, phone, MoMo transaction or code',
          ),
          onSubmitted: (value) => _change(() => _applied = value.trim()),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _filter(
              'Sources',
              _source,
              smsSourceKinds,
              (value) => _change(() => _source = value),
            ),
            _filter(
              'Statuses',
              _status,
              smsReceiptStatuses,
              (value) => _change(() => _status = value),
            ),
            _filter(
              'Extraction',
              _extraction,
              smsExtractionStatuses,
              (value) => _change(() => _extraction = value),
            ),
            _filter(
              'Duplicate references',
              _duplicates,
              const ['all', 'conflicting'],
              (value) => _change(() => _duplicates = value),
            ),
          ],
        ),
        const SizedBox(height: 20),
        ref
            .watch(_receiptsProvider(_query))
            .when(
              loading: () =>
                  const AdminLoadingState(message: 'Loading SMS receipts…'),
              error: (error, _) => _Message(_error(error), error: true),
              data: (page) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (page.rows.isEmpty)
                    const _Message('No SMS receipts match these filters.'),
                  AdminDataTable(
                    rows: page.rows.map((row) => _row(row.values)).toList(),
                    columns: _sourceColumns,
                    tableLabel: 'SMS receipts',
                    onOpen: _open,
                  ),
                  _Paging(page, (offset) {
                    setState(() => _offset = offset);
                    context.go(_location);
                  }),
                ],
              ),
            ),
      ],
    ),
  );
}

class CloudflareAdminSmsReceiptDetailPage extends ConsumerStatefulWidget {
  const CloudflareAdminSmsReceiptDetailPage({
    required this.sourceKind,
    required this.id,
    this.returnTo,
    super.key,
  });
  final String sourceKind, id;
  final String? returnTo;
  @override
  ConsumerState<CloudflareAdminSmsReceiptDetailPage> createState() =>
      _ReceiptDetailState();
}

class _ReceiptDetailState
    extends ConsumerState<CloudflareAdminSmsReceiptDetailPage> {
  final _reason = TextEditingController(),
      _revealReason = TextEditingController();
  int _offset = 0;
  bool _busy = false,
      _unknown = false,
      _retryAllowed = false,
      _needsRefresh = false,
      _confirmed = false,
      _revealConfirmed = false;
  Object? _authority;
  int _actionEpoch = 0;
  String? _message;
  SmsExtractionAttempt? _attempt;
  SmsExtractionReceipt? _receipt;
  SmsSourceContent? _content;
  _DetailQuery get _query =>
      (kind: widget.sourceKind, id: widget.id, offset: _offset);
  String get _identity => '${widget.sourceKind}/${widget.id}';
  String get _recoveryResource => '${widget.sourceKind}:${widget.id}';
  static const _recoverySchema = AdminPendingAttemptSchema(
    fields: {'reason', 'expected_source_sha256'},
  );
  bool get _locked => _busy || _unknown || _needsRefresh;
  @override
  void initState() {
    super.initState();
    _restore();
  }

  void _restore() {
    _authority = ref
        .read(cloudflareAdminSessionProvider)
        .asData
        ?.value
        ?.authorityKey;
    _attempt = ref.read(cloudflareAdminSmsAttemptsProvider)[_identity];
    if (_attempt == null) {
      final checkpoint = ref
          .read(adminPendingAttemptStoreProvider)
          .restore(
            family: 'sms-extraction',
            resourceId: _recoveryResource,
            schema: _recoverySchema,
          );
      if (checkpoint != null) {
        try {
          _attempt = ref
              .read(cloudflareAdminSmsApiProvider)
              .restoreAttempt(
                key: checkpoint.requestKey,
                sourceKind: widget.sourceKind,
                sourceId: widget.id,
                body: checkpoint.intent,
              );
        } catch (_) {
          _message =
              'Recovery data could not be verified. Keep the original request reference and check the server receipt.';
        }
      }
    }
    _unknown = _attempt != null;
    _reason.text = '${_attempt?.body['reason'] ?? ''}';
    _confirmed = _unknown;
    if (_unknown) {
      _message =
          'Outcome unknown. Check the original request receipt before continuing.';
    }
  }

  @override
  void didUpdateWidget(
    covariant CloudflareAdminSmsReceiptDetailPage oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceKind != widget.sourceKind ||
        oldWidget.id != widget.id) {
      _reset();
      _restore();
    }
  }

  void _reset() {
    _actionEpoch++;
    _offset = 0;
    _busy = false;
    _unknown = false;
    _retryAllowed = false;
    _needsRefresh = false;
    _confirmed = false;
    _revealConfirmed = false;
    _attempt = null;
    _receipt = null;
    _content = null;
    _message = null;
    _reason.clear();
    _revealReason.clear();
  }

  @override
  void dispose() {
    _reason.dispose();
    _revealReason.dispose();
    super.dispose();
  }

  void _remember(SmsExtractionAttempt attempt) {
    ref
        .read(adminPendingAttemptStoreProvider)
        .retain(
          family: 'sms-extraction',
          resourceId: _recoveryResource,
          requestKey: attempt.key,
          permission: 'sms.extract',
          intent: attempt.body,
          schema: _recoverySchema,
        );
    final store = ref.read(cloudflareAdminSmsAttemptsProvider.notifier);
    store.state = {...store.state, attempt.identity: attempt};
  }

  void _forget() {
    ref
        .read(adminPendingAttemptStoreProvider)
        .clear(family: 'sms-extraction', resourceId: _recoveryResource);
    final store = ref.read(cloudflareAdminSmsAttemptsProvider.notifier);
    store.state = {...store.state}..remove(_identity);
  }

  bool _same(Object? authority, int epoch) =>
      mounted &&
      epoch == _actionEpoch &&
      authority != null &&
      authority ==
          ref.read(cloudflareAdminSessionProvider).asData?.value?.authorityKey;
  void _accepted(SmsExtractionReceipt receipt) {
    _forget();
    setState(() {
      _receipt = receipt;
      _attempt = null;
      _unknown = false;
      _retryAllowed = false;
      _needsRefresh = false;
      _confirmed = false;
      _message =
          'Extraction recorded. The server receipt confirms saved facts; payment and settlement are not asserted.';
    });
    ref.invalidate(_detailProvider(_query));
    refreshCloudflareAdminData(ref);
  }

  Future<void> _submit([SmsReceiptSource? source]) async {
    if (_busy || !_confirmed || _unknown && !_retryAllowed) return;
    final api = ref.read(cloudflareAdminSmsApiProvider),
        authority = _authority,
        epoch = _actionEpoch;
    try {
      final attempt = _attempt ?? api.extract(source!, _reason.text);
      _remember(attempt);
      _attempt = attempt;
      setState(() {
        _busy = true;
        _retryAllowed = false;
        _message = null;
      });
      final receipt = await api.submit(attempt);
      if (_same(authority, epoch)) _accepted(receipt);
    } catch (error) {
      if (_same(authority, epoch)) {
        final unknown =
            error is CloudflareAdminRequestException &&
            (error.outcomeUnknown || error.code == 'request_pending');
        setState(() {
          _unknown = unknown;
          _needsRefresh = !unknown;
          _message = unknown
              ? 'Outcome unknown. Check the original request receipt before continuing.'
              : _error(error);
          if (!unknown) _attempt = null;
        });
        if (!unknown) _forget();
      }
    } finally {
      if (_same(authority, epoch)) setState(() => _busy = false);
    }
  }

  Future<void> _recover() async {
    if (_busy || _attempt == null) return;
    final authority = _authority, attempt = _attempt!, epoch = _actionEpoch;
    setState(() {
      _busy = true;
      _retryAllowed = false;
    });
    try {
      final lookup = await ref
          .read(cloudflareAdminSmsApiProvider)
          .lookup(attempt);
      if (!_same(authority, epoch)) return;
      if (lookup.receipt != null) {
        _accepted(lookup.receipt!);
      } else if (lookup.status == 'failed') {
        _forget();
        setState(() {
          _attempt = null;
          _unknown = false;
          _needsRefresh = true;
          _message =
              'The server recorded a failed request. Refresh the source before preparing another extraction.';
        });
      } else {
        setState(() {
          _unknown = true;
          _retryAllowed = lookup.status == 'not_found';
          _message = _retryAllowed
              ? 'No receipt was found for the original request. You may retry the same locked request key and payload.'
              : 'The original request is pending. Check its receipt again before continuing.';
        });
      }
    } catch (error) {
      if (_same(authority, epoch)) setState(() => _message = _error(error));
    } finally {
      if (_same(authority, epoch)) setState(() => _busy = false);
    }
  }

  Future<void> _reviewRetry() async {
    if (_busy || !_retryAllowed || _attempt == null) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review identical extraction retry'),
        content: SelectableText(
          'Source: $_identity\nSource SHA-256: ${_attempt!.body['expected_source_sha256']}\nReason: ${_attempt!.body['reason']}\nOriginal request: ${_attempt!.key}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back to review'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm identical retry'),
          ),
        ],
      ),
    );
    if (accepted == true && _same(_authority, _actionEpoch)) await _submit();
  }

  Future<void> _reveal(SmsReceiptSource source) async {
    if (_locked || !_revealConfirmed) return;
    final authority = _authority, epoch = _actionEpoch;
    setState(() {
      _busy = true;
      _message = null;
      _content = null;
    });
    try {
      final content = await ref
          .read(cloudflareAdminSmsApiProvider)
          .reveal(source, _revealReason.text);
      if (_same(authority, epoch)) {
        setState(() {
          _content = content;
          _revealConfirmed = false;
          _message =
              'Source access recorded. This original message remains evidence, not provider confirmation.';
        });
      }
    } catch (error) {
      if (_same(authority, epoch)) setState(() => _message = _error(error));
    } finally {
      if (_same(authority, epoch)) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    if (_busy) return;
    final authority = _authority, epoch = _actionEpoch;
    setState(() {
      _busy = true;
      _confirmed = _unknown;
      _content = null;
    });
    try {
      final refreshed = await ref.refresh(_detailProvider(_query).future);
      if (_same(authority, epoch) &&
          !_unknown &&
          refreshed.source.identity == _identity) {
        setState(() {
          _needsRefresh = false;
          _message = null;
        });
      }
    } catch (error) {
      if (_same(authority, epoch)) {
        setState(() {
          _needsRefresh = !_unknown;
          _message = _error(error);
        });
      }
    } finally {
      if (_same(authority, epoch)) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      cloudflareAdminSessionProvider.select(
        (state) => state.asData?.value?.authorityKey,
      ),
      (previous, next) {
        if (_authority != next) {
          setState(() {
            _reset();
            _restore();
          });
        }
      },
    );
    final api = ref.watch(cloudflareAdminSmsApiProvider),
        current =
            ref
                .watch(cloudflareAdminSessionProvider)
                .asData
                ?.value
                ?.authorityKey ==
            _authority;
    return AdminPage(
      title: 'SMS receipt detail',
      subtitle:
          'One preserved source. Extracted facts, duplicate references and source review remain separate from payment confirmation.',
      leading: IconButton(
        tooltip: 'Back to SMS receipts',
        onPressed: _busy
            ? null
            : () => context.go(smsReturnLocation(widget.returnTo)),
        icon: const Icon(Icons.arrow_back),
      ),
      trailing: IconButton(
        tooltip: 'Refresh SMS receipt',
        onPressed: _busy ? null : _refresh,
        icon: const Icon(Icons.refresh),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_message != null)
            _Message(_message!, error: _unknown || _needsRefresh),
          if (!ref.watch(adminPendingAttemptStoreProvider).storageAvailable)
            _Message(
              ref.read(adminPendingAttemptStoreProvider).storageMessage,
              error: true,
            ),
          if (_busy)
            const AdminLoadingState(
              message: 'Checking the SMS receipt service…',
            ),
          ref
              .watch(_detailProvider(_query))
              .when(
                loading: () =>
                    const AdminLoadingState(message: 'Loading SMS receipt…'),
                error: (error, _) => _Message(_error(error), error: true),
                data: (detail) => !current
                    ? const _Message(
                        'Reopen this receipt with your current account.',
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AdminDataTable(
                            rows: [_row(detail.source.values)],
                            columns: [
                              ..._sourceColumns,
                              _column('User ID', 'user_id'),
                              _column('Payee ID', 'payee_id'),
                              _column('Profile ID', 'public_id', numeric: true),
                              _column('Linked transaction', 'transaction_id'),
                              _column(
                                'Source version',
                                'version',
                                numeric: true,
                              ),
                              _column('Fact ID', 'source_fact_id'),
                              _column('Parser', 'parser_version'),
                              _column('Body SHA-256', 'source_body_sha256'),
                              _column(
                                'Payload SHA-256',
                                'source_payload_sha256',
                              ),
                              _column('Extracted', 'parsed_at', time: true),
                              _column('Created', 'created_at', time: true),
                            ],
                            tableLabel: 'SMS source facts',
                          ),
                          const _Message(
                            'A dash means the source did not establish that fact. A source timestamp without a timezone is shown exactly as extracted. Duplicate references require review and do not merge records.',
                          ),
                          Text(
                            'Duplicate MoMo references',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          if (detail.duplicates.rows.isEmpty)
                            const Text('No related duplicate references.'),
                          AdminDataTable(
                            rows: detail.duplicates.rows
                                .map((row) => _row(row.values))
                                .toList(),
                            columns: _sourceColumns,
                            tableLabel: 'Duplicate SMS references',
                            onOpen: (row) => context.go(
                              Uri(
                                path:
                                    '/admin/sms-receipts/${row.extra['source_kind']}/${row.extra['id']}',
                                queryParameters: {
                                  'returnTo': smsReturnLocation(
                                    widget.returnTo,
                                  ),
                                },
                              ).toString(),
                            ),
                          ),
                          _Paging(
                            detail.duplicates,
                            (offset) => setState(() => _offset = offset),
                          ),
                          if (detail.canExtract && api.canExtract) ...[
                            const SizedBox(height: 24),
                            Text(
                              'Extract source facts',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const _Message(
                              'Review the recorded source digest and your reason before confirming. Extraction records source facts only.',
                            ),
                            TextField(
                              key: const Key('sms-extraction-reason'),
                              controller: _reason,
                              enabled: !_locked,
                              maxLength: 1000,
                              decoration: const InputDecoration(
                                labelText: 'Extraction reason',
                              ),
                              onChanged: (_) =>
                                  setState(() => _confirmed = false),
                            ),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'I reviewed the source digest and reason for this extraction.',
                              ),
                              value: _confirmed,
                              onChanged: _locked
                                  ? null
                                  : (value) =>
                                        setState(() => _confirmed = value!),
                            ),
                            AdminDataTable(
                              rows: [
                                _row({
                                  'source_kind': widget.sourceKind,
                                  'id': widget.id,
                                  'expected_source_sha256':
                                      _attempt
                                          ?.body['expected_source_sha256'] ??
                                      detail.source.sourceHash,
                                  'reason':
                                      _attempt?.body['reason'] ?? _reason.text,
                                  'idempotency_key': _attempt?.key,
                                }),
                              ],
                              columns: [
                                _column('Source', 'source_kind'),
                                _column('Source ID', 'id'),
                                _column(
                                  'Expected source SHA-256',
                                  'expected_source_sha256',
                                ),
                                _column('Reason', 'reason'),
                                _column(
                                  'Original request key',
                                  'idempotency_key',
                                ),
                              ],
                              tableLabel: 'Extraction review',
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                FilledButton(
                                  onPressed:
                                      _locked ||
                                          !_confirmed ||
                                          _reason.text.trim().length < 8
                                      ? null
                                      : () => _submit(detail.source),
                                  child: const Text('Confirm extraction'),
                                ),
                                if (_unknown)
                                  OutlinedButton(
                                    onPressed: _busy ? null : _recover,
                                    child: const Text('Check original request'),
                                  ),
                                if (_unknown && _retryAllowed)
                                  OutlinedButton(
                                    onPressed: _busy ? null : _reviewRetry,
                                    child: const Text(
                                      'Retry unchanged request',
                                    ),
                                  ),
                              ],
                            ),
                          ],
                          if (_receipt != null) ...[
                            const SizedBox(height: 20),
                            Text(
                              'Saved extraction receipt',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            AdminDataTable(
                              rows: [_row(_receipt!.values)],
                              columns: [
                                _column('Request', 'request_id'),
                                _column('Status', 'status'),
                                _column('Fact ID', 'resource_id'),
                                _column('Source', 'source_kind'),
                                _column('Source ID', 'source_id'),
                                _column('Parser', 'parser_version'),
                              ],
                              tableLabel: 'Saved extraction receipt',
                            ),
                          ],
                          if (api.canReveal) ...[
                            const SizedBox(height: 24),
                            Text(
                              'Review original source',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const _Message(
                              'Opening the preserved source records an audit entry with your reason. Source content is restricted to authorised Admin and Owner accounts.',
                            ),
                            TextField(
                              key: const Key('sms-source-review-reason'),
                              controller: _revealReason,
                              enabled: !_locked,
                              maxLength: 1000,
                              decoration: const InputDecoration(
                                labelText: 'Source review reason',
                              ),
                              onChanged: (_) =>
                                  setState(() => _revealConfirmed = false),
                            ),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'Record my reason and open the original source.',
                              ),
                              value: _revealConfirmed,
                              onChanged: _locked
                                  ? null
                                  : (value) => setState(
                                      () => _revealConfirmed = value!,
                                    ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton(
                                onPressed:
                                    _locked ||
                                        !_revealConfirmed ||
                                        _revealReason.text.trim().length < 8
                                    ? null
                                    : () => _reveal(detail.source),
                                child: const Text('Open audited source'),
                              ),
                            ),
                            if (_content != null &&
                                _content!.sourceHash ==
                                    detail.source.sourceHash) ...[
                              const SizedBox(height: 16),
                              _SourceContentTable(content: _content!),
                            ],
                          ],
                        ],
                      ),
              ),
        ],
      ),
    );
  }
}

/// The original message remains complete and selectable in its own table column.
/// Its row grows to fit multiline content rather than imposing the listing height.
class _SourceContentTable extends StatefulWidget {
  const _SourceContentTable({required this.content});
  final SmsSourceContent content;
  @override
  State<_SourceContentTable> createState() => _SourceContentTableState();
}

class _SourceContentTableState extends State<_SourceContentTable> {
  final _scroll = ScrollController();
  final _focus = FocusNode(
    debugLabel: 'Original SMS source horizontal scrolling',
  );
  @override
  void dispose() {
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent ||
          !_scroll.hasClients ||
          !{
            LogicalKeyboardKey.arrowLeft,
            LogicalKeyboardKey.arrowRight,
          }.contains(event.logicalKey)) {
        return KeyEventResult.ignored;
      }
      _scroll.jumpTo(
        (_scroll.offset +
                (event.logicalKey == LogicalKeyboardKey.arrowRight
                    ? 180
                    : -180))
            .clamp(0, _scroll.position.maxScrollExtent),
      );
      return KeyEventResult.handled;
    },
    child: Semantics(
      container: true,
      label: 'Original SMS source table, 1 row',
      hint:
          'Scroll horizontally to see all columns. Use left and right arrows when focused.',
      child: Scrollbar(
        controller: _scroll,
        thumbVisibility: true,
        interactive: true,
        scrollbarOrientation: ScrollbarOrientation.bottom,
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          child: DataTable(
            dataRowMaxHeight: double.infinity,
            columns: const [
              DataColumn(label: Text('Sender')),
              DataColumn(label: Text('Original SMS')),
              DataColumn(label: Text('Source SHA-256')),
            ],
            rows: [
              DataRow(
                cells: [
                  DataCell(SelectableText(widget.content.sender)),
                  DataCell(
                    SizedBox(
                      width: 520,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SelectableText(widget.content.body),
                            TextButton.icon(
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: widget.content.body),
                                );
                              },
                              icon: const Icon(Icons.copy),
                              label: const Text('Copy original SMS'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  DataCell(SelectableText(widget.content.sourceHash)),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
