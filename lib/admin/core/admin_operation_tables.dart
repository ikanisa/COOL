part of 'admin_runtime.dart';

class _AdminTransactionWorkspace extends StatelessWidget {
  const _AdminTransactionWorkspace({required this.rows, required this.onOpen});

  final List<AdminTableRowData> rows;
  final ValueChanged<AdminTableRowData>? onOpen;

  @override
  Widget build(BuildContext context) {
    final allocated = rows
        .where(
          (row) =>
              AdminTransactionLifecycle.parse(
                row.extra['lifecycle'],
              )?.allocation ==
              'allocated',
        )
        .length;
    final review = rows.where((row) {
      final lifecycle = AdminTransactionLifecycle.parse(row.extra['lifecycle']);
      return lifecycle == null ||
          lifecycle.allocation != 'allocated' ||
          lifecycle.verification != 'confirmation_recorded' ||
          !{'posted', 'reversed'}.contains(lifecycle.ledger) ||
          {'failed_no_send', 'uncertain'}.contains(lifecycle.notification);
    }).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AdminOperationsSummary(
          semanticLabel:
              'Transaction page summary, ${rows.length} transactions, '
              '$allocated allocated, $review requiring attention, '
              'Rwanda MoMo transactions only',
          items: [
            _AdminOperationsSummaryItem(
              icon: Icons.receipt_long_outlined,
              value: '${rows.length}',
              label: 'This page',
            ),
            _AdminOperationsSummaryItem(
              icon: Icons.done_all_outlined,
              value: '$allocated',
              label: 'Allocated',
            ),
            _AdminOperationsSummaryItem(
              icon: Icons.error_outline,
              value: '$review',
              label: 'Attention',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Semantics(
          container: true,
          explicitChildNodes: true,
          label: 'Admin records table, ${rows.length} rows',
          child: _AdminTransactionTable(rows: rows, onOpen: onOpen),
        ),
      ],
    );
  }
}

class _AdminGroupsWorkspace extends StatelessWidget {
  const _AdminGroupsWorkspace({required this.rows, required this.onOpen});

  final List<AdminTableRowData> rows;
  final ValueChanged<AdminTableRowData>? onOpen;

  @override
  Widget build(BuildContext context) {
    final archived = rows.where(_isArchivedGroup).length;
    final publicCount = rows
        .where((row) => !_isArchivedGroup(row) && _isPublicGroup(row))
        .length;
    final privateCount = rows.length - publicCount - archived;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AdminOperationsSummary(
          semanticLabel:
              'Group page summary, ${rows.length} groups, $publicCount public, '
              '$privateCount private and $archived archived',
          items: [
            _AdminOperationsSummaryItem(
              icon: Icons.folder_copy_outlined,
              value: '${rows.length}',
              label: 'This page',
            ),
            _AdminOperationsSummaryItem(
              icon: Icons.public_outlined,
              value: '$publicCount',
              label: 'Public',
            ),
            _AdminOperationsSummaryItem(
              icon: Icons.lock_outline,
              value: '$privateCount',
              label: 'Private',
            ),
            if (archived > 0)
              _AdminOperationsSummaryItem(
                icon: Icons.archive_outlined,
                value: '$archived',
                label: 'Archived',
              ),
          ],
        ),
        const SizedBox(height: 12),
        Semantics(
          container: true,
          explicitChildNodes: true,
          label: 'Admin records table, ${rows.length} rows',
          child: _AdminGroupTable(rows: rows, onOpen: onOpen),
        ),
      ],
    );
  }
}

class _AdminMembersWorkspace extends StatelessWidget {
  const _AdminMembersWorkspace({
    required this.rows,
    required this.onOpen,
    this.scopeLabel = 'Members',
  });

  final List<AdminTableRowData> rows;
  final ValueChanged<AdminTableRowData>? onOpen;
  final String scopeLabel;

  @override
  Widget build(BuildContext context) {
    final rwanda = rows.where((row) => _country(row) == 'RW').length;
    final admins = rows
        .where(
          (row) => row.extra['user_type'] == 'Admin' || row.status == 'admin',
        )
        .length;
    final staff = rows.where((row) => row.extra['user_type'] == 'Staff').length;
    final apps = rows.where((row) => row.extra['user_type'] == 'App').length;
    final direct = rows
        .where((row) => row.extra['user_type'] == 'Direct')
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AdminOperationsSummary(
          semanticLabel:
              '$scopeLabel page summary, ${rows.length} ${scopeLabel.toLowerCase()}, $rwanda Rwanda, '
              '$admins platform admins',
          items: [
            _AdminOperationsSummaryItem(
              icon: Icons.people_outline,
              value: '${rows.length}',
              label: 'This page',
            ),
            if (scopeLabel != 'Members') ...[
              _AdminOperationsSummaryItem(
                icon: Icons.supervisor_account_outlined,
                value: '$staff',
                label: 'Staff',
              ),
              _AdminOperationsSummaryItem(
                icon: Icons.phone_android_outlined,
                value: '$apps',
                label: 'App',
              ),
              _AdminOperationsSummaryItem(
                icon: Icons.person_outline,
                value: '$direct',
                label: 'Direct',
              ),
            ],
            if (admins > 0)
              _AdminOperationsSummaryItem(
                icon: Icons.admin_panel_settings_outlined,
                value: '$admins',
                label: 'Admins',
              ),
          ],
        ),
        const SizedBox(height: 12),
        Semantics(
          container: true,
          explicitChildNodes: true,
          label: 'Admin records table, ${rows.length} rows',
          child: _AdminMemberTable(
            rows: rows,
            onOpen: onOpen,
            scopeLabel: scopeLabel,
          ),
        ),
      ],
    );
  }
}

class _AdminTransactionTable extends StatelessWidget {
  const _AdminTransactionTable({required this.rows, required this.onOpen});
  final List<AdminTableRowData> rows;
  final ValueChanged<AdminTableRowData>? onOpen;

  @override
  Widget build(BuildContext context) => _AdminPremiumTable(
    minimumWidth: 1850,
    columns: const [
      DataColumn(
        label: _AdminColumnLabel(icon: Icons.tag_outlined, label: 'ID'),
      ),
      DataColumn(
        label: _AdminColumnLabel(
          icon: Icons.person_outline,
          label: 'Payer name',
        ),
      ),
      DataColumn(
        label: _AdminColumnLabel(
          icon: Icons.phone_outlined,
          label: 'Payer last 3',
        ),
      ),
      DataColumn(
        label: _AdminColumnLabel(
          icon: Icons.phone_android_outlined,
          label: 'Payee MoMo',
        ),
      ),
      DataColumn(
        label: _AdminColumnLabel(
          icon: Icons.receipt_long_outlined,
          label: 'MoMo transaction',
        ),
      ),
      DataColumn(
        numeric: true,
        label: _AdminColumnLabel(
          icon: Icons.payments_outlined,
          label: 'Amount',
        ),
      ),
      DataColumn(
        numeric: true,
        label: _AdminColumnLabel(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Wallet balance',
        ),
      ),
      DataColumn(
        label: _AdminColumnLabel(
          icon: Icons.cell_tower_outlined,
          label: 'Network',
        ),
      ),
      DataColumn(
        label: _AdminColumnLabel(
          icon: Icons.swap_horiz_outlined,
          label: 'Direction',
        ),
      ),
      DataColumn(
        label: _AdminColumnLabel(
          icon: Icons.schedule_outlined,
          label: 'MoMo time',
        ),
      ),
      DataColumn(
        label: _AdminColumnLabel(
          icon: Icons.fact_check_outlined,
          label: 'Verification',
        ),
      ),
      DataColumn(
        label: _AdminColumnLabel(
          icon: Icons.account_tree_outlined,
          label: 'Allocation',
        ),
      ),
      DataColumn(
        label: _AdminColumnLabel(
          icon: Icons.account_balance_outlined,
          label: 'Ledger',
        ),
      ),
      DataColumn(
        label: _AdminColumnLabel(
          icon: Icons.notifications_outlined,
          label: 'Notification',
        ),
      ),
      DataColumn(
        label: _AdminColumnLabel(
          icon: Icons.sms_outlined,
          label: 'Receipt sender',
        ),
      ),
      DataColumn(
        label: _AdminColumnLabel(
          icon: Icons.event_note_outlined,
          label: 'Recorded at',
        ),
      ),
      DataColumn(
        label: _AdminColumnLabel(
          icon: Icons.open_in_new_outlined,
          label: 'Open',
        ),
      ),
    ],
    rows: [
      for (final row in rows)
        DataRow(
          onSelectChanged: onOpen == null ? null : (_) => onOpen!(row),
          cells: [
            DataCell(_AdminFullTableValue(_transactionReference(row))),
            DataCell(_AdminFullTableValue(_extraText(row, 'payer_name'))),
            DataCell(_AdminFullTableValue(_extraText(row, 'payer_last_three'))),
            DataCell(
              _AdminFullTableValue(
                _extraText(row, 'payee_momo_number_or_code'),
              ),
            ),
            DataCell(
              _AdminFullTableValue(_extraText(row, 'momo_transaction_id')),
            ),
            DataCell(
              _AdminFullTableValue(
                _transactionDisplayAmount(row),
                alignEnd: true,
              ),
            ),
            DataCell(
              _AdminFullTableValue(
                _transactionWalletBalance(row),
                alignEnd: true,
              ),
            ),
            DataCell(_AdminFullTableValue(_extraText(row, 'momo_network'))),
            DataCell(_AdminFullTableValue(_extraText(row, 'momo_direction'))),
            DataCell(_AdminDateTimeValue(_extraDate(row, 'momo_occurred_at'))),
            DataCell(
              AdminStatusChip(
                label: AdminTransactionLifecycle.label(
                  AdminTransactionLifecycle.parse(
                    row.extra['lifecycle'],
                  )?.verification,
                ),
              ),
            ),
            DataCell(
              AdminStatusChip(label: _transactionAllocationDisplay(row)),
            ),
            DataCell(
              AdminStatusChip(
                label: AdminTransactionLifecycle.label(
                  AdminTransactionLifecycle.parse(
                    row.extra['lifecycle'],
                  )?.ledger,
                ),
              ),
            ),
            DataCell(
              AdminStatusChip(
                label: AdminTransactionLifecycle.label(
                  AdminTransactionLifecycle.parse(
                    row.extra['lifecycle'],
                  )?.notification,
                ),
              ),
            ),
            DataCell(_AdminFullTableValue(_momoSender(row))),
            DataCell(_AdminDateTimeValue(row.createdAt)),
            DataCell(_AdminOpenButton(row: row, onOpen: onOpen)),
          ],
        ),
    ],
  );
}

class _AdminGroupTable extends StatelessWidget {
  const _AdminGroupTable({required this.rows, required this.onOpen});

  final List<AdminTableRowData> rows;
  final ValueChanged<AdminTableRowData>? onOpen;

  @override
  Widget build(BuildContext context) => _AdminPremiumTable(
    minimumWidth: 1160,
    columns: const [
      DataColumn(
        label: _AdminColumnLabel(icon: Icons.folder_outlined, label: 'Group'),
      ),
      DataColumn(
        label: _AdminColumnLabel(
          icon: Icons.visibility_outlined,
          label: 'Visibility',
        ),
      ),
      DataColumn(
        label: _AdminColumnLabel(
          icon: Icons.groups_2_outlined,
          label: 'Purpose',
        ),
      ),
      DataColumn(
        numeric: true,
        label: _AdminColumnLabel(icon: Icons.groups_outlined, label: 'Members'),
      ),
      DataColumn(
        label: _AdminColumnLabel(
          icon: Icons.location_on_outlined,
          label: 'Payee',
        ),
      ),
      DataColumn(
        label: _AdminColumnLabel(
          icon: Icons.toggle_on_outlined,
          label: 'Status',
        ),
      ),
      DataColumn(
        label: _AdminColumnLabel(
          icon: Icons.calendar_today_outlined,
          label: 'Created',
        ),
      ),
      DataColumn(
        label: _AdminColumnLabel(
          icon: Icons.open_in_new_outlined,
          label: 'Open',
        ),
      ),
    ],
    rows: [
      for (final row in rows)
        DataRow(
          cells: [
            DataCell(_AdminFullTableValue(row.title)),
            DataCell(_AdminAccessLabel(row: row)),
            DataCell(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_groupPurposeIcon(row), size: 18),
                  const SizedBox(width: 7),
                  _AdminFullTableValue(_groupPurpose(row)),
                ],
              ),
            ),
            DataCell(
              _AdminFullTableValue(
                '${_groupMemberCount(row) ?? '—'}',
                alignEnd: true,
              ),
            ),
            DataCell(_AdminFullTableValue(_extraText(row, 'receiver_label'))),
            DataCell(
              AdminStatusChip(
                label: _isArchivedGroup(row) ? 'archived' : 'active',
              ),
            ),
            DataCell(_AdminDateTimeValue(row.createdAt, dateOnly: true)),
            DataCell(_AdminOpenButton(row: row, onOpen: onOpen)),
          ],
        ),
    ],
  );
}

class _AdminMemberTable extends StatelessWidget {
  const _AdminMemberTable({
    required this.rows,
    required this.onOpen,
    required this.scopeLabel,
  });

  final List<AdminTableRowData> rows;
  final ValueChanged<AdminTableRowData>? onOpen;
  final String scopeLabel;

  @override
  Widget build(BuildContext context) {
    final showGroups = scopeLabel == 'Members';
    return _AdminPremiumTable(
      minimumWidth: showGroups ? 900 : 1350,
      columns: [
        const DataColumn(
          numeric: true,
          label: _AdminColumnLabel(
            icon: Icons.badge_outlined,
            label: 'Collect ID',
          ),
        ),
        const DataColumn(
          label: _AdminColumnLabel(icon: Icons.badge_outlined, label: 'Type'),
        ),
        const DataColumn(
          label: _AdminColumnLabel(icon: Icons.person_outline, label: 'Name'),
        ),
        if (showGroups)
          const DataColumn(
            label: _AdminColumnLabel(
              icon: Icons.account_circle_outlined,
              label: 'Account',
            ),
          ),
        if (!showGroups)
          const DataColumn(
            label: _AdminColumnLabel(
              icon: Icons.email_outlined,
              label: 'Email',
            ),
          ),
        const DataColumn(
          label: _AdminColumnLabel.brand(
            brandIcon: FontAwesomeIcons.whatsapp,
            label: 'WhatsApp',
          ),
        ),
        const DataColumn(
          label: _AdminColumnLabel(
            icon: Icons.phone_android_outlined,
            label: 'MoMo number',
          ),
        ),
        const DataColumn(
          label: _AdminColumnLabel(
            icon: Icons.dialpad_outlined,
            label: 'MoMo code',
          ),
        ),
        if (showGroups)
          const DataColumn(
            numeric: true,
            label: _AdminColumnLabel(
              icon: Icons.groups_outlined,
              label: 'Groups',
            ),
          ),
        DataColumn(
          label: _AdminColumnLabel(
            icon: Icons.update_outlined,
            label: showGroups ? 'Updated' : 'Created',
          ),
        ),
        const DataColumn(
          label: _AdminColumnLabel(
            icon: Icons.open_in_new_outlined,
            label: 'Open',
          ),
        ),
      ],
      rows: [
        for (final row in rows)
          DataRow(
            cells: [
              DataCell(_AdminFullTableValue(_extraText(row, 'public_id'))),
              DataCell(
                _AdminFullTableValue(
                  _extraText(row, showGroups ? 'member_type' : 'user_type'),
                ),
              ),
              DataCell(_AdminFullTableValue(_extraText(row, 'display_name'))),
              if (showGroups)
                DataCell(_AdminFullTableValue(_memberAccountLabel(row))),
              if (!showGroups)
                DataCell(_AdminFullTableValue(_extraText(row, 'email'))),
              DataCell(_AdminFullTableValue(_extraText(row, 'whatsapp_phone'))),
              DataCell(_AdminFullTableValue(_extraText(row, 'momo_number'))),
              DataCell(_AdminFullTableValue(_extraText(row, 'momo_pay_code'))),
              if (showGroups)
                DataCell(
                  _AdminFullTableValue(
                    '${_extraInt(row, 'active_groups') ?? '—'}',
                    alignEnd: true,
                  ),
                ),
              DataCell(
                _AdminDateTimeValue(
                  showGroups
                      ? _extraDate(row, 'updated_at') ?? row.createdAt
                      : row.createdAt,
                  dateOnly: true,
                ),
              ),
              DataCell(
                _AdminOpenButton(
                  row: row,
                  onOpen: onOpen,
                  label: showGroups
                      ? 'Open member record ${row.title}'
                      : 'Open user account',
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// Horizontal tables size cells to their stored values, including enlarged text.
class _AdminFullTableValue extends StatelessWidget {
  const _AdminFullTableValue(this.value, {this.alignEnd = false});

  final String value;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) => Text(
    value.isEmpty ? '—' : value,
    softWrap: false,
    textAlign: alignEnd ? TextAlign.end : TextAlign.start,
  );
}
