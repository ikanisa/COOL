import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/cool_foundations.dart';
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
import '../../../shared/widgets/cool_screen_background.dart';

part '../widgets/manage_admin_roles_parts.dart';

/// Super admin screen for managing admin role assignments.
/// Allows viewing, assigning, and revoking admin/bank/rayon_sport roles.
class ManageAdminRolesScreen extends ConsumerWidget {
  const ManageAdminRolesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final assignmentsAsync = ref.watch(adminRoleAssignmentsProvider);

    return CoolScreenBackground(
      showGlow: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            onPressed: () => Navigator.of(context).pop(),
            tooltip: context.l10n.back,
            icon: Icon(Icons.arrow_back_rounded, color: colors.primaryText),
          ),
        ),
        floatingActionButton: Semantics(
          button: true,
          label: 'Assign admin role',
          hint: 'Open role assignment form',
          child: FloatingActionButton(
            onPressed: () => _showAssignRoleSheet(context, ref),
            backgroundColor: colors.accent,
            foregroundColor: colors.accentForeground,
            shape: const CircleBorder(),
            child: const Icon(Icons.add_rounded, size: 28),
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: CoolSpace.pagePadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Admin Roles',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      color: colors.primaryText,
                    ),
                  ),
                  const SizedBox(height: CoolSpace.x1),
                  Text(
                    'Assign and revoke access',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.tertiaryText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: CoolSpace.x4),
            Expanded(
              child: CoolAsyncView<List<AdminRoleAssignment>>(
                value: assignmentsAsync,
                onRetry: () => ref.invalidate(adminRoleAssignmentsProvider),
                loadingWidget: const Padding(
                  padding: CoolSpace.scaffoldPadding,
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

                  return ListView.separated(
                    padding: CoolSpace.scaffoldPadding,
                    itemCount: assignments.length + 1,
                    separatorBuilder: (_, index) =>
                        SizedBox(height: index == 0 ? 24 : 12),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _SummaryCard(
                          totalAssignments: assignments.length,
                          adminCount: adminCount,
                        );
                      }

                      return _RoleAssignmentTile(
                        assignment: assignments[index - 1],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
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
