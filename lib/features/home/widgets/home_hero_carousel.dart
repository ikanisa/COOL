import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/rs_colors.dart';
import '../../partners/rayon/models/rs_models.dart';

// ═════════════════════════════════════════════════════════════════════
// 1. HERO CAROUSEL  (Match card + Stadium Lighting Fund card)
// ═════════════════════════════════════════════════════════════════════

class HomeHeroCarousel extends StatefulWidget {
  const HomeHeroCarousel({super.key, this.match, required this.banners});
  final RsMatch? match;
  final List<RsHomeBanner> banners;

  @override
  State<HomeHeroCarousel> createState() => _HomeHeroCarouselState();
}

class _HomeHeroCarouselState extends State<HomeHeroCarousel> {
  final _controller = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasMatch = widget.match != null;
    final pageCount = (hasMatch ? 1 : 0) + widget.banners.length;
    final heroHeight = MediaQuery.sizeOf(context).height * 0.50;

    if (pageCount == 0) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        SizedBox(
          height: heroHeight.clamp(280, 420),
          child: PageView(
            controller: _controller,
            onPageChanged: (i) => setState(() => _currentPage = i),
            children: [
              if (hasMatch) HomeHeroMatchCard(match: widget.match),
              for (final banner in widget.banners)
                HomePromoHeroCard(banner: banner),
            ],
          ),
        ),
        const SizedBox(height: CoolSpace.x3),
        // Page dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (int i = 0; i < pageCount; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              _buildDot(isActive: _currentPage == i),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildDot({required bool isActive}) {
    return Container(
      width: isActive ? 16 : 6,
      height: 4,
      decoration: BoxDecoration(
        color: isActive
            ? RsColors.rsBlue
            : Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

// ── Hero card 1: Match ──────────────────────────────────────────────

class HomeHeroMatchCard extends StatelessWidget {
  const HomeHeroMatchCard({super.key, this.match});
  final RsMatch? match;

  @override
  Widget build(BuildContext context) {
    final hasMatch = match != null;
    final colors = context.coolSemanticColors;

    return GestureDetector(
      onTap: () => context.push(AppRoutes.rayonTickets),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          image: DecorationImage(
            image: match?.imageUrl != null
                ? NetworkImage(match!.imageUrl!) as ImageProvider
                : const AssetImage('assets/images/hero_match_bg.png'),
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.6),
                colors.appBackground,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              CoolSpace.x5, CoolSpace.x5, CoolSpace.x5, CoolSpace.x7,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // LIVE tag + venue
                Row(
                  children: [
                    if (hasMatch) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: colors.success.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(CoolRadii.sm),
                          border: Border.all(
                            color: colors.success.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          'LIVE',
                          style: context.coolText.mono(
                            Theme.of(context).textTheme.labelSmall,
                            fontWeight: FontWeight.w800,
                            color: colors.success,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Text(
                      hasMatch
                          ? '${match!.venue.toUpperCase()} STADIUM'
                          : 'RAYON SPORTS',
                      style: context.coolText.mono(
                        Theme.of(context).textTheme.labelSmall,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.7),
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: CoolSpace.x4),

                // Team names
                if (hasMatch) ...[
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: match!.homeTeam.toUpperCase(),
                          style: context.coolText.rayonCondensed(
                            Theme.of(context).textTheme.displayLarge,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            height: 0.90,
                            letterSpacing: -0.5,
                          ),
                        ),
                        TextSpan(
                          text: ' VS ',
                          style: context.coolText.rayonCondensed(
                            Theme.of(context).textTheme.displayLarge,
                            fontWeight: FontWeight.w900,
                            color: RsColors.rsBlue,
                            height: 0.90,
                            letterSpacing: -0.5,
                          ),
                        ),
                        TextSpan(
                          text: match!.awayTeam.toUpperCase(),
                          style: context.coolText.rayonCondensed(
                            Theme.of(context).textTheme.displayLarge,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            height: 0.90,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Text(
                    'RAYON\nSPORTS FC',
                    style: context.coolText.rayonCondensed(
                      Theme.of(context).textTheme.displayLarge,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 0.90,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
                const SizedBox(height: CoolSpace.x4),

                // Date + time
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: colors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      hasMatch
                          ? 'TODAY, ${match!.kickoffTime}'.toUpperCase()
                          : 'SUPPORTERS MOVE TOGETHER',
                      style: context.coolText.mono(
                        Theme.of(context).textTheme.bodySmall,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.5),
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Hero card: Dynamic Promo Banner ──────────────────────────────────

class HomePromoHeroCard extends StatelessWidget {
  const HomePromoHeroCard({super.key, required this.banner});
  final RsHomeBanner banner;

  @override
  Widget build(BuildContext context) {
    final hasImage = banner.imageUrl != null && banner.imageUrl!.isNotEmpty;
    final colors = context.coolSemanticColors;

    return GestureDetector(
      onTap: () => context.push(banner.route),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          image: DecorationImage(
            image: hasImage
                ? NetworkImage(banner.imageUrl!) as ImageProvider
                : const AssetImage('assets/images/fan_registry_photo.png'),
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.6),
                colors.appBackground,
              ],
              stops: const [0.0, 0.4, 0.9],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              CoolSpace.x5, CoolSpace.x5, CoolSpace.x5, CoolSpace.x7,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (banner.badgeLabel != null && banner.badgeLabel!.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: RsColors.rsBlue.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(CoolRadii.sm),
                      border: Border.all(
                        color: RsColors.rsBlue.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      banner.badgeLabel!.toUpperCase(),
                      style: context.coolText.mono(
                        Theme.of(context).textTheme.labelSmall,
                        fontWeight: FontWeight.w800,
                        color: RsColors.rsBlueLight,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: CoolSpace.x4),
                ],

                // Title
                Text(
                  banner.title.toUpperCase(),
                  style: context.coolText.rayonCondensed(
                    Theme.of(context).textTheme.displayLarge,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 0.90,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: CoolSpace.x3),

                // Subtitle
                if (banner.subtitle != null && banner.subtitle!.isNotEmpty) ...[
                  Text(
                    banner.subtitle!,
                    style: context.coolText.mono(
                      Theme.of(context).textTheme.bodyMedium,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.8),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: CoolSpace.x5),
                ],

                // CTA Button
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CoolSpace.x5,
                    vertical: CoolSpace.x3,
                  ),
                  decoration: BoxDecoration(
                    color: RsColors.rsBlue,
                    borderRadius: BorderRadius.circular(CoolRadii.xl),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        banner.ctaLabel.toUpperCase(),
                        style: context.coolText.mono(
                          Theme.of(context).textTheme.labelMedium,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
