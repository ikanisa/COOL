import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/admin_detail_scaffold.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
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

/// Super admin screen for managing admin role assignments.
/// Allows viewing, assigning, and revoking admin/bank roles.
class ManageAdminRolesScreen extends ConsumerWidget {
  const ManageAdminRolesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final assignmentsAsync = ref.watch(adminRoleAssignmentsProvider);

    return AdminDetailScaffold(
      title: Text(
        'Admin Roles',
        style: theme.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
      subtitle: Text(
        'Assign and revoke access',
        style: theme.textTheme.bodySmall?.copyWith(
          color: context.coolSemanticColors.tertiaryText,
          fontWeight: FontWeight.w600,
        ),
      ),
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
          child: const Icon(Icons.add_rounded, size: 28),
        ),
      ),
      child: CoolAsyncView<List<AdminRoleAssignment>>(
        value: assignmentsAsync,
        onRetry: () => ref.invalidate(adminRoleAssignmentsProvider),
        loadingWidget: const Padding(
          padding: EdgeInsets.only(bottom: CoolSpace.x7),
          child: CoolSkeletonList(itemCount: 4),
        ),
        emptyCheck: (a) => a.isEmpty,
        emptyWidget: const CoolEmptyView(
          message: 'No admin roles yet',
          icon: Icons.admin_panel_settings_outlined,
        ),
        builder: (assignments) {
          final adminCount = assignments
              .where((a) => a.role == AdminRole.admin)
              .length;
          final bankCount = assignments
              .where((a) => a.role == AdminRole.bank)
              .length;

          return ListView.separated(
            padding: const EdgeInsets.only(bottom: CoolSpace.x7),
            itemCount: assignments.length + 1,
            separatorBuilder: (_, index) =>
                SizedBox(height: index == 0 ? 24 : 12),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _SummaryCard(
                  totalAssignments: assignments.length,
                  adminCount: adminCount,
                  bankCount: bankCount,
                );
              }

              return _RoleAssignmentTile(assignment: assignments[index - 1]);
            },
          );
        },
      ),
    );
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

// ═══════════════════════════════════════════════════════════════
// Summary card
// ═══════════════════════════════════════════════════════════════
