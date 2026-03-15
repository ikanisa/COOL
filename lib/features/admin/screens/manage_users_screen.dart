import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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

/// Read-only admin screen for inspecting user profiles and demo seed markers.
class ManageUsersScreen extends ConsumerWidget {
  const ManageUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          message: 'No users were returned for this environment.',
          icon: Icons.person_outline_rounded,
        ),
        builder: (users) {
          final mockCount = users.where((user) => user['is_mock'] == true).length;
          final adminCount =
              users.where((user) => user['is_admin'] == true).length;
          final driverCount =
              users.where((user) => user['is_driver'] == true).length;
          final mockBatches =
              users
                  .map((user) => user['mock_batch']?.toString().trim() ?? '')
                  .where((batch) => batch.isNotEmpty)
                  .toSet()
                  .toList(growable: false)
                ..sort();

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 96),
            itemCount: users.length + 1,
            separatorBuilder:
                (_, index) =>
                    index == 0
                        ? const SizedBox(height: 24)
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
                    const SizedBox(height: 24),
                    _SummaryCard(
                      totalUsers: users.length,
                      mockUsers: mockCount,
                      adminUsers: adminCount,
                      driverUsers: driverCount,
                      mockBatches: mockBatches,
                    ),
                  ],
                );
              }

              return _UserTile(user: users[index - 1]);
            },
          );
        },
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
    required this.mockBatches,
  });

  final int totalUsers;
  final int mockUsers;
  final int adminUsers;
  final int driverUsers;
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
            'Demo users are tagged here for cleanup later. Customer-facing screens do not show these markers.',
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

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user});

  final Map<String, dynamic> user;

  @override
  Widget build(BuildContext context) {
    final publicUserId = PublicUserIdentity.resolve(
      publicUserId: user['public_user_id']?.toString(),
      userId: user['id']?.toString(),
      phone: user['phone']?.toString(),
    );
    final momoProvider = user['momo_provider']?.toString().trim() ?? '';
    final vehicleType = user['vehicle_type']?.toString().trim() ?? '';
    final createdAt = user['created_at']?.toString().trim() ?? '';
    final isMock = user['is_mock'] == true;
    final isAdmin = user['is_admin'] == true;
    final isDriver = user['is_driver'] == true;
    final mockBatch = user['mock_batch']?.toString().trim() ?? '';

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
                      publicUserId,
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'User ID',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text3,
                      ),
                    ),
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
        ],
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
            'This deletes all rows tagged ${widget.batch} from the database. '
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
