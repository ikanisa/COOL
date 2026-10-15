part of 'admin_runtime.dart';

class _AdminPayeeWorkspace extends ConsumerStatefulWidget {
  const _AdminPayeeWorkspace({required this.rows, required this.onDone});
  final List<AdminTableRowData> rows;
  final VoidCallback onDone;

  @override
  ConsumerState<_AdminPayeeWorkspace> createState() =>
      _AdminPayeeWorkspaceState();
}

class _AdminPayeeWorkspaceState extends ConsumerState<_AdminPayeeWorkspace> {
  final _busy = <String>{};

  Future<void> _manage(AdminTableRowData row, {required bool edit}) async {
    if (_busy.contains(row.id)) return;
    setState(() => _busy.add(row.id));
    try {
      if (edit) {
        await editAdminPayee(context, ref, row: row, onDone: widget.onDone);
      } else {
        await setAdminPayeeActive(
          context,
          ref,
          row: row,
          active: row.status != 'active',
          onDone: widget.onDone,
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(row.id));
    }
  }

  Widget _actions(AdminTableRowData row) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton.filledTonal(
        tooltip:
            '${row.status == 'active' ? 'Deactivate' : 'Activate'} ${row.title}',
        onPressed: _busy.contains(row.id)
            ? null
            : () => _manage(row, edit: false),
        icon: _busy.contains(row.id)
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                row.status == 'active'
                    ? Icons.toggle_on_outlined
                    : Icons.toggle_off_outlined,
              ),
      ),
      const SizedBox(width: 8),
      _edit(row),
    ],
  );

  Widget _edit(AdminTableRowData row) => IconButton.outlined(
    tooltip: 'Edit ${row.title}',
    onPressed: _busy.contains(row.id) ? null : () => _manage(row, edit: true),
    icon: const Icon(Icons.edit_outlined, size: 18),
  );

  String _code(AdminTableRowData row) {
    final value = _extraText(row, 'momo_code');
    return RegExp(r'^[0-9]{4,9}$').hasMatch(value) ? value : '';
  }

  @override
  Widget build(BuildContext context) {
    final identity = _adminResolvedIdentity(ref.watch(adminIdentityProvider));
    final canManage = _adminHasPermission(identity, 'receivers.manage');
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Admin records table, ${widget.rows.length} rows',
      child: _AdminPremiumTable(
        minimumWidth: 1100,
        columns: [
          const DataColumn(
            label: _AdminColumnLabel(
              icon: Icons.person_outline,
              label: 'Payee',
            ),
          ),
          const DataColumn(
            label: _AdminColumnLabel(
              icon: Icons.folder_outlined,
              label: 'Group',
            ),
          ),
          const DataColumn(
            label: _AdminColumnLabel(
              icon: Icons.dialpad_outlined,
              label: 'MoMo code',
            ),
          ),
          const DataColumn(
            label: _AdminColumnLabel(
              icon: Icons.toggle_on_outlined,
              label: 'State',
            ),
          ),
          const DataColumn(
            label: _AdminColumnLabel(
              icon: Icons.calendar_today_outlined,
              label: 'Created',
            ),
          ),
          if (canManage)
            const DataColumn(
              label: _AdminColumnLabel(
                icon: Icons.edit_outlined,
                label: 'Actions',
              ),
            ),
        ],
        rows: [
          for (final row in widget.rows)
            DataRow(
              cells: [
                DataCell(_AdminFullTableValue(row.title)),
                DataCell(
                  _AdminFullTableValue(_extraText(row, 'collection_title')),
                ),
                DataCell(_AdminFullTableValue(_code(row))),
                DataCell(AdminStatusChip(label: row.status)),
                DataCell(_AdminDateTimeValue(row.createdAt, dateOnly: true)),
                if (canManage) DataCell(_actions(row)),
              ],
            ),
        ],
      ),
    );
  }
}
