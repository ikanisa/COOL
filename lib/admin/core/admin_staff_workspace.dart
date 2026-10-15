part of 'admin_runtime.dart';

class AdminStaffDetailPage extends ConsumerStatefulWidget {
  const AdminStaffDetailPage({required this.id, super.key});
  final String id;
  @override
  ConsumerState<AdminStaffDetailPage> createState() =>
      _AdminStaffDetailPageState();
}

class _AdminStaffDetailPageState extends ConsumerState<AdminStaffDetailPage> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final identity = _adminResolvedIdentity(ref.watch(adminIdentityProvider));
    if (!_adminHasPermission(identity, 'admin_users.read')) {
      return const AdminPage(
        title: 'Staff access',
        child: AdminEmptyState(title: 'Access review permission required'),
      );
    }
    final data = ref.watch(
      adminDetailRecordProvider((
        rpc: 'admin_get_staff_user_v1',
        id: widget.id,
      )),
    );
    return AdminPage(
      title: 'Staff access',
      leading: IconButton(
        tooltip: 'Back to Staff',
        onPressed: () => context.go('/admin/staff'),
        icon: const Icon(Icons.arrow_back),
      ),
      child: data.when(
        loading: () => const AdminLoadingState(title: 'Loading Staff access'),
        error: (e, _) => AdminSafeErrorPanel(
          error: e,
          onRetry: () => ref.read(adminRealtimeTickProvider.notifier).state++,
        ),
        data: (row) {
          if (row.isEmpty) {
            return const AdminEmptyState(title: 'Staff user not found');
          }
          final active = row['staff_access'] == true;
          final facts = [
            ('Name', '${row['display_name'] ?? 'Not recorded'}'),
            ('Collect ID', '${row['public_id'] ?? 'Not recorded'}'),
            ('Email', '${row['email'] ?? 'Not recorded'}'),
            ('Staff access', active ? 'Active' : 'Inactive'),
            (
              'Operator identity',
              row['operator_approved'] == true
                  ? 'Verified and approved'
                  : 'Approval required',
            ),
            (
              'Created',
              adminKigaliDateTime(DateTime.tryParse('${row['created_at']}')),
            ),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AdminRecordFactsTable(
                fields: facts,
                semanticLabel: 'Staff identity and access facts',
              ),
              const SizedBox(height: 12),
              if (_adminHasPermission(identity, 'admin_users.manage'))
                OutlinedButton.icon(
                  onPressed:
                      _busy || !active && row['operator_approved'] != true
                      ? null
                      : () => _change(active),
                  icon: Icon(
                    active ? Icons.person_off_outlined : Icons.person_add_alt,
                  ),
                  label: Text(
                    active
                        ? 'Deactivate Staff access'
                        : 'Activate Staff access',
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                'Staff role capabilities',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              const _AdminStaffCapabilitiesTable(),
            ],
          );
        },
      ),
    );
  }

  Future<void> _change(bool wasActive) async {
    if (_busy) return;
    final targetId = widget.id;
    final scope = _AdminActionScope(ref);
    if (!scope.isCurrent || !scope.permissions.contains('admin_users.manage')) {
      return;
    }
    final reason = await showAdminReasonDialog(
      context,
      title: wasActive ? 'Deactivate Staff access' : 'Activate Staff access',
      actionLabel: wasActive ? 'Deactivate' : 'Activate',
      minLength: 8,
      maxLength: 500,
      dialogWrapper: (_, child) =>
          _AdminSessionDialog(scope: scope, child: child),
    );
    if (reason == null ||
        !mounted ||
        !scope.isCurrent ||
        widget.id != targetId) {
      return;
    }
    setState(() => _busy = true);
    try {
      await scope.repository.action('admin_set_staff_access_v1', {
        'p_user_id': targetId,
        'p_active': !wasActive,
        'p_reason': reason,
      });
      if (!mounted || !scope.isCurrent || widget.id != targetId) return;
      ref.read(adminRealtimeTickProvider.notifier).state++;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Staff access updated')));
    } catch (error) {
      if (mounted && scope.isCurrent && widget.id == targetId) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_adminActionErrorMessage(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _AdminStaffCapabilitiesTable extends StatelessWidget {
  const _AdminStaffCapabilitiesTable();

  static const _areas = [
    ('Overview', 'View', '—'),
    ('Groups', 'View', 'Create private group'),
    ('Users', 'View', '—'),
    ('Members', 'View', '—'),
    ('Payees', 'View', '—'),
    ('Transactions', 'View', '—'),
    ('Reconciliations', 'View', 'Propose existing-member allocation'),
    ('Ledgers', 'View', '—'),
    ('SMS receipts', 'Metadata only', '—'),
  ];

  @override
  Widget build(BuildContext context) => _AdminPremiumTable(
    minimumWidth: 900,
    columns: const [
      DataColumn(label: Text('Area')),
      DataColumn(label: Text('Read access')),
      DataColumn(label: Text('Allowed actions')),
    ],
    rows: [
      for (final (area, read, actions) in _areas)
        DataRow(
          cells: [
            DataCell(_AdminFullTableValue(area)),
            DataCell(_AdminFullTableValue(read)),
            DataCell(_AdminFullTableValue(actions)),
          ],
        ),
    ],
  );
}

Future<void> createAdminStaffGroup(
  BuildContext context,
  WidgetRef ref, {
  required VoidCallback onDone,
}) async {
  final scope = _AdminActionScope(ref);
  if (!scope.isCurrent || !scope.permissions.contains('collections.create')) {
    return;
  }
  final title = TextEditingController(), reason = TextEditingController();
  final form = GlobalKey<FormState>();
  final values = await _showAdminFormDialog<({String title, String reason})>(
    context: context,
    builder: (context) => _AdminSessionDialog(
      scope: scope,
      child: AlertDialog(
        title: const Text('Create private group'),
        content: SizedBox(
          width: 460,
          child: Form(
            key: form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: title,
                    decoration: const InputDecoration(labelText: 'Group name'),
                    maxLength: 160,
                    validator: (v) => v == null || v.trim().length < 2
                        ? 'Enter a group name'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: reason,
                    decoration: const InputDecoration(labelText: 'Reason'),
                    maxLength: 500,
                    maxLines: 3,
                    validator: (v) => v == null || v.trim().length < 8
                        ? 'Enter a reason of at least 8 characters'
                        : null,
                  ),
                  const Text(
                    'An Admin can assign the group owner and review the member and MoMo receiver setup after creation.',
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, (
                  title: title.text.trim(),
                  reason: reason.text.trim(),
                ));
              }
            },
            child: const Text('Create group'),
          ),
        ],
      ),
    ),
  );
  title.dispose();
  reason.dispose();
  if (values == null || !context.mounted || !scope.isCurrent) return;
  try {
    final result = await scope.repository
        .action('admin_create_staff_group_v1', {
          'p_title': values.title,
          'p_reason': values.reason,
          'p_request_id': const Uuid().v4(),
        });
    if (!context.mounted || !scope.isCurrent) return;
    onDone();
    ref.read(adminRealtimeTickProvider.notifier).state++;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Private group created')));
    context.go('/admin/groups/${result['collection_id']}');
  } catch (error) {
    if (!context.mounted || !scope.isCurrent) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_adminActionErrorMessage(error))));
  }
}
