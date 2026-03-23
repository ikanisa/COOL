import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../shared/widgets/cool_button.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_toast.dart';
import '../../../../shared/widgets/cool_text_field.dart';
import '../../../../shared/widgets/rs_fan_club_card.dart';
import '../../../../shared/widgets/vehicle_chip.dart';
import '../../providers/rayon_sports_provider.dart';
import '../../widgets/rayon_screen_scaffold.dart';
import '../../widgets/rayon_state_views.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../shared/widgets/cool_bottom_sheet.dart';

class FanClubsScreen extends ConsumerStatefulWidget {
  const FanClubsScreen({super.key});

  @override
  ConsumerState<FanClubsScreen> createState() => _FanClubsScreenState();
}

class _FanClubsScreenState extends ConsumerState<FanClubsScreen> {
  String _selectedRegion = 'All';

  static const _regions = ['All', 'Kigali', 'Northern', 'Southern', 'Western'];

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    final clubDirectory = ref.watch(rayonClubDirectoryProvider);

    return RayonScreenScaffold(
      title: context.l10n.fanClubs,
      fallbackLocation: AppRoutes.rayonHome,
      scrollable: false,
      actions: [
        TextButton.icon(
          onPressed: () => _showCreateSheet(context),
          icon: const Icon(Icons.add, size: 18, color: RsColors.rsGoldLight),
          label: Text(
            'Create',
            style: text.rayon(
              theme.textTheme.labelLarge,
              fontWeight: FontWeight.w700,
              color: RsColors.rsGoldLight,
            ),
          ),
          style: TextButton.styleFrom(
            foregroundColor: RsColors.rsGoldLight,
            padding: EdgeInsets.symmetric(horizontal: space.x2),
            minimumSize: const Size(
              CoolTapTargets.minimum,
              CoolTapTargets.minimum,
            ),
          ),
        ),
      ],
      child: clubDirectory.when(
        data: (directory) {
          final myClub = directory.clubs
              .where((club) => directory.joinedClubIds.contains(club.id))
              .toList();
          final totalMemberCount = directory.clubs.fold<int>(
            0,
            (sum, club) => sum + club.memberCount,
          );

          final filtered = _selectedRegion == 'All'
              ? directory.clubs
              : directory.clubs
                    .where(
                      (c) => c.region.toLowerCase().contains(
                        _selectedRegion.toLowerCase(),
                      ),
                    )
                    .toList();

          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _FanClubCommandCard(
                      selectedRegion: _selectedRegion,
                      joinedCount: myClub.length,
                      totalClubs: directory.clubs.length,
                      visibleCount: filtered.length,
                      totalMemberCount: totalMemberCount,
                      regions: _regions,
                      onRegionSelected: (region) =>
                          setState(() => _selectedRegion = region),
                    ),
                    SizedBox(height: space.x5),
                  ]),
                ),
              ),
              if (myClub.isNotEmpty) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      Text(
                        'Joined clubs',
                        style: text.rayon(
                          theme.textTheme.labelLarge,
                          fontWeight: FontWeight.w700,
                          color: RsColors.rsBluePale,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ]),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final club = myClub[index];
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: index == myClub.length - 1 ? 0 : 12,
                        ),
                        child: RsFanClubCard(
                          club: club,
                          isJoined: true,
                          onJoinTap: () {},
                          onTap: () => context.push(
                            '/partners/rayon-sports/clubs/${club.id}',
                          ),
                        ),
                      );
                    }, childCount: myClub.length),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 14)),
              ],
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Text(
                      'All clubs',
                      style: text.rayon(
                        theme.textTheme.labelLarge,
                        fontWeight: FontWeight.w700,
                        color: colors.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ]),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 96),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final club = filtered[index];
                    final isJoined = directory.joinedClubIds.contains(club.id);
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index == filtered.length - 1 ? 0 : 12,
                      ),
                      child: RsFanClubCard(
                        club: club,
                        isJoined: isJoined,
                        onJoinTap: isJoined
                            ? () {}
                            : () => _joinClub(context, club.id),
                        onTap: () => context.push(
                          '/partners/rayon-sports/clubs/${club.id}',
                        ),
                      ),
                    );
                  }, childCount: filtered.length),
                ),
              ),
            ],
          );
        },
        loading: RayonLoadingView.new,
        error: (error, _) => RayonErrorView(
          message: error.toString(),
          onRetry: () {
            ref.invalidate(rayonFanClubsProvider);
            ref.invalidate(rayonJoinedClubIdsProvider);
          },
        ),
      ),
    );
  }

  Future<void> _joinClub(BuildContext context, String clubId) async {
    final notifier = ref.read(rayonSportsProvider.notifier);

    try {
      final message = await notifier.joinClub(clubId);
      ref.invalidate(rayonFanClubsProvider);
      ref.invalidate(rayonJoinedClubIdsProvider);
      ref.invalidate(rayonClubDirectoryProvider);
      if (!context.mounted) return;
      CoolToast.info(context, message);
    } catch (error) {
      if (!context.mounted) return;
      CoolToast.error(context, error.toString());
    }
  }

  void _showCreateSheet(BuildContext context) {
    final colors = context.coolSemanticColors;
    showCoolBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.overlaySurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalCtx) => _CreateClubSheet(
        onSubmit: (name, region, description) {
          Navigator.of(modalCtx).pop();
          CoolToast.success(context, 'Club creation request submitted.');
        },
      ),
    );
  }
}

class _FanClubCommandCard extends StatelessWidget {
  const _FanClubCommandCard({
    required this.selectedRegion,
    required this.joinedCount,
    required this.totalClubs,
    required this.visibleCount,
    required this.totalMemberCount,
    required this.regions,
    required this.onRegionSelected,
  });

  final String selectedRegion;
  final int joinedCount;
  final int totalClubs;
  final int visibleCount;
  final int totalMemberCount;
  final List<String> regions;
  final ValueChanged<String> onRegionSelected;

  @override
  Widget build(BuildContext context) {
    final text = context.coolText;
    final space = context.coolSpace;
    final theme = Theme.of(context);

    return CoolCard(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF051227), Color(0xFF0A2351), Color(0xFF14396B)],
      ),
      borderColor: RsColors.rsBlueBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Official Chapter Network',
            style: text.rayonCondensed(
              theme.textTheme.headlineSmall,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          SizedBox(height: space.x1 + 2),
          Text(
            'Browse chapters by region.',
            style: text.rayon(
              theme.textTheme.bodySmall,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.76),
              height: 1.4,
            ),
          ),
          SizedBox(height: space.x4),
          Wrap(
            spacing: space.x2,
            runSpacing: space.x2,
            children: regions
                .map(
                  (region) => VehicleChip(
                    label: region,
                    isSelected: region == selectedRegion,
                    onTap: () => onRegionSelected(region),
                  ),
                )
                .toList(),
          ),
          SizedBox(height: space.x4),
          Row(
            children: [
              Expanded(
                child: _FanClubMetricTile(
                  label: 'Joined',
                  value: '$joinedCount',
                  highlight: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _FanClubMetricTile(
                  label: 'Chapters',
                  value: '$totalClubs',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _FanClubMetricTile(
                  label: 'Supporters',
                  value: '$totalMemberCount',
                ),
              ),
            ],
          ),
          SizedBox(height: space.x3 + 2),
          Wrap(
            spacing: space.x2,
            runSpacing: space.x2,
            children: [
              _FanClubSignalPill(
                icon: Icons.public_rounded,
                label: selectedRegion == 'All'
                    ? 'National directory'
                    : '$selectedRegion focus',
              ),
              _FanClubSignalPill(
                icon: Icons.visibility_outlined,
                label: '$visibleCount chapters visible',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FanClubMetricTile extends StatelessWidget {
  const _FanClubMetricTile({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final text = context.coolText;
    final space = context.coolSpace;
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: space.x3, vertical: space.x3),
      decoration: BoxDecoration(
        color: highlight
            ? RsColors.rsGold.withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(CoolRadii.lg),
        border: Border.all(
          color: highlight
              ? RsColors.rsGold.withValues(alpha: 0.38)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: text.rayonCondensed(
              theme.textTheme.headlineSmall,
              fontWeight: FontWeight.w900,
              color: highlight ? RsColors.rsGoldLight : Colors.white,
            ),
          ),
          SizedBox(height: space.x1 / 2),
          Text(
            label,
            style: text.rayon(
              theme.textTheme.labelSmall,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
        ],
      ),
    );
  }
}

class _FanClubSignalPill extends StatelessWidget {
  const _FanClubSignalPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final text = context.coolText;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: RsColors.rsBluePale),
          const SizedBox(width: 6),
          Text(
            label,
            style: text.rayon(
              theme.textTheme.labelMedium,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.82),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Create Club Sheet ────────────────────────────────────────────────

class _CreateClubSheet extends StatefulWidget {
  const _CreateClubSheet({required this.onSubmit});

  final void Function(String name, String region, String description) onSubmit;

  @override
  State<_CreateClubSheet> createState() => _CreateClubSheetState();
}

class _CreateClubSheetState extends State<_CreateClubSheet> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  String _region = 'Kigali';

  static const _regionOptions = ['Kigali', 'Northern', 'Southern', 'Western'];

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colors.borderStrong,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Create Fan Club',
            style: text.rayonCondensed(
              theme.textTheme.headlineMedium,
              fontWeight: FontWeight.w900,
              color: RsColors.rsWhite,
            ),
          ),
          const SizedBox(height: 20),
          CoolTextField(
            hint: 'Club name',
            label: 'Name',
            controller: _nameController,
            prefixEmoji: '🥁',
          ),
          const SizedBox(height: 14),

          // Region selector
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Region',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.secondaryText,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _regionOptions.map((r) {
                  return VehicleChip(
                    label: r,
                    isSelected: r == _region,
                    onTap: () => setState(() => _region = r),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 14),
          CoolTextField(
            hint: 'Club purpose?',
            label: 'Description',
            controller: _descController,
            maxLines: 3,
          ),
          const SizedBox(height: 20),
          CoolButton(
            label: 'Create Club',
            onTap: () {
              final name = _nameController.text.trim();
              final desc = _descController.text.trim();
              if (name.isEmpty) return;
              widget.onSubmit(name, _region, desc);
            },
            icon: Icons.groups_2_outlined,
          ),
        ],
      ),
    );
  }
}
