import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/components/admin_data_table.dart';
import '../shared/components/admin_empty_state.dart';
import '../shared/components/admin_filter_bar.dart';
import '../shared/components/admin_loading_state.dart';
import '../shared/components/admin_page.dart';
import 'admin_error_boundary.dart';
import 'admin_auth_guard.dart';
import 'admin_display_formatters.dart';
import 'admin_list_paging.dart';
import 'admin_repository_base.dart';
import 'cloudflare_admin_repository.dart';
import 'cloudflare_admin_session.dart';

typedef _CoreQuery = ({
  CloudflareCoreArea area,
  String search,
  String status,
  String sort,
  int page,
});

/// Detail/create Back actions accept only this area's bounded list state.
String cloudflareCoreReturnLocation(CloudflareCoreArea area, String? location) {
  final uri = location == null ? null : Uri.tryParse(location);
  if (uri == null ||
      location!.length > 2000 ||
      uri.hasScheme ||
      uri.hasAuthority ||
      uri.hasFragment ||
      uri.path != area.path ||
      RegExp(r'[\x00-\x20\\]').hasMatch(location) ||
      uri.queryParametersAll.entries.any(
        (entry) =>
            !{'search', 'status', 'sort', 'page'}.contains(entry.key) ||
            entry.value.length != 1,
      )) {
    return area.path;
  }
  final parameters = uri.queryParameters;
  final search = parameters['search'] ?? '';
  final status = parameters['status'] ?? '';
  final sort = parameters['sort'] ?? 'created_at_desc';
  final page = int.tryParse(parameters['page'] ?? '1');
  if (search.length > 200 ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(search) ||
      status.isNotEmpty && !area.acceptsStatus(status) ||
      !area.acceptsSort(sort) ||
      page == null ||
      page < 1 ||
      page > 85899346) {
    return area.path;
  }
  return uri.toString();
}

final _coreListProvider = FutureProvider.autoDispose
    .family<AdminLoadedPage, _CoreQuery>((ref, query) async {
      ref.watch(adminRealtimeTickProvider);
      final authority = ref.watch(
        cloudflareAdminSessionProvider.select(
          (session) => session.asData?.value?.authorityKey,
        ),
      );
      if (authority == null) throw const AdminSessionChanged();
      final repository = ref.watch(adminRepositoryProvider);
      var current = true;
      ref.onDispose(() => current = false);
      final result = await loadAdminListPage(
        page: query.page,
        pageSize: 25,
        isCurrent: () => current,
        fetch: (limit, offset) => repository.list(
          query.area.rpcName,
          search: query.search,
          status: query.status,
          sortBy: query.sort,
          limit: limit,
          offset: offset,
          countryCode: 'RW',
        ),
      );
      if (!current) throw const AdminSessionChanged();
      ref.read(adminLastSuccessfulRefreshProvider.notifier).state = ref.read(
        adminClockProvider,
      )();
      return result;
    });

final _coreOverviewProvider = FutureProvider.autoDispose<List<AdminMetric>>((
  ref,
) async {
  ref.watch(adminRealtimeTickProvider);
  ref.watch(
    cloudflareAdminSessionProvider.select(
      (session) => session.asData?.value?.authorityKey,
    ),
  );
  final repository = ref.watch(adminRepositoryProvider);
  var current = true;
  ref.onDispose(() => current = false);
  final metrics = await repository.overviewMetrics();
  if (!current) throw const AdminSessionChanged();
  ref.read(adminLastSuccessfulRefreshProvider.notifier).state = ref.read(
    adminClockProvider,
  )();
  return metrics;
});

/// Fresh-table reads use the existing operator components and semantic theme.
/// They do not inherit legacy receipt details or unsupported mutation controls.
class CloudflareCoreListPage extends ConsumerStatefulWidget {
  const CloudflareCoreListPage({required this.area, super.key});
  final CloudflareCoreArea area;

  @override
  ConsumerState<CloudflareCoreListPage> createState() => _CoreListState();
}

class _CoreListState extends ConsumerState<CloudflareCoreListPage> {
  final _search = TextEditingController();
  String _appliedSearch = '';
  String _status = '';
  String _sort = 'created_at_desc';
  int _page = 0;
  String? _lastListLocation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uri = GoRouterState.of(context).uri;
    // A nested detail shares the parent route. Only list URLs own filter state.
    if (uri.path != widget.area.path || uri.toString() == _lastListLocation) {
      return;
    }
    _lastListLocation = uri.toString();
    final parameters = uri.queryParameters;
    final search = parameters['search'] ?? '';
    _appliedSearch =
        search.length <= 200 && !RegExp(r'[\x00-\x1f\x7f]').hasMatch(search)
        ? search
        : '';
    _search.text = _appliedSearch;
    _status = widget.area.acceptsStatus(parameters['status'] ?? '')
        ? parameters['status']!
        : '';
    _sort = widget.area.acceptsSort(parameters['sort'] ?? '')
        ? parameters['sort']!
        : 'created_at_desc';
    final page = int.tryParse(parameters['page'] ?? '1') ?? 1;
    _page = page > 0 && page <= 85899346 ? page - 1 : 0;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CloudflareCoreListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.area != oldWidget.area) {
      _search.clear();
      _appliedSearch = '';
      _status = '';
      _sort = 'created_at_desc';
      _page = 0;
      _lastListLocation = null;
    }
  }

  _CoreQuery get _query => (
    area: widget.area,
    search: _appliedSearch,
    status: _status,
    sort: _sort,
    page: _page,
  );

  void _refresh() {
    setState(() {
      _appliedSearch = _search.text.trim();
      _page = 0;
    });
    _navigateToList();
    ref.invalidate(_coreListProvider(_query));
  }

  String get _listLocation {
    final parameters = {
      if (_appliedSearch.isNotEmpty) 'search': _appliedSearch,
      if (_status.isNotEmpty) 'status': _status,
      if (_sort != 'created_at_desc') 'sort': _sort,
      if (_page > 0) 'page': '${_page + 1}',
    };
    return Uri(
      path: widget.area.path,
      queryParameters: parameters.isEmpty ? null : parameters,
    ).toString();
  }

  void _navigateToList() => context.go(_listLocation);

  void _changePage(int page) {
    setState(() => _page = page);
    _navigateToList();
  }

  void _openRecord(AdminTableRowData row) => context.go(
    Uri(
      path: '${widget.area.path}/${row.id}',
      queryParameters: {'returnTo': _listLocation},
    ).toString(),
  );

  @override
  Widget build(BuildContext context) {
    final area = widget.area;
    final user = ref.watch(cloudflareAdminSessionProvider).asData?.value;
    final createPermission = area == CloudflareCoreArea.groups
        ? 'collections.create'
        : area.createOperation.permission;
    final query = _query;
    final response = ref.watch(_coreListProvider(query));
    final canonical =
        response.asData?.value.result.sourceModel ==
        'canonical_evidence_ledger';
    final sortFields = canonical ? area.canonicalSortFields : area.sortFields;
    return AdminPage(
      title: area.title,
      trailing:
          area == CloudflareCoreArea.transactions &&
              user?.permissions.contains('payments.read') == true
          ? Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () => context.go('/admin/momo-receipts'),
                  icon: const Icon(Icons.receipt_long_rounded),
                  label: const Text('MoMo receipts'),
                ),
                if (user?.permissions.contains(createPermission) == true)
                  FilledButton.icon(
                    onPressed: () => context.go(
                      Uri(
                        path: '${area.path}/new',
                        queryParameters: {'returnTo': _listLocation},
                      ).toString(),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Record payment evidence'),
                  ),
              ],
            )
          : user?.permissions.contains(createPermission) == true
          ? canonical &&
                    (area == CloudflareCoreArea.ledgers ||
                        area == CloudflareCoreArea.payees)
                ? FilledButton(
                    onPressed:
                        area == CloudflareCoreArea.payees &&
                            user?.permissions.contains('collections.read') ==
                                true
                        ? () => context.go('/admin/groups')
                        : null,
                    child: Text(
                      area == CloudflareCoreArea.ledgers
                          ? 'Journal posting unavailable'
                          : 'Manage receivers in Groups',
                    ),
                  )
                : FilledButton.icon(
                    onPressed: () => context.go(
                      Uri(
                        path: '${area.path}/new',
                        queryParameters: {'returnTo': _listLocation},
                      ).toString(),
                    ),
                    icon: const Icon(Icons.add),
                    label: Text(switch (area) {
                      CloudflareCoreArea.groups => 'Create group',
                      CloudflareCoreArea.users => 'Add person',
                      CloudflareCoreArea.members => 'Add group member',
                      CloudflareCoreArea.payees => 'Add payee',
                      CloudflareCoreArea.transactions =>
                        'Record payment evidence',
                      CloudflareCoreArea.ledgers => 'Create journal draft',
                    }),
                  )
          : null,
      subtitle: switch (area) {
        CloudflareCoreArea.groups => 'Collect groups in Rwanda.',
        CloudflareCoreArea.users =>
          'All Admin, Staff, App and Direct people. Search by name, ID, phone or MoMo code.',
        CloudflareCoreArea.members =>
          'App and Direct members with an active group membership.',
        CloudflareCoreArea.payees =>
          'Group payees and their recorded MoMo numbers or codes.',
        CloudflareCoreArea.transactions =>
          canonical
              ? 'Payment evidence and reconciliation. Provider settlement is not verified.'
              : 'Recorded payments and their allocation status.',
        CloudflareCoreArea.ledgers =>
          canonical
              ? 'Signed contributions, reversals and corrections. Journal posting is unavailable.'
              : 'Draft and posted journals. Values show recorded debits.',
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminFilterBar(
            searchController: _search,
            status: _status,
            sortBy: _sort,
            searchLabel: 'Search ${area.title.toLowerCase()}',
            searchHint: 'Search ${area.title.toLowerCase()}',
            searchExamples: [
              AdminSearchExample(
                label: _searchExample(area),
                query: _searchExample(area),
              ),
            ],
            sortOptions: [
              for (final field in sortFields.entries)
                for (final direction in ['asc', 'desc'])
                  AdminFilterOption(
                    value: '${field.key}_$direction',
                    label: '${field.value} ${direction == 'asc' ? '↑' : '↓'}',
                  ),
            ],
            statusOptions: [
              const AdminFilterOption(value: '', label: 'All'),
              for (final status
                  in (canonical ? area.canonicalStatuses : area.statuses))
                AdminFilterOption(value: status, label: _statusLabel(status)),
            ],
            onStatusChanged: (status) {
              setState(() {
                _status = status;
                _page = 0;
              });
              _navigateToList();
            },
            onSortChanged: (sort) {
              setState(() {
                _sort = sort;
                _page = 0;
              });
              _navigateToList();
            },
            onRefresh: _refresh,
          ),
          const SizedBox(height: 18),
          response.when(
            skipLoadingOnReload: false,
            skipLoadingOnRefresh: false,
            loading: () => AdminLoadingState(
              title: 'Loading ${area.title.toLowerCase()}',
              message: 'Fetching current records.',
            ),
            error: (error, _) => AdminSafeErrorPanel(
              error: error,
              onRetry: () => ref.invalidate(_coreListProvider(query)),
            ),
            data: (loaded) {
              final rows = loaded.result.rows;
              if (rows.isEmpty) {
                final filtered =
                    _appliedSearch.isNotEmpty || _status.isNotEmpty;
                return AdminEmptyState(
                  key: ValueKey('cloudflare-core-empty-${area.name}'),
                  title: filtered
                      ? 'No matching ${area.title.toLowerCase()}'
                      : 'No ${area.title.toLowerCase()} yet',
                  message: filtered
                      ? 'Change your filters or refresh to check again.'
                      : 'There are no ${area.title.toLowerCase()} records in this workspace.',
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AdminDataTable(
                    rows: rows,
                    rpcName: 'cloudflare_core_${area.name}',
                    valueLabel: area.valueLabel,
                    columns: [
                      for (final column
                          in (canonical
                              ? _canonicalColumnsForArea(area)
                              : _columnsForArea(area)))
                        AdminTableColumn(
                          label: column.label,
                          value: column.value,
                          numeric: column.numeric,
                          icon: column.icon,
                          selectable: column.selectable,
                          cellBuilder: column.cellBuilder,
                          sortKey:
                              column.sortKey ??
                              (canonical
                                  ? area.canonicalSortFields.entries
                                        .where((e) => e.value == column.label)
                                        .firstOrNull
                                        ?.key
                                  : _columnSortKey(area, column.label)),
                        ),
                    ],
                    tableLabel: area.title,
                    sortBy: _sort,
                    onSortChanged: (sort) {
                      setState(() {
                        _sort = sort;
                        _page = 0;
                      });
                      _navigateToList();
                    },
                    onOpen: _openRecord,
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('${loaded.start}–${loaded.end} of ${loaded.total}'),
                      OutlinedButton(
                        onPressed: loaded.page == 0
                            ? null
                            : () => _changePage(loaded.page - 1),
                        child: const Text('Previous'),
                      ),
                      OutlinedButton(
                        onPressed: loaded.page >= loaded.lastPage
                            ? null
                            : () => _changePage(loaded.page + 1),
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

String _field(AdminTableRowData row, String key) => '${row.extra[key] ?? '—'}';
String _phone(AdminTableRowData row, String key) =>
    _field(row, key).replaceFirst(RegExp(r'^\+'), '');
String _amount(AdminTableRowData row, String key) =>
    row.extra[key] == null ? '—' : adminFormatWholeAmount(row.extra[key]);
String _time(AdminTableRowData row, String key) =>
    adminKigaliDateTime(DateTime.tryParse('${row.extra[key] ?? ''}'));

String? _columnSortKey(CloudflareCoreArea area, String label) {
  final aliases = {
    'Status': area == CloudflareCoreArea.transactions
        ? 'allocation_status'
        : 'status',
    'MoMo number': area == CloudflareCoreArea.payees
        ? 'momo_number_or_code'
        : 'momo_number',
    'MoMo code': area == CloudflareCoreArea.payees
        ? 'momo_number_or_code'
        : 'momo_pay_code',
  };
  return aliases[label] ??
      area.sortFields.entries.where((e) => e.value == label).firstOrNull?.key;
}

String _searchExample(CloudflareCoreArea area) => switch (area) {
  CloudflareCoreArea.groups => 'active private groups',
  CloudflareCoreArea.users => 'staff users',
  CloudflareCoreArea.members => 'direct members',
  CloudflareCoreArea.payees => 'active payees',
  CloudflareCoreArea.transactions => 'unallocated transactions',
  CloudflareCoreArea.ledgers => 'posted journals',
};

List<AdminTableColumn> _columnsForArea(CloudflareCoreArea area) {
  final created = AdminTableColumn(
    label: 'Created · Kigali',
    sortKey: 'created_at',
    value: (row) => adminKigaliDateTime(row.createdAt, includeZone: false),
  );
  final status = AdminTableColumn(
    label: 'Status',
    value: (row) => _statusLabel(row.status),
  );
  final people = <AdminTableColumn>[
    AdminTableColumn(
      label: 'ID',
      numeric: true,
      value: (row) => _field(row, 'public_id'),
    ),
    AdminTableColumn(
      label: 'Name',
      value: (row) => _field(row, 'display_name'),
    ),
    AdminTableColumn(
      label: 'Type',
      value: (row) => (row.extra['user_types'] as List).join(', '),
    ),
    if (area == CloudflareCoreArea.users)
      AdminTableColumn(label: 'Email', value: (row) => _field(row, 'email')),
    AdminTableColumn(
      label: 'WhatsApp',
      numeric: true,
      value: (row) => _phone(row, 'whatsapp_number'),
    ),
    AdminTableColumn(
      label: 'MoMo number',
      numeric: true,
      value: (row) => _phone(row, 'momo_number'),
    ),
    AdminTableColumn(
      label: 'MoMo code',
      numeric: true,
      value: (row) => _field(row, 'momo_pay_code'),
    ),
    AdminTableColumn(
      label: 'Groups',
      numeric: true,
      value: (row) => _field(row, 'active_groups'),
    ),
    AdminTableColumn(
      label: 'Contributed',
      numeric: true,
      value: (row) => _amount(row, 'total_contributed_rwf'),
    ),
    AdminTableColumn(
      label: 'Posted contributions',
      numeric: true,
      value: (row) => _amount(row, 'posted_contributed_rwf'),
    ),
    status,
    created,
  ];
  return switch (area) {
    CloudflareCoreArea.users || CloudflareCoreArea.members => people,
    CloudflareCoreArea.groups => [
      AdminTableColumn(label: 'Name', value: (row) => row.title),
      AdminTableColumn(label: 'Slug', value: (row) => _field(row, 'slug')),
      AdminTableColumn(
        label: 'Type',
        value: (row) => _statusLabel(_field(row, 'collection_type')),
      ),
      AdminTableColumn(
        label: 'Visibility',
        value: (row) =>
            row.extra['visibility'] == 'public_approved' ? 'Public' : 'Private',
      ),
      AdminTableColumn(
        label: 'Purpose',
        value: (row) => _field(row, 'purpose_label'),
      ),
      AdminTableColumn(
        label: 'Members',
        numeric: true,
        value: (row) => _field(row, 'active_members'),
      ),
      status,
      created,
    ],
    CloudflareCoreArea.payees => [
      AdminTableColumn(label: 'Name', value: (row) => row.title),
      AdminTableColumn(
        label: 'Group',
        value: (row) => _field(row, 'group_name'),
      ),
      AdminTableColumn(
        label: 'MoMo number',
        numeric: true,
        value: (row) => _phone(row, 'momo_number'),
      ),
      AdminTableColumn(
        label: 'MoMo code',
        numeric: true,
        value: (row) => _field(row, 'momo_pay_code'),
      ),
      status,
      created,
    ],
    CloudflareCoreArea.transactions => [
      AdminTableColumn(
        label: 'Transaction ID',
        value: (row) => _field(row, 'transaction_reference'),
        selectable: true,
      ),
      AdminTableColumn(
        label: 'Status',
        value: (row) => row.extra['allocation_status'] == 'allocated'
            ? 'Allocated'
            : 'Unallocated',
      ),
      AdminTableColumn(
        label: 'Amount',
        numeric: true,
        value: (row) => _amount(row, 'amount_rwf'),
      ),
      AdminTableColumn(
        label: 'Allocated',
        numeric: true,
        value: (row) => _amount(row, 'allocated_amount_rwf'),
      ),
      AdminTableColumn(
        label: 'Remaining',
        numeric: true,
        value: (row) => adminFormatWholeAmount(
          (row.extra['amount_rwf'] as int) -
              (row.extra['allocated_amount_rwf'] as int),
        ),
      ),
      AdminTableColumn(
        label: 'Payer name',
        value: (row) => _field(row, 'payer_name'),
      ),
      AdminTableColumn(
        label: 'Payer last 3',
        value: (row) => _field(row, 'payer_last3'),
        selectable: true,
      ),
      AdminTableColumn(
        label: 'Payee MoMo number / code',
        value: (row) => _field(row, 'payee_momo_number_or_code'),
        selectable: true,
      ),
      AdminTableColumn(
        label: 'SMS payee number',
        value: (row) => _field(row, 'payee_momo_number'),
        selectable: true,
      ),
      AdminTableColumn(
        label: 'SMS payee code',
        value: (row) => _field(row, 'payee_momo_code'),
        selectable: true,
      ),
      AdminTableColumn(
        label: 'MoMo transaction',
        value: (row) => _field(row, 'momo_transaction_reference'),
        selectable: true,
      ),
      AdminTableColumn(
        label: 'MoMo timestamp',
        value: (row) => _field(row, 'momo_timestamp_local'),
      ),
      AdminTableColumn(
        label: 'SMS timezone offset',
        value: (row) => _field(row, 'momo_timezone_offset'),
      ),
      AdminTableColumn(
        label: 'Wallet balance',
        value: (row) => _amount(row, 'wallet_balance_rwf'),
        numeric: true,
      ),
      AdminTableColumn(
        label: 'SMS network',
        value: (row) => _field(row, 'source_network'),
      ),
      AdminTableColumn(
        label: 'Direction',
        value: (row) => _field(row, 'direction'),
      ),
      AdminTableColumn(
        label: 'Provider reference',
        value: (row) => _field(row, 'provider_reference'),
      ),
      AdminTableColumn(
        label: 'Group',
        value: (row) => _field(row, 'group_name'),
      ),
      AdminTableColumn(
        label: 'Payee',
        value: (row) => _field(row, 'payee_label'),
      ),
      AdminTableColumn(
        label: 'Observed',
        value: (row) => _time(row, 'observed_at'),
      ),
      created,
    ],
    CloudflareCoreArea.ledgers => [
      AdminTableColumn(label: 'Description', value: (row) => row.title),
      AdminTableColumn(
        label: 'Group',
        value: (row) => _field(row, 'group_name'),
      ),
      AdminTableColumn(
        label: 'Debit',
        numeric: true,
        value: (row) => _amount(row, 'debit_rwf'),
      ),
      AdminTableColumn(
        label: 'Credit',
        numeric: true,
        value: (row) => _amount(row, 'credit_rwf'),
      ),
      AdminTableColumn(
        label: 'Entries',
        numeric: true,
        value: (row) => _field(row, 'entry_count'),
      ),
      AdminTableColumn(
        label: 'Balanced',
        value: (row) => row.extra['balanced'] == true ? 'Yes' : 'No',
      ),
      status,
      created,
      AdminTableColumn(
        label: 'Posted',
        value: (row) => _time(row, 'posted_at'),
      ),
    ],
  };
}

class CloudflareCoreOverviewPanel extends ConsumerWidget {
  const CloudflareCoreOverviewPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(_coreOverviewProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Recorded activity',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: 'Refresh workspace counts',
              onPressed: () => ref.invalidate(_coreOverviewProvider),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 8),
        metrics.when(
          data: (values) => Text(
            values.any((v) => v.sourceModel == 'canonical_evidence_ledger')
                ? 'Amounts reflect retained evidence and recorded contributions. Provider settlement and accounting journals are not verified.'
                : 'Collected amounts use confirmed payments. Posted contributions also have a posted journal.',
          ),
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
        ),
        const SizedBox(height: 16),
        metrics.when(
          skipLoadingOnReload: false,
          skipLoadingOnRefresh: false,
          loading: () =>
              const AdminLoadingState(title: 'Loading workspace counts'),
          error: (error, _) => AdminSafeErrorPanel(
            error: error,
            onRetry: () => ref.invalidate(_coreOverviewProvider),
          ),
          data: (values) {
            final permissions =
                ref
                    .watch(cloudflareAdminSessionProvider)
                    .asData
                    ?.value
                    ?.permissions ??
                const <String>[];
            bool canOpen(AdminTableRowData row) {
              final target = _targetForMetric(row.title);
              return target != null && permissions.contains(target.permission);
            }

            return AdminDataTable(
              key: const ValueKey('admin-all-workspace-totals'),
              tableLabel: 'Workspace summary',
              rows: [
                for (final metric in values)
                  AdminTableRowData(
                    id: metric.label,
                    title: metric.label,
                    subtitle: '',
                    status: metric.status,
                    amount: metric.value,
                    extra: {'source_model': metric.sourceModel},
                  ),
              ],
              columns: [
                AdminTableColumn(label: 'Metric', value: (row) => row.title),
                AdminTableColumn(
                  label: 'Total',
                  numeric: true,
                  value: (row) => adminFormatWholeAmount(row.amount),
                  cellBuilder: (row) => Text(
                    adminFormatWholeAmount(row.amount),
                    key: ValueKey('cloudflare-core-count-${row.title}'),
                  ),
                ),
                AdminTableColumn(
                  label: 'Data basis',
                  value: (row) =>
                      row.extra['source_model'] == 'canonical_evidence_ledger'
                      ? row.title.contains('contribution')
                            ? 'Reconciled evidence entries'
                            : row.title.contains('evidence')
                            ? 'Retained payment evidence'
                            : 'Current workspace records'
                      : row.title.contains('contribution')
                      ? 'Confirmed allocations with posted journals'
                      : row.title.startsWith('Total')
                      ? 'Confirmed recorded payments'
                      : 'Current workspace records',
                ),
                AdminTableColumn(
                  label: 'Action',
                  value: (row) => canOpen(row) ? 'Open ${row.title}' : '',
                  cellBuilder: (row) => canOpen(row)
                      ? IconButton(
                          tooltip: 'Open ${row.title}',
                          onPressed: () =>
                              context.go(_targetForMetric(row.title)!.location),
                          icon: const Icon(Icons.arrow_outward_rounded),
                        )
                      : const Text('—'),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

({String location, String permission})? _targetForMetric(
  String label,
) => switch (label) {
  'Groups' => (location: '/admin/groups', permission: 'collections.read'),
  'Users' => (location: '/admin/users', permission: 'users.read'),
  'App users' => (
    location: '/admin/users?search=type%3Aapp',
    permission: 'users.read',
  ),
  'Direct users' => (
    location: '/admin/users?search=type%3Adirect',
    permission: 'users.read',
  ),
  'Admin users' => (
    location: '/admin/users?search=type%3Aadmin',
    permission: 'users.read',
  ),
  'Staff users' => (
    location: '/admin/users?search=type%3Astaff',
    permission: 'users.read',
  ),
  'Active members' => (location: '/admin/members', permission: 'users.read'),
  'Payees' => (location: '/admin/payees', permission: 'receivers.read'),
  'Active payees' => (
    location: '/admin/payees?status=active',
    permission: 'receivers.read',
  ),
  'Transactions' => (
    location: '/admin/transactions',
    permission: 'payments.read',
  ),
  'Unallocated transactions' ||
  'Total unallocated' ||
  'Unallocated evidence amount' => (
    location: '/admin/reconciliations',
    permission: 'reconciliations.read',
  ),
  'Recorded evidence amount' ||
  'Reconciled evidence amount' ||
  'Retained payment evidence' => (
    location: '/admin/transactions',
    permission: 'payments.read',
  ),
  'Ledger entries' || 'Net recorded contributions' => (
    location: '/admin/ledgers',
    permission: 'ledger.read',
  ),
  'Reversal entries' => (
    location: '/admin/ledgers?status=reversal',
    permission: 'ledger.read',
  ),
  'Total collected' || 'Total allocated' => (
    location: '/admin/transactions?status=confirmation_recorded',
    permission: 'payments.read',
  ),
  'Draft journals' => (
    location: '/admin/ledgers?status=draft',
    permission: 'ledger.read',
  ),
  'Posted journals' || 'Posted contributions' => (
    location: '/admin/ledgers?status=posted',
    permission: 'ledger.read',
  ),
  'SMS receipts' => (location: '/admin/sms-receipts', permission: 'sms.read'),
  'Receipts needing review' => (
    location: '/admin/member-receipts?status=needs_review',
    permission: 'payments.read',
  ),
  _ => null,
};

String _statusLabel(String value) {
  final text = value.replaceAll('_', ' ');
  if (text.isEmpty) return '—';
  return '${text[0].toUpperCase()}${text.substring(1)}';
}

List<AdminTableColumn> _canonicalColumnsForArea(CloudflareCoreArea area) {
  final created = AdminTableColumn(
    label: 'Created · Kigali',
    sortKey: 'created_at',
    value: (row) => adminKigaliDateTime(row.createdAt, includeZone: false),
  );
  final status = AdminTableColumn(
    label: 'Status',
    value: (row) => _statusLabel(row.status),
  );
  final people = <AdminTableColumn>[
    AdminTableColumn(
      label: 'ID',
      numeric: true,
      value: (row) => _field(row, 'public_id'),
    ),
    AdminTableColumn(
      label: 'Name',
      value: (row) => _field(row, 'display_name'),
    ),
    AdminTableColumn(
      label: 'Type',
      value: (row) => (row.extra['user_types'] as List).join(', '),
    ),
    if (area == CloudflareCoreArea.users)
      AdminTableColumn(label: 'Email', value: (row) => _field(row, 'email')),
    AdminTableColumn(
      label: 'WhatsApp',
      numeric: true,
      value: (row) => _phone(row, 'whatsapp_number'),
    ),
    AdminTableColumn(
      label: 'MoMo number',
      numeric: true,
      value: (row) => _phone(row, 'momo_number'),
    ),
    AdminTableColumn(
      label: 'MoMo code',
      numeric: true,
      value: (row) => _field(row, 'momo_pay_code'),
    ),
    AdminTableColumn(
      label: 'Groups',
      numeric: true,
      value: (row) => _field(row, 'active_groups'),
    ),
    AdminTableColumn(
      label: 'Contributed',
      numeric: true,
      value: (row) => _amount(row, 'total_contributed_rwf'),
    ),
    AdminTableColumn(
      label: 'Posted contributions',
      numeric: true,
      value: (row) => _amount(row, 'posted_contributed_rwf'),
    ),
    status,
    created,
  ];
  return switch (area) {
    CloudflareCoreArea.users || CloudflareCoreArea.members => people,
    CloudflareCoreArea.groups => [
      AdminTableColumn(label: 'Name', value: (row) => row.title),
      AdminTableColumn(label: 'Slug', value: (row) => _field(row, 'slug')),
      AdminTableColumn(
        label: 'Type',
        value: (row) => _statusLabel(_field(row, 'collection_type')),
      ),
      AdminTableColumn(
        label: 'Visibility',
        value: (row) =>
            row.extra['visibility'] == 'public_approved' ? 'Public' : 'Private',
      ),
      AdminTableColumn(
        label: 'Purpose',
        value: (row) => _field(row, 'purpose_label'),
      ),
      AdminTableColumn(
        label: 'Members',
        numeric: true,
        value: (row) => _field(row, 'active_members'),
      ),
      status,
      created,
    ],
    CloudflareCoreArea.payees => [
      AdminTableColumn(label: 'Name', value: (row) => row.title),
      AdminTableColumn(
        label: 'Group',
        value: (row) => _field(row, 'group_name'),
      ),
      AdminTableColumn(
        label: 'MoMo number',
        numeric: true,
        value: (row) => _phone(row, 'momo_number'),
      ),
      AdminTableColumn(
        label: 'MoMo code',
        numeric: true,
        value: (row) => _field(row, 'momo_pay_code'),
      ),
      status,
      created,
    ],
    CloudflareCoreArea.transactions => [
      AdminTableColumn(
        label: 'Payment ID',
        value: (row) => row.id,
        selectable: true,
      ),
      status,
      AdminTableColumn(
        label: 'Amount',
        numeric: true,
        value: (row) => _amount(row, 'amount_rwf'),
      ),
      AdminTableColumn(
        label: 'Net contributions',
        numeric: true,
        value: (row) => _amount(row, 'allocated_amount_rwf'),
      ),
      AdminTableColumn(
        label: 'Unreconciled amount',
        numeric: true,
        value: (row) => {'reversed', 'corrected'}.contains(row.status)
            ? '—'
            : adminFormatWholeAmount(
                (row.extra['amount_rwf'] as int) -
                    (row.extra['allocated_amount_rwf'] as int),
              ),
      ),
      AdminTableColumn(
        label: 'Payer name',
        value: (row) => _field(row, 'payer_name'),
      ),
      AdminTableColumn(
        label: 'Evidence ID',
        value: (row) => _field(row, 'evidence_id'),
        selectable: true,
      ),
      AdminTableColumn(
        label: 'Recorded receiver',
        value: (row) => _field(row, 'payee_momo_number_or_code'),
        selectable: true,
      ),
      AdminTableColumn(
        label: 'Evidence reference',
        value: (row) => _field(row, 'provider_reference'),
      ),
      AdminTableColumn(
        label: 'Group',
        value: (row) => _field(row, 'group_name'),
      ),
      AdminTableColumn(
        label: 'Evidence source',
        value: (row) => switch (row.extra['evidence_level']) {
          'operator_recorded' => 'Operator recorded',
          'provider_authenticated' => 'Authenticated provider evidence',
          _ => '—',
        },
      ),
      AdminTableColumn(
        label: 'Observed',
        value: (row) => _time(row, 'observed_at'),
      ),
      created,
    ],
    CloudflareCoreArea.ledgers => [
      AdminTableColumn(label: 'Description', value: (row) => row.title),
      AdminTableColumn(
        label: 'Group',
        value: (row) => _field(row, 'group_name'),
      ),
      AdminTableColumn(
        label: 'Signed amount (RWF)',
        numeric: true,
        value: (row) => _amount(row, 'signed_amount_rwf'),
      ),
      AdminTableColumn(
        label: 'Payment ID',
        value: (row) => _field(row, 'payment_id'),
        selectable: true,
      ),
      AdminTableColumn(
        label: 'Evidence ID',
        value: (row) => _field(row, 'evidence_id'),
        selectable: true,
      ),
      AdminTableColumn(
        label: 'Reverses entry',
        value: (row) => _field(row, 'reverses_entry_id'),
        selectable: true,
      ),
      status,
      AdminTableColumn(
        label: 'Posted',
        value: (row) => _time(row, 'posted_at'),
      ),
    ],
  };
}
