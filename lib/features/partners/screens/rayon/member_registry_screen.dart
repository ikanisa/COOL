import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_screen_background.dart';
import '../../../../shared/widgets/rs_tier_badge.dart';
import '../../rayon/models/rs_models.dart';
import '../../providers/member_registry_provider.dart';
import '../../providers/rayon_sports_provider.dart';
import '../../widgets/partner_navigation.dart';
import '../../widgets/rayon_state_views.dart';
import '../../../../core/l10n/l10n.dart';

class MemberRegistryScreen extends ConsumerStatefulWidget {
  const MemberRegistryScreen({super.key});

  @override
  ConsumerState<MemberRegistryScreen> createState() =>
      _MemberRegistryScreenState();
}

class _MemberRegistryScreenState extends ConsumerState<MemberRegistryScreen> {
  late final TextEditingController _searchController;
  String? _initializedPartnerId;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final partnerIdAsync = ref.watch(rayonPartnerIdProvider);
    final registryState = ref.watch(memberRegistryProvider);
    final registryNotifier = ref.read(memberRegistryProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CoolScreenBackground(
        primaryColor: AppColors.rsBlue,
        secondaryColor: AppColors.rsGold,
        child: SafeArea(
          child: partnerIdAsync.when(
            data: (partnerId) {
              if (partnerId.isEmpty) {
                return RayonErrorView(
                  message: 'Rayon Sports partner not',
                  onRetry: _retryPartnerLookup,
                );
              }

              // Initialize pagination with the partner ID on first build.
              if (_initializedPartnerId != partnerId) {
                _initializedPartnerId = partnerId;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  registryNotifier.init(partnerId);
                });
              }

              final members = registryState.members;
              final topFan = registryState.topFan;

              return Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.surface2,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border2),
                          ),
                          child: buildPartnerBackButton(
                            context,
                            fallbackLocation: AppRoutes.rayonHome,
                            color: AppColors.rsWhite,
                          ),
                        ),
                        const Spacer(),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.surface2,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border2),
                          ),
                          child: buildPartnerHomeButton(
                            context,
                            color: AppColors.rsWhite,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _RegistryOverviewCard(
                      memberCount: members.length,
                      activeFilter: registryState.filter,
                    ),
                    const SizedBox(height: 18),
                    _SearchBar(
                      controller: _searchController,
                      onChanged: registryNotifier.search,
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 42,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: MemberRegistryFilter.values.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          final filter = MemberRegistryFilter.values[index];
                          return _RegistryFilterChip(
                            label: filter.label,
                            isSelected: filter == registryState.filter,
                            onTap: () => registryNotifier.selectFilter(filter),
                          );
                        },
                      ),
                    ),
                    if (registryState.filter == MemberRegistryFilter.all &&
                        topFan != null) ...[
                      const SizedBox(height: 18),
                      _TopFanSpotlight(member: topFan),
                    ],
                    const SizedBox(height: 18),
                    Expanded(
                      child: registryState.isLoading
                          ? const RayonInlineLoadingView(compact: true)
                          : registryState.error != null && members.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    registryState.error!,
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.barlow(
                                      fontSize: 14,
                                      color: AppColors.text2,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextButton(
                                    onPressed: () =>
                                        registryNotifier.init(partnerId),
                                    child: Text(context.l10n.retry),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.only(bottom: 24),
                              itemCount: _listItemCount(members, registryState),
                              itemBuilder: (context, index) {
                                if (members.isEmpty) {
                                  return _EmptyRegistryState(
                                    query: registryState.query,
                                  );
                                }

                                if (index < members.length) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _MemberListTile(
                                      member: members[index],
                                    ),
                                  );
                                }

                                if (registryState.hasMore &&
                                    index == members.length) {
                                  return Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      0,
                                      6,
                                      0,
                                      18,
                                    ),
                                    child: registryState.isLoadingMore
                                        ? const Center(
                                            child: Padding(
                                              padding: EdgeInsets.all(16),
                                              child: RayonInlineBusyIndicator(),
                                            ),
                                          )
                                        : _LoadMoreButton(
                                            visibleCount: members.length,
                                            onTap: registryNotifier.loadMore,
                                          ),
                                  );
                                }

                                if (index ==
                                    members.length +
                                        (registryState.hasMore ? 1 : 0)) {
                                  return const Padding(
                                    padding: EdgeInsets.only(top: 6),
                                    child: _TierLegendCard(),
                                  );
                                }

                                return const SizedBox.shrink();
                              },
                            ),
                    ),
                  ],
                ),
              );
            },
            loading: RayonLoadingView.new,
            error: (error, _) => RayonErrorView(
              message: error.toString(),
              onRetry: _retryPartnerLookup,
            ),
          ),
        ),
      ),
    );
  }

  void _retryPartnerLookup() {
    setState(() {
      _initializedPartnerId = null;
    });
    ref.invalidate(rayonPartnerIdProvider);
    ref.invalidate(memberRegistryProvider);
  }

  int _listItemCount(
    List<RsRegistryMember> members,
    MemberRegistryState state,
  ) {
    if (members.isEmpty) {
      return 1;
    }
    return members.length + (state.hasMore ? 1 : 0) + 1;
  }
}

class _RegistryOverviewCard extends StatelessWidget {
  const _RegistryOverviewCard({
    required this.memberCount,
    required this.activeFilter,
  });

  final int memberCount;
  final MemberRegistryFilter activeFilter;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      borderColor: AppColors.border2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Fan Registry',
                  style: GoogleFonts.barlowCondensed(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: AppColors.rsWhite,
                    height: 0.96,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.rsBlueGlow,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.rsBlueBorder),
                ),
                child: Text(
                  '$memberCount members',
                  style: GoogleFonts.dmMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.rsBluePale,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Search by supporter name',
            style: GoogleFonts.barlow(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'View: ${activeFilter.label}',
            style: GoogleFonts.dmMono(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.text3,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border2),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: GoogleFonts.barlow(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: AppColors.rsWhite,
        ),
        cursorColor: AppColors.rsBluePale,
        decoration: InputDecoration(
          hintText: context.l10n.searchNameOrId,
          hintStyle: GoogleFonts.barlow(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: AppColors.text3,
          ),
          prefixIcon: Icon(Icons.search_rounded, color: AppColors.text2),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
        ),
      ),
    );
  }
}

class _RegistryFilterChip extends StatelessWidget {
  const _RegistryFilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: isSelected,
      label: '$label filter',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.rsBlueGlow : AppColors.surface2,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: isSelected ? AppColors.rsBlueBorder : AppColors.border2,
              ),
            ),
            child: Text(
              label,
              style: GoogleFonts.barlow(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isSelected ? AppColors.rsBluePale : AppColors.text2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopFanSpotlight extends StatelessWidget {
  const _TopFanSpotlight({required this.member});

  final RsRegistryMember member;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.rsGold.withValues(alpha: 0.36)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.rsGold.withValues(alpha: 0.26),
            AppColors.surface2,
            AppColors.surface2,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.rsGold.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🏆 Top Fan This Month',
                  style: GoogleFonts.barlow(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.rsGoldLight,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  member.displayName,
                  style: GoogleFonts.barlowCondensed(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.rsWhite,
                    height: 0.98,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '#${member.membershipNumber} · ${_formatPoints(member.points)} Tokens',
                  style: GoogleFonts.dmMono(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          RsTierBadge(tier: member.tier),
        ],
      ),
    );
  }
}

class _MemberListTile extends StatelessWidget {
  const _MemberListTile({required this.member});

  final RsRegistryMember member;

  @override
  Widget build(BuildContext context) {
    final avatarTextColor = member.tier == FanTier.silver
        ? AppColors.bg
        : AppColors.rsWhite;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border2),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _avatarGradient(member.tier),
              ),
              border: Border.all(
                color: member.tier.color.withValues(alpha: 0.32),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              _initialsFor(member.displayName),
              style: GoogleFonts.barlowCondensed(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: avatarTextColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.displayName,
                  style: GoogleFonts.barlow(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.rsWhite,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '#${member.membershipNumber} · ${member.chapter} · ${_formatPoints(member.points)} Tokens',
                  style: GoogleFonts.dmMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          RsTierBadge(tier: member.tier),
        ],
      ),
    );
  }
}

class _LoadMoreButton extends StatelessWidget {
  const _LoadMoreButton({required this.visibleCount, required this.onTap});

  final int visibleCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.rsBluePale,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          side: const BorderSide(color: AppColors.rsBlueBorder),
          backgroundColor: AppColors.rsBlueGlow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          'Load more · $visibleCount loaded',
          style: GoogleFonts.barlowCondensed(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.rsWhite,
          ),
        ),
      ),
    );
  }
}

class _TierLegendCard extends StatelessWidget {
  const _TierLegendCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface2.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 26,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MEMBERSHIP TIERS',
            style: GoogleFonts.barlow(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.text2,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 12),
          for (final tier in FanTier.values) ...[
            _TierLegendRow(tier: tier, range: _tierRangeFor(tier)),
            if (tier != FanTier.values.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _TierLegendRow extends StatelessWidget {
  const _TierLegendRow({required this.tier, required this.range});

  final FanTier tier;
  final String range;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            tier.label,
            style: GoogleFonts.barlowCondensed(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: tier == FanTier.silver ? AppColors.text : tier.color,
            ),
          ),
        ),
        Text(
          range,
          style: GoogleFonts.dmMono(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.text2,
          ),
        ),
      ],
    );
  }
}

class _EmptyRegistryState extends StatelessWidget {
  const _EmptyRegistryState({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final message = query.trim().isEmpty
        ? 'No members match the selected filter.'
        : 'No members matched "$query".';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border2),
      ),
      child: Text(
        message,
        style: GoogleFonts.barlow(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.text2,
          height: 1.4,
        ),
      ),
    );
  }
}

List<Color> _avatarGradient(FanTier tier) {
  return switch (tier) {
    FanTier.blue => [AppColors.rsBlueLight, AppColors.rsBlue],
    FanTier.silver => [const Color(0xFFE4E8F1), const Color(0xFF8C94A9)],
    FanTier.gold => [AppColors.rsGoldLight, AppColors.rsGold],
    FanTier.platinum => [const Color(0xFFC8DCFF), AppColors.purple],
  };
}

String _initialsFor(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .toList(growable: false);

  if (parts.isEmpty) {
    return 'RS';
  }

  return parts.map((part) => part.characters.first.toUpperCase()).join();
}

String _formatPoints(int points) {
  final raw = points.toString();
  final buffer = StringBuffer();

  for (var i = 0; i < raw.length; i++) {
    final indexFromEnd = raw.length - i;
    buffer.write(raw[i]);
    if (indexFromEnd > 1 && indexFromEnd % 3 == 1) {
      buffer.write(',');
    }
  }

  return buffer.toString();
}

String _tierRangeFor(FanTier tier) {
  return switch (tier) {
    FanTier.blue => '0-999 Tokens',
    FanTier.silver => '1,000-1,999 Tokens',
    FanTier.gold => '2,000-4,999 Tokens',
    FanTier.platinum => '5,000+ Tokens',
  };
}