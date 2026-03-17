import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/cool_async_view.dart';
import '../../../../shared/widgets/cool_empty_view.dart';
import '../../../../shared/widgets/cool_skeleton.dart';
import '../../providers/rayon_sports_provider.dart';
import '../models/rs_models.dart';
import '../providers/rs_admin_provider.dart';
import '../widgets/rs_admin_shell.dart';

/// Admin screen for managing RS memberships — list, adjust tier/points.
class RsAdminMembersScreen extends ConsumerStatefulWidget {
  const RsAdminMembersScreen({super.key});

  @override
  ConsumerState<RsAdminMembersScreen> createState() =>
      _RsAdminMembersScreenState();
}

class _RsAdminMembersScreenState extends ConsumerState<RsAdminMembersScreen> {
  String _search = '';
  String _filter = 'all'; // all, active, expired

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(rsAdminMembersProvider);

    return RsAdminShell(
      title: 'Members',
      subtitle:
          'Search, renew & export the supporter base',
      metrics: [
        RsAdminMetric(
          label: 'members',
          value:
              membersAsync.whenOrNull(data: (members) => '${members.length}') ??
              '...',
        ),
        RsAdminMetric(
          label: 'expired',
          value:
              membersAsync.whenOrNull(
                data: (members) =>
                    '${members.where((m) => m.isExpired).length}',
              ) ??
              '...',
        ),
        RsAdminMetric(
          label: 'points',
          value:
              membersAsync.whenOrNull(
                data: (members) =>
                    '${members.fold<int>(0, (sum, m) => sum + m.points)}',
              ) ??
              '...',
        ),
      ],
      controls: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Filter tabs
          SizedBox(
            height: 36,
            child: Row(
              children: [
                _FilterTab('All', _filter == 'all', () => setState(() => _filter = 'all')),
                const SizedBox(width: 6),
                _FilterTab('Active', _filter == 'active', () => setState(() => _filter = 'active')),
                const SizedBox(width: 6),
                _FilterTab('Expired', _filter == 'expired', () => setState(() => _filter = 'expired')),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Search
          Semantics(
            textField: true,
            label: 'Search members',
            hint: 'Search members',
            child: TextField(
              onChanged: (value) => setState(() => _search = value.toLowerCase()),
              style: GoogleFonts.dmSans(color: AppColors.text, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search members…',
                hintStyle: GoogleFonts.dmSans(color: AppColors.text3, fontSize: 14),
                prefixIcon: Icon(Icons.search, color: AppColors.text3, size: 20),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: membersAsync.whenOrNull(
        data: (members) => members.isEmpty
            ? null
            : FloatingActionButton.small(
                backgroundColor: AppColors.rsBlue,
                onPressed: () => _exportCsv(members),
                child: const Icon(Icons.download_rounded, color: Colors.white, size: 20),
              ),
      ),
      child: CoolAsyncView<List<FanMembership>>(
        value: membersAsync,
        onRetry: () => ref.invalidate(rsAdminMembersProvider),
        loadingWidget: const Padding(
          padding: EdgeInsets.all(16),
          child: CoolSkeletonList(itemCount: 4),
        ),
        emptyCheck: (members) => members.isEmpty,
        emptyWidget: const CoolEmptyView(
          subtitle: 'No fan memberships yet',
          icon: Icons.people_alt_outlined,
          isPremium: true,
        ),
        builder: (members) {
          // Apply filter
          var list = members;
          if (_filter == 'active') {
            list = members.where((m) => !m.isExpired).toList();
          } else if (_filter == 'expired') {
            list = members.where((m) => m.isExpired).toList();
          }
          // Apply search
          final filtered = _search.isEmpty
              ? list
              : list
                    .where(
                      (member) =>
                          member.displayName.toLowerCase().contains(_search) ||
                          member.membershipNumber.toLowerCase().contains(
                            _search,
                          ),
                    )
                    .toList();
          if (filtered.isEmpty) {
            return const CoolEmptyView(
              subtitle: 'No members match filter',
              icon: Icons.search_off_rounded,
              isPremium: true,
            );
          }
          return ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: filtered.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final member = filtered[index];
              return _MemberTile(
                member: member,
                onEditTier: () => _showTierPicker(member),
                onEditPoints: () => _showPointsEditor(member),
                onRenew: () => _renewMember(member),
              );
            },
          );
        },
      ),
    );
  }

  void _showTierPicker(FanMembership member) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Set Tier for ${member.displayName}',
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 16),
            ...FanTier.values.map(
              (tier) => Semantics(
                button: true,
                label:
                    'Set ${member.displayName} tier to',
                hint: 'Edit member tier',
                excludeSemantics: true,
                child: ListTile(
                  leading: Icon(
                    _tierIcon(tier),
                    size: 20,
                    color: AppColors.rsGold,
                  ),
                  title: Text(
                    tier.name.toUpperCase(),
                    style: GoogleFonts.dmSans(
                      color: member.tier == tier
                          ? AppColors.accent
                          : AppColors.text,
                      fontWeight: member.tier == tier
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                  trailing: member.tier == tier
                      ? const Icon(
                          Icons.check_circle,
                          color: AppColors.accent,
                          size: 20,
                        )
                      : null,
                  onTap: () async {
                    final repo = ref.read(rayonSportsRepositoryProvider);
                    await repo.updateMemberTier(member.userId, tier.name);
                    ref.invalidate(rsAdminMembersProvider);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPointsEditor(FanMembership member) {
    final controller = TextEditingController(text: member.points.toString());
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Set Points for ${member.displayName}',
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 16),
            Semantics(
              textField: true,
              label: 'Points',
              hint: 'Edit member points',
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                style: GoogleFonts.dmSans(color: AppColors.text, fontSize: 16),
                decoration: InputDecoration(
                  labelText: 'Points',
                  labelStyle: GoogleFonts.dmSans(
                    color: AppColors.text3,
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor: AppColors.surface2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.rsBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () async {
                final points = int.tryParse(controller.text) ?? member.points;
                final repo = ref.read(rayonSportsRepositoryProvider);
                await repo.setMemberPoints(member.userId, points);
                ref.invalidate(rsAdminMembersProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  IconData _tierIcon(FanTier tier) => switch (tier) {
    FanTier.blue => Icons.favorite_rounded,
    FanTier.silver => Icons.workspace_premium_rounded,
    FanTier.gold => Icons.emoji_events_rounded,
    FanTier.platinum => Icons.diamond_rounded,
  };

  Future<void> _renewMember(FanMembership member) async {
    final now = DateTime.now();
    final newExpiry = DateTime(now.year + 1, now.month, now.day);
    final repo = ref.read(rayonSportsRepositoryProvider);
    await repo.renewMembership(member.userId, newExpiry);
    ref.invalidate(rsAdminMembersProvider);
    if (mounted) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${member.displayName} renewed until ${DateFormat('d MMM yyyy').format(newExpiry)}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _exportCsv(List<FanMembership> members) {
    final dateFmt = DateFormat('yyyy-MM-dd');
    final buf = StringBuffer()
      ..writeln('Name,Membership #,Tier,Points,Joined,Expires');
    for (final m in members) {
      final joined = dateFmt.format(m.joinedAt);
      final expires = m.expiresAt != null ? dateFmt.format(m.expiresAt!) : '';
      buf.writeln(
        '"${m.displayName}","${m.membershipNumber}",'
        '${m.tier.name},${ m.points},$joined,$expires',
      );
    }
    Clipboard.setData(ClipboardData(text: buf.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Member CSV copied to clipboard'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.onEditTier,
    required this.onEditPoints,
    required this.onRenew,
  });
  final FanMembership member;
  final VoidCallback onEditTier;
  final VoidCallback onEditPoints;
  final VoidCallback onRenew;

  IconData get _tierIcon => switch (member.tier) {
    FanTier.blue => Icons.favorite_rounded,
    FanTier.silver => Icons.workspace_premium_rounded,
    FanTier.gold => Icons.emoji_events_rounded,
    FanTier.platinum => Icons.diamond_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label:
          'Member ${member.displayName}. Membership ${member.membershipNumber}.'
          'Tier ${member.tier.name.toUpperCase()}. ${member.points} points.',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(_tierIcon, size: 24, color: AppColors.rsGold),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.displayName,
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${member.membershipNumber} · ${member.tier.name.toUpperCase()} · ${member.points} Tokens',
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      color: AppColors.text3,
                    ),
                  ),
                  if (member.expiresAt != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          member.isExpired
                              ? Icons.warning_amber_rounded
                              : Icons.event_available_rounded,
                          size: 12,
                          color: member.isExpired
                              ? AppColors.red
                              : AppColors.accent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          member.isExpired
                              ? 'Expired ${DateFormat('d MMM yyyy').format(member.expiresAt!)}'
                              : 'Expires ${DateFormat('d MMM yyyy').format(member.expiresAt!)}',
                          style: GoogleFonts.dmSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: member.isExpired
                                ? AppColors.red
                                : AppColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Semantics(
              button: true,
              label: 'Edit tier for ${member.displayName}',
              hint: 'Edit member tier',
              excludeSemantics: true,
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onEditTier();
                },
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.military_tech,
                    size: 20,
                    color: AppColors.rsGold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Semantics(
              button: true,
              label: 'Edit points for ${member.displayName}',
              hint: 'Edit member points',
              excludeSemantics: true,
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onEditPoints();
                },
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.stars, size: 20, color: AppColors.accent),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Semantics(
              button: true,
              label: 'Renew membership for ${member.displayName}',
              hint: 'Renew member',
              excludeSemantics: true,
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onRenew();
                },
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.autorenew_rounded, size: 20, color: AppColors.blue),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterTab extends StatelessWidget {
  const _FilterTab(this.label, this.isSelected, this.onTap);
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.rsBlue : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppColors.rsBlue : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : AppColors.text2,
            ),
          ),
        ),
      ),
    );
  }
}
