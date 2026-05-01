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
            AdminPageHeader(
              eyebrow: context.l10n.adminOpsEyebrow,
              title: context.l10n.adminOpsTitle,
              subtitle: context.l10n.adminOpsSubtitle,
              badges: [
                AdminStatusChip(
                  label: context.l10n.adminOpsLabelLive,
                  tone: AdminTone.success,
                  icon: CoolIcons.bolt,
                ),
              ],
            ),
            const SizedBox(height: CoolSpace.x4),
            AdminMetricStrip(
              metrics: [
                AdminMetricItem(
                  label: context.l10n.adminOpsLabelSurfaces,
                  value: _asyncCount(dashboardAsync),
                  hint: context.l10n.adminOpsHintMonitoredServices,
                  icon: CoolIcons.monitorHeart,
                  tone: AdminTone.info,
                ),
                AdminMetricItem(
                  label: context.l10n.adminOpsLabelTriage,
                  value: _asyncCount(triageAsync),
                  hint: context.l10n.adminOpsHintOpenBlockingIssues,
                  icon: CoolIcons.priorityHigh,
                  tone: AdminTone.danger,
                ),
                AdminMetricItem(
                  label: context.l10n.adminOpsLabelSenders,
                  value: _asyncCount(senderInventoryAsync),
                  hint: context.l10n.adminOpsHintSenderAuditRows,
                  icon: CoolIcons.sms,
                  tone: AdminTone.warning,
                ),
                AdminMetricItem(
                  label: context.l10n.adminOpsLabelManualReview,
                  value: _asyncCount(manualReviewAsync),
                  hint: context.l10n.adminOpsHintOpenReviewItems,
                  icon: CoolIcons.ruleFolder,
                  tone: AdminTone.accent,
                ),
                AdminMetricItem(
                  label: context.l10n.adminOpsLabelEvents,
                  value: _asyncCount(eventsAsync),
                  hint: context.l10n.adminOpsHintRecentHealthEvents,
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
              emptyWidget: CoolEmptyView(
                message: context.l10n.adminOpsEmptyDashboard,
                icon: CoolIcons.monitorHeart,
              ),
              builder: (rows) => AdminDataTableCard(
                title: context.l10n.releaseDashboard,
                subtitle: context.l10n.adminOpsHealthSubtitle,
                emptyLabel: context.l10n.adminOpsEmptyDashboard,
                minWidth: 980,
                columns: [
                  DataColumn(label: Text(context.l10n.adminColumnService)),
                  DataColumn(label: Text(context.l10n.adminColumnStatus)),
                  const DataColumn(label: Text('24h')),
                  DataColumn(label: Text(context.l10n.adminColumnIssues)),
                  DataColumn(label: Text(context.l10n.adminColumnLastSignal)),
                  DataColumn(label: Text(context.l10n.adminColumnSummary)),
                ],
                rows: rows
                    .map(
                      (row) => DataRow(
                        cells: [
                          DataCell(
                            Text(
                              _text(row['label']) ?? context.l10n.adminOpsFallbackSurface,
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
                              _text(row['summary']) ?? context.l10n.adminOpsFallbackSummary,
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
              emptyWidget: CoolEmptyView(
                message: context.l10n.adminOpsTriageEmpty,
                icon: CoolIcons.factCheck,
              ),
              builder: (rows) => AdminDataTableCard(
                title: context.l10n.adminOpsTriageTitle,
                subtitle: context.l10n.adminOpsTriageSubtitle,
                emptyLabel: context.l10n.adminOpsTriageEmpty,
                minWidth: 1020,
                columns: [
                  DataColumn(label: Text(context.l10n.adminColumnIssue)),
                  DataColumn(label: Text(context.l10n.adminColumnSeverity)),
                  DataColumn(label: Text(context.l10n.adminColumnService)),
                  DataColumn(label: Text(context.l10n.adminColumnReference)),
                  DataColumn(label: Text(context.l10n.adminColumnLastSeen)),
                  DataColumn(label: Text(context.l10n.adminColumnDetail)),
                ],
                rows: rows
                    .map(
                      (row) => DataRow(
                        cells: [
                          DataCell(
                            Text(
                              _text(row['title']) ?? context.l10n.adminOpsFallbackIssue,
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
                              _text(row['detail']) ?? context.l10n.adminOpsFallbackDetail,
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
              title: context.l10n.adminOpsMMoneyTitle,
              subtitle:
                  'Device sync audits, parser backlog, sender backlog, migration safety, reconciliation pressure, and retention backlog.',
              child: CoolAsyncView<List<Map<String, dynamic>>>(
                value: momoSmsSummaryAsync,
                onRetry: refresh,
                loadingWidget: const CoolSkeletonList(itemCount: 4),
                emptyCheck: (rows) => rows.isEmpty,
                emptyWidget: CoolEmptyView(
                  message: context.l10n.adminOpsMMoneyEmpty,
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
            AdminSectionCard(
              title: context.l10n.adminOpsSenderTitle,
              subtitle: context.l10n.adminOpsSenderSubtitle,
              child: const _SenderInventorySection(),
            ),
            const SizedBox(height: CoolSpace.x4),
            AdminSectionCard(
              title: context.l10n.adminOpsManualReviewTitle,
              subtitle: context.l10n.adminOpsManualReviewSubtitle,
              child: const _ManualReviewSection(),
            ),
            const SizedBox(height: CoolSpace.x4),
            AdminSectionCard(
              title: context.l10n.adminOpsActivityTitle,
              subtitle: context.l10n.adminOpsActivitySubtitle,
              child: CoolAsyncView<List<Map<String, dynamic>>>(
                value: eventsAsync,
                onRetry: refresh,
                loadingWidget: const CoolSkeletonList(itemCount: 5),
                emptyCheck: (rows) => rows.isEmpty,
                emptyWidget: CoolEmptyView(
                  message: context.l10n.adminOpsActivityEmpty,
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
