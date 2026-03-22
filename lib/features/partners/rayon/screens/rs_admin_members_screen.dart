import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../../shared/widgets/cool_async_view.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_empty_view.dart';
import '../../../../shared/widgets/cool_skeleton.dart';
import '../../providers/rayon_sports_provider.dart';
import '../models/rs_models.dart';
import '../providers/rs_admin_provider.dart';
import '../widgets/rs_admin_shell.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../shared/widgets/cool_bottom_sheet.dart';

/// Admin screen for managing RS memberships — list, adjust tier/tokens.
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
    final colors = context.coolSemanticColors;
    final membersAsync = ref.watch(rsAdminMembersProvider);

    return RsAdminShell(
      title: context.l10n.members4,
      subtitle:
          'Search, renew, and correct supporter records from one high-trust roster.',
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
          label: 'tokens',
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
          SizedBox(
            height: 44,
            child: Row(
              children: [
                _FilterTab(
                  'All',
                  _filter == 'all',
                  () => setState(() => _filter = 'all'),
                ),
                const SizedBox(width: 6),
                _FilterTab(
                  'Active',
                  _filter == 'active',
                  () => setState(() => _filter = 'active'),
                ),
                const SizedBox(width: 6),
                _FilterTab(
                  'Expired',
                  _filter == 'expired',
                  () => setState(() => _filter = 'expired'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Semantics(
            textField: true,
            label: 'Search members',
            hint: 'Search members',
            child: TextField(
              onChanged: (value) =>
                  setState(() => _search = value.toLowerCase()),
              style: GoogleFonts.dmSans(
                color: colors.primaryText,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                hintText: 'Search members…',
                hintStyle: GoogleFonts.dmSans(
                  color: colors.tertiaryText,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: colors.tertiaryText,
                  size: 22,
                ),
                filled: true,
                fillColor: colors.inputSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CoolRadii.lg),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CoolRadii.lg),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CoolRadii.lg),
                  borderSide: const BorderSide(color: AppColors.rsBlue),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
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
                child: const Icon(
                  Icons.download_rounded,
                  color: Colors.white,
                  size: 20,
                ),
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
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
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
    final colors = context.coolSemanticColors;
    showCoolBottomSheet(
      context: context,
      backgroundColor: colors.overlaySurface,
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
                label: 'Set ${member.displayName} tier to',
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
    final colors = context.coolSemanticColors;
    final controller = TextEditingController(text: member.points.toString());
    showCoolBottomSheet(
      context: context,
      backgroundColor: colors.overlaySurface,
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
              'Set Tokens for ${member.displayName}',
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 16),
            Semantics(
              textField: true,
              label: 'Tokens',
              hint: 'Edit member tokens',
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                style: GoogleFonts.dmSans(color: AppColors.text, fontSize: 16),
                decoration: InputDecoration(
                  labelText: 'Tokens',
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
              child: Text(context.l10n.save),
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
      ..writeln('Name,Membership #,Tier,Tokens,Joined,Expires');
    for (final m in members) {
      final joined = dateFmt.format(m.joinedAt);
      final expires = m.expiresAt != null ? dateFmt.format(m.expiresAt!) : '';
      buf.writeln(
        '"${m.displayName}","${m.membershipNumber}",'
        '${m.tier.name},${m.points},$joined,$expires',
      );
    }
    Clipboard.setData(ClipboardData(text: buf.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.memberCsvCopiedTo),
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
    final colors = context.coolSemanticColors;
    final expiryLabel = member.expiresAt == null
        ? 'No expiry set'
        : member.isExpired
        ? 'Expired ${DateFormat('d MMM yyyy').format(member.expiresAt!)}'
        : 'Expires ${DateFormat('d MMM yyyy').format(member.expiresAt!)}';
    return Semantics(
      container: true,
      label:
          'Member ${member.displayName}. Membership ${member.membershipNumber}.'
          'Tier ${member.tier.name.toUpperCase()}. ${member.points} tokens.',
      child: CoolCard(
        backgroundColor: colors.teamSurface,
        borderColor: member.tier.color.withValues(alpha: 0.26),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: member.tier.color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(CoolRadii.lg),
                border: Border.all(
                  color: member.tier.color.withValues(alpha: 0.28),
                ),
              ),
              alignment: Alignment.center,
              child: Icon(_tierIcon, size: 26, color: AppColors.rsGold),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          member.displayName,
                          style: GoogleFonts.barlowCondensed(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: colors.primaryText,
                            height: 0.95,
                          ),
                        ),
                      ),
                      _MemberStatusPill(member: member),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${member.membershipNumber}  •  ${member.tier.label.toUpperCase()}',
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: colors.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MemberInfoPill(
                        label: 'Tokens',
                        value: '${member.points}',
                      ),
                      _MemberInfoPill(label: 'Chapter', value: member.chapter),
                      _MemberInfoPill(label: 'Status', value: expiryLabel),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MemberActionPill(
                        icon: Icons.military_tech_rounded,
                        label: 'Tier',
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onEditTier();
                        },
                      ),
                      _MemberActionPill(
                        icon: Icons.stars_rounded,
                        label: 'Tokens',
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onEditPoints();
                        },
                      ),
                      _MemberActionPill(
                        icon: Icons.autorenew_rounded,
                        label: 'Renew',
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onRenew();
                        },
                      ),
                    ],
                  ),
                ],
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
    final colors = context.coolSemanticColors;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.rsBlue.withValues(alpha: 0.16)
                : colors.chipBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? AppColors.rsBlue : colors.border,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: isSelected ? AppColors.rsBlueLight : colors.secondaryText,
            ),
          ),
        ),
      ),
    );
  }
}

class _MemberInfoPill extends StatelessWidget {
  const _MemberInfoPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        '$label: $value',
        style: GoogleFonts.dmSans(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: colors.secondaryText,
        ),
      ),
    );
  }
}

class _MemberActionPill extends StatelessWidget {
  const _MemberActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colors.cardSurfaceStrong,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: colors.borderStrong),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AppColors.rsBlueLight),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: colors.primaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberStatusPill extends StatelessWidget {
  const _MemberStatusPill({required this.member});

  final FanMembership member;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final color = member.isExpired ? colors.danger : colors.success;
    final label = member.isExpired ? 'EXPIRED' : 'ACTIVE';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}
