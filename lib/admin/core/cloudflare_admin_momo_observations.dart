part of 'cloudflare_admin_momo_page.dart';

/// Read-only admissions across the approved group, apart from canonical captures.
class _ObservationAdmissions extends ConsumerStatefulWidget {
  const _ObservationAdmissions({super.key});
  @override
  ConsumerState<_ObservationAdmissions> createState() =>
      _ObservationAdmissionsState();
}

class _ObservationAdmissionsState extends ConsumerState<_ObservationAdmissions>
    with WidgetsBindingObserver {
  final _reason = TextEditingController();
  final _history = <String?>[];
  Timer? _timer;
  Timer? _contentDeadlineTimer;
  DateTime? _deadlineProofAt, _deadlineSessionExpiry;
  AppLifecycleState? _lifecycle;
  ModalRoute<dynamic>? _route;
  bool _tickerEnabled = true;
  List<ObservationCollection> _collections = [];
  ObservationAdmissionPage? _page;
  ObservationAdmission? _selected;
  ObservationContent? _content;
  String? _group, _cursor, _message;
  bool _busy = false, _confirmed = false;
  int _generation = 0;
  late final ({int epoch, Object? key}) _sessionFence;

  bool get _currentSession =>
      mounted &&
      ref.read(cloudflareAdminSessionProvider.notifier).authorityFence ==
          _sessionFence;

  @override
  void initState() {
    super.initState();
    _sessionFence = ref
        .read(cloudflareAdminSessionProvider.notifier)
        .authorityFence;
    WidgetsBinding.instance.addObserver(this);
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    _timer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshIfIdle(),
    );
    Future.microtask(_loadCollections);
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
    if (state != AppLifecycleState.resumed && mounted) _clearContent();
    if (state == AppLifecycleState.resumed) _refreshIfIdle();
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    _cancelContentDeadline();
    WidgetsBinding.instance.removeObserver(this);
    _reason.dispose();
    super.dispose();
  }

  void _refreshIfIdle() {
    if (!mounted) return;
    final currentUser = ref.read(cloudflareAdminSessionProvider).asData?.value;
    final now = ref.read(burimunsiObservationClockProvider)();
    if (_content != null &&
        (!_currentSession ||
            currentUser?.hasRecentSensitiveVerification(now: now) != true)) {
      _clearContent();
    }
    if (!_currentSession ||
        !_tickerEnabled ||
        _route?.isCurrent == false ||
        _lifecycle != null && _lifecycle != AppLifecycleState.resumed ||
        _busy ||
        _selected != null ||
        _cursor != null) {
      return;
    }
    _loadCollections();
  }

  void _clearContent() {
    _cancelContentDeadline();
    if (_content == null && !_confirmed && _reason.text.isEmpty) return;
    _generation++;
    setState(() {
      _content = null;
      _confirmed = false;
      _reason.clear();
      _busy = false;
    });
  }

  void _cancelContentDeadline() {
    _contentDeadlineTimer?.cancel();
    _contentDeadlineTimer = null;
    _deadlineProofAt = null;
    _deadlineSessionExpiry = null;
  }

  /// Recompute at the deadline in case the same session obtained a newer proof.
  void _scheduleContentDeadline() {
    _cancelContentDeadline();
    if (!mounted || _content == null) return;
    final user = ref.read(cloudflareAdminSessionProvider).asData?.value;
    final now = ref.read(burimunsiObservationClockProvider)();
    final proofAt = user?.sensitiveVerificationAt;
    if (!_currentSession ||
        user == null ||
        proofAt == null ||
        !user.hasRecentSensitiveVerification(now: now)) {
      _clearContent();
      return;
    }
    final proofExpiry = proofAt.add(const Duration(minutes: 5));
    final deadline = user.expiresAt.isBefore(proofExpiry)
        ? user.expiresAt
        : proofExpiry;
    if (!now.isBefore(deadline)) {
      _clearContent();
      return;
    }
    _deadlineProofAt = proofAt;
    _deadlineSessionExpiry = user.expiresAt;
    _contentDeadlineTimer = Timer(deadline.difference(now), () {
      if (!mounted || _content == null) return;
      final current = ref.read(cloudflareAdminSessionProvider).asData?.value;
      if (!_currentSession ||
          current == null ||
          current.sensitiveVerificationAt == proofAt &&
              current.expiresAt == user.expiresAt) {
        _clearContent();
      } else {
        // A same-session renewal can extend the deadline; recheck it rather than
        // treating a renewed proof as the original proof.
        _scheduleContentDeadline();
      }
    });
  }

  Future<void> _loadCollections() async {
    if (!_currentSession) return;
    _cancelContentDeadline();
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _message = null;
      _page = null;
      _selected = null;
      _content = null;
      _confirmed = false;
      _reason.clear();
      _history.clear();
      _cursor = null;
    });
    try {
      final result = await ref
          .read(cloudflareAdminObservationApiProvider)
          .collections();
      if (!_currentSession || generation != _generation) return;
      final previous = _group;
      setState(() {
        _collections = result.items;
        _group = result.items.any((item) => item.id == previous)
            ? previous
            : result.items.length == 1
            ? result.items.single.id
            : null;
        _busy = false;
      });
      if (_group != null) await _loadPage(null);
    } catch (error) {
      if (_currentSession && generation == _generation) {
        setState(() {
          _collections = [];
          _group = null;
          _busy = false;
          _message = _error(error);
        });
      }
    }
  }

  Future<void> _loadPage(String? cursor) async {
    if (!_currentSession) return;
    final group = _group;
    if (group == null) return;
    _cancelContentDeadline();
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _message = null;
      _page = null;
      _selected = null;
      _content = null;
      _confirmed = false;
      _reason.clear();
      _cursor = cursor;
    });
    try {
      final result = await ref
          .read(cloudflareAdminObservationApiProvider)
          .admissions(group, cursor: cursor);
      if (!_currentSession || generation != _generation || _group != group) {
        return;
      }
      setState(() {
        _page = result;
        _busy = false;
      });
    } catch (error) {
      if (_currentSession && generation == _generation && _group == group) {
        setState(() {
          _busy = false;
          _message = _error(error);
        });
      }
    }
  }

  void _selectGroup(String? group) {
    if (group == null || group == _group) return;
    setState(() {
      _group = group;
      _history.clear();
    });
    _loadPage(null);
  }

  void _select(ObservationAdmission item) {
    _generation++;
    _cancelContentDeadline();
    setState(() {
      _selected = _selected?.sourceId == item.sourceId ? null : item;
      _content = null;
      _confirmed = false;
      _reason.clear();
      _busy = false;
    });
  }

  Future<void> _reveal() async {
    final item = _selected, group = _group;
    if (!_currentSession ||
        item == null ||
        group == null ||
        !item.retained ||
        !_confirmed ||
        _busy) {
      return;
    }
    final generation = ++_generation;
    _cancelContentDeadline();
    setState(() {
      _busy = true;
      _message = null;
      _content = null;
    });
    try {
      final result = await ref
          .read(cloudflareAdminObservationApiProvider)
          .reveal(group, item, _reason.text);
      if (!_currentSession ||
          generation != _generation ||
          _group != group ||
          _selected?.sourceId != item.sourceId) {
        return;
      }
      setState(() {
        _content = result;
        _confirmed = false;
        _busy = false;
      });
      _scheduleContentDeadline();
    } catch (error) {
      if (_currentSession && generation == _generation) {
        setState(() {
          _busy = false;
          _message = _error(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Subscribe even when the ordinary receipt page is not refreshing. A
    // changed session fences pending replies and removes this keyed widget.
    final user = ref.watch(cloudflareAdminSessionProvider).asData?.value;
    if (!_currentSession) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _clearContent();
      });
      return const SizedBox.shrink();
    }
    final currentRoute = ModalRoute.of(context)?.isCurrent != false;
    if (!currentRoute &&
        (_content != null || _confirmed || _reason.text.isNotEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ModalRoute.of(context)?.isCurrent == false) {
          _clearContent();
        }
      });
    }
    final canReveal =
        user != null &&
        user.role != AdminAccountRole.staff &&
        user.permissions.contains('sms.read') &&
        user.permissions.contains('sms.reveal');
    final verified =
        user?.hasRecentSensitiveVerification(
          now: ref.read(burimunsiObservationClockProvider)(),
        ) ==
        true;
    if (_content != null &&
        (user?.sensitiveVerificationAt != _deadlineProofAt ||
            user?.expiresAt != _deadlineSessionExpiry)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _content != null) _scheduleContentDeadline();
      });
    }
    if (!verified && _content != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            ref
                    .read(cloudflareAdminSessionProvider)
                    .asData
                    ?.value
                    ?.hasRecentSensitiveVerification(
                      now: ref.read(burimunsiObservationClockProvider)(),
                    ) !=
                true) {
          _clearContent();
        }
      });
    }
    final page = _page;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Unassigned SMS',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Refresh unassigned SMS',
              onPressed: _busy ? null : _loadCollections,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const Text(
          'Requests for the selected group. Recorded retention needs source verification; it does not confirm a payment or receiving account.',
        ),
        if (_collections.length > 1)
          DropdownButtonFormField<String>(
            key: ValueKey('observation-group-$_group'),
            isExpanded: true,
            initialValue: _group,
            decoration: const InputDecoration(labelText: 'Approved group'),
            items: [
              for (final group in _collections)
                DropdownMenuItem(value: group.id, child: Text(group.label)),
            ],
            onChanged: _busy ? null : _selectGroup,
          )
        else if (_collections.length == 1)
          Text(_collections.single.label),
        if (_busy)
          const LinearProgressIndicator(
            semanticsLabel: 'Checking unassigned SMS',
          ),
        if (_message != null) _Note(_message!, error: true),
        if (!_busy && _collections.isEmpty && _message == null)
          const _Note('No approved groups are available.'),
        if (!_busy && _collections.length > 1 && _group == null)
          const _Note('Select an approved group.'),
        if (page != null) ...[
          if (page.items.isEmpty)
            const _Note('No unassigned SMS admissions in this group.')
          else
            AdminDataTable(
              tableLabel: 'Unassigned SMS admissions',
              rows: [
                for (final item in page.items)
                  AdminTableRowData(
                    id: item.sourceId,
                    title: item.sourceId,
                    subtitle: '',
                    status: item.retained
                        ? 'Retained for review'
                        : 'Admission outcome unresolved',
                    amount: '',
                    extra: {
                      'requestId': item.requestId,
                      'admittedAt': item.admittedAt,
                    },
                  ),
              ],
              columns: [
                AdminTableColumn(
                  label: 'Source ID',
                  selectable: true,
                  value: (row) => row.title,
                ),
                AdminTableColumn(
                  label: 'Request ID',
                  selectable: true,
                  value: (row) => '${row.extra['requestId']}',
                ),
                AdminTableColumn(
                  label: 'Admitted · Kigali',
                  value: (row) =>
                      adminKigaliDateTime(row.extra['admittedAt'] as DateTime),
                ),
                AdminTableColumn(label: 'Status', value: (row) => row.status),
              ],
              onOpen: (row) => _select(
                page.items.firstWhere((item) => item.sourceId == row.id),
              ),
            ),
          Row(
            children: [
              TextButton(
                onPressed: _busy || _history.isEmpty
                    ? null
                    : () {
                        final previous = _history.removeLast();
                        _loadPage(previous);
                      },
                child: const Text('Previous'),
              ),
              TextButton(
                onPressed: _busy || page.nextCursor == null
                    ? null
                    : () {
                        _history.add(_cursor);
                        _loadPage(page.nextCursor);
                      },
                child: const Text('Next'),
              ),
            ],
          ),
        ],
        if (_selected != null && !_selected!.retained)
          const _Note(
            'The admission outcome is unresolved. The original phone may retry its same request when its access is valid.',
          ),
        if (_selected?.retained == true && canReveal && currentRoute) ...[
          const SizedBox(height: 12),
          const Text('Review original source'),
          const Text('Opening the message records your review reason.'),
          if (!verified && user.usesEmailVerification == true)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => context.go(
                  Uri(
                    path: '/admin/security/verify-email',
                    queryParameters: {
                      'returnTo': GoRouterState.of(context).uri.toString(),
                    },
                  ).toString(),
                ),
                child: const Text('Verify email'),
              ),
            ),
          TextField(
            controller: _reason,
            enabled: !_busy,
            maxLength: 1000,
            decoration: const InputDecoration(
              labelText: 'Source review reason',
            ),
            onChanged: (_) => setState(() {
              _confirmed = false;
              _content = null;
            }),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Record my reason and open the original source.'),
            value: _confirmed,
            onChanged: _busy
                ? null
                : (value) => setState(() => _confirmed = value == true),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: _busy || !_confirmed || _reason.text.trim().length < 8
                  ? null
                  : _reveal,
              child: const Text('Open audited source'),
            ),
          ),
          if (_content != null && verified) ...[
            const SizedBox(height: 8),
            SelectableText(_content!.sender),
            SelectableText(_content!.body),
            if (_content!.displayHints?.hints.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              const Text(
                'Visible text from an incomplete message; not payment confirmation.',
              ),
              for (final hint in _content!.displayHints!.hints) ...[
                Text(
                  hint.kind == 'quoted_incoming_amount'
                      ? 'Visible amount text'
                      : 'Visible reference text',
                ),
                SelectableText(hint.text),
              ],
            ],
          ],
        ],
      ],
    );
  }
}
