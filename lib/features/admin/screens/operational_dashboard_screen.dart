import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/money_formatters.dart';
import '../../../shared/widgets/admin_detail_scaffold.dart';
import '../../../shared/widgets/admin_workspace_kit.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../providers/admin_providers.dart';

part 'operational_dashboard_cards.dart';
part 'operational_dashboard_manual_review.dart';
part 'operational_dashboard_release_cards.dart';
part 'operational_dashboard_sender_inventory.dart';
part 'operational_dashboard_utils.dart';

EdgeInsets _operationalMetricChipPadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x3,
  right: CoolSpace.x3,
  top: CoolSpace.x2,
  bottom: CoolSpace.x2,
);

EdgeInsets _operationalBadgePadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x3,
  right: CoolSpace.x3,
  top: CoolSpace.x1,
  bottom: CoolSpace.x1,
);

const BorderRadius _operationalPillRadius = BorderRadius.all(
  Radius.circular(CoolRadii.pill),
);

class OperationalDashboardScreen extends ConsumerWidget {
  const OperationalDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final dashboardAsync = ref.watch(adminOperationalReleaseDashboardProvider);
    final triageAsync = ref.watch(adminOperationalTriageIssuesProvider);
    final momoSmsSummaryAsync = ref.watch(
      adminMomoSmsOperationalSummaryProvider,
    );
    final senderInventoryAsync = ref.watch(adminMomoSmsSenderInventoryProvider);
    final manualReviewAsync = ref.watch(adminMomoSmsManualReviewQueueProvider);
    final eventsAsync = ref.watch(adminRecentOperationalHealthEventsProvider);

    Future<void> refresh() async {
      ref.invalidate(adminOperationalReleaseDashboardProvider);
      ref.invalidate(adminOperationalTriageIssuesProvider);
      ref.invalidate(adminMomoSmsOperationalSummaryProvider);
      ref.invalidate(adminMomoSmsSenderInventoryProvider);
      ref.invalidate(adminMomoSmsManualReviewQueueProvider);
      ref.invalidate(adminRecentOperationalHealthEventsProvider);
    }

    return AdminDetailScaffold(
      backTooltip: context.l10n.back,
      onBack: () => Navigator.of(context).pop(),
      actions: [
        IconButton(
          tooltip: context.l10n.refresh,
          onPressed: refresh,
          icon: const Icon(CoolIcons.refresh),
          color: colors.primaryText,
        ),
      ],
      child: RefreshIndicator(
        color: colors.accent,
        onRefresh: refresh,
        child: ListView(
          padding: CoolSpace.scaffoldPadding,
          children: [
            const AdminPageHeader(
              eyebrow: 'OPERATIONS',
              title: 'Operations',
              subtitle:
                  'Release health, triage queues, payment telemetry, and review backlogs.',
              badges: [
                AdminStatusChip(
                  label: 'Live',
                  tone: AdminTone.success,
                  icon: CoolIcons.bolt,
                ),
              ],
            ),
            const SizedBox(height: CoolSpace.x4),
            AdminMetricStrip(
              metrics: [
                AdminMetricItem(
                  label: 'Surfaces',
                  value: _asyncCount(dashboardAsync),
                  hint: 'Monitored services',
                  icon: CoolIcons.monitorHeart,
                  tone: AdminTone.info,
                ),
                AdminMetricItem(
                  label: 'Triage',
                  value: _asyncCount(triageAsync),
                  hint: 'Open blocking issues',
                  icon: CoolIcons.priorityHigh,
                  tone: AdminTone.danger,
                ),
                AdminMetricItem(
                  label: 'Senders',
                  value: _asyncCount(senderInventoryAsync),
                  hint: 'Sender audit rows',
                  icon: CoolIcons.sms,
                  tone: AdminTone.warning,
                ),
                AdminMetricItem(
                  label: 'Manual review',
                  value: _asyncCount(manualReviewAsync),
                  hint: 'Open review items',
                  icon: CoolIcons.ruleFolder,
                  tone: AdminTone.accent,
                ),
                AdminMetricItem(
                  label: 'Events',
                  value: _asyncCount(eventsAsync),
                  hint: 'Recent health events',
                  icon: CoolIcons.timeline,
                  tone: AdminTone.success,
                ),
              ],
            ),
            const SizedBox(height: CoolSpace.x4),
            CoolAsyncView<List<Map<String, dynamic>>>(
              value: dashboardAsync,
              onRetry: refresh,
              loadingWidget: const CoolSkeletonList(itemCount: 3),
              emptyCheck: (rows) => rows.isEmpty,
              emptyWidget: const CoolEmptyView(
                message: 'No operational dashboard yet',
                icon: CoolIcons.monitorHeart,
              ),
              builder: (rows) => AdminDataTableCard(
                title: context.l10n.releaseDashboard,
                subtitle: 'Live health by monitored service.',
                emptyLabel: 'No operational dashboard yet',
                minWidth: 980,
                columns: const [
                  DataColumn(label: Text('Service')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('24h')),
                  DataColumn(label: Text('Issues')),
                  DataColumn(label: Text('Last signal')),
                  DataColumn(label: Text('Summary')),
                ],
                rows: rows
                    .map(
                      (row) => DataRow(
                        cells: [
                          DataCell(
                            Text(
                              _text(row['label']) ?? 'Surface',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          DataCell(
                            AdminStatusChip(
                              label: (_text(row['health_status']) ?? 'unknown')
                                  .toUpperCase(),
                              tone: _toneForStatus(
                                _text(row['health_status']) ?? 'unknown',
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              '${_count(row['ok_count_24h'])} ok / '
                              '${_count(row['warn_count_24h'])} warn / '
                              '${_count(row['error_count_24h'])} error',
                            ),
                          ),
                          DataCell(Text('${_count(row['issue_count'])}')),
                          DataCell(
                            Text(_formatTimestamp(row['last_signal_at'])),
                          ),
                          DataCell(
                            Text(
                              _text(row['summary']) ?? 'No summary available.',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
            const SizedBox(height: CoolSpace.x4),
            CoolAsyncView<List<Map<String, dynamic>>>(
              value: triageAsync,
              onRetry: refresh,
              loadingWidget: const CoolSkeletonList(itemCount: 3),
              emptyCheck: (rows) => rows.isEmpty,
              emptyWidget: const CoolEmptyView(
                message: 'No release-blocking operational issues',
                icon: CoolIcons.factCheck,
              ),
              builder: (rows) => AdminDataTableCard(
                title: 'Triage Queue',
                subtitle: 'Focused on failed payment and release issues.',
                emptyLabel: 'No release-blocking operational issues',
                minWidth: 1020,
                columns: const [
                  DataColumn(label: Text('Issue')),
                  DataColumn(label: Text('Severity')),
                  DataColumn(label: Text('Service')),
                  DataColumn(label: Text('Reference')),
                  DataColumn(label: Text('Last seen')),
                  DataColumn(label: Text('Detail')),
                ],
                rows: rows
                    .map(
                      (row) => DataRow(
                        cells: [
                          DataCell(
                            Text(
                              _text(row['title']) ?? 'Issue',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          DataCell(
                            AdminStatusChip(
                              label: (_text(row['severity']) ?? 'warning')
                                  .toUpperCase(),
                              tone: _toneForSeverity(
                                _text(row['severity']) ?? 'warning',
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              (_text(row['service']) ?? 'unknown').replaceAll(
                                '_',
                                ' ',
                              ),
                            ),
                          ),
                          DataCell(Text(_text(row['reference']) ?? '—')),
                          DataCell(Text(_formatTimestamp(row['last_seen_at']))),
                          DataCell(
                            Text(
                              _text(row['detail']) ?? 'No detail available.',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
            const SizedBox(height: CoolSpace.x4),
            AdminSectionCard(
              title: 'M-Money SMS',
              subtitle:
                  'Device sync audits, parser backlog, sender backlog, migration safety, reconciliation pressure, and retention backlog.',
              child: CoolAsyncView<List<Map<String, dynamic>>>(
                value: momoSmsSummaryAsync,
                onRetry: refresh,
                loadingWidget: const CoolSkeletonList(itemCount: 4),
                emptyCheck: (rows) => rows.isEmpty,
                emptyWidget: const CoolEmptyView(
                  message: 'No M-Money SMS operational summary',
                  icon: CoolIcons.sms,
                ),
                builder: (rows) => Column(
                  children: _spacedChildren(
                    rows,
                    (row) => _OperationalMetricCard(row: row),
                    spacing: CoolSpace.x2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: CoolSpace.x4),
            const AdminSectionCard(
              title: 'Sender Inventory Audit',
              subtitle: 'Unsupported or alias sender drift detected.',
              child: _SenderInventorySection(),
            ),
            const SizedBox(height: CoolSpace.x4),
            const AdminSectionCard(
              title: 'Generic Manual Review',
              subtitle: 'SMS that could not be app-linked.',
              child: _ManualReviewSection(),
            ),
            const SizedBox(height: CoolSpace.x4),
            AdminSectionCard(
              title: 'Recent Activity',
              subtitle: 'Operational health stream.',
              child: CoolAsyncView<List<Map<String, dynamic>>>(
                value: eventsAsync,
                onRetry: refresh,
                loadingWidget: const CoolSkeletonList(itemCount: 5),
                emptyCheck: (rows) => rows.isEmpty,
                emptyWidget: const CoolEmptyView(
                  message: 'No recent operational events',
                  icon: CoolIcons.historyRounded,
                ),
                builder: (rows) => Column(
                  children: _spacedChildren(
                    rows,
                    (row) => _EventListTile(row: row),
                    spacing: CoolSpace.x2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventListTile extends StatelessWidget {
  const _EventListTile({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final status = _text(row['status']) ?? 'ok';
    final functionName = _text(row['function_name']);

    return AdminActivityTile(
      title: _text(row['service']) ?? 'service',
      subtitle: _text(row['message']) ?? 'No message',
      meta: _formatTimestamp(row['occurred_at']),
      icon: CoolIcons.timeline,
      tone: _toneForStatus(status),
      badges: [
        AdminStatusChip(
          label: status.toUpperCase(),
          tone: _toneForStatus(status),
        ),
        AdminStatusChip(
          label: _text(row['component']) ?? 'general',
          tone: AdminTone.neutral,
        ),
        if (functionName != null)
          AdminStatusChip(
            label: functionName,
            tone: AdminTone.info,
            icon: CoolIcons.functions,
          ),
        if (_text(row['issue_code']) case final issueCode?)
          AdminStatusChip(label: issueCode, tone: AdminTone.warning),
      ],
    );
  }
}

String _asyncCount(AsyncValue<List<Map<String, dynamic>>> value) {
  return value.maybeWhen(data: (rows) => '${rows.length}', orElse: () => '—');
}

AdminTone _toneForStatus(String status) {
  return switch (status) {
    'healthy' || 'ok' => AdminTone.success,
    'degraded' || 'warn' || 'warning' => AdminTone.warning,
    'failing' || 'error' => AdminTone.danger,
    _ => AdminTone.neutral,
  };
}

AdminTone _toneForSeverity(String severity) {
  return switch (severity) {
    'critical' => AdminTone.danger,
    'warning' => AdminTone.warning,
    _ => AdminTone.neutral,
  };
}
