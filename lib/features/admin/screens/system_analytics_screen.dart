import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/admin_detail_scaffold.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/admin_section_header.dart';
import '../providers/admin_providers.dart';

EdgeInsets _systemAnalyticsLoadingPadding() =>
    const EdgeInsets.only(bottom: CoolSpace.x4);

EdgeInsets _systemAnalyticsListPadding() =>
    const EdgeInsets.only(bottom: CoolSpace.x7);

const BorderRadius _systemAnalyticsMetricRadius = BorderRadius.all(
  Radius.circular(CoolRadii.xs),
);

const BorderRadius _systemAnalyticsProgressRadius = BorderRadius.all(
  Radius.circular(CoolSpace.x1),
);

/// System-wide analytics dashboard for platform admins.
class SystemAnalyticsScreen extends ConsumerWidget {
  const SystemAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final analyticsAsync = ref.watch(platformAnalyticsProvider);

    return AdminDetailScaffold(
      title: Text(
        'System Analytics',
        style: theme.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
      subtitle: Text(
        'Platform health, growth, and audit volume',
        style: theme.textTheme.bodySmall?.copyWith(
          color: context.coolSemanticColors.secondaryText,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: CoolAsyncView<Map<String, dynamic>>(
        value: analyticsAsync,
        onRetry: () => ref.invalidate(platformAnalyticsProvider),
        loadingWidget: Padding(
          padding: _systemAnalyticsLoadingPadding(),
          child: const CoolSkeletonList(itemCount: 6),
        ),
        emptyCheck: (a) => a.isEmpty,
        emptyWidget: const CoolEmptyView(
          message: 'No analytics available yet',
          icon: Icons.analytics_outlined,
        ),
        builder: (data) {
          final colors = context.coolSemanticColors;
          return ListView(
            padding: _systemAnalyticsListPadding(),
            children: [
              const AdminSectionHeader(title: 'Core Counts'),
              const SizedBox(height: CoolSpace.x3),
              _MetricGrid(
                surfaceColor: colors.analyticsSurface,
                metrics: [
                  _Metric(
                    'Users',
                    _fmt(data['total_users']),
                    Icons.person_rounded,
                    colors.info,
                  ),
                  _Metric(
                    'Real Users',
                    _fmt(data['real_users']),
                    Icons.verified_user_rounded,
                    colors.success,
                  ),
                  _Metric(
                    'Mock Users',
                    _fmt(data['mock_users']),
                    Icons.smart_toy_rounded,
                    colors.warning,
                  ),
                  _Metric(
                    'Admins',
                    _fmt(data['total_admins']),
                    Icons.admin_panel_settings_rounded,
                    colors.accent,
                  ),
                  _Metric(
                    'Partners',
                    _fmt(data['total_partners']),
                    Icons.handshake_rounded,
                    colors.info,
                  ),
                  _Metric(
                    'Groups',
                    _fmt(data['total_groups']),
                    Icons.group_rounded,
                    colors.info,
                  ),
                  _Metric(
                    'Active Groups',
                    _fmt(data['active_groups']),
                    Icons.groups_rounded,
                    colors.success,
                  ),

                ],
              ),
              const SizedBox(height: 28),
              const AdminSectionHeader(title: 'Growth'),
              const SizedBox(height: CoolSpace.x3),
              _MetricGrid(
                surfaceColor: colors.contactSurface,
                metrics: [
                  _Metric(
                    'Signups (7d)',
                    _fmt(data['signups_7d']),
                    Icons.trending_up_rounded,
                    colors.success,
                  ),
                  _Metric(
                    'Signups (30d)',
                    _fmt(data['signups_30d']),
                    Icons.show_chart_rounded,
                    colors.info,
                  ),

                  _Metric(
                    'Active Partners',
                    _fmt(data['active_partners']),
                    Icons.storefront_rounded,
                    colors.accent,
                  ),
                ],
              ),
              const SizedBox(height: 28),
              const AdminSectionHeader(title: 'Admin Role Distribution'),
              const SizedBox(height: CoolSpace.x3),
              _DistributionCard(
                data: _asStringIntMap(data['role_distribution']),
                emptyLabel: 'No roles assigned yet',
              ),
              const SizedBox(height: 28),
              const AdminSectionHeader(title: 'Event Distribution (30d)'),
              const SizedBox(height: CoolSpace.x3),
              _DistributionCard(
                data: _asStringIntMap(data['event_distribution']),
                emptyLabel: 'No events recorded',
              ),
              const SizedBox(height: 28),
              const AdminSectionHeader(title: 'Audit'),
              const SizedBox(height: CoolSpace.x3),
              _MetricGrid(
                surfaceColor: colors.operationalSurface,
                metrics: [
                  _Metric(
                    'Admin Actions (7d)',
                    _fmt(data['audit_actions_7d']),
                    Icons.history_rounded,
                    colors.warning,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  static String _fmt(dynamic value) {
    if (value == null) return '—';
    if (value is num) return value.toInt().toString();
    return value.toString();
  }

  static Map<String, int> _asStringIntMap(dynamic value) {
    if (value is! Map) return {};
    return value.map(
      (k, v) => MapEntry(
        k.toString(),
        v is num ? v.toInt() : int.tryParse(v.toString()) ?? 0,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Sub-widgets
// ═══════════════════════════════════════════════════════════════

class _Metric {
  const _Metric(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics, required this.surfaceColor});
  final List<_Metric> metrics;
  final Color surfaceColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width >= 1280
            ? 4
            : width >= 900
            ? 3
            : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            mainAxisExtent: 92,
          ),
          itemCount: metrics.length,
          itemBuilder: (context, index) {
            final m = metrics[index];
            return CoolCard(
              backgroundColor: surfaceColor,
              useGradient: false,
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: m.color.withValues(alpha: 0.12),
                      borderRadius: _systemAnalyticsMetricRadius,
                    ),
                    child: Icon(m.icon, size: 18, color: m.color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          m.value,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.primaryText,
                          ),
                        ),
                        Text(
                          m.label,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w400,
                            color: colors.tertiaryText,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _DistributionCard extends StatelessWidget {
  const _DistributionCard({required this.data, required this.emptyLabel});
  final Map<String, int> data;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    if (data.isEmpty) {
      return CoolCard(
        backgroundColor: colors.analyticsSurface,
        useGradient: false,
        child: Text(
          emptyLabel,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.tertiaryText,
            fontWeight: FontWeight.w400,
          ),
        ),
      );
    }

    final total = data.values.fold<int>(0, (a, b) => a + b);
    final entries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return CoolCard(
      backgroundColor: colors.analyticsSurface,
      useGradient: false,
      child: Column(
        children: [
          for (final entry in entries) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.key,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.primaryText,
                    ),
                  ),
                ),
                Text(
                  '${entry.value}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.primaryText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: _systemAnalyticsProgressRadius,
              child: LinearProgressIndicator(
                value: total > 0 ? entry.value / total : 0,
                minHeight: 6,
                backgroundColor: colors.border,
                valueColor: AlwaysStoppedAnimation<Color>(colors.info),
              ),
            ),
            const SizedBox(height: CoolSpace.x3),
          ],
        ],
      ),
    );
  }
}
