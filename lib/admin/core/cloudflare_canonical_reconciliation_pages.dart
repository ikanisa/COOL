import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/collect_motion.dart';
import '../../app/theme/collect_colors.dart';
import '../shared/components/admin_data_table.dart';
import '../shared/components/admin_empty_state.dart';
import '../shared/components/admin_loading_state.dart';
import '../shared/components/admin_page.dart';
import 'admin_account_api.dart';
import 'admin_auth_guard.dart';
import 'admin_display_formatters.dart';
import 'admin_pending_attempt_store.dart';
import 'admin_repository_base.dart'
    show
        AdminTableRowData,
        adminClockProvider,
        adminLastSuccessfulRefreshProvider,
        adminRealtimeTickProvider;
import 'cloudflare_admin_reconciliation_api.dart'
    show ReconciliationMember, ReconciliationPage, ReconciliationReceipt;
import 'cloudflare_admin_session.dart';
import 'cloudflare_canonical_reconciliation_api.dart';

part 'cloudflare_canonical_reconciliation_detail.dart';
part 'cloudflare_canonical_member_form.dart';
part 'cloudflare_canonical_reconciliation_dialogs.dart';
part 'cloudflare_canonical_reconciliation_records.dart';

final canonicalReconciliationApiProvider = Provider<CanonicalReconciliationApi>(
  (ref) {
    ref.watch(
      cloudflareAdminSessionProvider.select(
        (state) => state.asData?.value?.authorityKey,
      ),
    );
    return CanonicalReconciliationApi(
      ref.read(cloudflareAdminSessionProvider.notifier),
      pendingStore: ref.read(adminPendingAttemptStoreProvider),
    );
  },
);

typedef _QueueQuery = ({String search, String status, int offset});
final _queue = FutureProvider.autoDispose
    .family<ReconciliationPage<Map<String, dynamic>>, _QueueQuery>((
      ref,
      query,
    ) async {
      ref.watch(adminRealtimeTickProvider);
      final authority = ref.watch(
        cloudflareAdminSessionProvider.select(
          (state) => state.asData?.value?.authorityKey,
        ),
      );
      if (authority == null) throw const AdminSessionChanged();
      var current = true;
      ref.onDispose(() => current = false);
      final page = await ref
          .watch(canonicalReconciliationApiProvider)
          .queue(
            search: query.search,
            status: query.status,
            offset: query.offset,
          );
      if (!current ||
          ref
                  .read(cloudflareAdminSessionProvider)
                  .asData
                  ?.value
                  ?.authorityKey !=
              authority) {
        throw const AdminSessionChanged();
      }
      ref.read(adminLastSuccessfulRefreshProvider.notifier).state = ref.read(
        adminClockProvider,
      )();
      return page;
    });

String _safeError(Object error) => error is AdminAccountException
    ? error.message
    : error is FormatException
    ? 'The records could not be verified. Refresh before continuing.'
    : 'The service could not be reached. Try again.';
String _label(String key) => key
    .split('_')
    .map(
      (part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}',
    )
    .join(' ');
String _value(String key, Object? value) {
  if (value == null) return '—';
  if (key.endsWith('_rwf')) return adminFormatWholeAmount(value);
  if (key.endsWith('_at') && value is String) {
    return adminKigaliDateTime(DateTime.tryParse(value));
  }
  if (value is bool) return value ? 'Yes' : 'No';
  if (value is String &&
      {'status', 'evidence_level', 'settlement_status'}.contains(key)) {
    return _label(value);
  }
  return value is Map ? jsonEncode(value) : '$value';
}

class _Note extends StatelessWidget {
  const _Note(this.text, {this.error = false});
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: error ? Theme.of(context).colorScheme.error : null,
        ),
      ),
    ),
  );
}

Widget _records(
  String title,
  List<Map<String, dynamic>> records,
  Map<String, String> columns, {
  void Function(Map<String, dynamic>)? onOpen,
  Widget Function(Map<String, dynamic>)? trailing,
}) => AdminDataTable(
  tableLabel: title,
  rows: [
    for (final row in records)
      AdminTableRowData(
        id: '${row['id'] ?? row['request_id']}',
        title: '',
        subtitle: '',
        status: '',
        amount: '',
        extra: row,
      ),
  ],
  columns: [
    for (final entry in columns.entries)
      AdminTableColumn(
        label: entry.value,
        numeric: entry.key.endsWith('_rwf'),
        selectable: true,
        value: (row) => _value(entry.key, row.extra[entry.key]),
      ),
  ],
  onOpen: onOpen == null ? null : (row) => onOpen(row.extra),
  trailingBuilder: trailing == null ? null : (row) => trailing(row.extra),
);

Widget _pager<T>(
  ReconciliationPage<T> page,
  bool busy,
  void Function(int) go,
) => Wrap(
  spacing: 12,
  crossAxisAlignment: WrapCrossAlignment.center,
  children: [
    Text(
      page.total == 0
          ? '0 records'
          : '${page.rows.isEmpty ? 0 : page.offset + 1}–${page.offset + page.rows.length} of ${page.total}',
    ),
    TextButton(
      onPressed: busy || page.offset == 0
          ? null
          : () => go((page.offset - page.limit).clamp(0, page.total)),
      child: const Text('Previous'),
    ),
    TextButton(
      onPressed: busy || page.nextOffset == null
          ? null
          : () => go(page.nextOffset!),
      child: const Text('Next'),
    ),
  ],
);

bool _fresh(CloudflareAdminUser? user) =>
    user?.hasRecentSensitiveVerification() == true;

class CanonicalReconciliationQueuePage extends ConsumerStatefulWidget {
  const CanonicalReconciliationQueuePage({super.key});
  @override
  ConsumerState<CanonicalReconciliationQueuePage> createState() =>
      _QueueState();
}

class _QueueState extends ConsumerState<CanonicalReconciliationQueuePage> {
  final _search = TextEditingController();
  String _applied = '', _status = '';
  int _offset = 0;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = (search: _applied, status: _status, offset: _offset),
        result = ref.watch(_queue(query));
    void open(Map<String, dynamic> row) =>
        context.go('/admin/reconciliations/${row['id']}');
    return AdminPage(
      title: 'Payment reconciliation',
      subtitle:
          'Review retained payment evidence and member attribution. Provider settlement is not verified.',
      trailing: IconButton(
        tooltip: 'Refresh payment evidence',
        onPressed: () => ref.invalidate(_queue(query)),
        icon: const Icon(Icons.refresh),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final enlarged = MediaQuery.textScalerOf(context).scale(16) > 21;
              final stacked = constraints.maxWidth < 680 || enlarged;
              final searchWidth = stacked
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 292).clamp(280.0, 560.0);
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: searchWidth,
                    child: TextField(
                      controller: _search,
                      maxLength: 200,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        labelText: 'Search payment evidence',
                        hintText: 'Reference, group or recorded payer',
                        counterText: '',
                        prefixIcon: const Icon(Icons.search_rounded, size: 28),
                        suffixIcon: IconButton(
                          tooltip: 'Apply evidence search',
                          icon: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 28,
                          ),
                          onPressed: () => setState(() {
                            _applied = _search.text.trim();
                            _offset = 0;
                          }),
                        ),
                      ),
                      onSubmitted: (value) => setState(() {
                        _applied = value.trim();
                        _offset = 0;
                      }),
                    ),
                  ),
                  Semantics(
                    child: PopupMenuButton<String>(
                      tooltip: 'Evidence status',
                      initialValue: _status,
                      onSelected: (value) => setState(() {
                        _status = value;
                        _offset = 0;
                      }),
                      itemBuilder: (context) => [
                        for (final status in const [
                          '',
                          'recorded',
                          'ambiguous',
                          'reconciled',
                          'reversed',
                          'corrected',
                          'confirmed',
                        ])
                          CheckedPopupMenuItem(
                            value: status,
                            checked: status == _status,
                            child: Text(
                              status.isEmpty
                                  ? 'All recorded states'
                                  : _label(status),
                            ),
                          ),
                      ],
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: context.collectColors.surfaceReadable,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.filter_list_rounded, size: 28),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  _status.isEmpty
                                      ? 'All recorded states'
                                      : _label(_status),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.expand_more_rounded, size: 24),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          result.when(
            loading: () =>
                const AdminLoadingState(title: 'Loading payment evidence'),
            error: (error, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Note(_safeError(error), error: true),
                TextButton(
                  onPressed: () => ref.invalidate(_queue(query)),
                  child: const Text('Try again'),
                ),
              ],
            ),
            data: (page) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (page.rows.isEmpty)
                  const AdminEmptyState(
                    title: 'No matching evidence',
                    message:
                        'Retained payment evidence will appear here. Try another search or status if you expected a record.',
                  )
                else
                  _records(
                    'Payment evidence',
                    page.rows,
                    const {
                      'provider_reference': 'Evidence reference',
                      'group_name': 'Group',
                      'amount_rwf': 'Recorded amount (RWF)',
                      'status': 'Evidence status',
                      'evidence_level': 'Evidence basis',
                      'allocated_amount_rwf': 'Recorded contribution (RWF)',
                      'observed_at': 'Observed',
                      'settlement_status': 'Provider settlement',
                    },
                    trailing: (row) => TextButton.icon(
                      onPressed: () => open(row),
                      icon: const Icon(Icons.arrow_outward_rounded, size: 26),
                      label: const Text('Review'),
                    ),
                  ),
                _pager(
                  page,
                  false,
                  (offset) => setState(() => _offset = offset),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
