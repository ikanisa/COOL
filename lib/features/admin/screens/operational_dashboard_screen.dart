import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/admin_detail_scaffold.dart';
import '../../../shared/widgets/admin_section_header.dart';
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
    final theme = Theme.of(context);
    final dashboardAsync = ref.watch(adminOperationalReleaseDashboardProvider);
    final triageAsync = ref.watch(adminOperationalTriageIssuesProvider);
    final momoSmsSummaryAsync = ref.watch(
      adminMomoSmsOperationalSummaryProvider,
    );
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
          icon: const Icon(Icons.refresh_rounded),
          color: colors.primaryText,
        ),
      ],
      child: RefreshIndicator(
        color: colors.accent,
        onRefresh: refresh,
        child: ListView(
          padding: CoolSpace.scaffoldPadding,
          children: [
            Text(
              'Operations',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.1,
                color: colors.primaryText,
              ),
            ),
            const SizedBox(height: CoolSpace.x6),
            AdminSectionHeader(
              title: context.l10n.releaseDashboard,
              message: 'Live health by monitored',
            ),
            const SizedBox(height: CoolSpace.x3),
            CoolAsyncView<List<Map<String, dynamic>>>(
              value: dashboardAsync,
              onRetry: refresh,
              loadingWidget: const CoolSkeletonList(itemCount: 3),
              emptyCheck: (rows) => rows.isEmpty,
              emptyWidget: const CoolEmptyView(
                message: 'No operational dashboard yet',
                icon: Icons.monitor_heart_outlined,
              ),
              builder: (rows) => Column(
                children: _spacedChildren(
                  rows,
                  (row) => _DashboardCard(row: row),
                ),
              ),
            ),
            const SizedBox(height: CoolSpace.x6),
            const AdminSectionHeader(
              title: 'Triage Queue',
              message: 'Focused on failed payment',
            ),
            const SizedBox(height: CoolSpace.x3),
            CoolAsyncView<List<Map<String, dynamic>>>(
              value: triageAsync,
              onRetry: refresh,
              loadingWidget: const CoolSkeletonList(itemCount: 3),
              emptyCheck: (rows) => rows.isEmpty,
              emptyWidget: const CoolEmptyView(
                message: 'No release-blocking operational issues',
                icon: Icons.fact_check_outlined,
              ),
              builder: (rows) => Column(
                children: _spacedChildren(
                  rows,
                  (row) => _IssueCard(row: row),
                  spacing: CoolSpace.x2,
                ),
              ),
            ),
            const SizedBox(height: CoolSpace.x6),
            const AdminSectionHeader(
              title: 'M-Money SMS',
              message:
                  'Device sync audits, parser backlog, sender backlog, migration safety, reconciliation pressure, and retention backlog.',
            ),
            const SizedBox(height: CoolSpace.x3),
            CoolAsyncView<List<Map<String, dynamic>>>(
              value: momoSmsSummaryAsync,
              onRetry: refresh,
              loadingWidget: const CoolSkeletonList(itemCount: 4),
              emptyCheck: (rows) => rows.isEmpty,
              emptyWidget: const CoolEmptyView(
                message: 'No M-Money SMS operational summary',
                icon: Icons.sms_outlined,
              ),
              builder: (rows) => Column(
                children: _spacedChildren(
                  rows,
                  (row) => _OperationalMetricCard(row: row),
                  spacing: CoolSpace.x2,
                ),
              ),
            ),
            const SizedBox(height: CoolSpace.x6),
            const AdminSectionHeader(
              title: 'Sender Inventory Audit',
              message: 'Unsupported or alias sender drift detected.',
            ),
            const SizedBox(height: CoolSpace.x3),
            const _SenderInventorySection(),
            const SizedBox(height: CoolSpace.x6),
            const AdminSectionHeader(
              title: 'Generic Manual Review',
              message: 'SMS that could not be app-linked.',
            ),
            const SizedBox(height: CoolSpace.x3),
            const _ManualReviewSection(),
            const SizedBox(height: CoolSpace.x6),
            const AdminSectionHeader(
              title: 'Recent Activity',
              message: 'Operational health stream',
            ),
            const SizedBox(height: CoolSpace.x3),
            CoolAsyncView<List<Map<String, dynamic>>>(
              value: eventsAsync,
              onRetry: refresh,
              loadingWidget: const CoolSkeletonList(itemCount: 5),
              emptyCheck: (rows) => rows.isEmpty,
              emptyWidget: const CoolEmptyView(
                message: 'No recent operational events',
                icon: Icons.history_rounded,
              ),
              builder: (rows) => Column(
                children: _spacedChildren(
                  rows,
                  (row) => _EventTile(row: row),
                  spacing: CoolSpace.x2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
