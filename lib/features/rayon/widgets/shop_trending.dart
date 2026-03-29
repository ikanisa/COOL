part of '../screens/club_shop_screen.dart';

class _TrendingNow extends StatelessWidget {
  const _TrendingNow({
    required this.products,
    required this.hasMemberDiscount,
    required this.onProductTap,
  });

  final List<RsProduct> products;
  final bool hasMemberDiscount;
  final ValueChanged<RsProduct> onProductTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TRENDING NOW',
                        style: context.coolText.rayonCondensed(
                          const TextStyle(fontSize: 28),
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'MOST WANTED BY GIKUNDIRO FANS',
                        style: GoogleFonts.dmMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: colors.secondaryText,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => CoolToast.info(context, 'Showing all products.'),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'VIEW ALL',
                        style: context.coolText.rayon(
                          const TextStyle(fontSize: 13),
                          fontWeight: FontWeight.w800,
                          color: RsColors.rsNavyLight,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: RsColors.rsNavyLight,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 280,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              itemCount: products.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final product = products[index];
                return _TrendingCard(
                  product: product,
                  hasMemberDiscount: hasMemberDiscount,
                  onTap: () => onProductTap(product),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendingCard extends StatelessWidget {
  const _TrendingCard({
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

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 220,
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
                            style: const TextStyle(fontSize: 48),
                          ),
                        ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.star_rounded,
                            size: 20,
                            color: RsColors.rsNavyLight,
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.coolText.rayonCondensed(
                const TextStyle(fontSize: 15),
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_fmt(salePrice)} RWF',
              style: GoogleFonts.dmMono(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: RsColors.rsNavyLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
