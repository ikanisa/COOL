import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/whatsapp_contact_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/icon_mapper.dart';
import '../../../core/router/app_router.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/partners/models/partner.dart';
import '../../../features/partners/providers/partner_provider.dart';
import '../../../features/partners/rayon/models/rs_models.dart';
import '../../../features/partners/providers/rayon_sports_provider.dart';
import '../../../features/partners/rayon/widgets/rs_membership_card.dart';
import '../../../features/partners/widgets/partner_brand_mark.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/section_title.dart';
import '../../../shared/widgets/whatsapp_hint_chip.dart';

/// Partners hub — football clubs, banks, and organizations.
///
/// All partners are loaded dynamically from Supabase and filtered by the
/// current user's country.
class PartnersScreen extends ConsumerStatefulWidget {
  const PartnersScreen({super.key});

  @override
  ConsumerState<PartnersScreen> createState() => _PartnersScreenState();
}

class _PartnersScreenState extends ConsumerState<PartnersScreen> {
  int _activeTab = 0;

  static const _tabs = ['Football', 'Finance', 'Services'];

  Future<void> _openRayonSports() async {
    try {
      final authState = ref.read(authProvider);
      final userId = authState.user?.id ?? authState.session?.user.id;

      if (userId == null || userId.isEmpty) {
        if (!mounted) return;
        context.push('/partners/rayon-sports');
        return;
      }

      final notifier = ref.read(rayonSportsProvider.notifier);
      final membershipResult = await notifier.ensureMembership();

      if (membershipResult.created) {
        if (!mounted) return;
        await _showRayonWelcomeSheet(membershipResult.membership);
      }

      if (!mounted) return;
      context.push('/partners/rayon-sports');
    } catch (error) {
      if (!mounted) return;
      CoolToast.error(context, error.toString());
    }
  }

  Future<void> _showRayonWelcomeSheet(RsFanMembership membership) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).viewPadding.bottom + 16,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border2),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.border2,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  Text(
                    'Welcome to Gikundiro',
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: AppColors.rsWhite,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your fan membership is ready.',
                    style: GoogleFonts.barlow(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text2,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  RsMembershipCard(
                    fanName: membership.displayName,
                    fanId: membership.membershipNumber,
                    tier: membership.tier,
                    chapter: membership.chapter,
                    year: membership.joinedAt.year,
                    perks: _membershipPerks(membership.tier),
                  ),
                  const SizedBox(height: 18),
                  CoolButton(
                    label: 'Open Rayon Sports',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final country = ref.watch(currentUserCountryCodeProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: context.canPop(),
        title: Text(
          'Partners',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
      ),
      body: CoolScreenBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 96),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),

              // ═══════════════════════════════════════════════════════
              // TAB ROW
              // ═══════════════════════════════════════════════════════
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: List.generate(_tabs.length, (i) {
                    final isActive = _activeTab == i;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _activeTab = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: isActive
                                ? AppColors.accent
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _tabs[i],
                            style: GoogleFonts.dmSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isActive ? Colors.black : AppColors.text2,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 18),

              // ═══════════════════════════════════════════════════════
              // TAB CONTENT
              // ═══════════════════════════════════════════════════════
              IndexedStack(
                index: _activeTab,
                children: [
                  _FootballTab(
                    country: country,
                    onOpenRayonSports: _openRayonSports,
                  ),
                  _BanksTab(country: country),
                  _OrgsTab(country: country),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// FOOTBALL TAB
// ═════════════════════════════════════════════════════════════════════════

class _FootballTab extends ConsumerWidget {
  const _FootballTab({required this.country, required this.onOpenRayonSports});

  final String? country;
  final VoidCallback onOpenRayonSports;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partnersAsync = ref.watch(footballPartnersProvider(country));

    return partnersAsync.when(
      loading: () => const _LoadingState(),
      error: (err, _) => _ErrorState(error: err.toString()),
      data: (partners) {
        if (partners.isEmpty) {
          return const _EmptyState(label: 'No football partners yet');
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < partners.length; i++) ...[
              if (i > 0) const SizedBox(height: 18),
              _FootballHeroCard(
                partner: partners[i],
                onTap: partners[i].slug == 'rayon-sports'
                    ? onOpenRayonSports
                    : () {
                        CoolToast.info(
                          context,
                          '${partners[i].name} fan experience coming soon.',
                        );
                      },
              ),
              // Show features grid only for the first partner
              if (i == 0) ...[
                const SizedBox(height: 18),
                const SectionTitle(title: 'Features'),
                const SizedBox(height: 10),
                _ResponsiveFeatureGrid(
                  items: [
                    _FeatureTileData(
                      icon: Icons.people_rounded,
                      title: 'Fan Registry',
                      subtitle: _formatCount(partners[i].fanCount, 'fans'),
                    ),
                    _FeatureTileData(
                      icon: Icons.groups_rounded,
                      title: 'Fan Clubs',
                      subtitle: _formatCount(partners[i].clubCount, 'clubs'),
                    ),
                    _FeatureTileData(
                      icon: Icons.confirmation_number_rounded,
                      title: 'Ticketing',
                      subtitle: _formatCount(partners[i].gameCount, 'upcoming'),
                    ),
                    const _FeatureTileData(
                      icon: Icons.shopping_bag_rounded,
                      title: 'Club Shop',
                      subtitle: 'Browse merch',
                    ),
                  ],
                ),
              ],
            ],
          ],
        );
      },
    );
  }

  static String _formatCount(int count, String label) {
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K $label';
    }
    return '$count $label';
  }
}

// ── Football hero card ──────────────────────────────────────────────────

class _FootballHeroCard extends StatelessWidget {
  const _FootballHeroCard({required this.partner, required this.onTap});

  final Partner partner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isRayon = partner.slug == 'rayon-sports';
    return GestureDetector(
      onTap: onTap,
      child: CoolCard(
        gradient: isRayon ? AppColors.rsHeroGradient : AppColors.blueGradient,
        borderColor: isRayon ? AppColors.rsBlueBorder : AppColors.border,
        child: Stack(
          children: [
            Positioned(
              right: -5,
              top: 8,
              child: Icon(
                IconMapper.from(partner.emoji),
                size: 60,
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isRayon
                          ? AppColors.rsGold.withValues(alpha: 0.18)
                          : AppColors.blue.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isRayon
                            ? AppColors.rsGold.withValues(alpha: 0.4)
                            : AppColors.blue.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          IconMapper.from(partner.emoji),
                          size: 13,
                          color: isRayon ? AppColors.rsGoldLight : AppColors.blue,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isRayon
                              ? 'Gikundiro Hub'
                              : 'Official Partner',
                          style: GoogleFonts.dmSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isRayon ? AppColors.rsGoldLight : AppColors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    partner.name,
                    style: GoogleFonts.dmSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    partner.subtitle ?? '',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: AppColors.text2,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      _stat(_formatCount(partner.fanCount), 'Fans', isRayon),
                      _divider(),
                      _stat(partner.clubCount.toString(), 'Fan Clubs', isRayon),
                      _divider(),
                      _stat(partner.gameCount.toString(), 'Games', isRayon),
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

  Widget _stat(String value, String label, bool isRayon) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.dmMono(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: isRayon ? AppColors.rsGoldLight : AppColors.blue,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: AppColors.text3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Container(width: 1, height: 28, color: AppColors.border2);
  }

  static String _formatCount(int count) {
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }
}

List<String> _membershipPerks(FanTier tier) {
  return switch (tier) {
    FanTier.blue => const ['Registry Access', 'Club Updates', 'Member Queue'],
    FanTier.silver => const [
      'Priority Tickets',
      'Club Updates',
      'Member Queue',
    ],
    FanTier.gold => const ['Priority Tickets', 'Shop Discount', 'VIP Queue'],
    FanTier.platinum => const [
      'VIP Access',
      'Shop Discount',
      'Exclusive Events',
    ],
  };
}

// ═════════════════════════════════════════════════════════════════════════
// FEATURE TILE
// ═════════════════════════════════════════════════════════════════════════

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 26, color: AppColors.text),
            const SizedBox(height: 8),
            Text(
              title,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            Text(
              subtitle,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: AppColors.text2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResponsiveFeatureGrid extends StatelessWidget {
  const _ResponsiveFeatureGrid({required this.items});

  final List<_FeatureTileData> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 860 ? 4 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: constraints.maxWidth >= 860 ? 1.15 : 1.5,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return _FeatureTile(
              icon: item.icon,
              title: item.title,
              subtitle: item.subtitle,
            );
          },
        );
      },
    );
  }
}

class _FeatureTileData {
  const _FeatureTileData({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;
}

// ═════════════════════════════════════════════════════════════════════════
// BANKS TAB
// ═════════════════════════════════════════════════════════════════════════

class _BanksTab extends ConsumerWidget {
  const _BanksTab({required this.country});

  final String? country;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partnersAsync = ref.watch(bankPartnersProvider(country));

    return partnersAsync.when(
      loading: () => const _LoadingState(),
      error: (err, _) => _ErrorState(error: err.toString()),
      data: (partners) {
        if (partners.isEmpty) {
          return const _EmptyState(label: 'No finance partners yet');
        }

        return Column(
          children: [
            CoolCard(
              borderColor: AppColors.blue.withValues(alpha: 0.24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Before sending the user to a bank',
                    style: GoogleFonts.dmSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Check profile, KYC, and score readiness.',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text2,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),
                  CoolButton(
                    label: 'Open Readiness Checklist',
                    icon: Icons.assignment_turned_in_outlined,
                    onTap: () => context.push(AppRoutes.creditReadiness),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (int i = 0; i < partners.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _BankPartnerCard(partner: partners[i]),
            ],
          ],
        );
      },
    );
  }
}

// ── Bank partner card ───────────────────────────────────────────────────

class _BankPartnerCard extends StatelessWidget {
  const _BankPartnerCard({required this.partner});

  final Partner partner;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/partners/${partner.slug}'),
      child: CoolCard(
        gradient: AppColors.accentGradient,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        'Banking Partner',
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  PartnerBrandMark(
                    partner: partner,
                    width: 122,
                    height: 58,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                partner.name,
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              Text(
                partner.subtitle ?? '',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AppColors.text2,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _bankStat(
                    partner.fanCount > 0 ? partner.fanCount.toString() : '—',
                    'Active Groups',
                    AppColors.accent,
                  ),
                  const SizedBox(width: 20),
                  _bankStat(
                    partner.clubCount > 0 ? _formatRwf(partner.clubCount) : '—',
                    'RWF Held',
                    AppColors.accent,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bankStat(String value, String label, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: GoogleFonts.dmMono(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: AppColors.text3,
          ),
        ),
      ],
    );
  }

  static String _formatRwf(int amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)}M';
    }
    if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(0)}K';
    }
    return amount.toString();
  }
}

// ═════════════════════════════════════════════════════════════════════════
// ORGS TAB
// ═════════════════════════════════════════════════════════════════════════

class _OrgsTab extends ConsumerWidget {
  const _OrgsTab({required this.country});

  final String? country;

  Future<void> _openPartnerChat(
    BuildContext context, {
    required Partner partner,
  }) {
    final phone = partner.whatsappNumber ?? '';
    return WhatsAppContactService.openChat(
      context,
      phoneNumber: phone,
      message:
          'Hello, I would like to connect with ${partner.name} from the Cool partners section.',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partnersAsync = ref.watch(orgPartnersProvider(country));

    return partnersAsync.when(
      loading: () => const _LoadingState(),
      error: (err, _) => _ErrorState(error: err.toString()),
      data: (partners) {
        if (partners.isEmpty) {
          return const _EmptyState(label: 'No service partners yet');
        }

        return Column(
          children: [
            for (int i = 0; i < partners.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _OrgPartnerCard(
                partner: partners[i],
                onTap: () => _openPartnerChat(context, partner: partners[i]),
              ),
            ],
          ],
        );
      },
    );
  }
}

// ── Organization partner card ───────────────────────────────────────────

class _OrgPartnerCard extends StatelessWidget {
  const _OrgPartnerCard({required this.partner, required this.onTap});

  final Partner partner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isInsurance = partner.slug == 'radiant';
    return CoolCard(
      gradient: isInsurance ? AppColors.blueGradient : AppColors.accentGradient,
      onTap: onTap,
      child: Stack(
        children: [
          Positioned(
            right: -5,
            bottom: 5,
            child: Icon(
              IconMapper.from(partner.emoji),
              size: 50,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isInsurance
                        ? AppColors.blue.withValues(alpha: 0.15)
                        : AppColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isInsurance
                          ? AppColors.blue.withValues(alpha: 0.3)
                          : AppColors.accent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        IconMapper.from(partner.emoji),
                        size: 13,
                        color: isInsurance ? AppColors.blue : AppColors.accent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _categoryLabel(partner),
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isInsurance ? AppColors.blue : AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  partner.name,
                  style: GoogleFonts.dmSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                Text(
                  partner.subtitle ?? '',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AppColors.text2,
                  ),
                ),
                const SizedBox(height: 14),
                const WhatsAppHintChip(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _categoryLabel(Partner partner) {
    if (partner.category == PartnerCategory.bank) return 'Banking Partner';
    if (partner.slug == 'radiant') return 'Insurance Partner';
    if (partner.slug == 'prisma') return 'Professional Services';
    return 'Service Partner';
  }
}

// ═════════════════════════════════════════════════════════════════════════
// SHARED STATE WIDGETS (loading / error / empty)
// ═════════════════════════════════════════════════════════════════════════

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 32, color: AppColors.orange),
            const SizedBox(height: 8),
            Text(
              'Failed to load partners',
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              error,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.text3),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.handshake_outlined, size: 32, color: AppColors.text3),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.text2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
