part of 'cloudflare_admin_momo_page.dart';

typedef _IncomingQuery = ({String search, int offset});
final _incomingSms = FutureProvider.autoDispose
    .family<SmsReceiptPage<SmsReceiptSource>, _IncomingQuery>((ref, query) {
      ref.watch(adminRealtimeTickProvider);
      return ref
          .watch(cloudflareAdminSmsApiProvider)
          .receipts(
            sourceKind: 'capture',
            search: query.search,
            offset: query.offset,
          );
    });

/// Capture visibility is independent of gateway registration and payment review.
/// The capture metadata API authorizes both sides of each read. No message body
/// is disclosed here; opening the source retains its existing reveal controls.
class _IncomingSmsPanel extends ConsumerStatefulWidget {
  const _IncomingSmsPanel({super.key});
  @override
  ConsumerState<_IncomingSmsPanel> createState() => _IncomingSmsPanelState();
}

class _IncomingSmsPanelState extends ConsumerState<_IncomingSmsPanel>
    with WidgetsBindingObserver {
  final _search = TextEditingController();
  Timer? _timer;
  String _applied = '';
  int _offset = 0;
  bool _tickerEnabled = true;
  AppLifecycleState? _lifecycle;
  ModalRoute<dynamic>? _route;
  SmsReceiptPage<SmsReceiptSource>? _last;
  _IncomingQuery? _lastQuery;
  _IncomingQuery get _query => (search: _applied, offset: _offset);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _route = ModalRoute.of(context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() {
    if (!mounted ||
        !_tickerEnabled ||
        _route?.isCurrent == false ||
        _lifecycle != null && _lifecycle != AppLifecycleState.resumed) {
      return;
    }
    final user = ref.read(cloudflareAdminSessionProvider).asData?.value;
    if (user == null ||
        !user.permissions.contains('sms.read') ||
        !user.expiresAt.isAfter(DateTime.now()) ||
        ref.read(_incomingSms(_query)).isLoading) {
      return;
    }
    ref.invalidate(_incomingSms(_query));
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }

  String _time(Object? value) => value is int
      ? adminKigaliDateTime(
          DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true),
        )
      : 'Unknown';
  String _owner(SmsReceiptSource source) =>
      source.values['display_name'] as String? ?? 'App user';
  String _status(SmsReceiptSource source) => switch (source.values['status']) {
    'received' => 'Uploaded',
    'under_review' => 'Under review',
    'rejected' => 'Rejected',
    'linked' => 'Linked',
    _ => 'Received',
  };
  void _open(SmsReceiptSource source) => context.go(
    Uri(
      path: '/admin/sms-receipts/${source.kind}/${source.id}',
      queryParameters: {'returnTo': '/admin/momo-receipts'},
    ).toString(),
  );

  @override
  Widget build(BuildContext context) {
    final query = _query;
    final result = ref.watch(_incomingSms(query));
    if (result.asData case final confirmed?) {
      _last = confirmed.value;
      _lastQuery = query;
    }
    final page = result.asData?.value ?? (_lastQuery == query ? _last : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _search,
                maxLength: 200,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: 'Search SMS',
                  hintText: 'User name, member ID or receipt ID',
                  counterText: '',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    tooltip: 'Search uploaded SMS',
                    icon: const Icon(Icons.arrow_forward_rounded),
                    onPressed: () => setState(() {
                      _applied = _search.text.trim();
                      _offset = 0;
                      _last = null;
                    }),
                  ),
                ),
                onSubmitted: (value) => setState(() {
                  _applied = value.trim();
                  _offset = 0;
                  _last = null;
                }),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Refresh incoming SMS',
              onPressed: result.isLoading ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Updates automatically. An upload does not confirm payment.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (result.isLoading)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(
              semanticsLabel: 'Checking incoming SMS',
            ),
          ),
        if (result.hasError)
          _Note(
            '${_error(result.error!)}${page == null ? '' : ' Showing the last confirmed uploads.'}',
            error: true,
          ),
        if (page != null) ...[
          const SizedBox(height: 12),
          if (page.rows.isEmpty)
            _Note(
              _applied.isEmpty
                  ? 'No SMS uploaded yet. App users can turn on mobile-money SMS sharing in Settings.'
                  : 'No uploaded SMS match your search.',
            )
          else
            Builder(
              builder: (context) {
                final sources = {
                  for (final source in page.rows) source.id: source,
                };
                return AdminDataTable(
                  tableLabel: 'Incoming mobile-money SMS',
                  rows: [
                    for (final source in page.rows)
                      AdminTableRowData(
                        id: source.id,
                        title: _owner(source),
                        subtitle: '',
                        status: _status(source),
                        amount: '',
                        extra: source.values,
                      ),
                  ],
                  columns: [
                    AdminTableColumn(
                      label: 'App user',
                      value: (row) => row.title,
                    ),
                    AdminTableColumn(
                      label: 'Member ID',
                      value: (row) => '${row.extra['public_id'] ?? '—'}',
                    ),
                    AdminTableColumn(
                      label: 'SMS time · Kigali',
                      value: (row) => _time(row.extra['received_at']),
                    ),
                    AdminTableColumn(
                      label: 'Uploaded · Kigali',
                      value: (row) => _time(row.extra['created_at']),
                    ),
                    AdminTableColumn(
                      label: 'Status',
                      value: (row) => row.status,
                    ),
                  ],
                  onOpen: (row) => _open(sources[row.id]!),
                );
              },
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
      ],
    );
  }
}
