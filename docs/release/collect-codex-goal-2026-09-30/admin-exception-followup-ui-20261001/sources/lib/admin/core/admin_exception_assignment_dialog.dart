part of 'admin_runtime.dart';

bool _exceptionFollowupCanRead(AdminIdentity? identity) =>
    _exceptionCanRead(identity) && identity!.roles.contains('platform_owner');

bool _exceptionFollowupCanManage(AdminIdentity? identity) =>
    _exceptionFollowupCanRead(identity) && _exceptionCanManage(identity);

typedef AdminExceptionFollowupDirectoryAccess = ({
  AdminExceptionFollowupDirectoryQuery query,
  AdminSessionScope session,
});

final adminExceptionFollowupOperatorsProvider = FutureProvider.autoDispose
    .family<
      AdminExceptionFollowupDirectory,
      AdminExceptionFollowupDirectoryAccess
    >((ref, access) async {
      final session = ref.watch(adminAuthSessionScopeProvider);
      ref.watch(_adminIdentityRevisionProvider);
      final repository = ref.watch(adminRepositoryProvider);
      var current = true;
      ref.onDispose(() => current = false);
      if (session != access.session) throw const AdminSessionChanged();
      final identity = await ref.watch(adminIdentityProvider.future);
      if (!current) throw const AdminSessionChanged();
      if (identity?.userId != session?.key.userId ||
          !_exceptionFollowupCanManage(identity)) {
        throw const AdminExceptionDenied();
      }
      final raw = await repository
          .exceptionFollowupOperators(access.query)
          .timeout(const Duration(seconds: 15));
      if (!current) throw const AdminSessionChanged();
      return AdminExceptionFollowupDirectory.parse(raw, query: access.query);
    });

class _AdminExceptionAssignmentSelection {
  const _AdminExceptionAssignmentSelection({
    required this.operatorId,
    required this.displayLabel,
    required this.dueAt,
    required this.checkedAt,
    required this.validUntil,
  });
  final String operatorId, displayLabel;
  final DateTime dueAt, checkedAt, validUntil;

  bool isFresh(DateTime now) =>
      !now.isBefore(checkedAt) && now.isBefore(validUntil);
}

String _exceptionAssignmentDueInput(DateTime value) => value
    .toUtc()
    .add(const Duration(hours: 2))
    .toIso8601String()
    .substring(0, 16)
    .replaceFirst('T', ' ');

DateTime? _exceptionAssignmentDue(String text) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2}) ([0-2]\d):([0-5]\d)$',
  ).firstMatch(text);
  if (match == null) return null;
  final values = [for (var i = 1; i <= 5; i++) int.parse(match[i]!)];
  final wall = DateTime.utc(
    values[0],
    values[1],
    values[2],
    values[3],
    values[4],
  );
  if (wall.year != values[0] ||
      wall.month != values[1] ||
      wall.day != values[2] ||
      wall.hour != values[3] ||
      wall.minute != values[4]) {
    return null;
  }
  return wall.subtract(const Duration(hours: 2));
}

Future<_AdminExceptionAssignmentSelection?> _showExceptionAssignmentDialog(
  BuildContext context,
  _AdminActionScope scope, {
  _AdminExceptionAssignmentSelection? initial,
}) async {
  if (!scope.isCurrent || scope.session == null) return null;
  return _showAdminFormDialog<_AdminExceptionAssignmentSelection>(
    context: context,
    builder: (_) => _AdminSessionDialog(
      scope: scope,
      child: _AdminExceptionAssignmentDialog(scope: scope, initial: initial),
    ),
  );
}

class _AdminExceptionAssignmentDialog extends ConsumerStatefulWidget {
  const _AdminExceptionAssignmentDialog({required this.scope, this.initial});
  final _AdminActionScope scope;
  final _AdminExceptionAssignmentSelection? initial;
  @override
  ConsumerState<_AdminExceptionAssignmentDialog> createState() =>
      _AdminExceptionAssignmentDialogState();
}

class _AdminExceptionAssignmentDialogState
    extends ConsumerState<_AdminExceptionAssignmentDialog> {
  final _queries = <AdminExceptionFollowupDirectoryQuery>[
    const AdminExceptionFollowupDirectoryQuery(),
  ];
  late final TextEditingController _due;
  String? _selected, _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial?.operatorId;
    _due = TextEditingController(
      text: _exceptionAssignmentDueInput(
        widget.initial?.dueAt ??
            ref.read(adminClockProvider)().add(const Duration(hours: 1)),
      ),
    );
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _due.dispose();
    super.dispose();
  }

  AdminExceptionFollowupDirectoryAccess get _access =>
      (query: _queries.last, session: widget.scope.session!);

  @override
  Widget build(BuildContext context) {
    final identity = _adminResolvedIdentity(ref.watch(adminIdentityProvider));
    ref.watch(adminAuthSessionScopeProvider);
    final current =
        widget.scope.isCurrent && _exceptionFollowupCanManage(identity);
    if (!current) return const SizedBox.shrink();
    final state = ref.watch(adminExceptionFollowupOperatorsProvider(_access));
    final directory = state.isLoading ? null : state.asData?.value;
    final now = ref.watch(adminClockProvider)();
    final fresh = directory?.isFresh(now) == true;
    final rows = directory?.rows ?? const <AdminExceptionFollowupOperator>[];
    final selected = rows
        .where((row) => row.operatorId == _selected)
        .firstOrNull;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Assign exception follow-up',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Choose an operator with current exception access and a deadline. Escalations go to that operator’s Admin inbox.',
                ),
                const SizedBox(height: 16),
                Semantics(
                  header: true,
                  child: Text(
                    'Eligible operators',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (state.isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Checking eligible operators…'),
                  )
                else if (state.hasError)
                  const Text(
                    'Eligible operators could not be verified. Refresh and check current email access.',
                  )
                else if (rows.isEmpty)
                  const Text('No eligible operators were found on this page.')
                else
                  RadioGroup<String>(
                    groupValue: _selected,
                    onChanged: fresh
                        ? (value) => setState(() => _selected = value)
                        : (_) {},
                    child: Column(
                      children: [
                        for (final row in rows)
                          RadioListTile<String>(
                            value: row.operatorId,
                            enabled: fresh,
                            title: Text(
                              row.operatorId == identity?.userId
                                  ? '${row.displayLabel} · You'
                                  : row.displayLabel,
                            ),
                          ),
                      ],
                    ),
                  ),
                if (directory != null && !fresh)
                  const Text(
                    'The operator observation expired. Refresh before choosing an operator.',
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: _queries.length > 1 && !state.isLoading
                          ? () => setState(() {
                              _queries.removeLast();
                              _selected = null;
                            })
                          : null,
                      child: const Text('Previous operators'),
                    ),
                    OutlinedButton(
                      onPressed: fresh && directory!.nextCursor != null
                          ? () => setState(() {
                              _queries.add(
                                AdminExceptionFollowupDirectoryQuery(
                                  before: directory.nextCursor,
                                ),
                              );
                              _selected = null;
                            })
                          : null,
                      child: const Text('Next operators'),
                    ),
                    TextButton(
                      onPressed: () => ref.invalidate(
                        adminExceptionFollowupOperatorsProvider(_access),
                      ),
                      child: const Text('Refresh operators'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _due,
                  keyboardType: TextInputType.datetime,
                  onChanged: (_) => setState(() => _error = null),
                  decoration: InputDecoration(
                    labelText: 'Due at (Africa/Kigali)',
                    hintText: 'YYYY-MM-DD HH:mm',
                    helperText: 'Choose a future time within 30 days.',
                    errorText: _error,
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel assignment'),
                    ),
                    FilledButton(
                      onPressed: fresh && selected != null
                          ? () => _choose(directory!, selected)
                          : null,
                      child: const Text('Use operator and deadline'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _choose(
    AdminExceptionFollowupDirectory directory,
    AdminExceptionFollowupOperator operator,
  ) {
    final now = ref.read(adminClockProvider)();
    if (!widget.scope.isCurrent || !directory.isFresh(now)) return;
    final due = _exceptionAssignmentDue(_due.text);
    if (due == null ||
        !due.isAfter(now) ||
        due.isAfter(now.add(const Duration(days: 30)))) {
      setState(() => _error = 'Enter a valid future deadline within 30 days.');
      return;
    }
    Navigator.pop(
      context,
      _AdminExceptionAssignmentSelection(
        operatorId: operator.operatorId,
        displayLabel: operator.displayLabel,
        dueAt: due,
        checkedAt: directory.checkedAt,
        validUntil: directory.validUntil,
      ),
    );
  }
}
