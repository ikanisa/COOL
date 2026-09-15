part of 'admin_runtime.dart';

class _AdminTransactionWorkspace extends StatelessWidget {
  const _AdminTransactionWorkspace({required this.rows, required this.onOpen});

  final List<AdminTableRowData> rows;
  final ValueChanged<AdminTableRowData>? onOpen;

  @override
  Widget build(BuildContext context) {
    final allocated = rows.where((row) => row.status == 'allocated').length;
    final review = rows.where((row) => row.status != 'allocated').length;
    final momo = rows.where((row) => _rail(row) == 'rw_momo').length;
    final bank = rows.length - momo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AdminOperationsSummary(
          semanticLabel:
              'Transaction page summary, ${rows.length} transactions, '
              '$allocated allocated, $review requiring attention, '
              '$momo Rwanda MoMo and $bank diaspora bank transfers',
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
            _AdminOperationsSummaryItem(
              icon: Icons.swap_horiz_outlined,
              value: '$momo / $bank',
              label: 'MoMo / bank',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Semantics(
          container: true,
          explicitChildNodes: true,
          label: 'Admin records table, ${rows.length} rows',
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 900) {
                return _AdminTransactionCards(rows: rows, onOpen: onOpen);
              }
              return _AdminTransactionTable(rows: rows, onOpen: onOpen);
            },
          ),
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 980) {
                return _AdminGroupCards(rows: rows, onOpen: onOpen);
              }
              return _AdminGroupTable(rows: rows, onOpen: onOpen);
            },
          ),
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
    final diaspora = rows.length - rwanda;
    final admins = rows.where((row) => row.status == 'admin').length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AdminOperationsSummary(
          semanticLabel:
              '$scopeLabel page summary, ${rows.length} ${scopeLabel.toLowerCase()}, $rwanda Rwanda, '
              '$diaspora diaspora, $admins platform admins',
          items: [
            _AdminOperationsSummaryItem(
              icon: Icons.people_outline,
              value: '${rows.length}',
              label: 'This page',
            ),
            _AdminOperationsSummaryItem(
              icon: Icons.phone_android_outlined,
              value: '$rwanda',
              label: 'Rwanda',
            ),
            _AdminOperationsSummaryItem(
              icon: Icons.public_outlined,
              value: '$diaspora',
              label: 'Diaspora',
            ),
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 920) {
                return _AdminMemberCards(
                  rows: rows,
                  onOpen: onOpen,
                  scopeLabel: scopeLabel,
                );
              }
              return _AdminMemberTable(
                rows: rows,
                onOpen: onOpen,
                scopeLabel: scopeLabel,
              );
            },
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
  Widget build(BuildContext context) {
    return _AdminPremiumTable(
      minimumWidth: 1120,
      columns: const [
        DataColumn(
          label: _AdminColumnLabel(
            icon: Icons.tag_outlined,
            label: 'Reference',
          ),
        ),
        DataColumn(
          label: _AdminColumnLabel(
            icon: Icons.swap_horiz_outlined,
            label: 'Rail',
          ),
        ),
        DataColumn(
          label: _AdminColumnLabel(
            icon: Icons.phone_android_outlined,
            label: 'MoMo number',
          ),
        ),
        DataColumn(
          label: _AdminColumnLabel(
            icon: Icons.account_tree_outlined,
            label: 'Destination',
          ),
        ),
        DataColumn(
          label: _AdminColumnLabel(
            icon: Icons.fact_check_outlined,
            label: 'Status',
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
          label: _AdminColumnLabel(
            icon: Icons.schedule_outlined,
            label: 'Received',
          ),
        ),
        DataColumn(
          label: _AdminColumnLabel(
            icon: Icons.open_in_new_outlined,
            label: 'Open',
            iconOnly: true,
          ),
        ),
      ],
      rows: [
        for (final row in rows)
          DataRow(
            cells: [
              DataCell(
                _AdminPrimaryCell(
                  title: _transactionReference(row),
                  subtitle: '',
                ),
              ),
              DataCell(_AdminRailLabel(rail: _rail(row))),
              DataCell(
                _rail(row) == 'rw_momo'
                    ? _AdminSingleValue(_momoSender(row), maxWidth: 130)
                    : const SizedBox.shrink(),
              ),
              DataCell(
                _AdminPrimaryCell(
                  title: _extraText(
                    row,
                    'group_name',
                    fallback: _extraText(
                      row,
                      'allocated_to',
                      fallback: 'Unallocated',
                    ),
                  ),
                  subtitle: _extraText(
                    row,
                    'payee_label',
                    fallback: _transactionSource(row),
                  ),
                  maxWidth: 190,
                ),
              ),
              DataCell(AdminStatusChip(label: row.status)),
              DataCell(
                _AdminSingleValue(
                  _transactionDisplayAmount(row),
                  alignEnd: true,
                ),
              ),
              DataCell(_AdminDateTimeValue(row.createdAt)),
              DataCell(_AdminOpenButton(row: row, onOpen: onOpen)),
            ],
          ),
      ],
    );
  }
}

class _AdminGroupTable extends StatelessWidget {
  const _AdminGroupTable({required this.rows, required this.onOpen});

  final List<AdminTableRowData> rows;
  final ValueChanged<AdminTableRowData>? onOpen;

  @override
  Widget build(BuildContext context) {
    return _AdminPremiumTable(
      minimumWidth: 1160,
      columns: const [
        DataColumn(
          label: _AdminColumnLabel(icon: Icons.folder_outlined, label: 'Group'),
        ),
        DataColumn(
          label: _AdminColumnLabel(
            icon: Icons.visibility_outlined,
            label: 'Access',
          ),
        ),
        DataColumn(
          label: _AdminColumnLabel(icon: Icons.badge_outlined, label: 'Owner'),
        ),
        DataColumn(
          numeric: true,
          label: _AdminColumnLabel(
            icon: Icons.groups_outlined,
            label: 'Members',
          ),
        ),
        DataColumn(
          label: _AdminColumnLabel(
            icon: Icons.dialpad_outlined,
            label: 'Route',
          ),
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
            label: 'State',
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
            label: 'Manage',
            iconOnly: true,
          ),
        ),
      ],
      rows: [
        for (final row in rows)
          DataRow(
            cells: [
              DataCell(
                _AdminPrimaryCell(
                  title: row.title,
                  subtitle: _groupPurpose(row),
                  subtitleIcon: _groupPurposeIcon(row),
                  maxWidth: 210,
                ),
              ),
              DataCell(_AdminAccessLabel(row: row)),
              DataCell(
                _isPublicGroup(row)
                    ? _AdminSingleValue(
                        _extraText(
                          row,
                          'creator_label',
                          fallback: 'Collect platform',
                        ),
                        maxWidth: 120,
                      )
                    : const SizedBox.shrink(),
              ),
              DataCell(
                _AdminSingleValue('${_groupMemberCount(row)}', alignEnd: true),
              ),
              DataCell(_AdminGroupRouteLabel(row: row)),
              DataCell(
                _AdminPrimaryCell(
                  title: _extraText(
                    row,
                    'receiver_label',
                    fallback: 'Route missing',
                  ),
                  subtitle: _maskedReceiver(row),
                  maxWidth: 150,
                ),
              ),
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
    final showAdminState = rows.any((row) => row.status == 'admin');
    final accountLabel = showGroups ? 'member' : 'user';
    return _AdminPremiumTable(
      minimumWidth: 900,
      columns: [
        DataColumn(
          label: showGroups
              ? const _AdminColumnLabel(
                  icon: Icons.badge_outlined,
                  label: 'Member',
                )
              : const _AdminColumnLabel.brand(
                  brandIcon: FontAwesomeIcons.whatsapp,
                  label: 'WhatsApp',
                  iconOnly: true,
                ),
        ),
        if (showGroups)
          const DataColumn(
            label: _AdminColumnLabel(
              icon: Icons.phone_android_outlined,
              label: 'Account / contact',
            ),
          ),
        const DataColumn(
          label: _AdminColumnLabel(
            icon: Icons.public_outlined,
            label: 'Country',
            iconOnly: true,
          ),
        ),
        const DataColumn(
          label: _AdminColumnLabel(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Payment profile',
            iconOnly: true,
          ),
        ),
        if (showGroups)
          const DataColumn(
            numeric: true,
            label: _AdminColumnLabel(
              icon: Icons.groups_outlined,
              label: 'Groups',
              iconOnly: true,
            ),
          ),
        if (showAdminState)
          const DataColumn(
            label: _AdminColumnLabel(
              icon: Icons.verified_user_outlined,
              label: 'Admin access',
            ),
          ),
        const DataColumn(
          label: _AdminColumnLabel(
            icon: Icons.update_outlined,
            label: 'Updated',
          ),
        ),
        const DataColumn(
          label: _AdminColumnLabel(
            icon: Icons.open_in_new_outlined,
            label: 'Open',
            iconOnly: true,
          ),
        ),
      ],
      rows: [
        for (final row in rows)
          DataRow(
            cells: [
              DataCell(
                showGroups
                    ? _AdminPrimaryCell(
                        title: row.title,
                        subtitle: _extraText(row, 'display_name', fallback: ''),
                        maxWidth: 200,
                      )
                    : _AdminSingleValue(
                        _extraText(
                          row,
                          'whatsapp_masked',
                          fallback: row.subtitle,
                        ),
                        maxWidth: 130,
                      ),
              ),
              if (showGroups)
                DataCell(
                  _AdminPrimaryCell(
                    title: _memberAccountLabel(row),
                    subtitle: _memberContactLabel(row),
                    maxWidth: 200,
                  ),
                ),
              DataCell(_AdminCountryLabel(countryCode: _country(row))),
              DataCell(_AdminMemberPaymentLabel(row: row)),
              if (showGroups)
                DataCell(
                  _AdminSingleValue(
                    '${_extraInt(row, 'active_groups')}',
                    alignEnd: true,
                  ),
                ),
              if (showAdminState)
                DataCell(
                  row.status == 'admin'
                      ? const AdminStatusChip(label: 'admin')
                      : const SizedBox.shrink(),
                ),
              DataCell(
                _AdminDateTimeValue(
                  _extraDate(row, 'updated_at') ?? row.createdAt,
                  dateOnly: true,
                ),
              ),
              DataCell(
                _AdminOpenButton(
                  row: row,
                  onOpen: onOpen,
                  label: showGroups
                      ? 'Open member record ${row.title}'
                      : 'Open $accountLabel account',
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _AdminTransactionCards extends StatelessWidget {
  const _AdminTransactionCards({required this.rows, required this.onOpen});

  final List<AdminTableRowData> rows;
  final ValueChanged<AdminTableRowData>? onOpen;

  @override
  Widget build(BuildContext context) {
    return _AdminOperationsCardList(
      children: [
        for (final row in rows)
          _AdminOperationsCard(
            leading: _AdminRailIcon(rail: _rail(row)),
            title: _transactionReference(row),
            subtitle: '',
            iconOnlyFields: true,
            status: row.status == 'allocated' ? '' : row.status,
            onOpen: onOpen == null ? null : () => onOpen!(row),
            openLabel: 'Open transaction ${_transactionReference(row)}',
            fields: [
              if (_rail(row) == 'rw_momo')
                _AdminOperationsFieldData(
                  Icons.phone_android_outlined,
                  'MoMo number',
                  _momoSender(row),
                ),
              _AdminOperationsFieldData(
                Icons.account_tree_outlined,
                'Destination',
                _extraText(
                  row,
                  'group_name',
                  fallback: _extraText(
                    row,
                    'allocated_to',
                    fallback: 'Unallocated',
                  ),
                ),
              ),
              _AdminOperationsFieldData(
                Icons.payments_outlined,
                'Amount',
                _transactionDisplayAmount(row),
              ),
              _AdminOperationsFieldData(
                Icons.schedule_outlined,
                'Received',
                _adminDateTime(row.createdAt),
              ),
            ],
          ),
      ],
    );
  }
}

class _AdminGroupCards extends StatelessWidget {
  const _AdminGroupCards({required this.rows, required this.onOpen});

  final List<AdminTableRowData> rows;
  final ValueChanged<AdminTableRowData>? onOpen;

  @override
  Widget build(BuildContext context) {
    return _AdminOperationsCardList(
      children: [
        for (final row in rows)
          _AdminOperationsCard(
            leading: Icon(
              _isPublicGroup(row) ? Icons.public_outlined : Icons.lock_outline,
            ),
            title: row.title,
            subtitle: _groupPurpose(row),
            subtitleIcon: _groupPurposeIcon(row),
            iconOnlyFields: true,
            status: _isArchivedGroup(row) ? 'archived' : 'active',
            onOpen: onOpen == null ? null : () => onOpen!(row),
            openLabel: 'Open ${row.title}',
            fields: [
              _AdminOperationsFieldData(
                Icons.groups_outlined,
                'Members',
                '${_groupMemberCount(row)}',
              ),
              _AdminOperationsFieldData(
                Icons.dialpad_outlined,
                'Route',
                _hasGroupPaymentRoute(row) ? 'MoMo USSD' : 'Route missing',
              ),
              _AdminOperationsFieldData(
                Icons.location_on_outlined,
                'Payee',
                _extraText(row, 'receiver_label', fallback: 'Not configured'),
              ),
            ],
          ),
      ],
    );
  }
}

class _AdminMemberCards extends StatelessWidget {
  const _AdminMemberCards({
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
    final accountLabel = showGroups ? 'member' : 'user';
    return _AdminOperationsCardList(
      children: [
        for (final row in rows)
          _AdminOperationsCard(
            leading: showGroups
                ? const Icon(Icons.badge_outlined, size: 18)
                : const FaIcon(FontAwesomeIcons.whatsapp, size: 18),
            title: showGroups
                ? row.title
                : _extraText(row, 'whatsapp_masked', fallback: row.subtitle),
            subtitle: showGroups
                ? _extraText(row, 'display_name', fallback: '')
                : '',
            iconOnlyFields: true,
            status: row.status == 'admin' ? row.status : '',
            onOpen: onOpen == null ? null : () => onOpen!(row),
            openLabel: showGroups
                ? 'Open member record ${row.title}'
                : 'Open $accountLabel account',
            fields: [
              if (showGroups) ...[
                _AdminOperationsFieldData(
                  Icons.person_outline,
                  'Account',
                  _memberAccountLabel(row),
                ),
                _AdminOperationsFieldData(
                  Icons.phone_outlined,
                  'Contact',
                  _memberContactLabel(row),
                ),
              ],
              _AdminOperationsFieldData(
                Icons.public_outlined,
                'Country',
                _country(row),
              ),
              _AdminOperationsFieldData(
                Icons.account_balance_wallet_outlined,
                'Payment',
                _memberPaymentLabel(row),
              ),
              if (scopeLabel == 'Members')
                _AdminOperationsFieldData(
                  Icons.groups_outlined,
                  'Groups',
                  '${_extraInt(row, 'active_groups')}',
                ),
            ],
          ),
      ],
    );
  }
}

String _memberAccountLabel(AdminTableRowData row) =>
    switch (_extraText(row, 'account_state', fallback: '')) {
      'feature_phone' => 'Feature phone',
      'app' => 'App account',
      'app_claimed' => 'Claimed app account',
      _ => 'Account not recorded',
    };

String _memberContactLabel(AdminTableRowData row) {
  final momo = _extraText(row, 'momo_masked', fallback: '');
  if (momo.isNotEmpty) return 'MoMo $momo';
  // Absence of a MoMo identity must not imply a WhatsApp account exists.
  final whatsapp = _extraText(row, 'whatsapp_masked', fallback: '');
  return whatsapp.isEmpty ? 'Contact not recorded' : 'WhatsApp $whatsapp';
}
