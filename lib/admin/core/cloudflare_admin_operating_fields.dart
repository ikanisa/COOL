part of 'cloudflare_admin_operating_pages.dart';

String _recordTitle(CloudflareOperatingDetail detail) =>
    (detail.resource['title'] ??
            detail.resource['display_name'] ??
            detail.resource['label'] ??
            detail.resource['name'] ??
            detail.resource['transaction_reference'] ??
            detail.resource['provider_reference'] ??
            detail.resource['description'] ??
            'Record')
        .toString();

List<String> _fieldsForResource(String type) => switch (type) {
  'groups' => [
    'title',
    'slug',
    'description',
    'collection_type',
    'category_subtype',
    'purpose_label',
    'status',
    'visibility',
    'is_platform_sponsored',
    'recurring_cadence',
    'suggested_amount_rwf',
    'created_at',
    'updated_at',
  ],
  'users' => [
    'display_name',
    'public_id',
    'email',
    'user_types',
    'member_type',
    'whatsapp_number',
    'momo_number',
    'momo_pay_code',
    'total_contributed_rwf',
    'posted_contributed_rwf',
    'active_groups',
    'status',
    'created_at',
    'updated_at',
  ],
  'payees' => [
    'label',
    'group_id',
    'group_title',
    'network',
    'momo_number_or_code',
    'momo_masked',
    'status',
    'creation_reason',
    'created_at',
  ],
  'transactions' => [
    'transaction_reference',
    'verification_status',
    'amount_rwf',
    'allocated_amount_rwf',
    'payer_name',
    'payer_last3',
    'payee_momo_number_or_code',
    'momo_transaction_reference',
    'momo_timestamp_local',
    'reference_payer_last3_known',
    'reference_payee_last3_known',
    'payer_phone',
    'payer_masked_phone',
    'payee_momo_number',
    'payee_momo_code',
    'momo_timezone_offset',
    'wallet_balance_rwf',
    'source_network',
    'direction',
    'is_payment',
    'source_extraction_status',
    'source_kind',
    'source_link_basis',
    'source_review_id',
    'source_body_sha256',
    'source_payload_sha256',
    'parser_version',
    'payer_source_match_status',
    'payer_insights_status',
    'provider_reference',
    'group_id',
    'group_title',
    'payee_label',
    'network',
    'recorded_by_admin_id',
    'verified_by_admin_id',
    'observed_at',
    'created_at',
    'verified_at',
  ],
  'journals' => [
    'description',
    'group_id',
    'group_title',
    'status',
    'debit_rwf',
    'credit_rwf',
    'allocation_id',
    'transaction_id',
    'created_by_admin_id',
    'edited_by_admin_id',
    'created_at',
    'posted_at',
  ],
  'accounts' => [
    'code',
    'name',
    'group_id',
    'group_title',
    'account_type',
    'normal_side',
    'status',
    'created_at',
  ],
  _ => [],
};
List<String> _relatedFields(String type) => switch (type) {
  'memberships' => [
    'display_name',
    'public_id',
    'group_title',
    'role',
    'member_type',
    'whatsapp_number',
    'momo_number',
    'momo_pay_code',
    'total_contributed_rwf',
    'posted_contributed_rwf',
    'status',
    'version',
  ],
  'payees' => ['label', 'momo_number_or_code', 'status'],
  'accounts' => ['code', 'name', 'account_type', 'normal_side', 'status'],
  'evidence' => [
    'kind',
    'reference',
    'sha256',
    'recorded_by_admin_id',
    'recorded_at',
  ],
  'allocations' => [
    'id',
    'display_name',
    'public_id',
    'member_user_id',
    'amount_rwf',
    'created_at',
  ],
  'journals' => ['description', 'status', 'created_at'],
  'entries' => [
    'account_code',
    'account_name',
    'account_id',
    'debit_rwf',
    'credit_rwf',
    'description',
  ],
  'payer_insights' => [
    'public_id',
    'display_name',
    'member_type',
    'momo_number',
    'momo_pay_code',
    'group_title',
    'membership_role',
    'membership_status',
    'attribution_basis',
    'total_contributed_rwf',
    'posted_contributed_rwf',
    'group_total_contributed_rwf',
    'group_posted_contributed_rwf',
    'transaction_allocated_rwf',
    'attributed_transaction_count',
    'latest_transaction_reference',
    'latest_provider_reference',
    'latest_transaction_observed_at',
    'latest_transaction_verification_status',
    'name_verification',
  ],
  'reviews' => [
    'outcome',
    'evidence_id',
    'reviewed_by_admin_id',
    'reviewed_at',
    'reason',
  ],
  _ => [],
};

AdminTableColumn _operatingColumn(String key) => AdminTableColumn(
  label: switch (key) {
    'public_id' => 'User ID',
    'member_type' => 'Type',
    'user_types' => 'Roles / types',
    'display_name' => 'Name',
    'whatsapp_number' => 'WhatsApp',
    'momo_number' => 'MoMo number',
    'momo_pay_code' => 'MoMo code',
    'total_contributed_rwf' => 'Total contributed',
    'posted_contributed_rwf' => 'Posted contributions',
    _ => operatingLabel(key),
  },
  numeric: key.endsWith('_rwf'),
  selectable: true,
  value: (row) => _displayOperatingValue(key, row.extra[key]),
);

class _RecordFacts extends StatelessWidget {
  const _RecordFacts(this.record, this.fields);
  final Map<String, dynamic> record;
  final List<String> fields;
  @override
  Widget build(BuildContext context) => AdminDataTable(
    tableLabel: 'Record details',
    rows: [
      AdminTableRowData(
        id: '${record['id'] ?? 'details'}',
        title: 'Details',
        subtitle: '',
        status: '',
        amount: '',
        extra: record,
      ),
    ],
    columns: [
      for (final key in fields.where(record.containsKey)) _operatingColumn(key),
      if (record.containsKey('id'))
        AdminTableColumn(
          label: 'Record ID',
          selectable: true,
          value: (row) => '${row.extra['id']}',
        ),
    ],
  );
}

String _displayOperatingValue(String key, dynamic value) {
  if (value == null) return '—';
  if (key.endsWith('_rwf')) return adminFormatWholeAmount(value);
  if (key.endsWith('_at') && value is int) {
    return adminKigaliDateTime(
      DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true),
    );
  }
  if (value is bool) return value ? 'Yes' : 'No';
  if (value is List) {
    return value.map((item) => operatingLabel('$item')).join(', ');
  }
  if ({
    'status',
    'role',
    'kind',
    'outcome',
    'verification_status',
    'collection_type',
    'visibility',
    'network',
    'account_type',
    'normal_side',
  }.contains(key)) {
    return operatingLabel(value.toString());
  }
  return value.toString();
}

class CloudflareOperatingEditPage extends ConsumerStatefulWidget {
  const CloudflareOperatingEditPage({
    required this.type,
    required this.id,
    required this.backPath,
    super.key,
  });
  final String type, id, backPath;
  @override
  ConsumerState<CloudflareOperatingEditPage> createState() =>
      _OperatingEditState();
}

class _OperatingEditState extends ConsumerState<CloudflareOperatingEditPage> {
  late Future<CloudflareOperatingDetail> _detail;
  @override
  void initState() {
    super.initState();
    _detail = _repository(ref).operatingDetail(widget.type, widget.id);
  }

  @override
  Widget build(BuildContext context) {
    final action = switch (widget.type) {
      'groups' => CloudflareOperation.updateGroup,
      'users' => CloudflareOperation.updateUser,
      'payees' => CloudflareOperation.updatePayee,
      'journals' => CloudflareOperation.updateJournal,
      'accounts' => CloudflareOperation.updateAccount,
      _ => throw StateError('Unsupported edit route'),
    };
    return AdminPage(
      title: _actionTitle(action),
      subtitle: _actionExplanation(action),
      leading: IconButton(
        tooltip: 'Back to record',
        onPressed: () => context.go(widget.backPath),
        icon: const Icon(Icons.arrow_back),
      ),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: FutureBuilder<CloudflareOperatingDetail>(
            future: _detail,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const AdminLoadingState(
                  title: 'Loading current version',
                );
              }
              if (snapshot.hasError) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _OperatingMessage(
                      _safeOperatingError(snapshot.error!),
                      error: true,
                    ),
                    FilledButton.tonal(
                      onPressed: () => setState(
                        () => _detail = _repository(
                          ref,
                        ).operatingDetail(widget.type, widget.id),
                      ),
                      child: const Text('Refresh record'),
                    ),
                  ],
                );
              }
              final detail = snapshot.data!;
              if ((detail.type == 'groups' &&
                      detail.resource['status'] == 'archived') ||
                  (detail.type == 'users' &&
                      detail.resource['status'] == 'closed') ||
                  (detail.type == 'journals' &&
                      detail.resource['status'] == 'posted')) {
                return const _OperatingMessage(
                  'This record is permanent and cannot be edited.',
                );
              }
              return CloudflareOperatingForm(operation: action, detail: detail);
            },
          ),
        ),
      ),
    );
  }
}
