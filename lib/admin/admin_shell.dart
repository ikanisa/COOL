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
      data: (value) => value == null
          ? const AdminDeniedPage()
          : Column(
              children: [
                _AdminTopbar(envName: env.environmentName, identity: value),
                Expanded(child: child),
              ],
            ),
    );
    return Scaffold(
      body: Row(
        children: [
          _AdminSidebar(location: location),
          Expanded(child: content),
        ],
      ),
    );
  }
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
              _NavItem(
                'Overview',
                Icons.dashboard_outlined,
                '/admin',
                location,
              ),
              _NavItem(
                'Collections',
                Icons.folder_copy_outlined,
                '/admin/collections',
                location,
              ),
              _NavItem(
                'Public requests',
                Icons.fact_check_outlined,
                '/admin/public-requests',
                location,
              ),
              _NavItem('Users', Icons.people_outline, '/admin/users', location),
              _NavItem(
                'Payments',
                Icons.payments_outlined,
                '/admin/payments',
                location,
              ),
              _NavItem(
                'Payment events',
                Icons.receipt_long_outlined,
                '/admin/payment-events',
                location,
              ),
              _NavItem(
                'Unallocated payments',
                Icons.call_split_outlined,
                '/admin/unallocated',
                location,
              ),
              _NavItem(
                'Ledger',
                Icons.account_balance_outlined,
                '/admin/ledger',
                location,
              ),
              _NavItem(
                'Receivers',
                Icons.settings_phone_outlined,
                '/admin/receivers',
                location,
              ),
              _NavItem('SMS', Icons.sms_outlined, '/admin/sms', location),
              _NavItem(
                'Audit logs',
                Icons.policy_outlined,
                '/admin/audit-logs',
                location,
              ),
              _NavItem(
                'Settings',
                Icons.tune_outlined,
                '/admin/settings',
                location,
              ),
              _NavItem(
                'Feature flags',
                Icons.flag_outlined,
                '/admin/feature-flags',
                location,
              ),
              _NavItem(
                'System health',
                Icons.monitor_heart_outlined,
                '/admin/system-health',
                location,
              ),
              _NavItem(
                'Admin users',
                Icons.admin_panel_settings_outlined,
                '/admin/admin-users',
                location,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem(this.label, this.icon, this.path, this.location);

  final String label;
  final IconData icon;
  final String path;
  final String location;

  @override
  Widget build(BuildContext context) {
    final selected = path == '/admin'
        ? location == path
        : location.startsWith(path);
    return ListTile(
      selected: selected,
      leading: Icon(icon),
      title: Text(label),
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onTap: () => context.go(path),
    );
  }
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
