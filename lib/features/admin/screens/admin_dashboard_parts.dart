part of 'admin_dashboard_screen.dart';

class _DashboardGroups {
  const _DashboardGroups({
    required this.priority,
    required this.oversight,
    required this.configuration,
  });

  final List<AdminWorkspaceDestination> priority;
  final List<AdminWorkspaceDestination> oversight;
  final List<AdminWorkspaceDestination> configuration;
}

_DashboardGroups _groupDestinations(List<AdminWorkspaceDestination> items) {
  final priority = <AdminWorkspaceDestination>[];
  final oversight = <AdminWorkspaceDestination>[];
  final configuration = <AdminWorkspaceDestination>[];

  for (final item in items) {
    if (item.route == '/admin/users' ||
        item.route == '/admin/operations' ||
        item.route == '/admin/roles') {
      priority.add(item);
    } else if (item.route == '/admin/analytics' ||
        item.route == '/admin/audit-log') {
      oversight.add(item);
    } else {
      configuration.add(item);
    }
  }

  return _DashboardGroups(
    priority: priority,
    oversight: oversight,
    configuration: configuration,
  );
}

List<Widget> _buildAccessBadges(AdminWorkspaceAccess access) {
  final badges = <Widget>[];
  if (access.hasPlatformAccess) {
    badges.add(
      const AdminStatusChip(
        label: 'Platform Admin',
        tone: AdminTone.success,
        icon: Icons.verified_user_outlined,
      ),
    );
  }
  if (!access.hasPlatformAccess) {
    badges.add(
      const AdminStatusChip(
        label: 'Restricted',
        tone: AdminTone.warning,
        icon: Icons.lock_outline_rounded,
      ),
    );
  }
  return badges;
}

class _DashboardSection extends StatelessWidget {
  const _DashboardSection({
    required this.title,
    required this.subtitle,
    required this.destinations,
  });

  final String title;
  final String subtitle;
  final List<AdminWorkspaceDestination> destinations;

  @override
  Widget build(BuildContext context) {
    return AdminSectionCard(
      title: title,
      subtitle: subtitle,
      child: Column(
        children: [
          for (var index = 0; index < destinations.length; index++) ...[
            _DashboardModuleTile(destination: destinations[index]),
            if (index < destinations.length - 1)
              const SizedBox(height: CoolSpace.x2),
          ],
        ],
      ),
    );
  }
}

class _DashboardModuleTile extends StatelessWidget {
  const _DashboardModuleTile({required this.destination});

  final AdminWorkspaceDestination destination;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return AdminPanelSurface(
      backgroundColor: colors.inputSurface,
      padding: const EdgeInsets.all(CoolSpace.x4),
      onTap: () {
        HapticFeedback.selectionClick();
        context.push(destination.route);
      },
      radius: CoolRadii.md,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.cardSurfaceStrong,
              borderRadius: BorderRadius.circular(CoolRadii.sm),
            ),
            alignment: Alignment.center,
            child: Icon(destination.icon, size: 20, color: colors.primaryText),
          ),
          const SizedBox(width: CoolSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  destination.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colors.primaryText,
                  ),
                ),
                const SizedBox(height: CoolSpace.x1),
                Text(
                  destination.subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.secondaryText,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_forward_rounded,
            size: 18,
            color: colors.tertiaryText,
          ),
        ],
      ),
    );
  }
}
