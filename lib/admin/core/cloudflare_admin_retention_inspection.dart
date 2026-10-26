import 'package:flutter/material.dart';

import '../../shared/widgets/collect_components.dart';
import '../shared/components/admin_data_table.dart';
import '../shared/components/admin_loading_state.dart';
import 'admin_auth_guard.dart';
import 'admin_models.dart';
import 'admin_privacy_review_models.dart';

Map<String, dynamic> _exact(Object? value, Set<String> fields) {
  if (value is! Map ||
      value.length != fields.length ||
      value.keys.any((key) => key is! String || !fields.contains(key))) {
    privacyReviewInvalid();
  }
  return Map<String, dynamic>.unmodifiable(value);
}

String _sha(Object? value) {
  if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    privacyReviewInvalid();
  }
  return value;
}

int _count(Object? value) {
  if (value is! int || value < 0 || value > 9007199254740991) {
    privacyReviewInvalid();
  }
  return value;
}

DateTime _utc3(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
      ).hasMatch(value)) {
    privacyReviewInvalid();
  }
  final date = DateTime.tryParse(value);
  if (date == null || !date.isUtc || date.toIso8601String() != value) {
    privacyReviewInvalid();
  }
  return date;
}

class CloudflareAdminRetentionContext {
  const CloudflareAdminRetentionContext._(
    this.sourceId,
    this.checkedAt,
    this.validUntil,
  );
  final String sourceId;
  final DateTime checkedAt, validUntil;

  static Future<CloudflareAdminRetentionContext> receive(
    Object? value,
    DateTime Function() now,
  ) async {
    if (value is! Map) privacyReviewInvalid();
    await privacyReviewAwaitServerTime(_utc3(value['checked_at']), now);
    return CloudflareAdminRetentionContext.parse(value, now());
  }

  factory CloudflareAdminRetentionContext.parse(Object? value, DateTime now) {
    final row = _exact(value, const {
      'contract_version',
      'scope',
      'source_id',
      'checked_at',
      'valid_until',
      'approval_granted',
      'erasure_completed',
    });
    if (row['contract_version'] is! int ||
        row['contract_version'] != 1 ||
        row['scope'] != 'account_retention_inspection_context' ||
        row['approval_granted'] != false ||
        row['erasure_completed'] != false) {
      privacyReviewInvalid();
    }
    final context = CloudflareAdminRetentionContext._(
      _sha(row['source_id']),
      _utc3(row['checked_at']),
      _utc3(row['valid_until']),
    );
    if (!context.validUntil.isAfter(context.checkedAt) ||
        context.validUntil.difference(context.checkedAt) >
            const Duration(minutes: 5) ||
        !context.fresh(now)) {
      privacyReviewInvalid();
    }
    return context;
  }

  bool fresh(DateTime now) =>
      !now.toUtc().isBefore(checkedAt) && now.toUtc().isBefore(validUntil);
}

/// Server-owned inventory counts and fingerprints, never rows or an erasure
/// eligibility decision. Table membership is not guessed from client schema.
class CloudflareAdminRetentionInspection {
  const CloudflareAdminRetentionInspection._({
    required this.requestId,
    required this.subjectId,
    required this.sourceId,
    required this.schemaSha256,
    required this.snapshotSha256,
    required this.tableCounts,
    required this.objectCount,
    required this.activeHoldCount,
    required this.inFlightUnresolved,
  });
  final String requestId, subjectId, sourceId, schemaSha256, snapshotSha256;
  final Map<String, int> tableCounts;
  final int objectCount, activeHoldCount;
  final bool inFlightUnresolved;

  factory CloudflareAdminRetentionInspection.parse(
    Object? value, {
    required String requestId,
    required String sourceId,
  }) {
    final row = _exact(value, const {
      'contract_version',
      'request_id',
      'subject_id',
      'source_id',
      'schema_sha256',
      'snapshot_sha256',
      'table_counts',
      'object_count',
      'active_hold_count',
      'in_flight_unresolved',
      'approval_granted',
      'erasure_completed',
    });
    if (row['contract_version'] is! int ||
        row['contract_version'] != 1 ||
        privacyReviewUuid(row['request_id']) != requestId ||
        _sha(row['source_id']) != sourceId ||
        row['in_flight_unresolved'] is! bool ||
        row['approval_granted'] != false ||
        row['erasure_completed'] != false) {
      privacyReviewInvalid();
    }
    final counts = row['table_counts'];
    if (counts is! Map ||
        counts.isEmpty ||
        counts.length > 512 ||
        counts.keys.any(
          (key) =>
              key is! String ||
              !RegExp(r'^[a-z][a-z0-9_]{0,62}$').hasMatch(key),
        )) {
      privacyReviewInvalid();
    }
    return CloudflareAdminRetentionInspection._(
      requestId: requestId,
      subjectId: privacyReviewUuid(row['subject_id']),
      sourceId: sourceId,
      schemaSha256: _sha(row['schema_sha256']),
      snapshotSha256: _sha(row['snapshot_sha256']),
      tableCounts: Map<String, int>.unmodifiable({
        for (final key in (counts.keys.cast<String>().toList()..sort()))
          key: _count(counts[key]),
      }),
      objectCount: _count(row['object_count']),
      activeHoldCount: _count(row['active_hold_count']),
      inFlightUnresolved: row['in_flight_unresolved'] as bool,
    );
  }
}

class CloudflareAdminRetentionInspectionApi {
  const CloudflareAdminRetentionInspectionApi({
    required this.rpc,
    required this.context,
    required this.actorId,
    required this.isCurrent,
    required this.now,
  });
  final Future<Object?> Function(String, Map<String, dynamic>) rpc;
  final CloudflareAdminRetentionContext context;
  final String actorId;
  final bool Function() isCurrent;
  final DateTime Function() now;

  void _current() {
    if (!isCurrent() || !context.fresh(now())) {
      throw const AdminSessionChanged();
    }
  }

  Future<CloudflareAdminRetentionInspection> inspect(
    AdminPrivacyReviewDetail detail,
  ) async {
    _current();
    final item = detail.item;
    if (item == null || !detail.fresh(now())) privacyReviewInvalid();
    final raw = await rpc('admin_inspect_account_retention_scope_v1', {
      'p_request_id': item.requestId,
      'p_expected_review_revision': item.revision,
      'p_expected_source_id': context.sourceId,
    });
    _current();
    final observed = CloudflareAdminRetentionInspection.parse(
      raw,
      requestId: item.requestId,
      sourceId: context.sourceId,
    );
    if (observed.subjectId == actorId) privacyReviewInvalid();
    return observed;
  }
}

class CloudflareAdminRetentionInspectionPanel extends StatefulWidget {
  const CloudflareAdminRetentionInspectionPanel({
    required this.api,
    required this.detail,
    required this.onAccessLost,
    super.key,
  });
  final CloudflareAdminRetentionInspectionApi api;
  final AdminPrivacyReviewDetail detail;
  final VoidCallback onAccessLost;

  @override
  State<CloudflareAdminRetentionInspectionPanel> createState() =>
      _InspectionPanelState();
}

class _InspectionPanelState
    extends State<CloudflareAdminRetentionInspectionPanel> {
  CloudflareAdminRetentionInspection? _observed;
  bool _loading = false, _failed = false;

  Future<void> _inspect() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
      _observed = null;
    });
    try {
      final observed = await widget.api.inspect(widget.detail);
      if (mounted) setState(() => _observed = observed);
    } on AdminSessionChanged {
      if (mounted) widget.onAccessLost();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final observed = _observed;
    return Material(
      type: MaterialType.transparency,
      child: Column(
        key: const Key('privacy-retention-inspection'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Retained information',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Inspect retained information, legal holds and unresolved work for this request. Retained records are not automatically eligible for erasure. Policy approval and deletion remain unavailable.',
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: CollectButton(
              label: 'Inspect retained scope',
              icon: Icons.policy_outlined,
              variant: CollectButtonVariant.secondary,
              onPressed: _loading ? null : _inspect,
            ),
          ),
          if (_loading)
            const AdminLoadingState(
              title: 'Inspecting retained scope',
              message: 'Reading current inventory counts and fingerprints.',
            ),
          if (_failed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Semantics(
                liveRegion: true,
                child: const Text(
                  'Current retained information could not be verified. Reload this page to refresh the review context before inspecting again.',
                ),
              ),
            ),
          if (observed != null) ...[
            const SizedBox(height: 12),
            AdminDataTable(
              key: const Key('privacy-retention-inventory-table'),
              tableLabel: 'Observed retention inventory',
              rows: [
                for (final entry in <(String, String, Object)>[
                  ('Inventory', 'Stored objects', observed.objectCount),
                  ('Inventory', 'Active legal holds', observed.activeHoldCount),
                  (
                    'Inventory',
                    'Unresolved work',
                    observed.inFlightUnresolved
                        ? 'Unresolved work is present in this scope.'
                        : 'No unresolved work was observed in this scope.',
                  ),
                  for (final entry in observed.tableCounts.entries)
                    ('Retained record counts', entry.key, entry.value),
                  ('Scope fingerprints', 'Source', observed.sourceId),
                  ('Scope fingerprints', 'Schema', observed.schemaSha256),
                  (
                    'Scope fingerprints',
                    'Scope snapshot',
                    observed.snapshotSha256,
                  ),
                ])
                  AdminTableRowData(
                    id: '${entry.$1}/${entry.$2}',
                    title: entry.$2,
                    subtitle: '',
                    status: '',
                    amount: '',
                    extra: {'category': entry.$1, 'value': entry.$3},
                  ),
              ],
              columns: [
                AdminTableColumn(
                  label: 'Category',
                  value: (row) => row.extra['category'] as String,
                  selectable: true,
                ),
                AdminTableColumn(
                  label: 'Field',
                  value: (row) => row.title,
                  selectable: true,
                ),
                AdminTableColumn(
                  label: 'Value',
                  value: (row) => '${row.extra['value']}',
                  selectable: true,
                  compare: (left, right) {
                    final a = left.extra['value'], b = right.extra['value'];
                    if (a is int && b is int) return a.compareTo(b);
                    if (a is int) return -1;
                    if (b is int) return 1;
                    return '$a'.compareTo('$b');
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
