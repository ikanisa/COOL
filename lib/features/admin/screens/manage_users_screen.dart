import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/app_market.dart';
import '../../../core/identity/public_user_identity.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../providers/admin_providers.dart';

/// Admin screen for inspecting user profiles, toggling admin status, editing
/// user fields, and cleaning demo data.
class ManageUsersScreen extends ConsumerStatefulWidget {
  const ManageUsersScreen({super.key});

  @override
  ConsumerState<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends ConsumerState<ManageUsersScreen> {
  String _search = '';  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(adminUsersProvider);

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
      body: CoolAsyncView<List<Map<String, dynamic>>>(
        value: usersAsync,
        onRetry: () => ref.invalidate(adminUsersProvider),
        loadingWidget: const Padding(
          padding: EdgeInsets.fromLTRB(18, 0, 18, 16),
          child: CoolSkeletonList(itemCount: 5),
        ),
        emptyCheck: (u) => u.isEmpty,
        emptyWidget: const CoolEmptyView(
          message: 'No users were returned',
          icon: Icons.person_outline_rounded,
        ),
        builder: (users) {
          final mockCount = users.where((user) => user['is_mock'] == true).length;
          final adminCount =
              users.where((user) => user['is_admin'] == true).length;
          final driverCount =
              users.where((user) => user['is_driver'] == true).length;
          final verifiedCount = users
              .where((user) => user['kyc_status']?.toString() == 'verified')
              .length;
          final momoCount = users
              .where((user) =>
                  (user['momo_number']?.toString() ?? '').isNotEmpty)
              .length;
          final mockBatches =
              users
                  .map((user) => user['mock_batch']?.toString().trim() ?? '')
                  .where((batch) => batch.isNotEmpty)
                  .toSet()
                  .toList(growable: false)
                ..sort();

          // Filter by search
          final query = _search.trim().toLowerCase();
          final filtered = query.isEmpty
              ? users
              : users.where((u) {
                  final name =
                      (u['full_name']?.toString() ?? '').toLowerCase();
                  final phone = (u['phone']?.toString() ?? '').toLowerCase();
                  final id = (u['id']?.toString() ?? '').toLowerCase();
                  return name.contains(query) ||
                      phone.contains(query) ||
                      id.contains(query);
                }).toList();

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 96),
            itemCount: filtered.length + 1,
            separatorBuilder:
                (_, index) =>
                    index == 0
                        ? const SizedBox(height: 16)
                        : const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Manage Users',
                      style: GoogleFonts.dmSans(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Search bar ────────────────────────────
                    TextField(
                      onChanged: (v) => setState(() => _search = v),
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        color: AppColors.text,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search by name, phone, or ID…',
                        hintStyle: GoogleFonts.dmSans(
                          fontSize: 13,
                          color: AppColors.text3,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: AppColors.text3,
                        ),
                        filled: true,
                        fillColor: AppColors.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: AppColors.accent,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    _SummaryCard(
                      totalUsers: users.length,
                      mockUsers: mockCount,
                      adminUsers: adminCount,
                      driverUsers: driverCount,
                      verifiedUsers: verifiedCount,
                      momoUsers: momoCount,
                      mockBatches: mockBatches,
                    ),
                    if (query.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${filtered.length} result${filtered.length == 1 ? '' : 's'}',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text3,
                        ),
                      ),
                    ],
                  ],
                );
              }

              return _UserTile(
                user: filtered[index - 1],
                onEdit: () => _openEditSheet(context, filtered[index - 1]),
              );
            },
          );
        },
      ),
    );
  }

  void _openEditSheet(BuildContext context, Map<String, dynamic> user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditUserSheet(
        user: user,
        onSaved: () => ref.invalidate(adminUsersProvider),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.totalUsers,
    required this.mockUsers,
    required this.adminUsers,
    required this.driverUsers,
    required this.verifiedUsers,
    required this.momoUsers,
    required this.mockBatches,
  });

  final int totalUsers;
  final int mockUsers;
  final int adminUsers;
  final int driverUsers;
  final int verifiedUsers;
  final int momoUsers;
  final List<String> mockBatches;

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
            'User Inventory',
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Demo users are tagged',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.text3,
            ),
          ),
          const SizedBox(height: 12),
          Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _MetricChip(
                      label: 'Total',
                      value: totalUsers.toString(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MetricChip(
                      label: 'Mock',
                      value: mockUsers.toString(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _MetricChip(
                      label: 'Admins',
                      value: adminUsers.toString(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MetricChip(
                      label: 'Drivers',
                      value: driverUsers.toString(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _MetricChip(
                      label: 'Verified',
                      value: verifiedUsers.toString(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MetricChip(
                      label: 'MoMo',
                      value: momoUsers.toString(),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (mockBatches.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Cleanup',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final batch in mockBatches)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _BatchCleanupButton(batch: batch),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

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
              style: const TextStyle(fontWeight: FontWeight.w700),
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

class _UserTile extends ConsumerWidget {
  const _UserTile({required this.user, required this.onEdit});

  final Map<String, dynamic> user;
  final VoidCallback onEdit;

  Future<void> _toggleAdmin(BuildContext context, WidgetRef ref) async {
    final userId = user['id']?.toString();
    if (userId == null || userId.isEmpty) return;

    final isAdmin = user['is_admin'] == true;
    final action = isAdmin ? 'Remove admin' : 'Make admin';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          '$action?',
          style: GoogleFonts.dmSans(
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        content: Text(
          'This will ${isAdmin ? "remove" : "grant"} platform admin access for this user.',
          style: GoogleFonts.dmSans(color: AppColors.text3),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await ref
          .read(adminRepositoryProvider)
          .toggleUserAdmin(userId, !isAdmin);
      ref.invalidate(adminUsersProvider);
      if (context.mounted) {
        CoolToast.success(
          context,
          isAdmin ? 'Admin access removed' : 'Admin access granted',
        );
      }
    } catch (e) {
      if (context.mounted) {
        CoolToast.error(
          context,
          'Failed: $e',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final publicUserId = PublicUserIdentity.resolve(
      publicUserId: user['public_user_id']?.toString(),
      userId: user['id']?.toString(),
      phone: user['phone']?.toString(),
    );
    final momoProvider = user['momo_provider']?.toString().trim() ?? '';
    final momoNumber = user['momo_number']?.toString().trim() ?? '';
    final vehicleType = user['vehicle_type']?.toString().trim() ?? '';
    final createdAt = user['created_at']?.toString().trim() ?? '';
    final kycStatus = user['kyc_status']?.toString().trim() ?? '';
    final isMock = user['is_mock'] == true;
    final isAdmin = user['is_admin'] == true;
    final isDriver = user['is_driver'] == true;
    final mockBatch = user['mock_batch']?.toString().trim() ?? '';

    return GestureDetector(
      onLongPress: () {
        HapticFeedback.mediumImpact();
        _toggleAdmin(context, ref);
      },
      child: Container(
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
                        publicUserId,
                        style: GoogleFonts.dmSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      if (user['phone']?.toString().isNotEmpty ?? false) ...[
                        const SizedBox(height: 2),
                        Text(
                          user['phone'].toString(),
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.text2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (isMock)
                      const _MarkerChip(label: 'Mock', color: Colors.orange),
                    if (isAdmin) ...[
                      if (isMock) const SizedBox(height: 6),
                      const _MarkerChip(label: 'Admin', color: Colors.green),
                    ],
                    if (isDriver) ...[
                      if (isMock || isAdmin) const SizedBox(height: 6),
                      const _MarkerChip(label: 'Driver', color: AppColors.blue),
                    ],
                    if (kycStatus == 'verified') ...[
                      const SizedBox(height: 6),
                      const _MarkerChip(
                        label: 'KYC ✓',
                        color: AppColors.accent,
                      ),
                    ] else if (kycStatus == 'pending_review') ...[
                      const SizedBox(height: 6),
                      _MarkerChip(
                        label: 'KYC ⏳',
                        color: Colors.amber.shade700,
                      ),
                    ],
                    if (momoNumber.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      const _MarkerChip(
                        label: 'MoMo',
                        color: AppColors.purple,
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${AppMarket.country.name} · ${AppMarket.languageCode.toUpperCase()} · '
              '${momoProvider.isEmpty ? 'momo' : momoProvider}',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.text3,
              ),
            ),
            if (vehicleType.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Vehicle: $vehicleType',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text3,
                ),
              ),
            ],
            if (isMock && mockBatch.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Batch: $mockBatch',
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange,
                ),
              ),
            ],
            if (createdAt.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Created: $createdAt',
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: AppColors.text3,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: onEdit,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Edit',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarkerChip extends StatelessWidget {
  const _MarkerChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _BatchCleanupButton extends ConsumerStatefulWidget {
  const _BatchCleanupButton({required this.batch});

  final String batch;

  @override
  ConsumerState<_BatchCleanupButton> createState() =>
      _BatchCleanupButtonState();
}

class _BatchCleanupButtonState extends ConsumerState<_BatchCleanupButton> {
  bool _isLoading = false;

  Future<void> _purgeBatch() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            'Remove Mock Batch?',
            style: GoogleFonts.dmSans(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          content: Text(
            'This deletes all rows'
            'If your current admin account belongs to this batch, you may lose access immediately after cleanup.',
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
              child: const Text('Delete Batch'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _isLoading = true);
    try {
      final result = await ref
          .read(adminRepositoryProvider)
          .purgeMockBatch(widget.batch);

      ref.invalidate(adminUsersProvider);
      ref.invalidate(adminPartnersProvider);
      ref.invalidate(adminPartnerServicesProvider(null));

      if (!mounted) {
        return;
      }

      final deleted = result['deleted'];
      final summary = deleted is Map
          ? deleted.entries
                .where((entry) {
                  final value = entry.value;
                  return value is num && value > 0;
                })
                .map((entry) => '${entry.key}: ${entry.value}')
                .take(4)
                .join(', ')
          : '';

      CoolToast.success(
        context,
        summary.isEmpty
            ? 'Removed mock batch ${widget.batch}.'
            : 'Removed ${widget.batch}. $summary',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      CoolToast.error(context, 'Cleanup failed: $error');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _isLoading ? null : _purgeBatch,
      icon: _isLoading
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CupertinoActivityIndicator(radius: 7),
            )
          : const Icon(Icons.delete_outline_rounded, size: 16),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.orange,
        side: const BorderSide(color: Colors.orange),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      label: Text(
        widget.batch,
        style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Edit user bottom sheet
// ═══════════════════════════════════════════════════════════════

class _EditUserSheet extends ConsumerStatefulWidget {
  const _EditUserSheet({required this.user, required this.onSaved});
  final Map<String, dynamic> user;
  final VoidCallback onSaved;

  @override
  ConsumerState<_EditUserSheet> createState() => _EditUserSheetState();
}

class _EditUserSheetState extends ConsumerState<_EditUserSheet> {
  late final TextEditingController _nameController;
  late bool _isDriver;
  late bool _isAdmin;
  late final TextEditingController _vehicleController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.user['full_name']?.toString() ?? '',
    );
    _isDriver = widget.user['is_driver'] == true;
    _isAdmin = widget.user['is_admin'] == true;
    _vehicleController = TextEditingController(
      text: widget.user['vehicle_type']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _vehicleController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final userId = widget.user['id']?.toString();
    if (userId == null || userId.isEmpty) return;

    try {
      final fields = <String, dynamic>{
        'full_name': _nameController.text.trim(),
        'is_admin': _isAdmin,
        'is_driver': _isDriver,
        'vehicle_type': _vehicleController.text.trim().isEmpty
            ? null
            : _vehicleController.text.trim(),
      };

      await ref.read(adminRepositoryProvider).updateUserFields(userId, fields);

      widget.onSaved();
      if (mounted) {
        Navigator.of(context).pop();
        CoolToast.success(context, 'User updated');
      }
    } catch (e) {
      if (mounted) CoolToast.error(context, 'Failed: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = widget.user['id']?.toString() ?? '';
    final phone = widget.user['phone']?.toString() ?? '';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            22,
            12,
            22,
            MediaQuery.of(context).viewInsets.bottom + 22,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
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
                'Edit User',
                style: GoogleFonts.dmSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$phone · ${userId.substring(0, 8.clamp(0, userId.length))}',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: AppColors.text3,
                ),
              ),
              const SizedBox(height: 20),

              // Full name
              _FieldLabel('Full name'),
              const SizedBox(height: 6),
              _EditInput(controller: _nameController),
              const SizedBox(height: 16),

              // Admin toggle
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Platform Admin',
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                  Switch.adaptive(
                    value: _isAdmin,
                    onChanged: (v) => setState(() => _isAdmin = v),
                    activeColor: Colors.orange,
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Driver toggle
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Driver',
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  Switch.adaptive(
                    value: _isDriver,
                    onChanged: (v) => setState(() => _isDriver = v),
                    activeColor: AppColors.accent,
                  ),
                ],
              ),

              // Vehicle type (only when driver)
              if (_isDriver) ...[
                const SizedBox(height: 8),
                _FieldLabel('Vehicle type'),
                const SizedBox(height: 6),
                _EditInput(
                  controller: _vehicleController,
                  hint: 'e.g. motorcycle, car',
                ),
              ],
              const SizedBox(height: 24),

              // Save
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSaving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Save',
                          style: GoogleFonts.dmSans(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.dmSans(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppColors.text3,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _EditInput extends StatelessWidget {
  const _EditInput({required this.controller, this.hint});
  final TextEditingController controller;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.text),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.dmSans(fontSize: 13, color: AppColors.text3),
        filled: true,
        fillColor: AppColors.bg,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.accent, width: 1.5),
        ),
      ),
    );
  }
}
