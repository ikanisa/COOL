import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../providers/rayon_sports_provider.dart';
import '../../widgets/partner_navigation.dart';
import '../models/rs_models.dart';
import '../providers/rs_admin_provider.dart';

/// Admin screen for managing RS memberships — list, adjust tier/points.
class RsAdminMembersScreen extends ConsumerStatefulWidget {
  const RsAdminMembersScreen({super.key});

  @override
  ConsumerState<RsAdminMembersScreen> createState() =>
      _RsAdminMembersScreenState();
}

class _RsAdminMembersScreenState extends ConsumerState<RsAdminMembersScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(rsAdminMembersProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.rsBlue,
        elevation: 0,
        leading: buildPartnerBackButton(
          context,
          fallbackLocation: AppRoutes.adminRayon,
          color: Colors.white,
        ),
        title: Text(
          'Members',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        actions: buildPartnerAppBarActions(context, homeColor: Colors.white),
      ),
      body: Column(
        children: [
          // ── Search bar ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
              style: GoogleFonts.dmSans(color: AppColors.text, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search members…',
                hintStyle: GoogleFonts.dmSans(
                  color: AppColors.text3,
                  fontSize: 14,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  color: AppColors.text3,
                  size: 20,
                ),
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
          // ── Member list ──
          Expanded(
            child: membersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  'Error: $e',
                  style: const TextStyle(color: AppColors.red),
                ),
              ),
              data: (members) {
                final filtered = _search.isEmpty
                    ? members
                    : members
                          .where(
                            (m) =>
                                m.displayName.toLowerCase().contains(_search) ||
                                m.membershipNumber.toLowerCase().contains(
                                  _search,
                                ),
                          )
                          .toList();
                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      'No members found',
                      style: GoogleFonts.dmSans(color: AppColors.text3),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final member = filtered[index];
                    return _MemberTile(
                      member: member,
                      onEditTier: () => _showTierPicker(member),
                      onEditPoints: () => _showPointsEditor(member),
                    );
                  },
                );
              },
            ),
          ),
        ],
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
              (tier) => ListTile(
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
            TextField(
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
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.onEditTier,
    required this.onEditPoints,
  });
  final FanMembership member;
  final VoidCallback onEditTier;
  final VoidCallback onEditPoints;

  IconData get _tierIcon => switch (member.tier) {
    FanTier.blue => Icons.favorite_rounded,
    FanTier.silver => Icons.workspace_premium_rounded,
    FanTier.gold => Icons.emoji_events_rounded,
    FanTier.platinum => Icons.diamond_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
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
                  '${member.membershipNumber} · ${member.tier.name.toUpperCase()} · ${member.points} pts',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: AppColors.text3,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
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
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onEditPoints();
            },
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.stars, size: 20, color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }
}
