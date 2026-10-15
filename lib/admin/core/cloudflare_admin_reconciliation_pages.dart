import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/components/admin_data_table.dart';
import '../shared/components/admin_loading_state.dart';
import '../shared/components/admin_page.dart';
import 'admin_account_api.dart';
import 'admin_pending_attempt_store.dart';
import 'admin_display_formatters.dart';
import 'admin_models.dart';
import 'cloudflare_admin_reconciliation_api.dart';
import 'cloudflare_admin_session.dart';

part 'cloudflare_admin_reconciliation_detail_pages.dart';

typedef _QueueQuery = ({
  String search,
  String verification,
  String allocation,
  int offset,
});
typedef _DetailQuery = ({String id, String? relation, int offset});
typedef _MemberQuery = ({String id, String search, int offset});
final _queueProvider = FutureProvider.autoDispose
    .family<ReconciliationPage<ReconciliationTransaction>, _QueueQuery>(
      (ref, query) => ref
          .watch(cloudflareReconciliationApiProvider)
          .queue(
            search: query.search,
            verification: query.verification,
            allocation: query.allocation,
            offset: query.offset,
          ),
    );
final _detailProvider = FutureProvider.autoDispose
    .family<ReconciliationDetail, _DetailQuery>(
      (ref, query) => ref
          .watch(cloudflareReconciliationApiProvider)
          .detail(query.id, relation: query.relation, offset: query.offset),
    );
final _membersProvider = FutureProvider.autoDispose
    .family<ReconciliationPage<ReconciliationMember>, _MemberQuery>(
      (ref, query) => ref
          .watch(cloudflareReconciliationApiProvider)
          .members(query.id, search: query.search, offset: query.offset),
    );

String reconciliationReturnLocation(String? location) {
  final uri = location == null ? null : Uri.tryParse(location);
  if (uri == null ||
      location!.length > 2000 ||
      uri.hasScheme ||
      uri.hasAuthority ||
      uri.hasFragment ||
      uri.path != '/admin/reconciliations' ||
      RegExp(r'[\x00-\x20\\]').hasMatch(location) ||
      uri.queryParametersAll.entries.any(
        (entry) =>
            !{
              'search',
              'verification',
              'allocation',
              'page',
            }.contains(entry.key) ||
            entry.value.length != 1,
      )) {
    return '/admin/reconciliations';
  }
  final query = uri.queryParameters,
      page = int.tryParse(uri.queryParameters['page'] ?? '1');
  if ((query['search'] ?? '').length > 200 ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(query['search'] ?? '') ||
      !{
        '',
        'pending',
        'confirmation_recorded',
        'evidence_conflict',
      }.contains(query['verification'] ?? '') ||
      !{
        '',
        'unallocated',
        'partially_allocated',
      }.contains(query['allocation'] ?? '') ||
      page == null ||
      page < 1 ||
      page > 85899346) {
    return '/admin/reconciliations';
  }
  return uri.toString();
}

String _label(String value) => value
    .split('_')
    .map(
      (word) =>
          word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}',
    )
    .join(' ');
String _value(Object? value) => value == null || value == '' ? '—' : '$value';
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
AdminTableRowData _row(
  Map<String, dynamic> values, {
  String? title,
}) => AdminTableRowData(
  id: '${values['id'] ?? values['member_user_id'] ?? values['request_id'] ?? 'facts'}',
  title:
      title ??
      '${values['provider_reference'] ?? values['display_name'] ?? values['id'] ?? 'Record'}',
  subtitle: '',
  status: '${values['status'] ?? ''}',
  amount: '',
  extra: values,
);
AdminTableColumn _column(
  String label,
  String field, {
  bool numeric = false,
  bool time = false,
  bool amount = false,
  bool status = false,
}) => AdminTableColumn(
  label: label,
  numeric: numeric,
  selectable: true,
  value: (row) => time
      ? _time(row.extra[field])
      : amount
      ? adminFormatWholeAmount(row.extra[field])
      : status
      ? _label('${row.extra[field] ?? ''}')
      : _value(row.extra[field]),
);
List<AdminTableColumn> _transactionColumns({bool sourceFacts = false}) => [
  if (sourceFacts) _column('ID', 'transaction_reference', numeric: true),
  _column('Provider reference', 'provider_reference'),
  if (sourceFacts) ...[
    _column('Payer name', 'payer_name'),
    _column('Payer phone', 'payer_phone', numeric: true),
    _column('Payer last 3', 'payer_last3', numeric: true),
    _column('MoMo transaction', 'momo_transaction_reference'),
    _column('MoMo local time', 'momo_timestamp_local'),
    _column('MoMo time zone', 'momo_timezone_offset'),
    _column(
      'Wallet balance',
      'wallet_balance_rwf',
      numeric: true,
      amount: true,
    ),
    _column('Direction', 'direction', status: true),
    _column('SMS source', 'source_kind', status: true),
    _column('Extraction', 'source_extraction_status', status: true),
  ],
  _column('Group', 'group_title'),
  _column('Payee', 'payee_name'),
  _column('Payee MoMo', 'payee_momo', numeric: true),
  _column('Amount', 'amount_rwf', numeric: true, amount: true),
  _column('Allocated', 'allocated_amount_rwf', numeric: true, amount: true),
  _column('Remaining', 'unallocated_amount_rwf', numeric: true, amount: true),
  _column('Allocation', 'allocation_status', status: true),
  _column('Verification', 'verification_status', status: true),
  _column('Pending proposals', 'pending_proposals', numeric: true),
  _column('Observed', 'observed_at', time: true),
  _column('Version', 'version', numeric: true),
];
List<AdminTableColumn> get _memberColumns => [
  _column('ID', 'public_id', numeric: true),
  _column('Name', 'display_name'),
  _column('Type', 'member_type', status: true),
  _column('MoMo number', 'momo_number', numeric: true),
  _column('MoMo code', 'momo_pay_code', numeric: true),
  _column('Group', 'group_title'),
  _column('Member version', 'member_version', numeric: true),
  _column('Membership version', 'membership_version', numeric: true),
];

class _Paging extends StatelessWidget {
  const _Paging({
    required this.total,
    required this.offset,
    required this.count,
    required this.next,
    required this.onPage,
  });
  final int total, offset, count;
  final int? next;
  final ValueChanged<int> onPage;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          total == 0
              ? '0 records'
              : 'Showing ${offset + 1}–${offset + count} of $total',
        ),
      ),
      IconButton(
        tooltip: 'Previous page',
        onPressed: offset > 0
            ? () => onPage((offset - 25).clamp(0, offset))
            : null,
        icon: const Icon(Icons.chevron_left),
      ),
      IconButton(
        tooltip: 'Next page',
        onPressed: next == null ? null : () => onPage(next!),
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );
}

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

class CloudflareReconciliationQueuePage extends ConsumerStatefulWidget {
  const CloudflareReconciliationQueuePage({super.key});
  @override
  ConsumerState<CloudflareReconciliationQueuePage> createState() =>
      _QueueState();
}

class _QueueState extends ConsumerState<CloudflareReconciliationQueuePage> {
  final _search = TextEditingController();
  String _applied = '', _verification = '', _allocation = '';
  int _offset = 0;
  String? _last;
  _QueueQuery get _query => (
    search: _applied,
    verification: _verification,
    allocation: _allocation,
    offset: _offset,
  );
  String get _location => Uri(
    path: '/admin/reconciliations',
    queryParameters: {
      if (_applied.isNotEmpty) 'search': _applied,
      if (_verification.isNotEmpty) 'verification': _verification,
      if (_allocation.isNotEmpty) 'allocation': _allocation,
      if (_offset > 0) 'page': '${_offset ~/ 25 + 1}',
    },
  ).toString();
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uri = GoRouterState.of(context).uri;
    if (uri.path != '/admin/reconciliations' || uri.toString() == _last) return;
    _last = uri.toString();
    final parsed = Uri.parse(
      reconciliationReturnLocation(uri.toString()),
    ).queryParameters;
    _applied = parsed['search'] ?? '';
    _search.text = _applied;
    _verification = parsed['verification'] ?? '';
    _allocation = parsed['allocation'] ?? '';
    _offset = ((int.tryParse(parsed['page'] ?? '1') ?? 1) - 1) * 25;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _go() => context.go(_location);
  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Reconciliations',
    subtitle:
        'Unallocated payments and member allocation proposals. Approval records an allocation; settlement is not asserted.',
    trailing: IconButton(
      tooltip: 'Refresh queue',
      onPressed: () => ref.invalidate(_queueProvider(_query)),
      icon: const Icon(Icons.refresh),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          decoration: const InputDecoration(
            labelText: 'Search payments',
            hintText: 'MoMo transaction, group, payee or member identity',
          ),
          onSubmitted: (value) {
            setState(() {
              _applied = value.trim();
              _offset = 0;
            });
            _go();
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<String>(
                key: ValueKey('verification-$_verification'),
                initialValue: _verification,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Verification'),
                items: [
                  for (final value in [
                    '',
                    'pending',
                    'confirmation_recorded',
                    'evidence_conflict',
                  ])
                    DropdownMenuItem(
                      value: value,
                      child: Text(
                        value.isEmpty
                            ? 'All verification states'
                            : _label(value),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  setState(() {
                    _verification = value!;
                    _offset = 0;
                  });
                  _go();
                },
              ),
            ),
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<String>(
                key: ValueKey('allocation-$_allocation'),
                initialValue: _allocation,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Allocation'),
                items: [
                  for (final value in [
                    '',
                    'unallocated',
                    'partially_allocated',
                  ])
                    DropdownMenuItem(
                      value: value,
                      child: Text(
                        value.isEmpty
                            ? 'All remaining balances'
                            : _label(value),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  setState(() {
                    _allocation = value!;
                    _offset = 0;
                  });
                  _go();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        ref
            .watch(_queueProvider(_query))
            .when(
              loading: () =>
                  const AdminLoadingState(message: 'Loading reconciliations'),
              error: (error, _) => _Message(_error(error), error: true),
              data: (page) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (page.total == 0)
                    const _Message('No remaining payments match these filters.')
                  else
                    AdminDataTable(
                      tableLabel: 'Reconciliation queue',
                      rows: page.rows
                          .map((transaction) => _row(transaction.values))
                          .toList(),
                      columns: [
                        for (final column in _transactionColumns(
                          sourceFacts: page.rows.any(
                            (row) =>
                                row.values.containsKey('transaction_reference'),
                          ),
                        ))
                          AdminTableColumn(
                            label: column.label,
                            value: column.value,
                            numeric: column.numeric,
                          ),
                      ],
                      onOpen: (row) => context.go(
                        Uri(
                          path: '/admin/reconciliations/${row.id}',
                          queryParameters: {'returnTo': _location},
                        ).toString(),
                      ),
                    ),
                  _Paging(
                    total: page.total,
                    offset: page.offset,
                    count: page.rows.length,
                    next: page.nextOffset,
                    onPage: (offset) {
                      setState(() => _offset = offset);
                      _go();
                    },
                  ),
                ],
              ),
            ),
      ],
    ),
  );
}
