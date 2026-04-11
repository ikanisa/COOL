import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/admin_detail_scaffold.dart';
import '../../../shared/widgets/admin_workspace_kit.dart';
import '../models/admin_workspace_access.dart';
import '../models/admin_workspace_catalog.dart';
import '../providers/admin_workspace_access_provider.dart';

part 'admin_dashboard_parts.dart';

/// Admin Dashboard — role-filtered grouped module launcher.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(adminWorkspaceAccessProvider);
    final destinations = access.hasPlatformAccess
        ? buildPlatformAdminDestinations(context)
        : const <AdminWorkspaceDestination>[];
    final groups = _groupDestinations(destinations);

    return AdminDetailScaffold(
      backTooltip: context.l10n.back,
      onBack: () => context.pop(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(CoolSpace.x5, 0, CoolSpace.x5, 104),
        children: [
          AdminPageHeader(
            eyebrow: context.l10n.adminEyebrowPlatformControl,
            title: context.l10n.adminPanelTitle,
            subtitle: context.l10n.adminSubtitleOperationalModules,
            badges: _buildAccessBadges(access),
          ),
          const SizedBox(height: CoolSpace.x4),
          AdminMetricStrip(
            metrics: [
              AdminMetricItem(
                label: context.l10n.adminMetricModules,
                value: '${destinations.length}',
                hint: context.l10n.adminMetricModulesHint,
                icon: CoolIcons.dashboardCustomize,
                tone: AdminTone.info,
              ),
              AdminMetricItem(
                label: context.l10n.adminMetricPriority,
                value: '${groups.priority.length}',
                hint: context.l10n.adminMetricPriorityHint,
                icon: CoolIcons.flash,
                tone: AdminTone.warning,
              ),
              AdminMetricItem(
                label: context.l10n.adminMetricOversight,
                value: '${groups.oversight.length}',
                hint: context.l10n.adminMetricOversightHint,
                icon: CoolIcons.monitor,
                tone: AdminTone.accent,
              ),
              AdminMetricItem(
                label: context.l10n.adminMetricConfig,
                value: '${groups.configuration.length}',
                hint: context.l10n.adminMetricConfigHint,
                icon: CoolIcons.settingsOutlined,
                tone: AdminTone.success,
              ),
            ],
          ),
          if (groups.priority.isNotEmpty) ...[
            const SizedBox(height: CoolSpace.x4),
            _DashboardSection(
              title: context.l10n.adminSectionPriority,
              subtitle: context.l10n.adminSectionPrioritySub,
              destinations: groups.priority,
            ),
          ],
          if (groups.oversight.isNotEmpty) ...[
            const SizedBox(height: CoolSpace.x4),
            _DashboardSection(
              title: context.l10n.adminSectionOversight,
              subtitle: context.l10n.adminSectionOversightSub,
              destinations: groups.oversight,
            ),
          ],
          if (groups.configuration.isNotEmpty) ...[
            const SizedBox(height: CoolSpace.x4),
            _DashboardSection(
              title: context.l10n.adminSectionConfiguration,
              subtitle: context.l10n.adminSectionConfigurationSub,
              destinations: groups.configuration,
            ),
          ],
        ],
      ),
    );
  }
}
