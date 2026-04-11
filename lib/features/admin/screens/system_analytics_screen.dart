import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/admin_detail_scaffold.dart';
import '../../../shared/widgets/admin_workspace_kit.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../providers/admin_providers.dart';

/// System-wide analytics dashboard for platform admins.
class SystemAnalyticsScreen extends ConsumerWidget {
  const SystemAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(platformAnalyticsProvider);

    return AdminDetailScaffold(
      child: CoolAsyncView<Map<String, dynamic>>(
        value: analyticsAsync,
        onRetry: () => ref.invalidate(platformAnalyticsProvider),
        loadingWidget: const Padding(
          padding: EdgeInsets.fromLTRB(
            CoolSpace.x5,
            0,
            CoolSpace.x5,
            CoolSpace.x7,
          ),
          child: CoolSkeletonList(itemCount: 6),
        ),
        emptyCheck: (data) => data.isEmpty,
        emptyWidget: const Padding(
          padding: EdgeInsets.all(CoolSpace.x5),
          child: CoolEmptyView(
            message: 'No analytics available yet',
            icon: Icons.analytics_outlined,
          ),
        ),
        builder: (data) {
          final roleDistribution = _asStringIntMap(data['role_distribution']);
          final eventDistribution = _asStringIntMap(data['event_distribution']);

          return ListView(
            padding: CoolSpace.scaffoldPadding,
            children: [
              const AdminPageHeader(
                eyebrow: 'PLATFORM ANALYTICS',
                title: 'System Analytics',
                subtitle:
                    'Platform health, growth, role spread, and audit volume.',
              ),
              const SizedBox(height: CoolSpace.x4),
              AdminMetricStrip(
                metrics: [
                  AdminMetricItem(
                    label: 'Accounts',
                    value: _fmt(data['total_users']),
                    hint: 'All accounts',
                    icon: Icons.group_outlined,
                    tone: AdminTone.info,
                  ),
                  AdminMetricItem(
                    label: 'Signups (7d)',
                    value: _fmt(data['signups_7d']),
                    hint: 'New accounts',
                    icon: Icons.trending_up_rounded,
                    tone: AdminTone.success,
                  ),
                  AdminMetricItem(
                    label: 'Active groups',
                    value: _fmt(data['active_groups']),
                    hint: 'Currently live',
                    icon: Icons.groups_rounded,
                    tone: AdminTone.accent,
                  ),
                  AdminMetricItem(
                    label: 'Admin actions (7d)',
                    value: _fmt(data['audit_actions_7d']),
                    hint: 'Audit volume',
                    icon: Icons.history_rounded,
                    tone: AdminTone.warning,
                  ),
                ],
              ),
              const SizedBox(height: CoolSpace.x4),
              AdminSectionCard(
                title: 'Core Counts',
                child: AdminMetricStrip(
                  metrics: [
                    AdminMetricItem(
                      label: 'Users',
                      value: _fmt(data['total_users']),
                      hint: 'All users',
                      icon: Icons.person_rounded,
                      tone: AdminTone.info,
                    ),
                    AdminMetricItem(
                      label: 'Real Users',
                      value: _fmt(data['real_users']),
                      hint: 'Non-mock',
                      icon: Icons.verified_user_rounded,
                      tone: AdminTone.success,
                    ),
                    AdminMetricItem(
                      label: 'Mock Users',
                      value: _fmt(data['mock_users']),
                      hint: 'Demo data',
                      icon: Icons.smart_toy_rounded,
                      tone: AdminTone.warning,
                    ),
                    AdminMetricItem(
                      label: 'Admins',
                      value: _fmt(data['total_admins']),
                      hint: 'Privileged',
                      icon: Icons.admin_panel_settings_rounded,
                      tone: AdminTone.accent,
                    ),
                    AdminMetricItem(
                      label: 'Partners',
                      value: _fmt(data['total_partners']),
                      hint: 'Configured',
                      icon: Icons.handshake_rounded,
                      tone: AdminTone.info,
                    ),
                    AdminMetricItem(
                      label: 'Groups',
                      value: _fmt(data['total_groups']),
                      hint: 'Created',
                      icon: Icons.group_work_rounded,
                      tone: AdminTone.info,
                    ),
                    AdminMetricItem(
                      label: 'Active Groups',
                      value: _fmt(data['active_groups']),
                      hint: 'Running now',
                      icon: Icons.groups_rounded,
                      tone: AdminTone.success,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: CoolSpace.x4),
              AdminSectionCard(
                title: 'Growth',
                child: AdminMetricStrip(
                  metrics: [
                    AdminMetricItem(
                      label: 'Signups (7d)',
                      value: _fmt(data['signups_7d']),
                      hint: 'Weekly',
                      icon: Icons.trending_up_rounded,
                      tone: AdminTone.success,
                    ),
                    AdminMetricItem(
                      label: 'Signups (30d)',
                      value: _fmt(data['signups_30d']),
                      hint: 'Monthly',
                      icon: Icons.show_chart_rounded,
                      tone: AdminTone.info,
                    ),
                    AdminMetricItem(
                      label: 'Contributions (7d)',
                      value: _fmt(data['contributions_7d']),
                      hint: 'Recent activity',
                      icon: Icons.payments_outlined,
                      tone: AdminTone.accent,
                    ),
                    AdminMetricItem(
                      label: 'Active Partners',
                      value: _fmt(data['active_partners']),
                      hint: 'Currently transacting',
                      icon: Icons.storefront_rounded,
                      tone: AdminTone.warning,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: CoolSpace.x4),
              AdminSectionCard(
                title: 'Admin Role Distribution',
                child: AdminRankList(
                  items: roleDistribution.entries
                      .map(
                        (entry) =>
                            AdminRankItem(label: entry.key, value: entry.value),
                      )
                      .toList(growable: false),
                  emptyLabel: 'No roles assigned yet',
                  tone: AdminTone.accent,
                ),
              ),
              const SizedBox(height: CoolSpace.x4),
              AdminSectionCard(
                title: 'Event Distribution (30d)',
                child: AdminRankList(
                  items: eventDistribution.entries
                      .map(
                        (entry) =>
                            AdminRankItem(label: entry.key, value: entry.value),
                      )
                      .toList(growable: false),
                  emptyLabel: 'No events recorded',
                  tone: AdminTone.info,
                ),
              ),
              const SizedBox(height: CoolSpace.x4),
              AdminSectionCard(
                title: 'Audit',
                child: AdminMetricStrip(
                  metrics: [
                    AdminMetricItem(
                      label: 'Admin Actions (7d)',
                      value: _fmt(data['audit_actions_7d']),
                      hint: 'Recent admin writes',
                      icon: Icons.history_rounded,
                      tone: AdminTone.warning,
                    ),
                  ],
                ),
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
