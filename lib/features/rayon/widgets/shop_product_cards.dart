part of '../screens/club_shop_screen.dart';

class _ShopByCollection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SHOP BY COLLECTION',
          style: context.coolText.rayonCondensed(
            const TextStyle(fontSize: 28),
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: 160,
          height: 120,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF152D5B), Color(0xFF0B1E3F)],
            ),
            borderRadius: BorderRadius.circular(CoolRadii.lg),
            border: Border.all(color: colors.borderStrong),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'COLLECTION',
                style: GoogleFonts.dmMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: colors.secondaryText,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '2024/25\nSEASON',
                style: context.coolText.rayonCondensed(
                  const TextStyle(fontSize: 20, height: 1.1),
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeaturedProductCard extends StatelessWidget {
  const _FeaturedProductCard({
    required this.product,
    required this.hasMemberDiscount,
    required this.onTap,
  });

  final RsProduct product;
  final bool hasMemberDiscount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final salePrice = hasMemberDiscount
        ? product.discountedPrice(10)
        : product.price;
    final rating = _ratingFor(product);

    return GestureDetector(
      onTap: onTap,
      child: CoolCard(
        variant: CoolCardVariant.glass,
        cardPadding: CoolCardPadding.none,
        borderRadius: CoolRadii.lg,
        borderColor: colors.borderStrong.withValues(alpha: 0.5),
        child: Container(
          width: double.infinity,
          height: 260,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CoolRadii.lg),
            image: product.imageUrl != null
                ? DecorationImage(
                    image: NetworkImage(product.imageUrl!),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(CoolRadii.lg),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.3, 1.0],
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.85),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 14,
                left: 14,
                child: _BlueBadge(
                  label: product.badgeLabel?.toUpperCase() ?? 'OFFICIAL',
                ),
              ),
              if (product.imageUrl == null)
                Center(
                  child: Text(
                    product.imageEmoji,
                    style: const TextStyle(fontSize: 52),
                  ),
                ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 14,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            product.name.toUpperCase(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.coolText.rayonCondensed(
                              const TextStyle(fontSize: 22, height: 1.05),
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                size: 14,
                                color: RsColors.rsNavyLight,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                rating.toStringAsFixed(1),
                                style: GoogleFonts.dmMono(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white70,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '●',
                                style: TextStyle(
                                  fontSize: 5,
                                  color: Colors.white.withValues(alpha: 0.3),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  product.category.label.toUpperCase(),
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.dmMono(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white60,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _fmt(salePrice),
                          style: context.coolText.rayonCondensed(
                            const TextStyle(fontSize: 28),
                            fontWeight: FontWeight.w900,
                            color: RsColors.rsNavyLight,
                          ),
                        ),
                        Text(
                          'RWF',
                          style: GoogleFonts.dmMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: RsColors.rsNavyLight.withValues(alpha: 0.7),
                          ),
                        ),
                        if (hasMemberDiscount)
                          Text(
                            'MEMBER PRICE',
                            style: GoogleFonts.dmMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: colors.secondaryText,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductGridCard extends StatelessWidget {
  const _ProductGridCard({
    required this.product,
    required this.hasMemberDiscount,
    required this.onTap,
    required this.onAddToCart,
  });

  final RsProduct product;
  final bool hasMemberDiscount;
  final VoidCallback onTap;
  final VoidCallback onAddToCart;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final salePrice = hasMemberDiscount
        ? product.discountedPrice(10)
        : product.price;
    final showStrikethrough = hasMemberDiscount && salePrice != product.price;
    final rating = _ratingFor(product);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: CoolCard(
              variant: CoolCardVariant.glass,
              cardPadding: CoolCardPadding.none,
              borderRadius: CoolRadii.lg,
              borderColor: colors.borderStrong.withValues(alpha: 0.5),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(CoolRadii.lg),
                  image: product.imageUrl != null
                      ? DecorationImage(
                          image: NetworkImage(product.imageUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: Stack(
                  children: [
                    if (product.imageUrl == null)
                      Center(
                        child: Text(
                          product.imageEmoji,
                          style: const TextStyle(fontSize: 40),
                        ),
                      ),
                    if (product.badgeLabel != null || product.isNew)
                      Positioned(
                        top: 10,
                        left: 10,
                        child: _BlueBadge(
                          label: (product.badgeLabel ?? 'NEW').toUpperCase(),
                        ),
                      ),
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: GestureDetector(
                        onTap: onAddToCart,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: RsColors.rsRed,
                            borderRadius: BorderRadius.circular(CoolRadii.pill),
                            boxShadow: const [
                              BoxShadow(
                                color: RsColors.rsRedGlow,
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.add_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            product.name.toUpperCase(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.coolText.rayonCondensed(
              const TextStyle(fontSize: 14, height: 1.15),
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _fmt(salePrice),
            style: GoogleFonts.dmMono(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: RsColors.rsNavyLight,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              if (showStrikethrough) ...[
                Text(
                  _fmt(product.price),
                  style: GoogleFonts.dmMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.secondaryText,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              const Icon(
                Icons.star_rounded,
                size: 12,
                color: RsColors.rsNavyLight,
              ),
              const SizedBox(width: 3),
              Text(
                rating.toStringAsFixed(1),
                style: GoogleFonts.dmMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'RWF',
            style: GoogleFonts.dmMono(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: RsColors.rsNavyLight.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlueBadge extends StatelessWidget {
  const _BlueBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: RsColors.rsRed,
        borderRadius: BorderRadius.circular(CoolRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome_rounded, size: 12, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: context.coolText.rayon(
              const TextStyle(fontSize: 11),
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.query,
    required this.category,
    required this.onReset,
  });

  final String query;
  final ProductCategory? category;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return CoolCard(
      variant: CoolCardVariant.glass,
      padding: const EdgeInsets.all(24),
      borderRadius: CoolRadii.lg,
      borderColor: colors.borderStrong,
      child: SizedBox(
        width: double.infinity,
        child: Column(
          children: [
            Icon(
              Icons.storefront_outlined,
              size: 40,
              color: colors.secondaryText,
            ),
            const SizedBox(height: 16),
            Text(
              query.isNotEmpty
                  ? 'No results for "$query"'
                  : 'No items in ${category?.label ?? 'this collection'}',
              textAlign: TextAlign.center,
              style: context.coolText.rayonCondensed(
                const TextStyle(fontSize: 18),
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try a different search or category.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: colors.secondaryText,
              ),
            ),
            const SizedBox(height: 24),
            CoolButton(
              label: 'SHOW ALL',
              onTap: onReset,
              variant: CoolButtonVariant.secondary,
              size: CoolButtonSize.sm,
            ),
          ],
        ),
      ),
    );
  }
}
