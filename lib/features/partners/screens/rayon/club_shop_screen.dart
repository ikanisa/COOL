import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../shared/widgets/rs_shop_item.dart';
import '../../rayon/models/rs_models.dart';
import '../../rayon/rayon_payment.dart';
import '../../providers/rayon_sports_provider.dart';
import '../../widgets/rayon_screen_scaffold.dart';
import '../../widgets/rayon_state_views.dart';

class ClubShopScreen extends ConsumerStatefulWidget {
  const ClubShopScreen({super.key});

  @override
  ConsumerState<ClubShopScreen> createState() => _ClubShopScreenState();
}

class _ClubShopScreenState extends ConsumerState<ClubShopScreen> {
  String _category = 'All';

  static const _categories = [
    ('All', Icons.shopping_bag_rounded),
    ('Kits', Icons.checkroom_rounded),
    ('Caps', Icons.dry_cleaning_rounded),
    ('Scarves', Icons.gesture_rounded),
    ('Footwear', Icons.directions_walk_rounded),
    ('Bundles', Icons.inventory_2_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final shopCatalog = ref.watch(rayonShopCatalogProvider);
    final cartItemCount = ref.watch(rayonCartCountProvider);
    final cartController = ref.read(rayonCartControllerProvider.notifier);

    return RayonScreenScaffold(
      title: 'Club Shop',
      scrollable: false,
      actions: [
        // Cart icon with badge
        GestureDetector(
          onTap: cartItemCount > 0
              ? () => context.push('/partners/rayon-sports/shop/checkout')
              : null,
          child: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(
                  Icons.shopping_bag_outlined,
                  color: AppColors.rsWhite,
                  size: 22,
                ),
                if (cartItemCount > 0)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: RsColors.rsGold,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$cartItemCount',
                        style: GoogleFonts.dmMono(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
      child: shopCatalog.when(
        data: (shop) {
          final hasMemberDiscount = shop.hasMemberDiscount;

          final filtered = _category == 'All'
              ? shop.products
              : shop.products
                    .where(
                      (p) => p.category.value.toLowerCase().contains(
                        _category.toLowerCase(),
                      ),
                    )
                    .toList();

          return LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth >= 1200
                  ? 4
                  : constraints.maxWidth >= 720
                  ? 3
                  : 2;
              final childAspectRatio = switch (crossAxisCount) {
                4 => 0.92,
                3 => 0.86,
                _ => 0.78,
              };

              return Stack(
                children: [
                  CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF0A1E60),
                                    Color(0xFF0D2878),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: RsColors.rsBlueBorder,
                                ),
                              ),
                              child: Stack(
                                children: [
                                  Positioned(
                                    right: -10,
                                    top: -10,
                                    child: Opacity(
                                      opacity: 0.15,
                                      child: Icon(
                                        Icons.sports_soccer_rounded,
                                        size: 80,
                                        color: AppColors.rsWhite,
                                      ),
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.shopping_bag_rounded,
                                            size: 22,
                                            color: AppColors.text,
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            'Official gear, real colors.',
                                            style: GoogleFonts.barlowCondensed(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w800,
                                              color: AppColors.rsWhite,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Pay via MTN MoMo code $rayonSportsMomoCode at checkout.',
                                        style: GoogleFonts.barlow(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.text2,
                                          height: 1.35,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          if (hasMemberDiscount)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 5,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: RsColors.rsGold
                                                    .withValues(alpha: 0.18),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: RsColors.rsGold
                                                      .withValues(alpha: 0.4),
                                                ),
                                              ),
                                              child: Text(
                                                'GOLD −10%',
                                                style:
                                                    GoogleFonts.barlowCondensed(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color:
                                                          RsColors.rsGoldLight,
                                                    ),
                                              ),
                                            ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(
                                                alpha: 0.08,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: Colors.white.withValues(
                                                  alpha: 0.14,
                                                ),
                                              ),
                                            ),
                                            child: Text(
                                              'MTN MoMo code $rayonSportsMomoCode',
                                              style: GoogleFonts.dmMono(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.rsWhite,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              height: 36,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _categories.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (context, index) {
                                  final (cat, icon) = _categories[index];
                                  final selected = cat == _category;
                                  return GestureDetector(
                                    onTap: () =>
                                        setState(() => _category = cat),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 180,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
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
                                        cat,
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
                            const SizedBox(height: 16),
                          ]),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        sliver: SliverGrid(
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final product = filtered[index];
                            final quantity = shop.quantityFor(product.id);
                            return RsShopItem(
                              product: product,
                              onAddToCart: () =>
                                  cartController.addToCart(product.id),
                              hasMemberDiscount: hasMemberDiscount,
                              discountPct: hasMemberDiscount ? 10 : 0,
                              isNew: index == 0,
                              quantity: quantity,
                              onRemoveFromCart: quantity > 0
                                  ? () => cartController.removeFromCart(
                                      product.id,
                                    )
                                  : null,
                            );
                          }, childCount: filtered.length),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: childAspectRatio,
                              ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(height: shop.hasItems ? 92 : 18),
                      ),
                    ],
                  ),

                  if (shop.hasItems)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onTap: () => context.push(
                          '/partners/rayon-sports/shop/checkout',
                        ),
                        child: Container(
                          margin: const EdgeInsets.all(12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: RsColors.rsBlue,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: RsColors.rsBlue.withValues(alpha: 0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Text(
                                '${shop.cartItemCount} Items',
                                style: GoogleFonts.barlow(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${shop.cartTotal} RWF',
                                style: GoogleFonts.dmMono(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: RsColors.rsGoldLight,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'MTN MoMo Checkout →',
                                style: GoogleFonts.barlow(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
        loading: RayonLoadingView.new,
        error: (error, _) => RayonErrorView(
          message: error.toString(),
          onRetry: () {
            ref.invalidate(rayonShopProductsProvider);
            ref.invalidate(rayonUserMembershipProvider);
          },
        ),
      ),
    );
  }
}
