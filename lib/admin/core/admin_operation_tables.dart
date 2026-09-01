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
        const DataColumn(
          label: _AdminColumnLabel.brand(
            brandIcon: FontAwesomeIcons.whatsapp,
            label: 'WhatsApp',
            iconOnly: true,
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
                _AdminSingleValue(
                  _extraText(row, 'whatsapp_masked', fallback: row.subtitle),
                  maxWidth: 130,
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
                  label: 'Open $accountLabel account',
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
    final accountLabel = scopeLabel == 'Members' ? 'member' : 'user';
    return _AdminOperationsCardList(
      children: [
        for (final row in rows)
          _AdminOperationsCard(
            leading: const FaIcon(FontAwesomeIcons.whatsapp, size: 18),
            title: _extraText(row, 'whatsapp_masked', fallback: row.subtitle),
            subtitle: '',
            iconOnlyFields: true,
            status: row.status == 'admin' ? row.status : '',
            onOpen: onOpen == null ? null : () => onOpen!(row),
            openLabel: 'Open $accountLabel account',
            fields: [
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

class _AdminPremiumTable extends StatelessWidget {
  const _AdminPremiumTable({
    required this.minimumWidth,
    required this.columns,
    required this.rows,
  });

  final double minimumWidth;
  final List<DataColumn> columns;
  final List<DataRow> rows;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceReadable,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.borderSoft),
        boxShadow: [
          BoxShadow(
            color: CollectColors.publicBlack.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Scrollbar(
              scrollbarOrientation: ScrollbarOrientation.bottom,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: math.max(minimumWidth, constraints.maxWidth),
                  ),
                  child: DataTable(
                    headingRowColor: WidgetStatePropertyAll(
                      colors.surfaceRaised.withValues(alpha: 0.82),
                    ),
                    headingTextStyle: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(
                          color: colors.textSecondary,
                          fontWeight: CollectTypography.weightBold,
                        ),
                    dataTextStyle: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: CollectTypography.weightSemibold,
                        ),
                    dividerThickness: 0.7,
                    headingRowHeight: 48 + ((textScale - 1) * 20),
                    dataRowMinHeight: 64 + ((textScale - 1) * 36),
                    dataRowMaxHeight: 78 + ((textScale - 1) * 44),
                    horizontalMargin: 18,
                    columnSpacing: 20,
                    columns: columns,
                    rows: rows,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AdminColumnLabel extends StatelessWidget {
  const _AdminColumnLabel({
    required this.icon,
    required this.label,
    this.iconOnly = true,
  }) : brandIcon = null;

  const _AdminColumnLabel.brand({
    required this.brandIcon,
    required this.label,
    this.iconOnly = true,
  }) : icon = null;

  final IconData? icon;
  final FaIconData? brandIcon;
  final String label;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (brandIcon != null)
              FaIcon(brandIcon!, size: 17, color: colors.textSecondary)
            else
              Icon(icon, size: 17, color: colors.textSecondary),
            if (!iconOnly) ...[const SizedBox(width: 6), Text(label)],
          ],
        ),
      ),
    );
  }
}

class _AdminPrimaryCell extends StatelessWidget {
  const _AdminPrimaryCell({
    required this.title,
    required this.subtitle,
    this.maxWidth = 170,
    this.subtitleIcon,
  });

  final String title;
  final String subtitle;
  final double maxWidth;
  final IconData? subtitleIcon;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: CollectTypography.weightBold,
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 3),
            if (subtitleIcon != null)
              Tooltip(
                message: subtitle,
                excludeFromSemantics: true,
                child: Semantics(
                  label: subtitle,
                  excludeSemantics: true,
                  child: Icon(
                    subtitleIcon,
                    size: 16,
                    color: colors.textSecondary,
                  ),
                ),
              )
            else
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: colors.textSecondary),
              ),
          ],
        ],
      ),
    );
  }
}

class _AdminSingleValue extends StatelessWidget {
  const _AdminSingleValue(
    this.value, {
    this.maxWidth = 150,
    this.alignEnd = false,
  });

  final String value;
  final double maxWidth;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Text(
        value.isEmpty ? '—' : value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: alignEnd ? TextAlign.end : TextAlign.start,
      ),
    );
  }
}

class _AdminDateTimeValue extends StatelessWidget {
  const _AdminDateTimeValue(this.value, {this.dateOnly = false});

  final DateTime? value;
  final bool dateOnly;

  @override
  Widget build(BuildContext context) {
    final formatted = _adminDateTime(value, dateOnly: dateOnly);
    final separator = formatted.indexOf(' · ');
    if (dateOnly || separator < 0) return Text(formatted);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(formatted.substring(0, separator)),
        Text(
          formatted.substring(separator + 3),
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    );
  }
}

class _AdminOpenButton extends StatelessWidget {
  const _AdminOpenButton({required this.row, required this.onOpen, this.label});

  final AdminTableRowData row;
  final ValueChanged<AdminTableRowData>? onOpen;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: label ?? 'Open ${row.title}',
      onPressed: onOpen == null ? null : () => onOpen!(row),
      icon: const Icon(Icons.arrow_outward, size: 18),
    );
  }
}

class _AdminRailLabel extends StatelessWidget {
  const _AdminRailLabel({required this.rail});

  final String rail;

  @override
  Widget build(BuildContext context) {
    final isMomo = rail == 'rw_momo';
    return Tooltip(
      message: isMomo
          ? 'Rwanda MoMo USSD receipt'
          : 'Diaspora account transfer',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AdminRailIcon(rail: rail),
          const SizedBox(width: 7),
          Text(isMomo ? 'MoMo' : 'Bank'),
        ],
      ),
    );
  }
}

class _AdminRailIcon extends StatelessWidget {
  const _AdminRailIcon({required this.rail});

  final String rail;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final isMomo = rail == 'rw_momo';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: (isMomo ? colors.success : colors.info).withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: SizedBox.square(
        dimension: 34,
        child: Icon(
          isMomo ? Icons.sms_outlined : Icons.account_balance_outlined,
          size: 18,
          color: isMomo ? colors.successForeground : colors.infoForeground,
        ),
      ),
    );
  }
}

class _AdminAccessLabel extends StatelessWidget {
  const _AdminAccessLabel({required this.row});

  final AdminTableRowData row;

  @override
  Widget build(BuildContext context) {
    final publicGroup = _isPublicGroup(row);
    return Tooltip(
      message: publicGroup
          ? 'Platform-sponsored public group'
          : 'Member-created private group',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            publicGroup ? Icons.public_outlined : Icons.lock_outline,
            size: 18,
          ),
          const SizedBox(width: 7),
          Text(publicGroup ? 'Public' : 'Private'),
        ],
      ),
    );
  }
}

class _AdminGroupRouteLabel extends StatelessWidget {
  const _AdminGroupRouteLabel({required this.row});

  final AdminTableRowData row;

  @override
  Widget build(BuildContext context) {
    final ready = _hasGroupPaymentRoute(row);
    return Tooltip(
      message: ready
          ? 'Rwanda MoMo USSD contribution route'
          : 'No active contribution route',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ready ? Icons.dialpad_outlined : Icons.warning_amber_outlined,
            size: 18,
          ),
          const SizedBox(width: 7),
          Text(ready ? 'MoMo USSD' : 'Missing'),
        ],
      ),
    );
  }
}

class _AdminCountryLabel extends StatelessWidget {
  const _AdminCountryLabel({required this.countryCode});

  final String countryCode;

  @override
  Widget build(BuildContext context) {
    final isRwanda = countryCode == 'RW';
    return Tooltip(
      message: isRwanda ? 'Rwanda member' : 'Diaspora member',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isRwanda ? Icons.phone_android_outlined : Icons.public_outlined,
            size: 18,
          ),
          const SizedBox(width: 7),
          Text(isRwanda ? 'RW' : countryCode),
        ],
      ),
    );
  }
}

class _AdminMemberPaymentLabel extends StatelessWidget {
  const _AdminMemberPaymentLabel({required this.row});

  final AdminTableRowData row;

  @override
  Widget build(BuildContext context) {
    final isRwanda = _country(row) == 'RW';
    final label = _memberPaymentLabel(row);
    return Tooltip(
      message: isRwanda
          ? 'Masked Rwanda MoMo profile'
          : 'Diaspora Revolut profile readiness',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isRwanda
                ? Icons.phone_android_outlined
                : Icons.account_balance_outlined,
            size: 18,
          ),
          const SizedBox(width: 7),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class _AdminOperationsSummary extends StatelessWidget {
  const _AdminOperationsSummary({
    required this.semanticLabel,
    required this.items,
  });

  final String semanticLabel;
  final List<_AdminOperationsSummaryItem> items;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      container: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceReadable.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.borderSoft),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Wrap(spacing: 10, runSpacing: 8, children: items),
          ),
        ),
      ),
    );
  }
}

class _AdminOperationsSummaryItem extends StatelessWidget {
  const _AdminOperationsSummaryItem({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        label: '$label: $value',
        excludeSemantics: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceRaised.withValues(alpha: 0.66),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: colors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: CollectTypography.weightBold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminOperationsCardList extends StatelessWidget {
  const _AdminOperationsCardList({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('admin-compact-record-list'),
      children: [
        for (var index = 0; index < children.length; index++) ...[
          children[index],
          if (index != children.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _AdminOperationsCard extends StatelessWidget {
  const _AdminOperationsCard({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.fields,
    required this.onOpen,
    required this.openLabel,
    this.subtitleIcon,
    this.iconOnlyFields = false,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final String status;
  final List<_AdminOperationsFieldData> fields;
  final VoidCallback? onOpen;
  final String openLabel;
  final IconData? subtitleIcon;
  final bool iconOnlyFields;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceReadable,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.borderSoft),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Tooltip(
                  message: title,
                  child: SizedBox.square(
                    dimension: 38,
                    child: Center(child: leading),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _AdminPrimaryCell(
                    title: title,
                    subtitle: subtitle,
                    subtitleIcon: subtitleIcon,
                    maxWidth: double.infinity,
                  ),
                ),
                const SizedBox(width: 8),
                if (status.isNotEmpty) AdminStatusChip(label: status),
                if (onOpen != null) ...[
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    tooltip: openLabel,
                    onPressed: onOpen,
                    icon: const Icon(Icons.arrow_outward, size: 18),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            Divider(height: 1, color: colors.borderSoft),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth < 420
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 12) / 2;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final field in fields)
                      SizedBox(
                        width: width,
                        child: _AdminOperationsField(
                          data: field,
                          iconOnly: iconOnlyFields,
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminOperationsFieldData {
  const _AdminOperationsFieldData(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;
}

class _AdminOperationsField extends StatelessWidget {
  const _AdminOperationsField({required this.data, this.iconOnly = false});

  final _AdminOperationsFieldData data;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final value = data.value.isEmpty ? '—' : data.value;
    return Tooltip(
      message: data.label,
      excludeFromSemantics: true,
      child: Semantics(
        label: '${data.label}: $value',
        excludeSemantics: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: iconOnly ? 1 : 0),
              child: Icon(data.icon, size: 17, color: colors.textSecondary),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: iconOnly
                  ? Text(
                      value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: CollectTypography.weightBold,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.label,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          value,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontWeight: CollectTypography.weightBold,
                              ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

String _rail(AdminTableRowData row) => _extraText(
  row,
  'rail',
  fallback: row.id.startsWith('momo:') ? 'rw_momo' : 'diaspora_account',
);

String _transactionReference(AdminTableRowData row) =>
    adminCompactTransactionReference(
      _extraText(row, 'reference', fallback: row.title),
    );

String _momoSender(AdminTableRowData row) {
  final masked = _extraText(row, 'sender_masked').trim();
  if (masked.isEmpty) return '—';
  return masked
      .replaceFirst(
        RegExp(r'^(payer|momo|phone)\s*[·•:\-]*\s*', caseSensitive: false),
        '',
      )
      .trim();
}

String _transactionDisplayAmount(AdminTableRowData row) {
  final raw = row.amount.trim();
  if (raw.isEmpty) return '—';
  if (_rail(row) == 'rw_momo') {
    final digits = raw.replaceAll(RegExp(r'[^0-9\-]'), '');
    final amount = int.tryParse(digits);
    return amount == null ? raw : formatRwf(amount);
  }
  final currency = RegExp(r'\b[A-Z]{3}\b').firstMatch(raw)?.group(0) ?? 'EUR';
  final normalized = raw.replaceAll(RegExp(r'[^0-9.\-]'), '');
  final amount = double.tryParse(normalized);
  return amount == null
      ? raw
      : formatMoneyMinor((amount * 100).round(), currency: currency);
}

String _transactionSource(AdminTableRowData row) => _extraText(
  row,
  'source_label',
  fallback: _rail(row) == 'rw_momo'
      ? 'MTN MoMo receipt'
      : 'EUR account transfer',
);

bool _isPublicGroup(AdminTableRowData row) =>
    row.status == 'public_approved' ||
    _extraBool(row, 'is_platform_sponsored') ||
    _extraText(row, 'visibility') == 'public';

bool _isArchivedGroup(AdminTableRowData row) => row.status == 'archived';

bool _hasGroupPaymentRoute(AdminTableRowData row) =>
    _extraText(row, 'receiver_label').isNotEmpty ||
    _extraText(row, 'momo_code').isNotEmpty ||
    _extraText(row, 'momo_identifier').isNotEmpty;

String _groupPurpose(AdminTableRowData row) => _extraText(
  row,
  'purpose_label',
  fallback: _extraText(row, 'collection_type', fallback: row.subtitle),
);

IconData _groupPurposeIcon(AdminTableRowData row) {
  final type = _extraText(row, 'collection_type').toLowerCase();
  final purpose = _groupPurpose(row).toLowerCase();
  if (type.contains('sport') || purpose.contains('club')) {
    return Icons.sports_soccer_outlined;
  }
  if (purpose.contains('saving') || type.contains('ikimina')) {
    return Icons.savings_outlined;
  }
  return Icons.groups_2_outlined;
}

int _groupMemberCount(AdminTableRowData row) {
  final explicit = _extraInt(row, 'active_members');
  if (explicit > 0) return explicit;
  return int.tryParse(row.amount.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
}

String _maskedReceiver(AdminTableRowData row) {
  final value = _extraText(
    row,
    'momo_identifier',
    fallback: _extraText(row, 'momo_code'),
  );
  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length <= 6) return value;
  return '${digits.substring(0, 2)}••••••${digits.substring(digits.length - 2)}';
}

String _country(AdminTableRowData row) =>
    _extraText(row, 'country_code', fallback: 'RW').toUpperCase();

String _memberPaymentLabel(AdminTableRowData row) {
  if (_country(row) == 'RW') {
    return _extraText(
      row,
      'momo_masked',
      fallback: _extraText(row, 'momo_provider', fallback: 'MoMo not set'),
    );
  }
  return _extraBool(row, 'has_revolut_profile')
      ? 'Revolut ready'
      : 'Revolut incomplete';
}

String _extraText(AdminTableRowData row, String key, {String fallback = ''}) {
  final value = row.extra[key];
  if (value == null) return fallback;
  final text = '$value'.trim();
  return text.isEmpty || text == 'null' ? fallback : text;
}

int _extraInt(AdminTableRowData row, String key) {
  final value = row.extra[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}') ?? 0;
}

bool _extraBool(AdminTableRowData row, String key) {
  final value = row.extra[key];
  return value == true || '$value'.toLowerCase() == 'true';
}

DateTime? _extraDate(AdminTableRowData row, String key) {
  final value = row.extra[key];
  if (value is DateTime) return value;
  return DateTime.tryParse('${value ?? ''}')?.toLocal();
}

String _adminDateTime(DateTime? value, {bool dateOnly = false}) {
  if (value == null) return '—';
  final local = value.toLocal();
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final date = '${local.day} ${months[local.month - 1]} ${local.year}';
  if (dateOnly) return date;
  final time =
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
  return '$date · $time';
}
