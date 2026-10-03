part of 'admin_runtime.dart';

enum CollectAdminOperation { payees, transactions, reconciliations, ledgers }

extension CollectAdminOperationSpec on CollectAdminOperation {
  String get title => switch (this) {
    CollectAdminOperation.payees => 'Payees',
    CollectAdminOperation.transactions => 'Transactions',
    CollectAdminOperation.reconciliations => 'Reconciliations',
    CollectAdminOperation.ledgers => 'Ledgers',
  };

  String get subtitle => switch (this) {
    CollectAdminOperation.payees => 'Official receivers for public groups.',
    CollectAdminOperation.transactions =>
      'Received payments and allocation state.',
    CollectAdminOperation.reconciliations =>
      'Independent evidence review before ledger posting.',
    CollectAdminOperation.ledgers => 'Balanced postings.',
  };

  String get rpcName => switch (this) {
    CollectAdminOperation.payees => 'admin_list_collect_payees',
    CollectAdminOperation.transactions => 'admin_list_collect_transactions',
    CollectAdminOperation.reconciliations =>
      'admin_list_collect_reconciliations',
    CollectAdminOperation.ledgers => 'admin_list_collect_ledgers',
  };

  String? get detailPath => switch (this) {
    CollectAdminOperation.transactions => '/admin/transactions',
    _ => null,
  };

  String? get actionKind => switch (this) {
    CollectAdminOperation.payees => 'collect_payee_manage',
    CollectAdminOperation.reconciliations => null,
    _ => null,
  };

  String get valueLabel => switch (this) {
    CollectAdminOperation.payees => 'Payment route',
    CollectAdminOperation.transactions ||
    CollectAdminOperation.reconciliations => 'Amount',
    CollectAdminOperation.ledgers => 'Debit = credit',
  };
}

class AdminCollectOperationsPage extends StatelessWidget {
  const AdminCollectOperationsPage({required this.operation, super.key});

  final CollectAdminOperation operation;

  @override
  Widget build(BuildContext context) =>
      operation == CollectAdminOperation.reconciliations
      ? const AdminReconciliationPage()
      : AdminRpcListPage(
          title: operation.title,
          rpcName: operation.rpcName,
          detailPathPrefix: operation.detailPath,
          actionKind: operation.actionKind,
          subtitleOverride: operation.subtitle,
          valueLabelOverride: operation.valueLabel,
          minimal: true,
        );
}

class AdminRpcListPage extends ConsumerStatefulWidget {
  const AdminRpcListPage({
    required this.title,
    required this.rpcName,
    this.detailPathPrefix,
    this.actionKind,
    this.subtitleOverride,
    this.valueLabelOverride,
    this.initialStatus,
    this.minimal = false,
    super.key,
  });

  final String title;
  final String rpcName;
  final String? detailPathPrefix;
  final String? actionKind;
  final String? subtitleOverride;
  final String? valueLabelOverride;

  /// Explicit deep-link filters override remembered view preferences.
  final String? initialStatus;
  final bool minimal;

  @override
  ConsumerState<AdminRpcListPage> createState() => _AdminRpcListPageState();
}

class _AdminQueueViewState {
  const _AdminQueueViewState({
    required this.search,
    required this.status,
    required this.sortBy,
    required this.page,
    required this.country,
    required this.scrollOffset,
  });

  final String search;
  final String status;
  final String sortBy;
  final int page;
  final AdminCountryScope country;
  final double scrollOffset;
}

// Only view preferences are retained, in memory, for the current Admin identity.
// Record data is fetched again whenever the route is reopened.
final _adminQueueViewStatesProvider =
    Provider<Map<String, _AdminQueueViewState>>((ref) {
      ref.watch(
        adminIdentityProvider.select((value) => value.valueOrNull?.userId),
      );
      ref.watch(adminAuthSessionScopeProvider);
      return {};
    });

class _AdminRpcListPageState extends ConsumerState<AdminRpcListPage> {
  static const _pageSize = 25;

  late final TextEditingController _search;
  final _scroll = ScrollController();
  late Map<String, _AdminQueueViewState> _viewStates;
  var _canRememberView = true;
  double _lastScrollOffset = 0;
  double? _restoreScrollOffset;
  var _status = '';
  var _sortBy = 'created_at_desc';
  var _page = 0;
  var _requestGeneration = 0;
  var _appliedSearch = '';
  late Future<AdminLoadedPage> _future;
  var _lastRealtimeTick = 0;
  var _appliedRealtimeTick = 0;
  late AdminCountryScope _lastCountryScope;

  @override
  void initState() {
    super.initState();
    _lastCountryScope = ref.read(adminCountryScopeProvider);
    _viewStates = ref.read(_adminQueueViewStatesProvider);
    final saved = _viewStates[widget.rpcName];
    _search = TextEditingController(
      text: widget.initialStatus == null ? saved?.search ?? '' : '',
    );
    _appliedSearch = _search.text;
    _lastRealtimeTick = ref.read(adminRealtimeTickProvider);
    _status = widget.initialStatus == null
        ? saved?.status ?? ''
        : _queryStatus(widget.initialStatus!);
    _sortBy = widget.initialStatus == null
        ? saved?.sortBy ?? 'created_at_desc'
        : 'created_at_desc';
    if (widget.initialStatus == null &&
        saved != null &&
        saved.country == _lastCountryScope) {
      _page = saved.page;
      _restoreScrollOffset = saved.scrollOffset;
    }
    _scroll.addListener(() => _lastScrollOffset = _scroll.offset);
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant AdminRpcListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rpcName == widget.rpcName) {
      if (oldWidget.initialStatus != widget.initialStatus) {
        _search.clear();
        _appliedSearch = '';
        _status = _queryStatus(widget.initialStatus ?? '');
        _sortBy = 'created_at_desc';
        _page = 0;
        _restoreScrollOffset = 0;
        _future = _load();
      }
      return;
    }
    _rememberView(rpcName: oldWidget.rpcName);
    _lastCountryScope = ref.read(adminCountryScopeProvider);
    final currentViewStates = ref.read(_adminQueueViewStatesProvider);
    // Do not restore another account's route preferences during a simultaneous
    // route/account change. Its provider owns a separate in-memory map.
    _viewStates = currentViewStates;
    _canRememberView = true;
    final saved = _viewStates[widget.rpcName];
    _search.text = widget.initialStatus == null ? saved?.search ?? '' : '';
    _appliedSearch = _search.text;
    _status = widget.initialStatus == null
        ? saved?.status ?? ''
        : _queryStatus(widget.initialStatus!);
    _sortBy = widget.initialStatus == null
        ? saved?.sortBy ?? 'created_at_desc'
        : 'created_at_desc';
    if (widget.initialStatus == null &&
        saved != null &&
        saved.country == _lastCountryScope) {
      _page = saved.page;
      _restoreScrollOffset = saved.scrollOffset;
    } else {
      _page = 0;
      _restoreScrollOffset = 0;
    }
    _future = _load();
  }

  String _queryStatus(String value) {
    final spec = _AdminListSpec.forRpc(
      widget.rpcName,
      runtimeConfig: ref.read(adminRuntimeConfigProvider).valueOrNull,
    );
    return spec.statusOptions.any((option) => option.value == value)
        ? value
        : '';
  }

  @override
  void dispose() {
    _requestGeneration++;
    _rememberView();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentViewStates = ref.watch(_adminQueueViewStatesProvider);
    if (!identical(currentViewStates, _viewStates)) {
      _requestGeneration++;
      _canRememberView = false;
      _viewStates = currentViewStates;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _search.clear();
          _appliedSearch = '';
          _status = _queryStatus(widget.initialStatus ?? '');
          _sortBy = 'created_at_desc';
          _page = 0;
          _restoreScrollOffset = 0;
          _canRememberView = true;
          _future = _load();
        });
      });
      return const AdminLoadingState(title: 'Loading admin workspace');
    }
    final realtimeTick = ref.watch(adminRealtimeTickProvider);
    final countryScope = ref.watch(adminCountryScopeProvider);
    if (_lastRealtimeTick != realtimeTick) {
      _lastRealtimeTick = realtimeTick;
    }
    if (_lastCountryScope != countryScope) {
      _requestGeneration++;
      _lastCountryScope = countryScope;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refresh(resetPage: true);
      });
      return const AdminLoadingState(title: 'Loading admin workspace');
    }
    final runtimeConfig = ref.watch(adminRuntimeConfigProvider).valueOrNull;
    final spec = _AdminListSpec.forRpc(
      widget.rpcName,
      runtimeConfig: runtimeConfig,
    );
    return AdminPage(
      title: widget.title,
      scrollController: _scroll,
      subtitle: widget.subtitleOverride ?? spec.subtitle,
      trailing: switch (widget.rpcName) {
        'admin_list_collect_payees' => _AdminPayeeWorkspaceActions(
          onDone: () => _refresh(resetPage: true),
        ),
        'admin_list_collections' => _AdminGroupWorkspaceActions(
          onDone: () => _refresh(resetPage: true),
        ),
        _ => null,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminFilterBar(
            searchController: _search,
            status: _status,
            sortBy: _sortBy,
            statusOptions: spec.statusOptions,
            sortOptions: spec.sortOptions,
            onStatusChanged: (value) => setState(() {
              _status = value;
              _page = 0;
              _restoreScrollOffset = 0;
              _future = _load(applySearch: true);
            }),
            onSortChanged: (value) => setState(() {
              _sortBy = value;
              _page = 0;
              _restoreScrollOffset = 0;
              _future = _load(applySearch: true);
            }),
            onRefresh: () => _refresh(resetPage: true),
          ),
          if (_lastRealtimeTick != _appliedRealtimeTick) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: const InfoSecurityBanner(
                key: Key('admin-new-activity-banner'),
                title: 'New activity available',
                message:
                    'Refresh to load the latest records. Current rows stay in place.',
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('admin-apply-new-activity'),
                onPressed: () => _refresh(),
                icon: const Icon(Icons.refresh_outlined),
                label: const Text('Refresh records'),
              ),
            ),
          ],
          const SizedBox(height: 16),
          FutureBuilder<AdminLoadedPage>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return AdminLoadingState(
                  title: 'Loading ${widget.title.toLowerCase()}',
                  message: 'Fetching the latest rows and filters.',
                );
              }
              if (snapshot.hasError) {
                return AdminSafeErrorPanel(
                  error: snapshot.error!,
                  onRetry: () => _refresh(),
                );
              }
              final loaded = snapshot.requireData;
              final rows = loaded.result.rows;
              final scoped = adminRpcUsesCountryScope(widget.rpcName);
              final total = loaded.total;
              final page = loaded.page;
              final maxPage = loaded.lastPage;
              if (rows.isEmpty) {
                return AdminEmptyState(
                  title: scoped
                      ? 'No ${widget.title.toLowerCase()} in ${countryScope.label}'
                      : 'No ${widget.title.toLowerCase()}',
                  message: scoped
                      ? 'Refresh or change the filters.'
                      : _adminEmptyMessage(widget.rpcName),
                );
              }
              final start = loaded.start;
              final end = loaded.end;
              final restoreOffset = _restoreScrollOffset;
              if (restoreOffset != null) {
                _restoreScrollOffset = null;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted || !_scroll.hasClients) return;
                  _scroll.jumpTo(
                    restoreOffset.clamp(0, _scroll.position.maxScrollExtent),
                  );
                });
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.rpcName == 'admin_list_collect_transactions')
                    _AdminTransactionWorkspace(
                      rows: rows,
                      onOpen: widget.detailPathPrefix == null ? null : _openRow,
                    )
                  else if (widget.rpcName == 'admin_list_collections')
                    _AdminGroupsWorkspace(
                      rows: rows,
                      onOpen: widget.detailPathPrefix == null ? null : _openRow,
                    )
                  else if (widget.rpcName == 'admin_list_members' ||
                      widget.rpcName == 'admin_list_non_member_users')
                    _AdminMembersWorkspace(
                      rows: rows,
                      onOpen: widget.detailPathPrefix == null ? null : _openRow,
                      scopeLabel:
                          widget.rpcName == 'admin_list_non_member_users'
                          ? 'Users'
                          : 'Members',
                    )
                  else
                    AdminDataTable(
                      rows: rows,
                      rpcName: widget.rpcName,
                      onOpen: widget.detailPathPrefix == null ? null : _openRow,
                      valueLabel:
                          widget.valueLabelOverride ??
                          _adminQueueValueLabel(widget.rpcName),
                      trailingBuilder: widget.actionKind == null
                          ? null
                          : (row) => _AdminRowActions(
                              row: row,
                              actionKind: widget.actionKind!,
                              onDone: () => _refresh(),
                            ),
                    ),
                  if (total > _pageSize) ...[
                    const SizedBox(height: 12),
                    _AdminPaginationBar(
                      start: start,
                      end: end,
                      total: total,
                      canGoBack: page > 0,
                      canGoNext: page < maxPage,
                      onPrevious: () => setState(() {
                        _page = page - 1;
                        _restoreScrollOffset = 0;
                        _future = _load();
                      }),
                      onNext: () => setState(() {
                        _page = page + 1;
                        _restoreScrollOffset = 0;
                        _future = _load();
                      }),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<AdminLoadedPage> _load({bool applySearch = false}) async {
    final generation = ++_requestGeneration;
    // A realtime event advertises new work without replacing rows under an
    // operator's focus or pointer. Only an explicit load consumes that event.
    _appliedRealtimeTick = ref.read(adminRealtimeTickProvider);
    _lastRealtimeTick = _appliedRealtimeTick;
    final repository = ref.read(adminRepositoryProvider);
    final sessionScope = ref.read(adminAuthSessionScopeProvider);
    final countryScope = ref.read(adminCountryScopeProvider);
    final userId = _adminResolvedIdentity(
      ref.read(adminIdentityProvider),
    )?.userId;
    final rpcName = widget.rpcName;
    if (applySearch) _appliedSearch = _search.text.trim();
    // Freeze the query before awaiting: a retry must not mix an old page with
    // a newly typed search, another route, country, or Admin identity.
    final search = _appliedSearch;
    final status = _status;
    final sortBy = _sortBy;
    final requestedPage = _page;
    bool isCurrent() =>
        mounted &&
        generation == _requestGeneration &&
        ref.read(adminAuthSessionScopeProvider) == sessionScope &&
        identical(ref.read(adminRepositoryProvider), repository) &&
        widget.rpcName == rpcName &&
        ref.read(adminCountryScopeProvider) == countryScope &&
        _adminResolvedIdentity(ref.read(adminIdentityProvider))?.userId ==
            userId;
    final loaded = await loadAdminListPage(
      page: requestedPage,
      pageSize: _pageSize,
      isCurrent: isCurrent,
      fetch: (limit, offset) async {
        final result = await repository.list(
          rpcName,
          search: search,
          status: status,
          limit: limit,
          offset: offset,
          sortBy: sortBy,
          countryCode: countryScope.rpcCode,
        );
        if (adminRpcUsesCountryScope(rpcName) &&
            result.rows.any(
              (row) => !adminRowMatchesCountryScope(row, countryScope),
            )) {
          throw const FormatException(
            'Admin list returned rows outside the requested country.',
          );
        }
        return result;
      },
    );
    if (!isCurrent()) throw const AdminPageRequestSuperseded();
    _page = loaded.page;
    if (loaded.page != requestedPage) _restoreScrollOffset = 0;
    ref.read(adminLastSuccessfulRefreshProvider.notifier).state = ref.read(
      adminClockProvider,
    )();
    return loaded;
  }

  void _refresh({bool resetPage = false}) {
    setState(() {
      if (resetPage) {
        _page = 0;
        _restoreScrollOffset = 0;
      }
      _future = _load(applySearch: resetPage);
    });
  }

  void _openRow(AdminTableRowData row) {
    final prefix = widget.detailPathPrefix;
    if (prefix == null) return;
    _rememberView();
    context.go('$prefix/${Uri.encodeComponent(row.id)}');
  }

  void _rememberView({String? rpcName}) {
    if (!_canRememberView) return;
    _viewStates[rpcName ?? widget.rpcName] = _AdminQueueViewState(
      search: _appliedSearch,
      status: _status,
      sortBy: _sortBy,
      page: _page,
      country: _lastCountryScope,
      scrollOffset: _restoreScrollOffset ?? _lastScrollOffset,
    );
  }
}

String _adminEmptyMessage(String rpcName) => switch (rpcName) {
  'admin_list_collect_ledgers' => 'Balanced postings appear here.',
  'admin_list_hybrid_sms_receipts' =>
    'Feature-phone receipt acknowledgements appear here after a posted payment.',
  'admin_list_notifications' => 'Delivery activity appears here.',
  _ => 'No records match the current view.',
};

String _adminQueueValueLabel(String rpcName) => switch (rpcName) {
  'admin_list_collections' => 'Members',
  'admin_list_hybrid_sms_receipts' => 'Amount',
  'admin_list_notifications' => 'Deliveries',
  'admin_list_admin_users' => 'Access',
  'admin_list_users' ||
  'admin_list_members' ||
  'admin_list_non_member_users' ||
  'admin_list_audit_logs' ||
  'admin_list_settings' ||
  'admin_list_feature_flags' => 'Detail',
  _ => 'Amount',
};

class _AdminPaginationBar extends StatelessWidget {
  const _AdminPaginationBar({
    required this.start,
    required this.end,
    required this.total,
    required this.canGoBack,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
  });

  final int start;
  final int end;
  final int total;
  final bool canGoBack;
  final bool canGoNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceReadable.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.borderAccent),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Showing $start-$end of $total',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: CollectTypography.weightBold,
                ),
              ),
            ),
            Semantics(
              button: true,
              label: 'Previous admin results page',
              hint: canGoBack
                  ? 'Shows the previous page of admin queue results.'
                  : 'Unavailable on the first page.',
              enabled: canGoBack,
              child: IconButton.outlined(
                tooltip: 'Previous page',
                onPressed: canGoBack ? onPrevious : null,
                icon: const Icon(Icons.chevron_left),
              ),
            ),
            const SizedBox(width: 8),
            Semantics(
              button: true,
              label: 'Next admin results page',
              hint: canGoNext
                  ? 'Shows the next page of admin queue results.'
                  : 'Unavailable on the last page.',
              enabled: canGoNext,
              child: IconButton.outlined(
                tooltip: 'Next page',
                onPressed: canGoNext ? onNext : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminRowActions extends ConsumerWidget {
  const _AdminRowActions({
    required this.row,
    required this.actionKind,
    required this.onDone,
  });

  final AdminTableRowData row;
  final String actionKind;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = _adminResolvedIdentity(ref.watch(adminIdentityProvider));
    final List<Widget> actions = switch (actionKind) {
      'payment_event_reparse'
          when _adminHasPermission(identity, 'payment_events.reparse') =>
        [
          IconButton.filledTonal(
            tooltip: 'Reparse ${row.title}',
            onPressed: () => _reparse(context, ref),
            icon: const Icon(Icons.refresh_outlined, size: 18),
          ),
        ],
      'feature_flag_toggle'
          when _adminHasPermission(identity, 'feature_flags.manage') =>
        [
          IconButton.filledTonal(
            tooltip:
                '${row.status == 'enabled' ? 'Disable' : 'Enable'} feature flag ${row.title}',
            onPressed: () =>
                _setFeatureFlag(context, ref, enabled: row.status != 'enabled'),
            icon: Icon(
              row.status == 'enabled'
                  ? Icons.toggle_off_outlined
                  : Icons.toggle_on_outlined,
              size: 18,
            ),
          ),
        ],
      'collect_allocate'
          when (_adminHasPermission(identity, 'payments.allocate')) &&
              (row.extra['can_allocate'] == true ||
                  '${row.extra['event_id'] ?? ''}'.isNotEmpty ||
                  '${row.extra['transaction_id'] ?? ''}'.isNotEmpty) =>
        [
          IconButton.filledTonal(
            tooltip: 'Allocate ${row.title}',
            onPressed: () => _allocate(context, ref),
            icon: const Icon(Icons.account_tree_outlined, size: 18),
          ),
        ],
      'collect_payee_manage'
          when _adminHasPermission(identity, 'receivers.manage') =>
        [
          IconButton.outlined(
            tooltip: 'Edit ${row.title}',
            onPressed: () =>
                editAdminPayee(context, ref, row: row, onDone: onDone),
            icon: const Icon(Icons.edit_outlined, size: 18),
          ),
          IconButton.outlined(
            tooltip:
                '${row.status == 'active' ? 'Deactivate' : 'Activate'} ${row.title}',
            style: IconButton.styleFrom(
              foregroundColor: row.status == 'active'
                  ? context.collectColors.dangerForeground
                  : context.collectColors.successForeground,
              side: BorderSide(
                color: row.status == 'active'
                    ? context.collectColors.dangerForeground
                    : context.collectColors.successForeground,
              ),
            ),
            onPressed: () => setAdminPayeeActive(
              context,
              ref,
              row: row,
              active: row.status != 'active',
              onDone: onDone,
            ),
            icon: Icon(
              row.status == 'active'
                  ? Icons.pause_circle_outline
                  : Icons.play_circle_outline,
              size: 18,
            ),
          ),
        ],
      _ => const [],
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < actions.length; index++) ...[
          if (index > 0) const SizedBox(width: 8),
          actions[index],
        ],
      ],
    );
  }

  Future<void> _reparse(BuildContext context, WidgetRef ref) async {
    final scope = _AdminActionScope(ref);
    final reason = await showAdminReasonDialog(
      context,
      dialogWrapper: (_, child) =>
          _AdminSessionDialog(scope: scope, child: child),
      title: 'Request MoMo SMS reparse',
      actionLabel: 'Request reparse',
    );
    if (reason == null || !context.mounted || !scope.isCurrent) return;
    try {
      await scope.repository.action('admin_reparse_payment_event', {
        'p_event_id': row.id,
        'p_reason': reason,
      });
      if (!context.mounted || !scope.isCurrent) return;
      onDone();
    } catch (error) {
      if (!context.mounted || !scope.isCurrent) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_adminActionErrorMessage(error))));
    }
  }

  Future<void> _setFeatureFlag(
    BuildContext context,
    WidgetRef ref, {
    required bool enabled,
  }) async {
    final revision = row.extra['runtime_revision'];
    if (revision is! int || revision < 1 || revision > 1000000000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Refresh this feature flag before saving.'),
        ),
      );
      return;
    }
    final scope = _AdminActionScope(ref);
    final reason = await showAdminReasonDialog(
      context,
      dialogWrapper: (_, child) =>
          _AdminSessionDialog(scope: scope, child: child),
      title: enabled ? 'Enable feature flag' : 'Disable feature flag',
      actionLabel: enabled ? 'Enable flag' : 'Disable flag',
      minLength: 8,
      maxLength: 500,
    );
    if (reason == null || !context.mounted || !scope.isCurrent) return;
    try {
      await scope.repository.action('admin_set_feature_flag_v2', {
        'p_key': row.title,
        'p_enabled': enabled,
        'p_expected_revision': revision,
        'p_reason': reason,
      });
      if (!context.mounted || !scope.isCurrent) return;
      onDone();
    } catch (error) {
      if (!context.mounted || !scope.isCurrent) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is PostgrestException && error.code == '40001'
                ? 'This feature flag changed. Refresh and review it before saving again.'
                : _adminActionErrorMessage(error),
          ),
        ),
      );
    }
  }

  Future<void> _allocate(BuildContext context, WidgetRef ref) async {
    final scope = _AdminActionScope(ref);
    final isRwanda = row.extra['rail'] == 'rw_momo';
    final targetId = TextEditingController(
      text:
          '${row.extra[isRwanda ? 'collection_id' : 'payment_intent_id'] ?? ''}',
    );
    final reason = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      animationStyle: CollectMotion.animationStyle(context),
      builder: (dialogContext) => _AdminSessionDialog(
        scope: scope,
        child: AlertDialog(
          scrollable: true,
          title: Text(isRwanda ? 'Allocate transaction' : 'Propose allocation'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: targetId,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: isRwanda
                        ? 'Group UUID'
                        : 'Group contribution intent UUID',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reason,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Allocation reason',
                    helperText: 'Required for the audit trail.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Allocate'),
            ),
          ],
        ),
      ),
    );
    if (submitted != true || !context.mounted || !scope.isCurrent) {
      targetId.dispose();
      reason.dispose();
      return;
    }
    try {
      await scope.repository.action('admin_manual_allocate_payment', {
        'p_event_id': row.extra['event_id'],
        'p_collection_id': targetId.text.trim(),
        'p_payment_intent_id': row.extra['payment_intent_id'],
        'p_reason': reason.text.trim(),
      });
      if (!context.mounted || !scope.isCurrent) return;
      onDone();
      if (!context.mounted || !scope.isCurrent) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Transaction allocated')));
    } catch (_) {
      if (!context.mounted || !scope.isCurrent) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Allocation could not be completed. Review the inputs.',
          ),
        ),
      );
    } finally {
      targetId.dispose();
      reason.dispose();
    }
  }
}
