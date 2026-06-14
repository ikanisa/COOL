import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/env/app_env.dart';
import 'core/admin_error_boundary.dart';
import 'core/admin_repository_base.dart';

class AdminShell extends ConsumerWidget {
  const AdminShell({required this.location, required this.child, super.key});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final env = ref.watch(appEnvProvider);
    final identity = ref.watch(adminIdentityProvider);
    return Scaffold(
      body: identity.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: AdminSafeErrorPanel(error: error)),
        data: (value) {
          if (value == null) return const AdminDeniedPage();
          ref.watch(adminRealtimeSubscriptionProvider);
          final destinations = _adminNavDestinationsFor(value);
          final requiredPermission = adminRequiredPermissionForPath(location);
          final page = adminCanOpenPath(value, location)
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
                  _AdminSidebar(location: location, destinations: destinations),
                  Expanded(child: content),
                ],
              );
            },
          );
        },
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
}

class _AdminSidebar extends StatelessWidget {
  const _AdminSidebar({required this.location, required this.destinations});

  final String location;
  final List<_AdminNavDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: 'Collect admin primary navigation',
      child: SizedBox(
        width: 260,
        child: Material(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: .45),
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(10),
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    'Collect Admin',
                    style: Theme.of(context).textTheme.titleLarge,
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
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: 'Collect admin mobile navigation',
      child: Material(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: .45),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                          ? colorScheme.primaryContainer
                          : colorScheme.surface,
                      foregroundColor: selected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
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
    return Semantics(
      button: true,
      selected: selected,
      label: '${destination.label} admin section',
      hint: 'Opens ${destination.label} in the admin console.',
      child: ListTile(
        selected: selected,
        leading: Icon(destination.icon),
        title: Text(destination.label),
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onTap: () => context.go(destination.path),
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
    return Semantics(
      container: true,
      label:
          'Signed in as ${identity.displayName}. Roles: ${identity.roles.join(', ')}. Environment: $envName.',
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          bottom: false,
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${identity.displayName}  ${identity.roles.join(', ')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    envName.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
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

List<_AdminNavDestination> _adminNavDestinationsFor(AdminIdentity identity) {
  return [
    for (final destination in _adminNavDestinations)
      if (adminIdentityAllows(identity, destination.requiredPermission))
        destination,
  ];
}

bool adminCanOpenPath(AdminIdentity identity, String path) {
  final permission = adminRequiredPermissionForPath(path);
  return permission == null || adminIdentityAllows(identity, permission);
}

bool adminIdentityAllows(AdminIdentity identity, String permission) {
  return identity.permissions.contains(permission);
}

String? adminRequiredPermissionForPath(String path) {
  for (final destination in _adminNavDestinations.reversed) {
    if (_isSelected(destination.path, path)) {
      return destination.requiredPermission;
    }
  }
  return null;
}
