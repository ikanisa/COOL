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
            eyebrow: 'PLATFORM CONTROL',
            title: context.l10n.adminPanelTitle,
            subtitle:
                'Operational modules, oversight surfaces, and release controls.',
            badges: _buildAccessBadges(access),
          ),
          const SizedBox(height: CoolSpace.x4),
          AdminMetricStrip(
            metrics: [
              AdminMetricItem(
                label: 'Modules',
                value: '${destinations.length}',
                hint: 'Platform surfaces',
                icon: Icons.dashboard_customize_outlined,
                tone: AdminTone.info,
              ),
              AdminMetricItem(
                label: 'Priority',
                value: '${groups.priority.length}',
                hint: 'Daily-use modules',
                icon: Icons.flash_on_outlined,
                tone: AdminTone.warning,
              ),
              AdminMetricItem(
                label: 'Oversight',
                value: '${groups.oversight.length}',
                hint: 'Monitoring surfaces',
                icon: Icons.monitor_outlined,
                tone: AdminTone.accent,
              ),
              AdminMetricItem(
                label: 'Config',
                value: '${groups.configuration.length}',
                hint: 'System controls',
                icon: Icons.settings_outlined,
                tone: AdminTone.success,
              ),
            ],
          ),
          if (groups.priority.isNotEmpty) ...[
            const SizedBox(height: CoolSpace.x4),
            _DashboardSection(
              title: 'Priority',
              subtitle: 'Users, operations, and access changes first.',
              destinations: groups.priority,
            ),
          ],
          if (groups.oversight.isNotEmpty) ...[
            const SizedBox(height: CoolSpace.x4),
            _DashboardSection(
              title: 'Oversight',
              subtitle: 'Platform metrics, history, and operational context.',
              destinations: groups.oversight,
            ),
          ],
          if (groups.configuration.isNotEmpty) ...[
            const SizedBox(height: CoolSpace.x4),
            _DashboardSection(
              title: 'Configuration',
              subtitle: 'Core settings and structural management surfaces.',
              destinations: groups.configuration,
            ),
          ],
        ],
      ),
    );
  }
}
