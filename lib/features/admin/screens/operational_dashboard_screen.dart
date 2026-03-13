import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../providers/admin_providers.dart';

class OperationalDashboardScreen extends ConsumerWidget {
  const OperationalDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(adminOperationalReleaseDashboardProvider);
    final triageAsync = ref.watch(adminOperationalTriageIssuesProvider);
    final eventsAsync = ref.watch(adminRecentOperationalHealthEventsProvider);

    Future<void> refresh() async {
      ref.invalidate(adminOperationalReleaseDashboardProvider);
      ref.invalidate(adminOperationalTriageIssuesProvider);
      ref.invalidate(adminRecentOperationalHealthEventsProvider);
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(
          'Operations',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.text),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _SectionHeader(
              title: 'Release Dashboard',
              subtitle:
                  'Live health by monitored surface so release blockers show up before user reports do.',
            ),
            const SizedBox(height: 12),
            CoolAsyncView<List<Map<String, dynamic>>>(
              value: dashboardAsync,
              onRetry: refresh,
              loadingWidget: const CoolSkeletonList(itemCount: 3),
              emptyCheck: (rows) => rows.isEmpty,
              emptyWidget: const CoolEmptyView(
                message: 'No operational dashboard rows are available yet.',
                icon: Icons.monitor_heart_outlined,
              ),
              builder: (rows) => Wrap(
                spacing: 12,
                runSpacing: 12,
                children: rows
                    .map((row) => _DashboardCard(row: row))
                    .toList(growable: false),
              ),
            ),
            const SizedBox(height: 24),
            _SectionHeader(
              title: 'Triage Queue',
              subtitle:
                  'Focused on failed payment sync, failed function invocation, and stale config.',
            ),
            const SizedBox(height: 12),
            CoolAsyncView<List<Map<String, dynamic>>>(
              value: triageAsync,
              onRetry: refresh,
              loadingWidget: const CoolSkeletonList(itemCount: 3),
              emptyCheck: (rows) => rows.isEmpty,
              emptyWidget: const CoolEmptyView(
                message:
                    'No release-blocking operational issues need triage right now.',
                icon: Icons.fact_check_outlined,
              ),
              builder: (rows) => Column(
                children: rows
                    .map(
                      (row) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _IssueCard(row: row),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
            const SizedBox(height: 24),
            _SectionHeader(
              title: 'Recent Signals',
              subtitle:
                  'Raw health events from mobile and Edge Function instrumentation.',
            ),
            const SizedBox(height: 12),
            CoolAsyncView<List<Map<String, dynamic>>>(
              value: eventsAsync,
              onRetry: refresh,
              loadingWidget: const CoolSkeletonList(itemCount: 3),
              emptyCheck: (rows) => rows.isEmpty,
              emptyWidget: const CoolEmptyView(
                message: 'No operational health events have been recorded yet.',
                icon: Icons.sensors_outlined,
              ),
              builder: (rows) => Column(
                children: rows
                    .map(
                      (row) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _EventTile(row: row),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.dmSans(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.text2,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final status = _text(row['health_status']) ?? 'unknown';
    final issueCount = _count(row['issue_count']);
    final okCount = _count(row['ok_count_24h']);
    final warnCount = _count(row['warn_count_24h']);
    final errorCount = _count(row['error_count_24h']);

    return Container(
      width: 260,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _statusColor(status).withValues(alpha: 0.45),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _text(row['label']) ?? 'Surface',
                  style: GoogleFonts.dmSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ),
              _Badge(label: status.toUpperCase(), color: _statusColor(status)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricChip(label: 'OK', value: '$okCount'),
              _MetricChip(label: 'Warn', value: '$warnCount'),
              _MetricChip(label: 'Error', value: '$errorCount'),
              _MetricChip(label: 'Issues', value: '$issueCount'),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _text(row['summary']) ?? 'No summary available.',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Last signal: ${_formatTimestamp(row['last_signal_at'])}',
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.text3,
            ),
          ),
        ],
      ),
    );
  }
}

class _IssueCard extends StatelessWidget {
  const _IssueCard({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final severity = _text(row['severity']) ?? 'warning';
    final reference = _text(row['reference']);
    final subjectTable = _text(row['subject_table']);
    final subjectId = _text(row['subject_id']);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _severityColor(severity).withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _text(row['title']) ?? 'Issue',
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ),
              _Badge(
                label: severity.toUpperCase(),
                color: _severityColor(severity),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _text(row['detail']) ?? 'No detail available.',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricChip(
                label: 'Service',
                value: (_text(row['service']) ?? 'unknown').replaceAll(
                  '_',
                  ' ',
                ),
              ),
              if (reference != null)
                _MetricChip(label: 'Reference', value: reference),
              if (subjectTable != null)
                _MetricChip(label: 'Table', value: subjectTable),
              if (subjectId != null)
                _MetricChip(label: 'Record', value: subjectId),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Seen ${_formatTimestamp(row['first_seen_at'])} • Last signal ${_formatTimestamp(row['last_seen_at'])}',
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.text3,
            ),
          ),
        ],
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final status = _text(row['status']) ?? 'ok';
    final functionName = _text(row['function_name']);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _statusColor(status).withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Badge(label: status.toUpperCase(), color: _statusColor(status)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _text(row['service']) ?? 'service',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ),
              Text(
                _formatTimestamp(row['occurred_at']),
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _text(row['message']) ?? 'No message',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricChip(
                label: 'Component',
                value: _text(row['component']) ?? 'general',
              ),
              if (functionName != null)
                _MetricChip(label: 'Function', value: functionName),
              if (_text(row['issue_code']) case final issueCode?)
                _MetricChip(label: 'Code', value: issueCode),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'healthy':
    case 'ok':
      return AppColors.accent;
    case 'degraded':
    case 'warn':
    case 'warning':
      return const Color(0xFFF4B942);
    case 'failing':
    case 'error':
      return const Color(0xFFFF6B6B);
    default:
      return AppColors.text2;
  }
}

Color _severityColor(String severity) {
  switch (severity) {
    case 'critical':
      return const Color(0xFFFF6B6B);
    case 'warning':
      return const Color(0xFFF4B942);
    default:
      return AppColors.text2;
  }
}

String? _text(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty || text == 'null' || text == '-infinity') {
    return null;
  }
  return text;
}

int _count(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _formatTimestamp(dynamic value) {
  final text = _text(value);
  if (text == null) {
    return 'No signal yet';
  }

  final timestamp = DateTime.tryParse(text)?.toLocal();
  if (timestamp == null) {
    return text;
  }

  return DateFormat('MMM d, HH:mm').format(timestamp);
}
