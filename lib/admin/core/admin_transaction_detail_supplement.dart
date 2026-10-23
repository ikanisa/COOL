part of 'admin_runtime.dart';

class _AdminTransactionDetailSupplement extends ConsumerStatefulWidget {
  const _AdminTransactionDetailSupplement({
    required this.transactionId,
    required this.details,
  });

  final String transactionId;
  final AdminTransactionDetails details;

  @override
  ConsumerState<_AdminTransactionDetailSupplement> createState() =>
      _AdminTransactionDetailSupplementState();
}

class _AdminTransactionDetailSupplementState
    extends ConsumerState<_AdminTransactionDetailSupplement> {
  _AdminActionScope? _initialScope;
  AdminPayerGroupsPage? _page;
  String? _payerStatus;
  Object? _pageError;
  bool _loading = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _page = widget.details.groups;
  }

  @override
  void didUpdateWidget(covariant _AdminTransactionDetailSupplement oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transactionId != widget.transactionId ||
        !identical(oldWidget.details, widget.details)) {
      _request++;
      _initialScope = null;
      _page = widget.details.groups;
      _payerStatus = null;
      _pageError = null;
      _loading = false;
    }
  }

  Future<void> _loadGroups(int offset) async {
    if (_loading || _initialScope?.isCurrent != true) return;
    final scope = _AdminActionScope(ref);
    if (!scope.isCurrent || !scope.permissions.contains('users.read')) return;
    final request = ++_request;
    final memberId = widget.details.member?['id'];
    setState(() {
      _loading = true;
      _pageError = null;
    });
    try {
      var page = await scope.repository.transactionPayerGroups(
        widget.transactionId,
        offset: offset,
      );
      bool current() =>
          mounted &&
          request == _request &&
          scope.isCurrent &&
          _initialScope?.isCurrent == true;
      if (!current()) return;
      // A page belongs to the initially verified payer. A different member,
      // even with the same visible suffix, cannot replace that relationship.
      if (page.status == 'available' && page.memberId != memberId) {
        throw const FormatException('Payer group identity changed.');
      }
      if (page.status == 'available' && offset > 0 && page.rows.isEmpty) {
        final lastOffset = page.total == 0 ? 0 : ((page.total - 1) ~/ 10) * 10;
        page = await scope.repository.transactionPayerGroups(
          widget.transactionId,
          offset: lastOffset,
        );
        if (!current()) return;
        if (page.status == 'available' && page.memberId != memberId) {
          throw const FormatException('Payer group identity changed.');
        }
      }
      setState(() {
        _page = page;
        _payerStatus = page.status;
        _loading = false;
      });
    } catch (error) {
      if (!mounted ||
          request != _request ||
          !scope.isCurrent ||
          _initialScope?.isCurrent != true) {
        return;
      }
      setState(() {
        _pageError = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(adminAuthSessionScopeProvider);
    ref.watch(adminRepositoryProvider);
    ref.watch(_adminIdentityRevisionProvider);
    final identity = _adminResolvedIdentity(ref.watch(adminIdentityProvider));
    if (identity != null && _initialScope == null) {
      _initialScope = _AdminActionScope(ref);
    }
    final details = widget.details;
    final sms = details.sms;
    final payerStatus = _payerStatus ?? details.payerStatus;
    final canReadPayer =
        _adminHasPermission(identity, 'users.read') &&
        _initialScope?.isCurrent == true;
    final member = details.member;
    final counts = details.counts;
    String recorded(String field) => sms[field]?.toString() ?? 'Not recorded';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _AdminTransactionEvidencePanel(
          key: const ValueKey('transaction-momo-facts'),
          title: 'MoMo payment',
          fields: [
            ('Collect transaction ID', details.collectId ?? 'Unavailable'),
            if (details.collectId == null)
              (
                'Transaction identity',
                _transactionIdentityMessage(details.identityStatus),
              ),
            ('MoMo transaction', recorded('provider_transaction_id')),
            (
              'MoMo timestamp',
              _transactionEvidenceTime(sms['provider_occurred_at']),
            ),
            ('Payer name', recorded('payer_name')),
            ('Payer last three digits', recorded('payer_last_three')),
            ('Payee MoMo number / code', recorded('payee_momo_number_or_code')),
            ('Amount', _transactionEvidenceAmount(sms['amount_rwf'])),
            (
              'Wallet balance',
              _transactionEvidenceAmount(sms['wallet_balance_rwf']),
            ),
            ('Network', recorded('network')),
            ('Direction', recorded('direction')),
            (
              'Status',
              sms['allocation_status'] == 'allocated'
                  ? 'Allocated'
                  : 'Unallocated',
            ),
          ],
        ),
        const SizedBox(height: 16),
        _AdminTransactionEvidencePanel(
          title: 'Payer insights',
          fields: payerStatus == 'available' && canReadPayer
              ? [
                  (
                    'Registered MoMo name',
                    member!['momo_registered_name']?.toString() ??
                        'Not recorded',
                  ),
                  ('Member type', member['member_type'].toString()),
                  (
                    'User ID',
                    member['collect_id']?.toString() ?? 'Not recorded',
                  ),
                  (
                    'MoMo number',
                    member['momo_number']?.toString() ?? 'Not recorded',
                  ),
                  (
                    'MoMo code',
                    member['momo_pay_code']?.toString() ?? 'Not recorded',
                  ),
                  if (member['member_type'] == 'App')
                    (
                      'WhatsApp number',
                      member['whatsapp_phone']?.toString() ?? 'Not recorded',
                    ),
                  (
                    'Total contributed',
                    member['contribution_status'] == 'available'
                        ? _transactionEvidenceAmount(
                            member['contributed_amount_rwf'],
                          )
                        : 'Unavailable',
                  ),
                  ('Transactions', counts!['total'].toString()),
                  ('Allocated transactions', counts['allocated'].toString()),
                  (
                    'Unallocated transactions',
                    counts['unallocated'].toString(),
                  ),
                ]
              : const [],
          child: payerStatus == 'available' && canReadPayer
              ? _groups(context, identity)
              : Text(
                  !canReadPayer || payerStatus == 'not_authorized'
                      ? 'Payer insights require current access to users. Refresh this transaction after access changes.'
                      : 'No verified member identity is linked to this payer. A phone suffix does not identify a member.',
                ),
        ),
        const SizedBox(height: 16),
        Material(
          type: MaterialType.transparency,
          child: ExpansionTile(
            key: const ValueKey('transaction-source-evidence'),
            title: const Text('Receipt and device evidence'),
            tilePadding: const EdgeInsets.symmetric(vertical: 4),
            childrenPadding: const EdgeInsets.only(bottom: 20),
            expandedAlignment: Alignment.centerLeft,
            children: [
              _AdminTransactionEvidenceFields(
                fields: [
                  ('Currency', recorded('currency')),
                  ('Parse status', recorded('parse_status')),
                  ('Parser model', recorded('parser_model')),
                  ('Parser schema', recorded('parser_schema_version')),
                  ('Parser confidence', recorded('confidence')),
                  ('SMS record', recorded('raw_sms_id')),
                  ('Parsed event', recorded('event_id')),
                  ('Payment record', recorded('payment_id')),
                  (
                    'Received on device',
                    _transactionEvidenceTime(sms['received_at_device']),
                  ),
                  ('Ingested', _transactionEvidenceTime(sms['ingested_at'])),
                  (
                    'SMS record created',
                    _transactionEvidenceTime(sms['raw_created_at']),
                  ),
                  ('Parsed', _transactionEvidenceTime(sms['parsed_at'])),
                  ('Message digest', recorded('body_sha256')),
                  ('Client envelope', recorded('client_envelope_id')),
                  (
                    'Native action capability',
                    recorded('native_action_capability_id'),
                  ),
                  (
                    'Attestation request digest',
                    recorded('attestation_request_sha256'),
                  ),
                  (
                    'Device attested',
                    _transactionEvidenceTime(sms['device_attested_at']),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _groups(BuildContext context, AdminIdentity? identity) {
    final page = _page!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text(
          'Group relationships (${page.total})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        if (_pageError != null)
          AdminSafeErrorPanel(
            error: _pageError!,
            onRetry: () => _loadGroups(page.offset),
          )
        else if (page.total == 0)
          const Text('No group relationships recorded')
        else
          _AdminPremiumTable(
            minimumWidth: 960,
            columns: const [
              DataColumn(
                label: _AdminColumnLabel(
                  icon: Icons.folder_outlined,
                  label: 'Group',
                ),
              ),
              DataColumn(
                label: _AdminColumnLabel(
                  icon: Icons.person_outline,
                  label: 'Roles',
                ),
              ),
              DataColumn(
                label: _AdminColumnLabel(
                  icon: Icons.group_outlined,
                  label: 'Membership states',
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
              for (final group in page.rows)
                DataRow(
                  cells: [
                    DataCell(Text(group.title, softWrap: false)),
                    DataCell(
                      Text(
                        group.roles.map(_humanizeDetailValue).join(', '),
                        softWrap: false,
                      ),
                    ),
                    DataCell(
                      Text(
                        group.membershipStatuses.isEmpty
                            ? 'Not recorded'
                            : group.membershipStatuses
                                  .map(_humanizeDetailValue)
                                  .join(', '),
                        softWrap: false,
                      ),
                    ),
                    DataCell(
                      IconButton.filledTonal(
                        tooltip: 'Open ${group.title}',
                        onPressed:
                            _adminHasPermission(identity, 'collections.read')
                            ? () => context.go('/admin/groups/${group.id}')
                            : null,
                        icon: const Icon(Icons.arrow_outward, size: 18),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        if (_loading) const LinearProgressIndicator(),
        if (page.total > 0) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${page.offset + 1}–${page.offset + page.rows.length} of ${page.total} groups',
              ),
              IconButton.outlined(
                key: const ValueKey('payer-groups-previous'),
                tooltip: 'Previous payer groups',
                onPressed: _loading || page.offset == 0
                    ? null
                    : () =>
                          _loadGroups((page.offset - 10).clamp(0, page.offset)),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton.outlined(
                key: const ValueKey('payer-groups-next'),
                tooltip: 'Next payer groups',
                onPressed:
                    _loading ||
                        page.offset + page.rows.length >= page.total ||
                        page.offset > 2147483637
                    ? null
                    : () => _loadGroups(page.offset + 10),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

String _transactionIdentityMessage(String status) => switch (status) {
  'missing_payer_identity' => 'Payer identity is not recorded',
  'missing_payee_identity' => 'Payee identity is not recorded',
  'missing_payer_and_payee_identity' =>
    'Payer and payee identities are not recorded',
  'raw_missing' => 'Source receipt is unavailable',
  'not_rwanda_scope' => 'Source receipt is outside the supported scope',
  _ => 'Unavailable',
};

String _transactionEvidenceTime(Object? value) => value == null
    ? 'Not recorded'
    : adminKigaliDateTime(DateTime.parse(value as String));

String _transactionEvidenceAmount(Object? value) {
  if (value == null) return 'Not recorded';
  final parts = value.toString().split('.');
  final sign = parts.first.startsWith('-') ? '-' : '';
  final digits = sign.isEmpty ? parts.first : parts.first.substring(1);
  final result = StringBuffer(sign);
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) result.write(',');
    result.write(digits[index]);
  }
  if (parts.length == 2) result.write('.${parts[1]}');
  return result.toString();
}

class _AdminTransactionEvidencePanel extends StatelessWidget {
  const _AdminTransactionEvidencePanel({
    required this.title,
    required this.fields,
    this.child,
    super.key,
  });

  final String title;
  final List<(String, String)> fields;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      if (fields.isNotEmpty) ...[
        const SizedBox(height: 16),
        AdminRecordFactsTable(fields: fields, semanticLabel: '$title facts'),
      ],
      if (child != null) ...[const SizedBox(height: 12), child!],
    ],
  );
}

class _AdminTransactionEvidenceFields extends StatelessWidget {
  const _AdminTransactionEvidenceFields({required this.fields});
  final List<(String, String)> fields;

  @override
  Widget build(BuildContext context) => AdminRecordFactsTable(
    fields: fields,
    semanticLabel: 'Receipt and device evidence facts',
  );
}
