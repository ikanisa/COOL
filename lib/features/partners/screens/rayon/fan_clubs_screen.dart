import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../shared/widgets/cool_button.dart';
import '../../../../shared/widgets/cool_text_field.dart';
import '../../../../shared/widgets/rs_fan_club_card.dart';
import '../../providers/rayon_sports_provider.dart';
import '../../widgets/rayon_screen_scaffold.dart';
import '../../widgets/rayon_state_views.dart';

class FanClubsScreen extends ConsumerStatefulWidget {
  const FanClubsScreen({super.key});

  @override
  ConsumerState<FanClubsScreen> createState() => _FanClubsScreenState();
}

class _FanClubsScreenState extends ConsumerState<FanClubsScreen> {
  String _selectedRegion = 'All';

  static const _regions = ['All', 'Kigali', 'Northern', 'Southern', 'Diaspora'];

  @override
  Widget build(BuildContext context) {
    final clubDirectory = ref.watch(rayonClubDirectoryProvider);
    final notifier = ref.read(rayonSportsProvider.notifier);

    return RayonScreenScaffold(
      title: 'Fan Clubs',
      scrollable: false,
      actions: [
        TextButton.icon(
          onPressed: () => _showCreateSheet(context, notifier),
          icon: const Icon(Icons.add, size: 18, color: AppColors.rsGoldLight),
          label: Text(
            'Create',
            style: GoogleFonts.barlow(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.rsGoldLight,
            ),
          ),
        ),
      ],
      child: clubDirectory.when(
        data: (directory) {
          final myClub = directory.clubs
              .where((club) => directory.joinedClubIds.contains(club.id))
              .toList();

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
                    Text(
                      'Local chapters, louder stands.',
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        color: AppColors.rsWhite,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Choose your region, organize away trips, and join the supporters moving the club forward.',
                      style: GoogleFonts.barlow(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text2,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 36,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _regions.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final region = _regions[index];
                          final selected = region == _selectedRegion;
                          return GestureDetector(
                            onTap: () =>
                                setState(() => _selectedRegion = region),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: selected
                                    ? RsColors.rsBlue
                                    : AppColors.surface2,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: selected
                                      ? RsColors.rsBlueBorder
                                      : AppColors.border,
                                ),
                              ),
                              child: Text(
                                region,
                                style: GoogleFonts.barlow(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: selected
                                      ? Colors.white
                                      : AppColors.text2,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                  ]),
                ),
              ),
              if (myClub.isNotEmpty) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      Text(
                        'MY CLUB',
                        style: GoogleFonts.barlow(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.blue,
                          letterSpacing: 1,
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
                        child: GestureDetector(
                          onTap: () => context.push(
                            '/partners/rayon-sports/clubs/${club.id}',
                          ),
                          child: RsFanClubCard(
                            club: club,
                            isJoined: true,
                            onJoinTap: () {},
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
                      'ALL CLUBS',
                      style: GoogleFonts.barlow(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text2,
                        letterSpacing: 1,
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
                      child: GestureDetector(
                        onTap: () => context.push(
                          '/partners/rayon-sports/clubs/${club.id}',
                        ),
                        child: RsFanClubCard(
                          club: club,
                          isJoined: isJoined,
                          onJoinTap: isJoined
                              ? () {}
                              : () => _joinClub(context, notifier, club.id),
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
        error: (error, _) =>
            RayonErrorView(message: error.toString(), onRetry: notifier.load),
      ),
    );
  }

  Future<void> _joinClub(
    BuildContext context,
    RayonSportsNotifier notifier,
    String clubId,
  ) async {
    try {
      final message = await notifier.joinClub(clubId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _showCreateSheet(BuildContext context, RayonSportsNotifier notifier) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalCtx) => _CreateClubSheet(
        onSubmit: (name, region, description) {
          Navigator.of(modalCtx).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Club creation request submitted.')),
          );
        },
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

  static const _regionOptions = ['Kigali', 'Northern', 'Southern', 'Diaspora'];

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              color: AppColors.border2,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Create Fan Club',
            style: GoogleFonts.barlowCondensed(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: AppColors.rsWhite,
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
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text2,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _regionOptions.map((r) {
                  final selected = r == _region;
                  return GestureDetector(
                    onTap: () => setState(() => _region = r),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: selected ? RsColors.rsBlue : AppColors.surface2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected
                              ? RsColors.rsBlueBorder
                              : AppColors.border,
                        ),
                      ),
                      child: Text(
                        r,
                        style: GoogleFonts.barlow(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: selected ? Colors.white : AppColors.text2,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 14),
          CoolTextField(
            hint: 'What does your club do?',
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
