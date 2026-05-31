import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/env/app_env.dart';
import 'core/admin_repository_base.dart';

class AdminShell extends ConsumerWidget {
  const AdminShell({required this.location, required this.child, super.key});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final env = ref.watch(appEnvProvider);
    final identity = ref.watch(adminIdentityProvider);
    final content = identity.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AdminPageError(message: error.toString()),
      data: (value) {
        if (value == null) return const AdminDeniedPage();
        ref.watch(adminRealtimeSubscriptionProvider);
        return Column(
          children: [
            _AdminTopbar(envName: env.environmentName, identity: value),
            Expanded(child: child),
          ],
        );
      },
    );
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 720) {
            return Column(
              children: [
                _AdminMobileNav(location: location),
                Expanded(child: content),
              ],
            );
          }
          return Row(
            children: [
              _AdminSidebar(location: location),
              Expanded(child: content),
            ],
          );
        },
      ),
    );
  }
}

const _adminNavDestinations = <_AdminNavDestination>[
  _AdminNavDestination('Overview', Icons.dashboard_outlined, '/admin'),
  _AdminNavDestination('Groups', Icons.folder_copy_outlined, '/admin/groups'),
  _AdminNavDestination('Members', Icons.people_outline, '/admin/members'),
  _AdminNavDestination(
    'Payment intents',
    Icons.payments_outlined,
    '/admin/payment-intents',
  ),
  _AdminNavDestination(
    'SMS parsing',
    Icons.receipt_long_outlined,
    '/admin/payment-events',
  ),
  _AdminNavDestination(
    'Allocations',
    Icons.account_tree_outlined,
    '/admin/allocations',
  ),
  _AdminNavDestination(
    'Exceptions',
    Icons.call_split_outlined,
    '/admin/exceptions',
  ),
  _AdminNavDestination(
    'Ledger',
    Icons.account_balance_outlined,
    '/admin/ledger',
  ),
  _AdminNavDestination(
    'Receivers',
    Icons.settings_phone_outlined,
    '/admin/receivers',
  ),
  _AdminNavDestination('SMS', Icons.sms_outlined, '/admin/sms'),
  _AdminNavDestination(
    'Audit logs',
    Icons.policy_outlined,
    '/admin/audit-logs',
  ),
  _AdminNavDestination('Settings', Icons.tune_outlined, '/admin/settings'),
  _AdminNavDestination(
    'Feature flags',
    Icons.flag_outlined,
    '/admin/feature-flags',
  ),
  _AdminNavDestination(
    'System health',
    Icons.monitor_heart_outlined,
    '/admin/system-health',
  ),
  _AdminNavDestination(
    'Admin users',
    Icons.admin_panel_settings_outlined,
    '/admin/admin-users',
  ),
];

class _AdminNavDestination {
  const _AdminNavDestination(this.label, this.icon, this.path);

  final String label;
  final IconData icon;
  final String path;
}

class _AdminSidebar extends StatelessWidget {
  const _AdminSidebar({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
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
              for (final destination in _adminNavDestinations)
                _NavItem(destination, location),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminMobileNav extends StatelessWidget {
  const _AdminMobileNav({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: .45),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            itemCount: _adminNavDestinations.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final destination = _adminNavDestinations[index];
              final selected = _isSelected(destination.path, location);
              return FilledButton.tonalIcon(
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
              );
            },
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
    return ListTile(
      selected: selected,
      leading: Icon(destination.icon),
      title: Text(destination.label),
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onTap: () => context.go(destination.path),
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
    return Material(
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
