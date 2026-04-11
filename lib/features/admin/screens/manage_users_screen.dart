import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_market.dart';
import '../../../core/identity/public_user_identity.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/admin_detail_scaffold.dart';
import '../../../shared/widgets/admin_workspace_kit.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_chip_bar.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_search_field.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../providers/admin_providers.dart';
import 'package:cool_app/core/l10n/l10n.dart';
import '../widgets/edit_user_sheet.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';

part '../widgets/manage_users_parts.dart';
part '../widgets/manage_users_summary_parts.dart';

enum _UserInventoryFilter { all, admin, mock, momo }

/// Admin screen for inspecting user profiles, toggling admin status, editing
/// user fields, and cleaning demo data.
class ManageUsersScreen extends ConsumerStatefulWidget {
  const ManageUsersScreen({super.key});

  @override
  ConsumerState<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends ConsumerState<ManageUsersScreen> {
  String _search = '';
  _UserInventoryFilter _filter = _UserInventoryFilter.all;

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(adminUsersProvider);

    return AdminDetailScaffold(
      child: CoolAsyncView<List<Map<String, dynamic>>>(
        value: usersAsync,
        onRetry: () => ref.invalidate(adminUsersProvider),
        loadingWidget: const Padding(
          padding: EdgeInsets.fromLTRB(
            CoolSpace.x5,
            0,
            CoolSpace.x5,
            CoolSpace.x7,
          ),
          child: CoolSkeletonList(itemCount: 5),
        ),
        emptyCheck: (u) => u.isEmpty,
        emptyWidget: const Padding(
          padding: EdgeInsets.all(CoolSpace.x5),
          child: CoolEmptyView(
            message: 'No users were returned',
            icon: CoolIcons.profile,
          ),
        ),
        builder: (users) {
          final query = _search.trim().toLowerCase();
          final filtered = users
              .where((user) => _matchesFilter(user, _filter))
              .where((user) => _matchesSearch(user, query))
              .toList(growable: false);

          final adminCount = users
              .where((user) => user['is_admin'] == true)
              .length;
          final mockCount = users
              .where((user) => user['is_mock'] == true)
              .length;
          final momoCount = users
              .where(
                (user) =>
                    (user['momo_number']?.toString() ?? '').trim().isNotEmpty,
              )
              .length;
          final mockBatches =
              users
                  .map((user) => user['mock_batch']?.toString().trim() ?? '')
                  .where((batch) => batch.isNotEmpty)
                  .toSet()
                  .toList(growable: false)
                ..sort();

          return ListView(
            padding: CoolSpace.scaffoldPadding,
            children: [
              AdminPageHeader(
                eyebrow: 'USER MANAGEMENT',
                title: 'Manage Users',
                subtitle:
                    'Accounts, role signals, payment reachability, and demo cleanup.',
                badges: [
                  const AdminStatusChip(
                    label: 'Live inventory',
                    tone: AdminTone.info,
                    icon: CoolIcons.datasetLinked,
                  ),
                  AdminStatusChip(
                    label: 'Visible',
                    trailing: '${filtered.length}',
                    tone: AdminTone.accent,
                    icon: CoolIcons.visibility,
                  ),
                ],
              ),
              const SizedBox(height: CoolSpace.x4),
              AdminMetricStrip(
                metrics: [
                  AdminMetricItem(
                    label: 'Users',
                    value: '${users.length}',
                    hint: 'Total accounts',
                    icon: CoolIcons.groupOutlined,
                    tone: AdminTone.info,
                  ),
                  AdminMetricItem(
                    label: 'Admins',
                    value: '$adminCount',
                    hint: 'Privileged accounts',
                    icon: CoolIcons.adminPanel,
                    tone: AdminTone.success,
                  ),
                  AdminMetricItem(
                    label: 'Mock',
                    value: '$mockCount',
                    hint: 'Demo inventory',
                    icon: CoolIcons.science,
                    tone: AdminTone.warning,
                  ),
                  AdminMetricItem(
                    label: 'MoMo',
                    value: '$momoCount',
                    hint: 'Payment-linked',
                    icon: CoolIcons.walletOutlined,
                    tone: AdminTone.accent,
                  ),
                ],
              ),
              const SizedBox(height: CoolSpace.x4),
              AdminToolbar(
                search: CoolSearchField(
                  hint: 'Search by name, phone, or ID…',
                  debounce: Duration.zero,
                  onChanged: (value) => setState(() => _search = value),
                ),
                filters: _buildFilterChips(users),
              ),
              const SizedBox(height: CoolSpace.x4),
              AdminDataTableCard(
                title: 'User Inventory',
                subtitle:
                    'Primary identifiers, status, market scope, and edit access.',
                emptyLabel: 'No users match the current filters',
                minWidth: 980,
                columns: const [
                  DataColumn(label: Text('User')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Market')),
                  DataColumn(label: Text('Batch')),
                  DataColumn(label: Text('Created')),
                  DataColumn(label: Text('Action')),
                ],
                rows: filtered.map(_buildRow).toList(growable: false),
                footer: Text(
                  '${filtered.length} result${filtered.length == 1 ? '' : 's'} shown',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.coolSemanticColors.tertiaryText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (mockBatches.isNotEmpty) ...[
                const SizedBox(height: CoolSpace.x4),
                AdminSectionCard(
                  title: 'Batch Cleanup',
                  subtitle:
                      'Remove demo inventory without leaving the user table.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (
                        var index = 0;
                        index < mockBatches.length;
                        index++
                      ) ...[
                        _BatchCleanupButton(batch: mockBatches[index]),
                        if (index < mockBatches.length - 1)
                          const SizedBox(height: CoolSpace.x2),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildFilterChips(List<Map<String, dynamic>> users) {
    final counts = <_UserInventoryFilter, int>{
      _UserInventoryFilter.all: users.length,
      _UserInventoryFilter.admin: users
          .where((user) => user['is_admin'] == true)
          .length,
      _UserInventoryFilter.mock: users
          .where((user) => user['is_mock'] == true)
          .length,
      _UserInventoryFilter.momo: users
          .where(
            (user) => (user['momo_number']?.toString() ?? '').trim().isNotEmpty,
          )
          .length,
    };

    return [
      CoolChipBar(
        scrollable: true,
        expand: false,
        items: _UserInventoryFilter.values
            .map(
              (filter) => CoolChipItem(
                label: _labelForFilter(filter),
                count: counts[filter],
                isActive: _filter == filter,
                onTap: () => setState(() => _filter = filter),
              ),
            )
            .toList(growable: false),
      ),
    ];
  }

  DataRow _buildRow(Map<String, dynamic> user) {
    final publicUserId = PublicUserIdentity.resolve(
      publicUserId: user['public_user_id']?.toString(),
      userId: user['id']?.toString(),
      phone: user['phone']?.toString(),
    );
    final phone = user['phone']?.toString().trim() ?? 'No phone';
    final provider = user['momo_provider']?.toString().trim();
    final marketLine =
        '${AppMarket.country.name} · ${AppMarket.languageCode.toUpperCase()} · '
        '${provider == null || provider.isEmpty ? 'momo' : provider}';
    final batch = user['mock_batch']?.toString().trim();
    final createdAt = _compactDate(user['created_at']?.toString());

    return DataRow(
      cells: [
        DataCell(
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                publicUserId,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: context.coolSemanticColors.primaryText,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                phone,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.coolSemanticColors.tertiaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        DataCell(
          Wrap(
            spacing: CoolSpace.x1,
            runSpacing: CoolSpace.x1,
            children: _userChips(user),
          ),
        ),
        DataCell(
          Text(
            marketLine,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.coolSemanticColors.secondaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        DataCell(
          Text(
            batch?.isNotEmpty == true ? batch! : '—',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.coolSemanticColors.primaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        DataCell(
          Text(
            createdAt,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.coolSemanticColors.secondaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        DataCell(
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => _openEditSheet(context, user),
              child: const Text('Edit'),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _userChips(Map<String, dynamic> user) {
    final chips = <Widget>[];
    if (user['is_admin'] == true) {
      chips.add(
        const AdminStatusChip(
          label: 'Admin',
          tone: AdminTone.success,
          icon: CoolIcons.shield,
        ),
      );
    }
    if (user['is_mock'] == true) {
      chips.add(
        const AdminStatusChip(
          label: 'Mock',
          tone: AdminTone.warning,
          icon: CoolIcons.science,
        ),
      );
    }
    if ((user['momo_number']?.toString() ?? '').trim().isNotEmpty) {
      chips.add(
        const AdminStatusChip(
          label: 'MoMo',
          tone: AdminTone.accent,
          icon: CoolIcons.phoneAndroidOutlined,
        ),
      );
    }
    if (chips.isEmpty) {
      chips.add(
        const AdminStatusChip(
          label: 'Standard',
          tone: AdminTone.neutral,
          icon: CoolIcons.profile,
        ),
      );
    }
    return chips;
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

bool _matchesFilter(Map<String, dynamic> user, _UserInventoryFilter filter) {
  return switch (filter) {
    _UserInventoryFilter.all => true,
    _UserInventoryFilter.admin => user['is_admin'] == true,
    _UserInventoryFilter.mock => user['is_mock'] == true,
    _UserInventoryFilter.momo =>
      (user['momo_number']?.toString() ?? '').trim().isNotEmpty,
  };
}

bool _matchesSearch(Map<String, dynamic> user, String query) {
  if (query.isEmpty) {
    return true;
  }
  final name = (user['full_name']?.toString() ?? '').toLowerCase();
  final phone = (user['phone']?.toString() ?? '').toLowerCase();
  final id = (user['id']?.toString() ?? '').toLowerCase();
  final publicId = (user['public_user_id']?.toString() ?? '').toLowerCase();
  return name.contains(query) ||
      phone.contains(query) ||
      id.contains(query) ||
      publicId.contains(query);
}

String _labelForFilter(_UserInventoryFilter filter) {
  return switch (filter) {
    _UserInventoryFilter.all => 'All',
    _UserInventoryFilter.admin => 'Admins',
    _UserInventoryFilter.mock => 'Mock',
    _UserInventoryFilter.momo => 'MoMo',
  };
}

String _compactDate(String? raw) {
  final parsed = DateTime.tryParse(raw ?? '')?.toLocal();
  if (parsed == null) {
    return '—';
  }
  final month = parsed.month.toString().padLeft(2, '0');
  final day = parsed.day.toString().padLeft(2, '0');
  return '${parsed.year}-$month-$day';
}
