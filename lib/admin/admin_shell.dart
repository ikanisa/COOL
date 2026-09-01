import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/env/app_env.dart';
import '../app/theme/collect_colors.dart';
import '../app/theme/collect_spacing.dart';
import '../app/theme/collect_typography.dart';
import 'core/admin_auth_guard.dart';
import 'core/admin_error_boundary.dart';
import 'core/admin_repository_base.dart';
import 'shared/components/admin_loading_state.dart';

class AdminShell extends ConsumerStatefulWidget {
  const AdminShell({required this.location, required this.child, super.key});

  final String location;
  final Widget child;

  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  var _railCollapsed = false;

  @override
  Widget build(BuildContext context) {
    final env = ref.watch(appEnvProvider);
    final identity = ref.watch(adminIdentityProvider);
    final colors = context.collectColors;
    return Scaffold(
      backgroundColor: colors.canvas,
      body: ColoredBox(
        color: colors.canvas,
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
              widget.location,
              runtimeConfig: runtimeConfig,
            );
            final page =
                adminCanOpenPath(
                  value,
                  widget.location,
                  runtimeConfig: runtimeConfig,
                )
                ? widget.child
                : AdminDeniedPage(requiredPermission: requiredPermission);

            return LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 720;
                const forcedCompactRail = false;
                final collapsed = _railCollapsed || forcedCompactRail;
                final content = Semantics(
                  container: true,
                  label: 'Collect admin workspace',
                  child: Column(
                    children: [
                      _AdminTopbar(
                        envName: env.environmentName,
                        identity: value,
                        location: widget.location,
                        destinations: destinations,
                      ),
                      Expanded(child: page),
                    ],
                  ),
                );
                if (compact) {
                  return Column(
                    children: [
                      _AdminMobileNav(
                        location: widget.location,
                        destinations: destinations,
                      ),
                      Expanded(child: content),
                    ],
                  );
                }
                return Row(
                  children: [
                    _AdminSidebar(
                      location: widget.location,
                      destinations: destinations,
                      collapsed: collapsed,
                      canToggle: !forcedCompactRail,
                      onToggle: () =>
                          setState(() => _railCollapsed = !_railCollapsed),
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

class _AdminSidebar extends StatelessWidget {
  const _AdminSidebar({
    required this.location,
    required this.destinations,
    required this.collapsed,
    required this.canToggle,
    required this.onToggle,
  });

  final String location;
  final List<_AdminNavDestination> destinations;
  final bool collapsed;
  final bool canToggle;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final width = collapsed ? 80.0 : 256.0;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Collect admin primary navigation',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: width,
        child: Material(
          color: CollectColors.referenceChromeBlack,
          child: SafeArea(
            child: Column(
              children: [
                _AdminBrand(collapsed: collapsed),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    children: [
                      for (final section in _AdminNavSection.values) ...[
                        if (!collapsed)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 16, 8, 7),
                            child: Text(
                              _sectionLabels[section]!,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: colors.onImagePrimary.withValues(
                                      alpha: 0.58,
                                    ),
                                    fontWeight: CollectTypography.weightBold,
                                    letterSpacing:
                                        CollectTypography.trackingEyebrow,
                                  ),
                            ),
                          )
                        else if (section != _AdminNavSection.workspace)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Divider(
                              height: 1,
                              color: colors.onImagePrimary.withValues(
                                alpha: 0.10,
                              ),
                            ),
                          ),
                        for (final destination in destinations)
                          if (_sectionForPath(destination.path) == section)
                            _NavItem(
                              destination,
                              location,
                              collapsed: collapsed,
                            ),
                      ],
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  indent: 18,
                  endIndent: 18,
                  color: colors.onImagePrimary.withValues(alpha: 0.12),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Tooltip(
                    message: collapsed ? 'Expand navigation' : 'Collapse',
                    child: TextButton.icon(
                      onPressed: canToggle ? onToggle : null,
                      style: TextButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        foregroundColor: colors.onImagePrimary,
                        alignment: collapsed
                            ? Alignment.center
                            : Alignment.centerLeft,
                      ),
                      icon: Icon(
                        collapsed
                            ? Icons.chevron_right_rounded
                            : Icons.chevron_left_rounded,
                      ),
                      label: collapsed
                          ? const SizedBox.shrink()
                          : const Text('Collapse'),
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

class _AdminBrand extends StatelessWidget {
  const _AdminBrand({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Padding(
      padding: EdgeInsets.fromLTRB(collapsed ? 12 : 20, 10, 12, 12),
      child: Row(
        mainAxisAlignment: collapsed
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.onImagePrimary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: colors.onImagePrimary.withValues(alpha: 0.14),
              ),
            ),
            child: SizedBox.square(
              dimension: 42,
              child: Icon(
                Icons.admin_panel_settings_outlined,
                color: colors.onImagePrimary,
                size: 22,
              ),
            ),
          ),
          if (!collapsed) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Collect Admin',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colors.onImagePrimary,
                      fontWeight: CollectTypography.weightBold,
                    ),
                  ),
                  Text(
                    'Operations',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.onImagePrimary.withValues(alpha: 0.58),
                      fontWeight: CollectTypography.weightMedium,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
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
    final current = _destinationForLocation(location, destinations);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Collect admin mobile navigation',
      child: Material(
        color: CollectColors.referenceChromeBlack,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                const Icon(
                  Icons.admin_panel_settings_outlined,
                  color: CollectColors.brandPaper,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Semantics(
                    label: current == null
                        ? 'Collect Admin'
                        : '${current.label} admin section',
                    excludeSemantics: true,
                    child: Text(
                      current?.label ?? 'Collect Admin',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colors.onImagePrimary,
                        fontWeight: CollectTypography.weightBold,
                      ),
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Open admin navigation',
                  icon: const Icon(
                    Icons.menu_rounded,
                    color: CollectColors.brandPaper,
                  ),
                  onSelected: context.go,
                  itemBuilder: (context) => [
                    for (final section in _AdminNavSection.values) ...[
                      PopupMenuItem<String>(
                        enabled: false,
                        height: 32,
                        child: Text(_sectionLabels[section]!),
                      ),
                      for (final destination in destinations)
                        if (_sectionForPath(destination.path) == section)
                          PopupMenuItem<String>(
                            value: destination.path,
                            child: Semantics(
                              label: '${destination.label} admin section',
                              hint:
                                  'Opens ${destination.label} in the admin console.',
                              excludeSemantics: true,
                              child: Row(
                                children: [
                                  Icon(destination.icon, size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(child: Text(destination.label)),
                                  if (_isSelected(destination.path, location))
                                    const Icon(Icons.check_rounded, size: 18),
                                ],
                              ),
                            ),
                          ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem(this.destination, this.location, {required this.collapsed});

  final _AdminNavDestination destination;
  final String location;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final selected = _isSelected(destination.path, location);
    final colors = context.collectColors;
    final foreground = colors.onImagePrimary;
    final tile = ListTile(
      selected: selected,
      selectedTileColor: colors.onImagePrimary.withValues(alpha: 0.10),
      tileColor: Colors.transparent,
      iconColor: foreground.withValues(alpha: selected ? 1 : 0.78),
      textColor: foreground,
      leading: Icon(destination.icon, size: 20),
      title: collapsed
          ? null
          : Semantics(
              label: '${destination.label} admin section',
              hint: 'Opens ${destination.label} in the admin console.',
              excludeSemantics: true,
              child: Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: foreground.withValues(alpha: selected ? 1 : 0.84),
                  fontWeight: selected
                      ? CollectTypography.weightBold
                      : CollectTypography.weightMedium,
                ),
              ),
            ),
      minTileHeight: CollectSpacing.iconTarget,
      minLeadingWidth: collapsed ? 0 : null,
      contentPadding: EdgeInsets.symmetric(horizontal: collapsed ? 16 : 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onTap: () => context.go(destination.path),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Semantics(
        label: collapsed ? '${destination.label} admin section' : null,
        hint: collapsed
            ? 'Opens ${destination.label} in the admin console.'
            : null,
        button: collapsed,
        child: collapsed
            ? Tooltip(message: destination.label, child: tile)
            : tile,
      ),
    );
  }
}

bool _isSelected(String path, String location) {
  return path == '/admin' ? location == path : location.startsWith(path);
}

class _AdminTopbar extends ConsumerWidget {
  const _AdminTopbar({
    required this.envName,
    required this.identity,
    required this.location,
    required this.destinations,
  });

  final String envName;
  final AdminIdentity identity;
  final String location;
  final List<_AdminNavDestination> destinations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.collectColors;
    final current = _destinationForLocation(location, destinations);
    return Semantics(
      container: true,
      label:
          'Signed in as ${identity.displayName}. Roles: ${identity.roles.join(', ')}. Environment: $envName.',
      child: Material(
        color: CollectColors.referenceChromeBlack,
        child: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 760;
              final showSearch = constraints.maxWidth >= 620;
              final showIdentity = constraints.maxWidth >= 900;
              return Container(
                constraints: BoxConstraints(minHeight: compact ? 64 : 88),
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 14 : 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: colors.onImagePrimary.withValues(alpha: 0.10),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              InkWell(
                                onTap: () => context.go('/admin'),
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox.square(
                                  dimension: 44,
                                  child: Center(
                                    child: Icon(
                                      Icons.home_outlined,
                                      size: 19,
                                      color: colors.onImagePrimary.withValues(
                                        alpha: 0.60,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: colors.onImagePrimary.withValues(
                                  alpha: 0.44,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  _workspaceTitle(current),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        color: colors.onImagePrimary,
                                        fontWeight:
                                            CollectTypography.weightBold,
                                      ),
                                ),
                              ),
                            ],
                          ),
                          if (!compact) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.refresh_rounded,
                                  size: 15,
                                  color: colors.onImagePrimary.withValues(
                                    alpha: 0.54,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Last refreshed: ${_clockTime(DateTime.now())}',
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        color: colors.onImagePrimary.withValues(
                                          alpha: 0.62,
                                        ),
                                      ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (showSearch) ...[
                      const SizedBox(width: 16),
                      SizedBox(
                        width: constraints.maxWidth >= 1100 ? 280 : 210,
                        height: 46,
                        child: TextField(
                          textInputAction: TextInputAction.search,
                          onSubmitted: (query) => _openMatchingDestination(
                            context,
                            destinations,
                            query,
                          ),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colors.onImagePrimary),
                          decoration: InputDecoration(
                            hintText: 'Search or press ⌘K',
                            hintStyle: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: colors.onImagePrimary.withValues(
                                    alpha: 0.56,
                                  ),
                                ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: colors.onImagePrimary.withValues(
                                alpha: 0.62,
                              ),
                            ),
                            filled: true,
                            fillColor: colors.onImagePrimary.withValues(
                              alpha: 0.04,
                            ),
                            contentPadding: EdgeInsets.zero,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: colors.onImagePrimary.withValues(
                                  alpha: 0.18,
                                ),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: colors.onImagePrimary.withValues(
                                  alpha: 0.18,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 14),
                    _EnvironmentBadge(envName: envName),
                    const SizedBox(width: 12),
                    PopupMenuButton<String>(
                      tooltip: 'Operator menu',
                      onSelected: (value) async {
                        if (value != 'sign-out') return;
                        await ref.read(adminRepositoryProvider).signOut();
                        ref.invalidate(adminAuthStateProvider);
                        ref.invalidate(adminAuthGuardProvider);
                        ref.invalidate(adminIdentityProvider);
                        if (context.mounted) context.go('/admin/login');
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'sign-out',
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.logout_rounded),
                            title: Text('Sign out'),
                          ),
                        ),
                      ],
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: colors.onImagePrimary.withValues(
                              alpha: 0.10,
                            ),
                            foregroundColor: colors.onImagePrimary,
                            child: Text(
                              _initials(identity.displayName),
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: colors.onImagePrimary,
                                    fontWeight: CollectTypography.weightBold,
                                  ),
                            ),
                          ),
                          if (showIdentity) ...[
                            const SizedBox(width: 9),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 120),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    identity.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          color: colors.onImagePrimary,
                                          fontWeight:
                                              CollectTypography.weightBold,
                                        ),
                                  ),
                                  Text(
                                    identity.roles.isEmpty
                                        ? 'Operator'
                                        : identity.roles.first.replaceAll(
                                            '_',
                                            ' ',
                                          ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: colors.onImagePrimary
                                              .withValues(alpha: 0.62),
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_drop_down_rounded,
                              color: colors.onImagePrimary.withValues(
                                alpha: 0.56,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _EnvironmentBadge extends StatelessWidget {
  const _EnvironmentBadge({required this.envName});

  final String envName;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.onImagePrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colors.onImagePrimary.withValues(alpha: 0.14),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        child: Text(
          envName.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colors.onImagePrimary,
            fontWeight: CollectTypography.weightBold,
            letterSpacing: CollectTypography.trackingMeta,
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
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.error,
          ),
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

_AdminNavSection _sectionForPath(String path) {
  if (path == '/admin') return _AdminNavSection.workspace;
  if (path.startsWith('/admin/groups') || path.startsWith('/admin/members')) {
    return _AdminNavSection.people;
  }
  if (path.startsWith('/admin/payees') ||
      path.startsWith('/admin/transactions') ||
      path.startsWith('/admin/reconciliations') ||
      path.startsWith('/admin/ledgers')) {
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

String _clockTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}';
}

String _workspaceTitle(_AdminNavDestination? destination) {
  if (destination == null) return 'Admin workspace';
  if (destination.path == '/admin') return 'Operations overview';
  return '${destination.label} workspace';
}

IconData _adminIconForKey(String iconKey) {
  return switch (iconKey.trim().toLowerCase()) {
    'dashboard' || 'dashboard_outlined' => Icons.home_rounded,
    'groups' || 'folder_copy' => Icons.folder_copy_outlined,
    'members' || 'people' => Icons.people_outline,
    'payees' || 'person_pin_circle' => Icons.person_pin_circle_outlined,
    'transactions' => Icons.receipt_long_outlined,
    'reconciliations' => Icons.balance_outlined,
    'ledgers' => Icons.menu_book_outlined,
    'payments' || 'payment_intents' => Icons.payments_outlined,
    'sms_parsing' || 'receipt_long' => Icons.receipt_long_outlined,
    'allocations' || 'account_tree' => Icons.account_tree_outlined,
    'exceptions' || 'call_split' => Icons.call_split_outlined,
    'ledger' || 'account_balance' => Icons.account_balance_outlined,
    'fact_check' => Icons.fact_check_outlined,
    'balance' => Icons.balance_outlined,
    'report_problem' => Icons.report_problem_outlined,
    'rule' => Icons.rule_outlined,
    'menu_book' => Icons.menu_book_outlined,
    'receivers' || 'settings_phone' => Icons.settings_phone_outlined,
    'sms' => Icons.sms_outlined,
    'notifications' => Icons.notifications_outlined,
    'audit' || 'policy' => Icons.policy_outlined,
    'settings' || 'tune' => Icons.tune_outlined,
    'feature_flags' || 'flag' => Icons.flag_outlined,
    'system_health' || 'monitor_heart' => Icons.monitor_heart_outlined,
    'admin_users' ||
    'admin_panel_settings' => Icons.admin_panel_settings_outlined,
    _ => Icons.admin_panel_settings_outlined,
  };
}
