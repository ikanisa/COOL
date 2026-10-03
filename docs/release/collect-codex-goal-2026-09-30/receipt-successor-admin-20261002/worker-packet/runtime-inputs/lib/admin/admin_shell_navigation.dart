part of 'admin_shell.dart';

const _adminNavDestinations = <_AdminNavDestination>[
  _AdminNavDestination(
    'Overview',
    Icons.home_rounded,
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
    'Users',
    Icons.person_outline,
    '/admin/users',
    'users.read',
  ),
  _AdminNavDestination(
    'Members',
    Icons.people_outline,
    '/admin/members',
    'users.read',
  ),
  _AdminNavDestination(
    'Payees',
    Icons.person_pin_circle_outlined,
    '/admin/payees',
    'receivers.read',
  ),
  _AdminNavDestination(
    'Transactions',
    Icons.receipt_long_outlined,
    '/admin/transactions',
    'payments.read',
  ),
  _AdminNavDestination(
    'Reconciliations',
    Icons.balance_outlined,
    '/admin/reconciliations',
    'payment_events.read',
  ),
  _AdminNavDestination(
    'Ledgers',
    Icons.menu_book_outlined,
    '/admin/ledgers',
    'ledger.read',
  ),
  _AdminNavDestination(
    'SMS receipts',
    Icons.sms_outlined,
    '/admin/sms-receipts',
    'notifications.read',
  ),
  _AdminNavDestination(
    'Notifications',
    Icons.notifications_outlined,
    '/admin/notifications',
    'notifications.read',
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
    'Automations',
    Icons.manage_search_outlined,
    '/admin/automations',
    'system_health.read',
  ),
  _AdminNavDestination(
    'SMS Gateway',
    Icons.phonelink_ring_outlined,
    '/admin/sms-gateway',
    'notifications.read',
  ),
  _AdminNavDestination(
    'Exceptions',
    Icons.warning_amber_outlined,
    '/admin/exceptions',
    'payments.read',
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

enum _AdminNavSection { workspace, people, operations, control }

const _sectionLabels = <_AdminNavSection, String>{
  _AdminNavSection.workspace: 'WORKSPACE',
  _AdminNavSection.people: 'PEOPLE',
  _AdminNavSection.operations: 'OPERATIONS',
  _AdminNavSection.control: 'CONTROL',
};

bool _isSelected(String path, String location) {
  return path == '/admin' ? location == path : location.startsWith(path);
}

List<_AdminNavDestination> _adminNavDestinationsFor(
  AdminIdentity identity, [
  AdminRuntimeConfig? runtimeConfig,
]) {
  final configuredDestinations = runtimeConfig?.navigationItems
      .map(_AdminNavDestination.fromConfig)
      .toList();
  final source = configuredDestinations ?? _adminNavDestinations;
  return [
    for (final destination in source)
      if (adminIdentityAllows(identity, destination.requiredPermission) &&
          adminCanOpenPath(
            identity,
            destination.path,
            runtimeConfig: runtimeConfig,
          ))
        destination,
  ];
}

bool adminCanOpenPath(
  AdminIdentity identity,
  String path, {
  AdminRuntimeConfig? runtimeConfig,
}) {
  if ((path == '/admin/sms-gateway' ||
          path.startsWith('/admin/sms-gateway/')) &&
      !adminIdentityAllows(identity, 'system_health.read')) {
    return false;
  }
  if ((path == '/admin/exceptions' || path.startsWith('/admin/exceptions/')) &&
      !{
        'payments.read',
        'notifications.read',
        'system_health.read',
      }.every(identity.permissions.contains)) {
    return false;
  }
  final baseline = adminRequiredPermissionForPath(path);
  if (baseline != null && !adminIdentityAllows(identity, baseline)) {
    return false;
  }
  for (final item
      in runtimeConfig?.navigationItems ?? <AdminNavigationItemConfig>[]) {
    if (_isSelected(item.path, path) &&
        !adminIdentityAllows(identity, item.requiredPermission)) {
      return false;
    }
  }
  return true;
}

bool adminIdentityAllows(AdminIdentity identity, String permission) {
  return identity.permissions.contains(permission);
}

String? adminRequiredPermissionForPath(
  String path, {
  AdminRuntimeConfig? runtimeConfig,
}) {
  for (final destination in _adminNavDestinations.reversed) {
    if (_isSelected(destination.path, path)) {
      return destination.requiredPermission;
    }
  }
  for (final item
      in runtimeConfig?.navigationItems.reversed ??
          <AdminNavigationItemConfig>[]) {
    if (_isSelected(item.path, path)) return item.requiredPermission;
  }
  return null;
}

_AdminNavSection _sectionForPath(String path) {
  if (path == '/admin') return _AdminNavSection.workspace;
  if (path.startsWith('/admin/groups') ||
      path.startsWith('/admin/users') ||
      path.startsWith('/admin/members')) {
    return _AdminNavSection.people;
  }
  if (path.startsWith('/admin/payees') ||
      path.startsWith('/admin/transactions') ||
      path.startsWith('/admin/reconciliations') ||
      path.startsWith('/admin/ledgers') ||
      path.startsWith('/admin/sms-receipts') ||
      path.startsWith('/admin/exceptions')) {
    return _AdminNavSection.operations;
  }
  return _AdminNavSection.control;
}

_AdminNavDestination? _destinationForLocation(
  String location,
  List<_AdminNavDestination> destinations,
) {
  for (final destination in destinations.reversed) {
    if (_isSelected(destination.path, location)) return destination;
  }
  return null;
}

void _openMatchingDestination(
  BuildContext context,
  List<_AdminNavDestination> destinations,
  String query,
) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return;
  for (final destination in destinations) {
    if (destination.label.toLowerCase().contains(normalized)) {
      context.go(destination.path);
      return;
    }
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('No admin section matches “${query.trim()}”.')),
  );
}

String _initials(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) return 'CA';
  if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
  return '${words.first[0]}${words.last[0]}'.toUpperCase();
}

String _workspaceTitle(_AdminNavDestination? destination) {
  if (destination == null) return 'Admin';
  if (destination.path == '/admin') return 'Operations overview';
  return destination.label;
}

IconData _adminIconForKey(String iconKey) {
  return switch (iconKey.trim().toLowerCase()) {
    'dashboard' || 'dashboard_outlined' => Icons.home_rounded,
    'groups' || 'folder_copy' => Icons.folder_copy_outlined,
    'person' || 'users' => Icons.person_outline,
    'members' || 'people' => Icons.people_outline,
    'payees' || 'person_pin_circle' => Icons.person_pin_circle_outlined,
    'transactions' => Icons.receipt_long_outlined,
    'reconciliations' => Icons.balance_outlined,
    'ledgers' => Icons.menu_book_outlined,
    'payments' || 'payment_intents' => Icons.payments_outlined,
    'sms_parsing' || 'receipt_long' => Icons.receipt_long_outlined,
    'allocations' || 'account_tree' => Icons.account_tree_outlined,
    'exceptions' || 'warning_amber' => Icons.warning_amber_outlined,
    'call_split' => Icons.call_split_outlined,
    'ledger' || 'account_balance' => Icons.account_balance_outlined,
    'fact_check' => Icons.fact_check_outlined,
    'balance' => Icons.balance_outlined,
    'report_problem' => Icons.report_problem_outlined,
    'rule' => Icons.rule_outlined,
    'menu_book' => Icons.menu_book_outlined,
    'receivers' || 'settings_phone' => Icons.settings_phone_outlined,
    'sms' => Icons.sms_outlined,
    'sms_gateway' ||
    'phonelink_ring' ||
    'router' => Icons.phonelink_ring_outlined,
    'notifications' => Icons.notifications_outlined,
    'automations' || 'manage_search' => Icons.manage_search_outlined,
    'audit' || 'policy' => Icons.policy_outlined,
    'settings' || 'tune' => Icons.tune_outlined,
    'feature_flags' || 'flag' => Icons.flag_outlined,
    'system_health' || 'monitor_heart' => Icons.monitor_heart_outlined,
    'admin_users' ||
    'admin_panel_settings' => Icons.admin_panel_settings_outlined,
    _ => Icons.admin_panel_settings_outlined,
  };
}
