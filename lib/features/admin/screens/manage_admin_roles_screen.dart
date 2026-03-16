import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../models/admin_workspace_access.dart';
import '../providers/admin_workspace_access_provider.dart';
import '../providers/admin_providers.dart';

/// Super admin screen for managing admin role assignments.
/// Allows viewing, assigning, and revoking admin/bank/rayon_sport roles.
class ManageAdminRolesScreen extends ConsumerWidget {
  const ManageAdminRolesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignmentsAsync = ref.watch(adminRoleAssignmentsProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.text),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAssignRoleSheet(context, ref),
        backgroundColor: AppColors.blue,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_rounded, size: 20),
        label: Text(
          'Assign Role',
          style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
        ),
      ),
      body: CoolAsyncView<List<AdminRoleAssignment>>(
        value: assignmentsAsync,
        onRetry: () => ref.invalidate(adminRoleAssignmentsProvider),
        loadingWidget: const Padding(
          padding: EdgeInsets.fromLTRB(18, 0, 18, 16),
          child: CoolSkeletonList(itemCount: 4),
        ),
        emptyCheck: (a) => a.isEmpty,
        emptyWidget: const CoolEmptyView(
          message: 'No admin roles assigned yet',
          icon: Icons.admin_panel_settings_outlined,
        ),
        builder: (assignments) {
          final adminCount =
              assignments.where((a) => a.role == AdminRole.admin).length;
          final bankCount =
              assignments.where((a) => a.role == AdminRole.bank).length;
          final rayonCount =
              assignments.where((a) => a.role == AdminRole.rayonSport).length;

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 96),
            itemCount: assignments.length + 1,
            separatorBuilder: (_, index) => SizedBox(
              height: index == 0 ? 24 : 12,
            ),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Admin Roles',
                      style: GoogleFonts.dmSans(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _SummaryCard(
                      totalAssignments: assignments.length,
                      adminCount: adminCount,
                      bankCount: bankCount,
                      rayonCount: rayonCount,
                    ),
                  ],
                );
              }

              return _RoleAssignmentTile(
                assignment: assignments[index - 1],
              );
            },
          );
        },
      ),
    );
  }

  void _showAssignRoleSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _AssignRoleSheet(ref: ref),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Summary card
// ═══════════════════════════════════════════════════════════════

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.totalAssignments,
    required this.adminCount,
    required this.bankCount,
    required this.rayonCount,
  });

  final int totalAssignments;
  final int adminCount;
  final int bankCount;
  final int rayonCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Role Distribution',
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MetricChip(
                  label: 'Total',
                  value: totalAssignments.toString(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricChip(
                  label: 'Admin',
                  value: adminCount.toString(),
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _MetricChip(
                  label: 'Bank',
                  value: bankCount.toString(),
                  color: AppColors.blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricChip(
                  label: 'Rayon',
                  value: rayonCount.toString(),
                  color: Colors.purple,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.dmSans(color: AppColors.text),
          children: [
            TextSpan(
              text: '$value ',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            TextSpan(
              text: label,
              style: TextStyle(
                color: AppColors.text3,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Role assignment tile
// ═══════════════════════════════════════════════════════════════

class _RoleAssignmentTile extends ConsumerStatefulWidget {
  const _RoleAssignmentTile({required this.assignment});

  final AdminRoleAssignment assignment;

  @override
  ConsumerState<_RoleAssignmentTile> createState() =>
      _RoleAssignmentTileState();
}

class _RoleAssignmentTileState extends ConsumerState<_RoleAssignmentTile> {
  bool _isRevoking = false;

  Color get _roleColor {
    switch (widget.assignment.role) {
      case AdminRole.admin:
        return Colors.green;
      case AdminRole.bank:
        return AppColors.blue;
      case AdminRole.rayonSport:
        return Colors.purple;
    }
  }

  Future<void> _revoke() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Revoke Role?',
          style: GoogleFonts.dmSans(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        content: Text(
          'This will remove ${widget.assignment.role.label} access'
          '${widget.assignment.partnerName != null ? ' for ${widget.assignment.partnerName}' : ''}'
          ' from this user. They can be re-assigned later.',
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: AppColors.text3,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isRevoking = true);
    try {
      final repo = ref.read(adminRoleRepositoryProvider);
      await repo.revokeRole(assignmentId: widget.assignment.id);
      ref.invalidate(adminRoleAssignmentsProvider);
      if (!mounted) return;
      CoolToast.success(context, 'Role revoked successfully.');
    } catch (error) {
      if (!mounted) return;
      CoolToast.error(context, 'Failed to revoke: $error');
    } finally {
      if (mounted) setState(() => _isRevoking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.assignment;
    final displayName = a.userName ?? a.userPhone ?? a.userId;
    final grantedDate = '${a.grantedAt.day}/${a.grantedAt.month}/${a.grantedAt.year}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    if (a.userPhone != null && a.userName != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        a.userPhone!,
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _roleColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  a.role.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _roleColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (a.partnerName != null)
            Text(
              'Scope: ${a.partnerName}',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.text3,
              ),
            ),
          Text(
            'Granted: $grantedDate',
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: AppColors.text3,
            ),
          ),
          if (a.notes != null && a.notes!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              a.notes!,
              style: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: AppColors.text3,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _isRevoking ? null : _revoke,
              icon: _isRevoking
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CupertinoActivityIndicator(radius: 7),
                    )
                  : const Icon(Icons.remove_circle_outline_rounded, size: 16),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              label: Text(
                'Revoke',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Assign role bottom sheet
// ═══════════════════════════════════════════════════════════════

class _AssignRoleSheet extends ConsumerStatefulWidget {
  const _AssignRoleSheet({required this.ref});

  final WidgetRef ref;

  @override
  ConsumerState<_AssignRoleSheet> createState() => _AssignRoleSheetState();
}

class _AssignRoleSheetState extends ConsumerState<_AssignRoleSheet> {
  final _userIdController = TextEditingController();
  AdminRole _selectedRole = AdminRole.admin;
  String? _selectedPartnerId;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _userIdController.dispose();
    super.dispose();
  }

  bool get _needsPartnerScope =>
      _selectedRole == AdminRole.bank || _selectedRole == AdminRole.rayonSport;

  Future<void> _submit() async {
    final userId = _userIdController.text.trim();
    if (userId.isEmpty) {
      CoolToast.error(context, 'Please enter a user ID.');
      return;
    }
    if (_needsPartnerScope && (_selectedPartnerId == null || _selectedPartnerId!.isEmpty)) {
      CoolToast.error(context, 'Please select a partner scope.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(adminRoleRepositoryProvider);
      await repo.assignRole(
        targetUserId: userId,
        role: _selectedRole,
        partnerScopeId: _needsPartnerScope ? _selectedPartnerId : null,
      );
      ref.invalidate(adminRoleAssignmentsProvider);
      if (!mounted) return;
      CoolToast.success(context, '${_selectedRole.label} role assigned.');
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      CoolToast.error(context, 'Failed: $error');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final partnersAsync = ref.watch(adminPartnersProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Assign Admin Role',
              style: GoogleFonts.dmSans(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 24),

            // User ID input
            Text(
              'User ID',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _userIdController,
              style: GoogleFonts.dmSans(color: AppColors.text, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Paste user UUID',
                hintStyle:
                    GoogleFonts.dmSans(color: AppColors.text3, fontSize: 14),
                filled: true,
                fillColor: AppColors.bg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                suffixIcon: IconButton(
                  icon: Icon(Icons.paste_rounded,
                      size: 18, color: AppColors.text3),
                  onPressed: () async {
                    final clipboard = await Clipboard.getData('text/plain');
                    if (clipboard?.text != null) {
                      _userIdController.text = clipboard!.text!;
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Role selector
            Text(
              'Role',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: AdminRole.values.map((role) {
                final isSelected = role == _selectedRole;
                return ChoiceChip(
                  label: Text(role.label),
                  selected: isSelected,
                  onSelected: (_) => setState(() {
                    _selectedRole = role;
                    if (!_needsPartnerScope) _selectedPartnerId = null;
                  }),
                  backgroundColor: AppColors.bg,
                  selectedColor: AppColors.blue.withValues(alpha: 0.2),
                  labelStyle: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? AppColors.blue : AppColors.text3,
                  ),
                  side: BorderSide(
                    color: isSelected ? AppColors.blue : AppColors.border,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Partner scope selector (if needed)
            if (_needsPartnerScope) ...[
              Text(
                'Partner Scope',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 8),
              partnersAsync.when(
                data: (partners) {
                  final filtered = _selectedRole == AdminRole.bank
                      ? partners
                          .where((p) =>
                              p['category']?.toString() == 'bank')
                          .toList()
                      : partners
                          .where((p) =>
                              p['category']?.toString() == 'football')
                          .toList();
                  return DropdownButtonFormField<String>(
                    value: _selectedPartnerId,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.bg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                    ),
                    hint: Text(
                      'Select partner',
                      style: GoogleFonts.dmSans(
                          color: AppColors.text3, fontSize: 14),
                    ),
                    dropdownColor: AppColors.surface,
                    items: filtered
                        .map((p) => DropdownMenuItem(
                              value: p['id']?.toString(),
                              child: Text(
                                p['name']?.toString() ?? 'Unknown',
                                style: GoogleFonts.dmSans(
                                  color: AppColors.text,
                                  fontSize: 14,
                                ),
                              ),
                            ))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _selectedPartnerId = value),
                  );
                },
                loading: () => const Center(
                  child: CupertinoActivityIndicator(radius: 10),
                ),
                error: (e, _) => Text(
                  'Failed to load partners',
                  style: GoogleFonts.dmSans(
                      color: Colors.red, fontSize: 12),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Submit button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CupertinoActivityIndicator(
                          radius: 10,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Assign Role',
                        style: GoogleFonts.dmSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
