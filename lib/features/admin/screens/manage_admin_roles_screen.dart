import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/admin_detail_scaffold.dart';
import '../../../shared/widgets/admin_workspace_kit.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_chip_bar.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../models/admin_workspace_access.dart';
import '../providers/admin_providers.dart';
import '../providers/admin_workspace_access_provider.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';

part '../widgets/manage_admin_roles_parts.dart';
part '../widgets/manage_admin_roles_assignment_sheet.dart';

enum _RoleInventoryFilter { all, platform, bank }

/// Super admin screen for managing admin role assignments.
/// Allows viewing, assigning, and revoking admin/bank roles.
class ManageAdminRolesScreen extends ConsumerStatefulWidget {
  const ManageAdminRolesScreen({super.key});

  @override
  ConsumerState<ManageAdminRolesScreen> createState() =>
      _ManageAdminRolesScreenState();
}

class _ManageAdminRolesScreenState
    extends ConsumerState<ManageAdminRolesScreen> {
  _RoleInventoryFilter _filter = _RoleInventoryFilter.all;

  @override
  Widget build(BuildContext context) {
    final assignmentsAsync = ref.watch(adminRoleAssignmentsProvider);

    return AdminDetailScaffold(
      floatingActionButton: Semantics(
        button: true,
        label: 'Assign admin role',
        hint: 'Open role assignment form',
        child: FloatingActionButton(
          onPressed: () => _showAssignRoleSheet(context, ref),
          backgroundColor: context.coolSemanticColors.accent,
          foregroundColor: context.coolSemanticColors.accentForeground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CoolRadii.lg),
          ),
          child: const Icon(CoolIcons.add, size: 28),
        ),
      ),
      child: CoolAsyncView<List<AdminRoleAssignment>>(
        value: assignmentsAsync,
        onRetry: () => ref.invalidate(adminRoleAssignmentsProvider),
        loadingWidget: const Padding(
          padding: EdgeInsets.fromLTRB(
            CoolSpace.x5,
            0,
            CoolSpace.x5,
            CoolSpace.x7,
          ),
          child: CoolSkeletonList(itemCount: 4),
        ),
        emptyCheck: (items) => items.isEmpty,
        emptyWidget: const Padding(
          padding: EdgeInsets.all(CoolSpace.x5),
          child: CoolEmptyView(
            message: 'No admin roles yet',
            icon: CoolIcons.adminPanel,
          ),
        ),
        builder: (assignments) {
          final filtered = assignments
              .where((assignment) => _matchesRoleFilter(assignment, _filter))
              .toList(growable: false);
          final platformCount = assignments
              .where((assignment) => assignment.role == AdminRole.admin)
              .length;
          final bankCount = assignments
              .where((assignment) => assignment.role == AdminRole.bank)
              .length;
          final bankScopes = assignments
              .where((assignment) => assignment.role == AdminRole.bank)
              .map(
                (assignment) => assignment.bankId ?? assignment.bankName ?? '',
              )
              .where((scope) => scope.isNotEmpty)
              .toSet()
              .length;

          return ListView(
            padding: CoolSpace.scaffoldPadding,
            children: [
              AdminPageHeader(
                eyebrow: 'ACCESS CONTROL',
                title: 'Admin Roles',
                subtitle:
                    'Role assignments, scope, grant date, and revoke actions.',
                actions: [
                  OutlinedButton.icon(
                    onPressed: () => _showAssignRoleSheet(context, ref),
                    icon: const Icon(CoolIcons.add, size: 18),
                    label: const Text('Assign'),
                  ),
                ],
                badges: [
                  AdminStatusChip(
                    label: 'Assignments',
                    trailing: '${assignments.length}',
                    tone: AdminTone.accent,
                    icon: CoolIcons.badge,
                  ),
                ],
              ),
              const SizedBox(height: CoolSpace.x4),
              AdminMetricStrip(
                metrics: [
                  AdminMetricItem(
                    label: 'Assignments',
                    value: '${assignments.length}',
                    hint: 'Active grants',
                    icon: CoolIcons.badge,
                    tone: AdminTone.info,
                  ),
                  AdminMetricItem(
                    label: 'Platform',
                    value: '$platformCount',
                    hint: 'Global access',
                    icon: CoolIcons.adminPanel,
                    tone: AdminTone.success,
                  ),
                  AdminMetricItem(
                    label: 'Bank',
                    value: '$bankCount',
                    hint: 'Scoped workspaces',
                    icon: CoolIcons.accountBalanceOutlined,
                    tone: AdminTone.accent,
                  ),
                  AdminMetricItem(
                    label: 'Bank scopes',
                    value: '$bankScopes',
                    hint: 'Distinct banks',
                    icon: CoolIcons.accountTree,
                    tone: AdminTone.warning,
                  ),
                ],
              ),
              const SizedBox(height: CoolSpace.x4),
              AdminToolbar(
                filters: [
                  CoolChipBar(
                    scrollable: true,
                    expand: false,
                    items: _RoleInventoryFilter.values
                        .map(
                          (filter) => CoolChipItem(
                            label: _roleFilterLabel(filter),
                            count: _countForFilter(assignments, filter),
                            isActive: _filter == filter,
                            onTap: () => setState(() => _filter = filter),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
              ),
              const SizedBox(height: CoolSpace.x4),
              AdminDataTableCard(
                title: 'Role Ledger',
                subtitle:
                    'Grant history kept visible, revoke path kept direct.',
                emptyLabel: 'No assignments match the current filter',
                minWidth: 940,
                columns: const [
                  DataColumn(label: Text('User')),
                  DataColumn(label: Text('Role')),
                  DataColumn(label: Text('Scope')),
                  DataColumn(label: Text('Granted')),
                  DataColumn(label: Text('Notes')),
                  DataColumn(label: Text('Action')),
                ],
                rows: filtered
                    .map(
                      (assignment) => _buildAssignmentRow(context, assignment),
                    )
                    .toList(growable: false),
                footer: Text(
                  '${filtered.length} assignment${filtered.length == 1 ? '' : 's'} visible',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.coolSemanticColors.tertiaryText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  DataRow _buildAssignmentRow(
    BuildContext context,
    AdminRoleAssignment assignment,
  ) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final displayName =
        assignment.userName ?? assignment.userPhone ?? assignment.userId;
    final secondary =
        assignment.userName != null && assignment.userPhone != null
        ? assignment.userPhone!
        : assignment.userId;
    final scope = assignment.role == AdminRole.bank
        ? assignment.bankName ?? assignment.bankId ?? 'Scoped bank'
        : 'All workspaces';
    final granted =
        '${assignment.grantedAt.year}-${assignment.grantedAt.month.toString().padLeft(2, '0')}-${assignment.grantedAt.day.toString().padLeft(2, '0')}';

    return DataRow(
      cells: [
        DataCell(
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                secondary,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.tertiaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        DataCell(
          AdminStatusChip(
            label: assignment.role.label,
            tone: assignment.role == AdminRole.admin
                ? AdminTone.success
                : AdminTone.accent,
            icon: assignment.role == AdminRole.admin
                ? CoolIcons.shield
                : CoolIcons.accountBalanceOutlined,
          ),
        ),
        DataCell(
          Text(
            scope,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.secondaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        DataCell(
          Text(
            granted,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        DataCell(
          Text(
            assignment.notes?.trim().isNotEmpty == true
                ? assignment.notes!
                : '—',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.secondaryText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        DataCell(
          OutlinedButton.icon(
            onPressed: () => _revokeAssignment(assignment),
            icon: const Icon(CoolIcons.removeCircle, size: 16),
            label: const Text('Revoke'),
          ),
        ),
      ],
    );
  }

  Future<void> _revokeAssignment(AdminRoleAssignment assignment) async {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: colors.overlaySurface,
        title: Text(
          'Revoke Role',
          style: theme.textTheme.titleLarge?.copyWith(
            color: colors.primaryText,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          'Remove ${assignment.role.label}'
          '${assignment.bankName != null ? ' for ${assignment.bankName}' : ''}?'
          ' This user can be assigned again later.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.secondaryText,
            fontWeight: FontWeight.w500,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colors.danger,
              foregroundColor: colors.accentForeground,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.revoke),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      final repo = ref.read(adminRoleRepositoryProvider);
      await repo.revokeRole(assignmentId: assignment.id);
      ref.invalidate(adminRoleAssignmentsProvider);
      if (!mounted) {
        return;
      }
      CoolToast.success(context, 'Role revoked.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      CoolToast.error(context, 'Failed: $error');
    }
  }

  void _showAssignRoleSheet(BuildContext context, WidgetRef ref) {
    showCoolBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AssignRoleSheet(ref: ref),
    );
  }
}

bool _matchesRoleFilter(
  AdminRoleAssignment assignment,
  _RoleInventoryFilter filter,
) {
  return switch (filter) {
    _RoleInventoryFilter.all => true,
    _RoleInventoryFilter.platform => assignment.role == AdminRole.admin,
    _RoleInventoryFilter.bank => assignment.role == AdminRole.bank,
  };
}

String _roleFilterLabel(_RoleInventoryFilter filter) {
  return switch (filter) {
    _RoleInventoryFilter.all => 'All',
    _RoleInventoryFilter.platform => 'Platform',
    _RoleInventoryFilter.bank => 'Bank',
  };
}

int _countForFilter(
  List<AdminRoleAssignment> assignments,
  _RoleInventoryFilter filter,
) {
  return assignments
      .where((assignment) => _matchesRoleFilter(assignment, filter))
      .length;
}
