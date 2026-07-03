import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/env/app_env.dart';
import '../app/theme/collect_colors.dart';
import 'core/admin_error_boundary.dart';
import 'core/admin_repository_base.dart';
import 'shared/components/admin_loading_state.dart';

class AdminShell extends ConsumerWidget {
  const AdminShell({required this.location, required this.child, super.key});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final env = ref.watch(appEnvProvider);
    final identity = ref.watch(adminIdentityProvider);
    final colors = context.collectColors;
    return Scaffold(
      backgroundColor: CollectColors.inkPrimary,
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: colors.adminScreenGradient),
        child: identity.when(
          loading: () => const AdminLoadingState(
            title: 'Loading admin workspace',
            message: 'Checking access.',
          ),
          error: (error, _) => Center(child: AdminSafeErrorPanel(error: error)),
          data: (value) {
            if (value == null) return const AdminDeniedPage();
            ref.watch(adminRealtimeSubscriptionProvider);
            final runtimeConfig = ref
                .watch(adminRuntimeConfigProvider)
                .valueOrNull;
            final destinations = _adminNavDestinationsFor(value, runtimeConfig);
            final requiredPermission = adminRequiredPermissionForPath(
              location,
              runtimeConfig: runtimeConfig,
            );
            final page =
                adminCanOpenPath(value, location, runtimeConfig: runtimeConfig)
                ? child
                : AdminDeniedPage(requiredPermission: requiredPermission);
            final content = Semantics(
              container: true,
              label: 'Collect admin workspace',
              child: Column(
                children: [
                  _AdminTopbar(envName: env.environmentName, identity: value),
                  Expanded(child: page),
                ],
              ),
            );
            return LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 720) {
                  return Column(
                    children: [
                      _AdminMobileNav(
                        location: location,
                        destinations: destinations,
                      ),
                      Expanded(child: content),
                    ],
                  );
                }
                return Row(
                  children: [
                    _AdminSidebar(
                      location: location,
                      destinations: destinations,
                    ),
                    Expanded(child: content),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

const _adminNavDestinations = <_AdminNavDestination>[
  _AdminNavDestination(
    'Overview',
    Icons.dashboard_outlined,
    '/admin',
    'overview.read',
  ),
  _AdminNavDestination(
    'Groups',
    Icons.folder_copy_outlined,
    '/admin/groups',
    'collections.read',
  ),
  _AdminNavDestination(
    'Members',
    Icons.people_outline,
    '/admin/members',
    'users.read',
  ),
  _AdminNavDestination(
    'Payment intents',
    Icons.payments_outlined,
    '/admin/payment-intents',
    'payments.read',
  ),
  _AdminNavDestination(
    'SMS parsing',
    Icons.receipt_long_outlined,
    '/admin/payment-events',
    'payment_events.read',
  ),
  _AdminNavDestination(
    'Allocations',
    Icons.account_tree_outlined,
    '/admin/allocations',
    'payment_events.read',
  ),
  _AdminNavDestination(
    'Exceptions',
    Icons.call_split_outlined,
    '/admin/exceptions',
    'payment_events.read',
  ),
  _AdminNavDestination(
    'Ledger',
    Icons.account_balance_outlined,
    '/admin/ledger',
    'ledger.read',
  ),
  _AdminNavDestination(
    'Receivers',
    Icons.settings_phone_outlined,
    '/admin/receivers',
    'receivers.read',
  ),
  _AdminNavDestination(
    'SMS',
    Icons.sms_outlined,
    '/admin/sms',
    'sms.metadata.read',
  ),
  _AdminNavDestination(
    'Audit logs',
    Icons.policy_outlined,
    '/admin/audit-logs',
    'audit.read',
  ),
  _AdminNavDestination(
    'Settings',
    Icons.tune_outlined,
    '/admin/settings',
    'settings.read',
  ),
  _AdminNavDestination(
    'Feature flags',
    Icons.flag_outlined,
    '/admin/feature-flags',
    'feature_flags.read',
  ),
  _AdminNavDestination(
    'System health',
    Icons.monitor_heart_outlined,
    '/admin/system-health',
    'system_health.read',
  ),
  _AdminNavDestination(
    'Admin users',
    Icons.admin_panel_settings_outlined,
    '/admin/admin-users',
    'admin_users.read',
  ),
];

class _AdminNavDestination {
  const _AdminNavDestination(
    this.label,
    this.icon,
    this.path,
    this.requiredPermission,
  );

  final String label;
  final IconData icon;
  final String path;
  final String requiredPermission;

  factory _AdminNavDestination.fromConfig(AdminNavigationItemConfig config) {
    return _AdminNavDestination(
      config.label,
      _adminIconForKey(config.iconKey),
      config.path,
      config.requiredPermission,
    );
  }
}

class _AdminSidebar extends StatelessWidget {
  const _AdminSidebar({required this.location, required this.destinations});

  final String location;
  final List<_AdminNavDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      container: true,
      label: 'Collect admin primary navigation',
      child: SizedBox(
        width: 260,
        child: Material(
          color: CollectColors.inkPrimary.withValues(alpha: 0.94),
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 18),
                  child: Row(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.onImagePrimary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: colors.onImagePrimary.withValues(
                              alpha: 0.16,
                            ),
                          ),
                        ),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Icon(
                            Icons.admin_panel_settings_outlined,
                            color: colors.onImagePrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Collect Admin',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: colors.onImagePrimary,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            Text(
                              'Operations',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: colors.onImagePrimary.withValues(
                                      alpha: 0.62,
                                    ),
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                for (final destination in destinations)
                  _NavItem(destination, location),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminMobileNav extends StatelessWidget {
  const _AdminMobileNav({required this.location, required this.destinations});

  final String location;
  final List<_AdminNavDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      container: true,
      label: 'Collect admin mobile navigation',
      child: Material(
        color: CollectColors.inkPrimary.withValues(alpha: 0.96),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              itemCount: destinations.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final destination = destinations[index];
                final selected = _isSelected(destination.path, location);
                return Semantics(
                  button: true,
                  selected: selected,
                  label: '${destination.label} admin section',
                  hint: 'Opens ${destination.label} in the admin console.',
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: selected
                          ? colors.surfaceReadable
                          : colors.onImagePrimary.withValues(alpha: 0.12),
                      foregroundColor: selected
                          ? colors.textPrimary
                          : colors.onImagePrimary,
                      side: BorderSide(
                        color: colors.onImagePrimary.withValues(alpha: 0.16),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => context.go(destination.path),
                    icon: Icon(destination.icon, size: 18),
                    label: Text(destination.label),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem(this.destination, this.location);

  final _AdminNavDestination destination;
  final String location;

  @override
  Widget build(BuildContext context) {
    final selected = _isSelected(destination.path, location);
    final colors = context.collectColors;
    final foreground = selected ? colors.textPrimary : colors.onImagePrimary;
    return Semantics(
      button: true,
      selected: selected,
      label: '${destination.label} admin section',
      hint: 'Opens ${destination.label} in the admin console.',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: ListTile(
          selected: selected,
          selectedTileColor: colors.surfaceReadable,
          tileColor: selected
              ? colors.surfaceReadable
              : colors.onImagePrimary.withValues(alpha: 0.07),
          iconColor: foreground,
          textColor: foreground,
          leading: Icon(destination.icon, size: 20),
          title: Text(
            destination.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: selected ? FontWeight.w900 : null),
          ),
          dense: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: colors.surfaceReadable.withValues(
                alpha: selected ? 0.0 : 0.10,
              ),
            ),
          ),
          onTap: () => context.go(destination.path),
        ),
      ),
    );
  }
}

bool _isSelected(String path, String location) {
  return path == '/admin' ? location == path : location.startsWith(path);
}

class _AdminTopbar extends StatelessWidget {
  const _AdminTopbar({required this.envName, required this.identity});

  final String envName;
  final AdminIdentity identity;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      container: true,
      label:
          'Signed in as ${identity.displayName}. Roles: ${identity.roles.join(', ')}. Environment: $envName.',
      child: Material(
        color: CollectColors.inkPrimary.withValues(alpha: 0.90),
        child: SafeArea(
          bottom: false,
          child: Container(
            height: 68,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: colors.surfaceReadable.withValues(alpha: 0.10),
                ),
              ),
            ),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.mintPaint.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: SizedBox(
                    width: 10,
                    height: 10,
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.mintPaint,
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox.square(dimension: 5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${identity.displayName}  ${identity.roles.join(', ')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colors.onImagePrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.onImagePrimary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: colors.onImagePrimary.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Text(
                      envName.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.onImagePrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AdminPageError extends StatelessWidget {
  const AdminPageError({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }
}

List<_AdminNavDestination> _adminNavDestinationsFor(
  AdminIdentity identity, [
  AdminRuntimeConfig? runtimeConfig,
]) {
  final configuredDestinations = runtimeConfig?.navigationItems
      .map(_AdminNavDestination.fromConfig)
      .toList();
  final source = configuredDestinations?.isEmpty == false
      ? configuredDestinations!
      : _adminNavDestinations;
  return [
    for (final destination in source)
      if (adminIdentityAllows(identity, destination.requiredPermission))
        destination,
  ];
}

bool adminCanOpenPath(
  AdminIdentity identity,
  String path, {
  AdminRuntimeConfig? runtimeConfig,
}) {
  final permission = adminRequiredPermissionForPath(
    path,
    runtimeConfig: runtimeConfig,
  );
  return permission == null || adminIdentityAllows(identity, permission);
}

bool adminIdentityAllows(AdminIdentity identity, String permission) {
  return identity.permissions.contains(permission);
}

String? adminRequiredPermissionForPath(
  String path, {
  AdminRuntimeConfig? runtimeConfig,
}) {
  final configuredDestinations = runtimeConfig?.navigationItems
      .map(_AdminNavDestination.fromConfig)
      .toList();
  if (configuredDestinations?.isEmpty == false) {
    for (final destination in configuredDestinations!.reversed) {
      if (_isSelected(destination.path, path)) {
        return destination.requiredPermission;
      }
    }
  }
  for (final destination in _adminNavDestinations.reversed) {
    if (_isSelected(destination.path, path)) {
      return destination.requiredPermission;
    }
  }
  return null;
}

IconData _adminIconForKey(String iconKey) {
  return switch (iconKey.trim().toLowerCase()) {
    'dashboard' || 'dashboard_outlined' => Icons.dashboard_outlined,
    'groups' || 'folder_copy' => Icons.folder_copy_outlined,
    'members' || 'people' => Icons.people_outline,
    'payments' || 'payment_intents' => Icons.payments_outlined,
    'sms_parsing' || 'receipt_long' => Icons.receipt_long_outlined,
    'allocations' || 'account_tree' => Icons.account_tree_outlined,
    'exceptions' || 'call_split' => Icons.call_split_outlined,
    'ledger' || 'account_balance' => Icons.account_balance_outlined,
    'receivers' || 'settings_phone' => Icons.settings_phone_outlined,
    'sms' => Icons.sms_outlined,
    'audit' || 'policy' => Icons.policy_outlined,
    'settings' || 'tune' => Icons.tune_outlined,
    'feature_flags' || 'flag' => Icons.flag_outlined,
    'system_health' || 'monitor_heart' => Icons.monitor_heart_outlined,
    'admin_users' ||
    'admin_panel_settings' => Icons.admin_panel_settings_outlined,
    _ => Icons.admin_panel_settings_outlined,
  };
}
