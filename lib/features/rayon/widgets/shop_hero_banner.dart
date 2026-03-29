part of '../screens/club_shop_screen.dart';

// ═══════════════════════════════════════════════════════════
// Section 1  — Hero Banner
// ═══════════════════════════════════════════════════════════

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.product, required this.onShopNow});

  final RsProduct product;
  final VoidCallback onShopNow;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 420),
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong,
        image: product.imageUrl != null
            ? DecorationImage(
                image: NetworkImage(product.imageUrl!),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withValues(alpha: 0.35),
                  BlendMode.darken,
                ),
              )
            : null,
      ),
      child: Stack(
        children: [
          // Gradient overlay
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.4, 1.0],
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.3),
                    Colors.black.withValues(alpha: 0.85),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const SizedBox(height: 40),
                // Giant title
                Text(
                  'OFFICIAL\nHOME\nKIT\n24/25',
                  style: context.coolText.rayonCondensed(
                    const TextStyle(fontSize: 64, height: 0.92),
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                // Description copy
                Text(
                  'THE ICONIC ROYAL BLUE AND WHITE HOME JERSEY WITH PREMIUM MOISTURE-WICKING FABRIC AND THE GIKUNDIRO CREST.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: Colors.white.withValues(alpha: 0.72),
                    height: 1.5,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 24),
                // SHOP NOW + price row
                Row(
                  children: [
                    // SHOP NOW button (ROUGEBLACK clay)
                    CoolButton(
                      label: 'SHOP NOW',
                      onTap: onShopNow,
                      variant: CoolButtonVariant.clay,
                      size: CoolButtonSize.md,
                    ),
                    const SizedBox(width: 20),
                    // Starting from price
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'STARTING FROM',
                          style: GoogleFonts.dmMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.55),
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_fmt(product.price)} RWF',
                          style: context.coolText.rayonCondensed(
                            const TextStyle(fontSize: 22),
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
