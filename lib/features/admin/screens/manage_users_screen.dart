import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_market.dart';
import '../../../core/identity/public_user_identity.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_search_field.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/dense_admin_workspace_scaffold.dart';
import '../providers/admin_providers.dart';
import 'package:cool_app/core/l10n/l10n.dart';
import '../widgets/edit_user_sheet.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';

part '../widgets/manage_users_parts.dart';
part '../widgets/manage_users_summary_parts.dart';

/// Admin screen for inspecting user profiles, toggling admin status, editing
/// user fields, and cleaning demo data.
class ManageUsersScreen extends ConsumerStatefulWidget {
  const ManageUsersScreen({super.key});

  @override
  ConsumerState<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends ConsumerState<ManageUsersScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(adminUsersProvider);

    return DenseAdminWorkspaceScaffold(
      title: Text(
        'Manage Users',
        style: Theme.of(
          context,
        ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
      searchBar: CoolSearchField(
        hint: 'Search by name, phone, or ID…',
        debounce: Duration.zero,
        onChanged: (v) => setState(() => _search = v),
      ),
      child: CoolAsyncView<List<Map<String, dynamic>>>(
        value: usersAsync,
        onRetry: () => ref.invalidate(adminUsersProvider),
        loadingWidget: const Padding(
          padding: EdgeInsets.only(bottom: CoolSpace.x7),
          child: CoolSkeletonList(itemCount: 5),
        ),
        emptyCheck: (u) => u.isEmpty,
        emptyWidget: const CoolEmptyView(
          message: 'No users were returned',
          icon: Icons.person_outline_rounded,
        ),
        builder: (users) {
          final theme = Theme.of(context);
          final colors = context.coolSemanticColors;
          final mockCount = users
              .where((user) => user['is_mock'] == true)
              .length;
          final adminCount = users
              .where((user) => user['is_admin'] == true)
              .length;
          final momoCount = users
              .where(
                (user) => (user['momo_number']?.toString() ?? '').isNotEmpty,
              )
              .length;
          final mockBatches =
              users
                  .map((user) => user['mock_batch']?.toString().trim() ?? '')
                  .where((batch) => batch.isNotEmpty)
                  .toSet()
                  .toList(growable: false)
                ..sort();

          final query = _search.trim().toLowerCase();
          final filtered = query.isEmpty
              ? users
              : users.where((u) {
                  final name = (u['full_name']?.toString() ?? '').toLowerCase();
                  final phone = (u['phone']?.toString() ?? '').toLowerCase();
                  final id = (u['id']?.toString() ?? '').toLowerCase();
                  return name.contains(query) ||
                      phone.contains(query) ||
                      id.contains(query);
                }).toList();

          return ListView.separated(
            padding: const EdgeInsets.only(bottom: CoolSpace.x7),
            itemCount: filtered.length + 1,
            separatorBuilder: (_, index) => index == 0
                ? const SizedBox(height: CoolSpace.x4)
                : const SizedBox(height: CoolSpace.x3),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SummaryCard(
                      totalUsers: users.length,
                      mockUsers: mockCount,
                      adminUsers: adminCount,
                      momoUsers: momoCount,
                      mockBatches: mockBatches,
                    ),
                    if (query.isNotEmpty) ...[
                      const SizedBox(height: CoolSpace.x2),
                      Text(
                        '${filtered.length} result${filtered.length == 1 ? '' : 's'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: colors.tertiaryText,
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
    showCoolBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditUserSheet(
        user: user,
        onSaved: () => ref.invalidate(adminUsersProvider),
      ),
    );
  }
}
