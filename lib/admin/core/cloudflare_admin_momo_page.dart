import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/data/exact_json_values.dart';
import '../../app/theme/collect_motion.dart';
import '../shared/components/admin_data_listing.dart';
import '../shared/components/admin_data_table.dart';
import '../shared/components/admin_page.dart';
import 'admin_account_api.dart';
import 'admin_display_formatters.dart';
import 'admin_models.dart';
import 'admin_pending_attempt_store.dart';
import 'admin_repository_base.dart' show adminRealtimeTickProvider;
import 'cloudflare_admin_session.dart';
import 'cloudflare_admin_repository.dart';
import 'cloudflare_admin_sms_api.dart';

part 'cloudflare_admin_momo_transaction_dialogs.dart';
part 'cloudflare_admin_momo_source_review.dart';
part 'cloudflare_admin_momo_gateway_setup.dart';
part 'cloudflare_admin_momo_incoming_sms.dart';

const momoStatusLabels = {
  'needs_allocation': 'Needs allocation',
  'awaiting_review': 'Awaiting independent review',
  'credited': 'Credited',
  'needs_review': 'Needs review',
  'reversed': 'Reversed',
};
final _id = RegExp(r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$');
Never _invalid() =>
    throw const FormatException('The MoMo records could not be verified.');
Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : _invalid();
String _text(Object? value, {bool nullable = false}) {
  if (nullable && value == null) return '—';
  if (value is! String || value.trim().isEmpty || value.length > 2000) {
    _invalid();
  }
  return value;
}

String _identifier(Object? value) =>
    value is String && _id.hasMatch(value) ? value : _invalid();
String _error(Object error) => error is AdminAccountException
    ? error.message
    : error is FormatException
    ? 'The returned records could not be verified. Refresh to check again.'
    : 'The service could not be reached. Your last confirmed records are unchanged.';

class MomoTransaction {
  MomoTransaction._(this.values);
  final Map<String, dynamic> values;
  String get id => values['id'] as String;
  String get status => values['status'] as String;
  String get label => momoStatusLabels[status]!;
  int get amount => values['amount_minor'] as int;
  int get version => values['version'] as int;
  String? get paymentId => values['payment_id'] as String?;
  bool get hasConflict => values['has_conflict'] == 1;
  String get payer =>
      '${values['payer_name'] ?? 'Unknown payer'}'
      '${values['payer_last3'] == null ? '' : ' · …${values['payer_last3']}'}';
  String get transactionTime => values['transaction_at'] == null
      ? 'Received ${adminKigaliDateTime(DateTime.parse(values['created_at'] as String))}'
      : adminKigaliDateTime(DateTime.parse(values['transaction_at'] as String));
  factory MomoTransaction.parse(Map<String, dynamic> values) {
    _identifier(values['id']);
    _identifier(values['receiving_account_id']);
    _text(values['provider_transaction_id']);
    _text(values['recipient_name']);
    _text(values['public_code']);
    for (final field in [
      'payer_name',
      'payer_last3',
      'member_name',
      'group_name',
    ]) {
      _text(values[field], nullable: true);
    }
    if (values['payer_last3'] != null &&
        !RegExp(r'^[0-9]{3}$').hasMatch(values['payer_last3'] as String)) {
      _invalid();
    }
    for (final field in ['payment_id', 'beneficiary_member_id', 'group_id']) {
      if (values[field] != null) _identifier(values[field]);
    }
    final amount = exactJsonInteger(
      values['amount_minor'],
      field: 'MoMo amount',
      minimum: 1,
    );
    final credited = exactJsonInteger(
      values['credited_amount_minor'],
      field: 'MoMo credited amount',
      minimum: 0,
    );
    exactJsonInteger(values['version'], field: 'MoMo version', minimum: 1);
    exactJsonTimestamp(values['created_at'], field: 'MoMo received time');
    if (values['transaction_at'] != null) {
      exactJsonTimestamp(values['transaction_at'], field: 'MoMo provider time');
    }
    if (values['currency'] != 'RWF' ||
        !const {0, 1}.contains(values['has_conflict']) ||
        !momoStatusLabels.containsKey(values['status']) ||
        credited > amount ||
        (values['status'] == 'credited' &&
            (values['payment_id'] == null || credited == 0)) ||
        (values['status'] == 'awaiting_review' &&
            values['payment_id'] == null)) {
      _invalid();
    }
    return MomoTransaction._(Map.unmodifiable(values));
  }
}

class MomoTransactionPage {
  MomoTransactionPage(
    this.rows,
    this.total,
    this.offset,
    this.limit,
    this.totals,
    this.asOf,
  );
  final List<MomoTransaction> rows;
  final int total, offset, limit;
  final Map<String, int> totals;
  final DateTime asOf;
  factory MomoTransactionPage.parse(Map<String, dynamic> data) {
    if (data['contract_version'] != 1 ||
        data['currency'] != 'RWF' ||
        data['date_basis'] != 'provider_transaction_time' ||
        data['rows'] is! List) {
      _invalid();
    }
    final total = exactJsonInteger(
      data['total'],
      field: 'MoMo total',
      minimum: 0,
    );
    final offset = exactJsonInteger(
      data['offset'],
      field: 'MoMo offset',
      minimum: 0,
    );
    final limit = exactJsonInteger(
      data['limit'],
      field: 'MoMo limit',
      minimum: 1,
      maximum: 100,
    );
    final rows = [
      for (final row in data['rows'] as List) MomoTransaction.parse(_map(row)),
    ];
    if (rows.length != (total - offset).clamp(0, limit) ||
        rows.map((row) => row.id).toSet().length != rows.length) {
      _invalid();
    }
    final amounts = _map(data['totals']);
    return MomoTransactionPage(
      List.unmodifiable(rows),
      total,
      offset,
      limit,
      {
        for (final field in [
          'received_minor',
          'credited_minor',
          'unallocated_minor',
        ])
          field: exactJsonInteger(amounts[field], field: field, minimum: 0),
      },
      exactJsonTimestamp(data['as_of'], field: 'MoMo measured time'),
    );
  }
}

class MomoAdminApi {
  MomoAdminApi(this.session) : _fence = session.authorityFence;
  final CloudflareAdminSession session;
  final Object _fence;
  Object get fence => _fence;
  void require(String permission, {bool fresh = false}) {
    final user = session.user;
    if (user == null ||
        _fence != session.authorityFence ||
        !user.expiresAt.isAfter(DateTime.now()) ||
        !user.permissions.contains(permission)) {
      throw const AdminAccountException(
        'Reopen this view with an authorized account.',
      );
    }
    if (fresh && !user.hasRecentSensitiveVerification()) {
      throw AdminAccountException(
        user.usesEmailVerification
            ? 'Verify your email before saving.'
            : 'Complete a current authenticator check before saving.',
      );
    }
  }

  Future<Map<String, dynamic>> read(
    String path,
    String permission, {
    String? reason,
  }) async {
    require(permission);
    final data = await session.request(
      'momo/$path',
      authenticated: true,
      reviewReason: reason,
    );
    require(permission);
    return data;
  }

  Future<MomoTransactionPage> transactions(
    String search,
    String status,
    int offset, {
    String receivingAccount = '',
    String group = '',
    String from = '',
    String to = '',
  }) async {
    if (receivingAccount.isNotEmpty) _identifier(receivingAccount);
    if (group.isNotEmpty) _identifier(group);
    final fromDate = from.isEmpty
        ? null
        : exactJsonTimestamp(from, field: 'Filter start');
    final toDate = to.isEmpty
        ? null
        : exactJsonTimestamp(to, field: 'Filter end');
    final query = Uri(
      queryParameters: {
        'search': search,
        'status': status,
        'limit': '25',
        'offset': '$offset',
        if (receivingAccount.isNotEmpty)
          'receiving_account_id': receivingAccount,
        if (group.isNotEmpty) 'group_id': group,
        if (from.isNotEmpty) 'from': from,
        if (to.isNotEmpty) 'to': to,
      },
    ).query;
    final page = MomoTransactionPage.parse(
      await read('transactions?$query', 'payments.read'),
    );
    bool matches(MomoTransaction row) => switch (status) {
      '' => true,
      'needs_attention' =>
        row.hasConflict ||
            const {
              'needs_allocation',
              'awaiting_review',
              'needs_review',
            }.contains(row.status),
      'needs_review' => row.hasConflict || row.status == 'needs_review',
      _ => row.status == status,
    };
    bool inScope(MomoTransaction row) {
      final time = row.values['transaction_at'] == null
          ? null
          : DateTime.parse(row.values['transaction_at'] as String);
      return (receivingAccount.isEmpty ||
              row.values['receiving_account_id'] == receivingAccount) &&
          (group.isEmpty || row.values['group_id'] == group) &&
          (fromDate == null || time != null && !time.isBefore(fromDate)) &&
          (toDate == null || time != null && !time.isAfter(toDate));
    }

    if (page.offset != offset ||
        page.limit != 25 ||
        page.rows.any((row) => !matches(row) || !inScope(row))) {
      _invalid();
    }
    return page;
  }
}

class _Scope extends ConsumerWidget {
  const _Scope({required this.fence, required this.child});
  final Object fence;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(cloudflareAdminSessionProvider);
    if (ref.read(cloudflareAdminSessionProvider.notifier).authorityFence !=
        fence) {
      return AlertDialog(
        title: const Text('Account changed'),
        content: const Text(
          'Reopen this record with the current authorized account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    }
    return child;
  }
}

@immutable
class MomoTransactionFilters {
  const MomoTransactionFilters({
    this.accountId = '',
    this.accountLabel = '',
    this.groupId = '',
    this.groupLabel = '',
    this.dates,
  });
  final String accountId, accountLabel, groupId, groupLabel;
  final DateTimeRange? dates;
  // Use the same Africa/Kigali calendar as adminKigaliDateTime, independently
  // of the operator's browser timezone. The API's upper bound is inclusive.
  String get fromUtc => dates == null
      ? ''
      : DateTime.utc(
          dates!.start.year,
          dates!.start.month,
          dates!.start.day,
        ).subtract(const Duration(hours: 2)).toIso8601String();
  String get toUtc => dates == null
      ? ''
      : DateTime.utc(
          dates!.end.year,
          dates!.end.month,
          dates!.end.day + 1,
        ).subtract(const Duration(hours: 2, milliseconds: 1)).toIso8601String();
  String get dateLabel => dates == null
      ? 'All transaction dates'
      : '${adminKigaliDate(DateTime.parse(fromUtc))} – ${adminKigaliDate(DateTime.parse(toUtc))}';
  int get count =>
      (accountId.isEmpty ? 0 : 1) +
      (groupId.isEmpty ? 0 : 1) +
      (dates == null ? 0 : 1);
  String get summary => [
    if (dates != null) dateLabel,
    if (accountId.isNotEmpty) accountLabel,
    if (groupId.isNotEmpty) groupLabel,
  ].join(' · ');
}

class _MomoFilterControls extends ConsumerStatefulWidget {
  const _MomoFilterControls({
    required this.applied,
    required this.onApply,
    super.key,
  });
  final MomoTransactionFilters applied;
  final ValueChanged<MomoTransactionFilters> onApply;
  @override
  ConsumerState<_MomoFilterControls> createState() => _MomoFilterControlState();
}

class _MomoFilterControlState extends ConsumerState<_MomoFilterControls> {
  late String _account = widget.applied.accountId,
      _accountLabel = widget.applied.accountLabel,
      _group = widget.applied.groupId,
      _groupLabel = widget.applied.groupLabel;
  late DateTimeRange? _dates = widget.applied.dates;
  List<Map<String, dynamic>> _accounts = [];
  String? _lookupError;
  bool _accountsLoading = false, _unselectedGroup = false;
  int _groupLookup = 0;
  @override
  void initState() {
    super.initState();
    if (ref
            .read(cloudflareAdminSessionProvider)
            .asData
            ?.value
            ?.permissions
            .contains('receivers.read') ==
        true) {
      Future.microtask(_loadAccounts);
    }
  }

  Future<void> _loadAccounts() async {
    if (mounted) setState(() => _accountsLoading = true);
    try {
      final data = await ref
          .read(momoAdminApiProvider)
          .read('accounts', 'receivers.read');
      if (data['rows'] is! List) _invalid();
      final rows = [for (final value in data['rows'] as List) _map(value)];
      for (final row in rows) {
        _identifier(row['id']);
        _text(row['recipient_name']);
        _text(row['public_code']);
      }
      if (mounted) {
        setState(() {
          _accounts = rows;
          _lookupError = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _lookupError = _error(error));
    } finally {
      if (mounted) setState(() => _accountsLoading = false);
    }
  }

  Future<Iterable<AdminTableRowData>> _groups(TextEditingValue value) async {
    if (value.text.trim().isEmpty) return const [];
    final operation = ++_groupLookup;
    try {
      final api = ref.read(momoAdminApiProvider);
      api.require('collections.read');
      final result = await CloudflareAdminRepository(api.session).list(
        CloudflareCoreArea.groups.rpcName,
        search: value.text.trim(),
        limit: 25,
        offset: 0,
        status: '',
        sortBy: 'created_at_desc',
      );
      api.require('collections.read');
      if (mounted && operation == _groupLookup) {
        setState(() => _lookupError = null);
      }
      return result.rows;
    } catch (error) {
      if (mounted && operation == _groupLookup) {
        setState(() => _lookupError = _error(error));
      }
      return const [];
    }
  }

  Future<void> _pickDates() async {
    final dates = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100, 12, 31),
      initialDateRange: _dates,
      helpText: 'Provider transaction dates · Kigali',
    );
    if (mounted && dates != null) setState(() => _dates = dates);
  }

  void _apply() => widget.onApply(
    MomoTransactionFilters(
      accountId: _account,
      accountLabel: _accountLabel,
      groupId: _group,
      groupLabel: _groupLabel,
      dates: _dates,
    ),
  );
  @override
  Widget build(BuildContext context) {
    final permissions =
        ref.watch(cloudflareAdminSessionProvider).asData?.value?.permissions ??
        [];
    final selected = MomoTransactionFilters(dates: _dates);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < 700
            ? constraints.maxWidth
            : (constraints.maxWidth - 24) / 3;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.start,
                children: [
                  SizedBox(
                    width: width,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _pickDates,
                          icon: const Icon(Icons.date_range_outlined),
                          label: Text(selected.dateLabel),
                        ),
                        Text(
                          'Provider transaction date · Africa/Kigali',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        if (_dates != null)
                          TextButton(
                            onPressed: () => setState(() => _dates = null),
                            child: const Text('Clear dates'),
                          ),
                      ],
                    ),
                  ),
                  if (permissions.contains('receivers.read'))
                    SizedBox(
                      width: width,
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _account,
                        key: ValueKey(
                          'filter-account-$_account:${_accounts.length}',
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Receiving account',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('All receiving accounts'),
                          ),
                          for (final account in _accounts)
                            DropdownMenuItem(
                              value: account['id'] as String,
                              child: Text(
                                '${account['recipient_name']} · ${account['public_code']}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          if (_account.isNotEmpty &&
                              !_accounts.any((row) => row['id'] == _account))
                            DropdownMenuItem(
                              value: _account,
                              child: const Text('Selected account unavailable'),
                            ),
                        ],
                        onChanged: _accountsLoading
                            ? null
                            : (id) => setState(() {
                                _account = id ?? '';
                                final selected = _accounts
                                    .where((row) => row['id'] == _account)
                                    .firstOrNull;
                                if (_account.isEmpty) {
                                  _accountLabel = '';
                                } else if (selected != null) {
                                  _accountLabel =
                                      '${selected['recipient_name']}';
                                }
                              }),
                      ),
                    ),
                  if (permissions.contains('collections.read'))
                    SizedBox(
                      width: width,
                      child: Autocomplete<AdminTableRowData>(
                        initialValue: TextEditingValue(text: _groupLabel),
                        displayStringForOption: (row) => row.title,
                        optionsBuilder: _groups,
                        onSelected: (row) => setState(() {
                          _group = row.id;
                          _groupLabel = row.title;
                          _unselectedGroup = false;
                        }),
                        fieldViewBuilder:
                            (context, controller, focus, submit) => TextField(
                              key: const ValueKey('momo-group-filter-search'),
                              controller: controller,
                              focusNode: focus,
                              maxLength: 200,
                              decoration: const InputDecoration(
                                labelText: 'Find group',
                                counterText: '',
                                helperText:
                                    'Search a group name, then select a result.',
                              ),
                              onChanged: (value) => setState(() {
                                if (value != _groupLabel) {
                                  _group = '';
                                  _groupLabel = '';
                                }
                                _unselectedGroup =
                                    value.trim().isNotEmpty && _group.isEmpty;
                              }),
                              onSubmitted: (_) => submit(),
                            ),
                      ),
                    ),
                ],
              ),
              if (_accountsLoading)
                const LinearProgressIndicator(
                  semanticsLabel: 'Loading receiving accounts',
                ),
              if (_lookupError != null)
                Row(
                  children: [
                    Expanded(child: _Note(_lookupError!, error: true)),
                    if (permissions.contains('receivers.read'))
                      IconButton(
                        tooltip: 'Retry account lookup',
                        onPressed: _loadAccounts,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                  ],
                ),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _unselectedGroup ? null : _apply,
                    icon: const Icon(Icons.filter_alt_outlined),
                    label: const Text('Apply filters'),
                  ),
                  TextButton(
                    onPressed: () =>
                        widget.onApply(const MomoTransactionFilters()),
                    child: const Text('Clear filters'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

final momoAdminApiProvider = Provider<MomoAdminApi>((ref) {
  ref.watch(
    cloudflareAdminSessionProvider.select(
      (value) => value.asData?.value?.authorityKey,
    ),
  );
  return MomoAdminApi(ref.read(cloudflareAdminSessionProvider.notifier));
});
typedef _Query = ({
  String search,
  String status,
  int offset,
  String account,
  String group,
  String from,
  String to,
});
final _transactions = FutureProvider.autoDispose
    .family<MomoTransactionPage, _Query>((ref, query) {
      ref.watch(adminRealtimeTickProvider);
      return ref
          .watch(momoAdminApiProvider)
          .transactions(
            query.search,
            query.status,
            query.offset,
            receivingAccount: query.account,
            group: query.group,
            from: query.from,
            to: query.to,
          );
    });

class CloudflareAdminMomoPage extends ConsumerStatefulWidget {
  const CloudflareAdminMomoPage({super.key});
  @override
  ConsumerState<CloudflareAdminMomoPage> createState() => _MomoPageState();
}

class _MomoPageState extends ConsumerState<CloudflareAdminMomoPage> {
  final _search = TextEditingController();
  String _applied = '', _status = '';
  int _offset = 0;
  bool _attention = false, _incoming = true;
  MomoTransactionFilters _filters = const MomoTransactionFilters();
  MomoTransactionPage? _last;
  _Query? _lastQuery;
  Object? _authority;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _change(VoidCallback action) => setState(() {
    action();
    _offset = 0;
    _last = null;
  });
  Future<void> _open(MomoTransaction transaction) async {
    await showDialog<void>(
      context: context,
      animationStyle: CollectMotion.animationStyle(context),
      builder: (_) => _TransactionDialog(id: transaction.id),
    );
    if (mounted) ref.invalidate(_transactions);
  }

  Widget _views(List<String> permissions) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (permissions.contains('sms.read'))
          ChoiceChip(
            label: const Text('Incoming SMS'),
            selected: _incoming,
            onSelected: (_) => setState(() => _incoming = true),
          ),
        if (permissions.contains('payments.read'))
          ChoiceChip(
            label: const Text('Transactions'),
            selected: !_incoming || !permissions.contains('sms.read'),
            onSelected: (_) => setState(() => _incoming = false),
          ),
      ],
    ),
  );

  Widget? _operatorTools(List<String> permissions) =>
      permissions.contains('receivers.manage') &&
          permissions.contains('receivers.read')
      ? PopupMenuButton<String>(
          tooltip: 'More MoMo tools',
          popUpAnimationStyle: CollectMotion.animationStyle(context),
          icon: const Icon(Icons.more_horiz_rounded),
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'gateway',
              child: Text('Dedicated gateway (optional)'),
            ),
          ],
          onSelected: (_) => showDialog<void>(
            context: context,
            animationStyle: CollectMotion.animationStyle(context),
            builder: (_) => const _GatewaySetupDialog(),
          ),
        )
      : null;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(cloudflareAdminSessionProvider).asData?.value;
    if (_authority != user?.authorityKey) {
      _last = null;
      _filters = const MomoTransactionFilters();
      _incoming = true;
      _authority = user?.authorityKey;
    }
    final permissions = user?.permissions ?? <String>[];
    if (_incoming && permissions.contains('sms.read')) {
      return AdminPage(
        title: 'MoMo receipts',
        subtitle: 'Mobile-money SMS shared by app users.',
        trailing: _operatorTools(permissions),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _views(permissions),
            _IncomingSmsPanel(key: ValueKey(user?.authorityKey)),
          ],
        ),
      );
    }
    final query = (
      search: _applied,
      status: _status,
      offset: _offset,
      account: _filters.accountId,
      group: _filters.groupId,
      from: _filters.fromUtc,
      to: _filters.toUtc,
    );
    final result = ref.watch(_transactions(query));
    if (result.asData != null) {
      _last = result.asData!.value;
      _lastQuery = query;
    }
    final page = result.asData?.value ?? (_lastQuery == query ? _last : null);
    return AdminPage(
      title: 'MoMo receipts',
      subtitle: 'Validated payments and their allocation status.',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Refresh MoMo receipts',
            onPressed: () => ref.invalidate(_transactions(query)),
            icon: const Icon(Icons.refresh_rounded),
          ),
          ?_operatorTools(permissions),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _views(permissions),
          if (user?.permissions.contains('payments.read') == true &&
              user?.permissions.contains('users.read') == true &&
              user?.permissions.contains('collections.read') == true)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.support_agent_rounded),
                label: const Text('Member checks'),
                onPressed: () => showDialog<void>(
                  context: context,
                  animationStyle: CollectMotion.animationStyle(context),
                  builder: (dialogContext) => _MemberChecksDialog(
                    onSearch: (reference) {
                      Navigator.pop(dialogContext);
                      if (!mounted) return;
                      _change(() {
                        _search.text = reference;
                        _applied = reference;
                        _attention = false;
                        _status = '';
                      });
                    },
                  ),
                ),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All payments'),
                selected: !_attention,
                onSelected: (_) => _change(() {
                  _attention = false;
                  _status = '';
                }),
              ),
              ChoiceChip(
                label: const Text('Needs attention'),
                selected: _attention,
                onSelected: (_) => _change(() {
                  _attention = true;
                  _status = 'needs_attention';
                }),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _search,
            maxLength: 200,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: 'Search MoMo TX ID or payer',
              counterText: '',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                tooltip: 'Search receipts',
                icon: const Icon(Icons.arrow_forward_rounded),
                onPressed: () => _change(() => _applied = _search.text.trim()),
              ),
            ),
            onSubmitted: (value) => _change(() => _applied = value.trim()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _status,
            key: ValueKey('$_attention:$_status'),
            decoration: const InputDecoration(labelText: 'Payment status'),
            items: [
              if (!_attention)
                const DropdownMenuItem(value: '', child: Text('All statuses')),
              if (_attention)
                const DropdownMenuItem(
                  value: 'needs_attention',
                  child: Text('All attention'),
                ),
              for (final entry in momoStatusLabels.entries)
                if (!_attention ||
                    {
                      'needs_allocation',
                      'needs_review',
                      'awaiting_review',
                    }.contains(entry.key))
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (value) => _change(() => _status = value ?? ''),
          ),
          ExpansionTile(
            key: const ValueKey('momo-transaction-filters'),
            tilePadding: EdgeInsets.zero,
            leading: const Icon(Icons.filter_alt_outlined),
            title: const Text('Date, account and group'),
            subtitle: _filters.count == 0 ? null : Text(_filters.summary),
            children: [
              _MomoFilterControls(
                key: ValueKey((
                  _authority,
                  _filters.accountId,
                  _filters.groupId,
                  _filters.fromUtc,
                  _filters.toUtc,
                )),
                applied: _filters,
                onApply: (filters) => _change(() => _filters = filters),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (result.hasError) _Note(_error(result.error!), error: true),
          if (result.isLoading)
            const LinearProgressIndicator(
              semanticsLabel: 'Refreshing MoMo receipts',
            ),
          if (page != null) ...[
            Text(
              'Received ${adminFormatWholeAmount(page.totals['received_minor'])} RWF · '
              'Credited ${adminFormatWholeAmount(page.totals['credited_minor'])} RWF · '
              'Unallocated ${adminFormatWholeAmount(page.totals['unallocated_minor'])} RWF',
            ),
            const SizedBox(height: 6),
            Text(
              'Provider transaction date · As of ${adminKigaliDateTime(page.asOf)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (page.rows.isEmpty)
              const _Note('No matching validated payments.')
            else
              AdminDataTable(
                tableLabel: 'MoMo transactions',
                rows: [
                  for (final row in page.rows)
                    AdminTableRowData(
                      id: row.id,
                      title: row.values['provider_transaction_id'] as String,
                      subtitle: '',
                      status: '',
                      amount: '',
                      extra: row.values,
                    ),
                ],
                columns: [
                  AdminTableColumn(
                    label: 'Transaction time · Kigali',
                    value: (row) =>
                        MomoTransaction.parse(row.extra).transactionTime,
                  ),
                  AdminTableColumn(
                    label: 'Amount · RWF',
                    numeric: true,
                    value: (row) =>
                        adminFormatWholeAmount(row.extra['amount_minor']),
                  ),
                  AdminTableColumn(
                    label: 'Payer',
                    value: (row) => MomoTransaction.parse(row.extra).payer,
                  ),
                  AdminTableColumn(
                    label: 'MoMo TX ID',
                    selectable: true,
                    value: (row) => '${row.extra['provider_transaction_id']}',
                  ),
                  AdminTableColumn(
                    label: 'Beneficiary',
                    value: (row) =>
                        '${row.extra['member_name'] ?? 'Unassigned'}',
                  ),
                  AdminTableColumn(
                    label: 'Group',
                    value: (row) =>
                        '${row.extra['group_name'] ?? 'Unassigned'}',
                  ),
                  AdminTableColumn(
                    label: 'Status',
                    value: (row) => momoStatusLabels[row.extra['status']]!,
                  ),
                  AdminTableColumn(
                    label: 'Review issue',
                    value: (row) =>
                        row.extra['has_conflict'] == 1 ? 'Needs review' : '—',
                  ),
                ],
                onOpen: (row) => _open(MomoTransaction.parse(row.extra)),
              ),
            _Pager(
              total: page.total,
              offset: page.offset,
              limit: page.limit,
              onPage: (offset) => setState(() {
                _offset = offset;
                _last = null;
              }),
            ),
          ],
          if (_attention && user?.permissions.contains('sms.read') == true)
            _SourceExceptions(key: ValueKey(user?.authorityKey)),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {this.error = false});
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Semantics(
      liveRegion: true,
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: error ? Theme.of(context).colorScheme.error : null,
        ),
      ),
    ),
  );
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.total,
    required this.offset,
    required this.limit,
    required this.onPage,
  });
  final int total, offset, limit;
  final ValueChanged<int> onPage;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(
        total == 0
            ? '0 records'
            : '${offset + 1}–${(offset + limit).clamp(0, total)} of $total',
      ),
      IconButton(
        tooltip: 'Previous page',
        onPressed: offset == 0
            ? null
            : () => onPage((offset - limit).clamp(0, total)),
        icon: const Icon(Icons.chevron_left_rounded),
      ),
      IconButton(
        tooltip: 'Next page',
        onPressed: offset + limit >= total
            ? null
            : () => onPage(offset + limit),
        icon: const Icon(Icons.chevron_right_rounded),
      ),
    ],
  );
}
