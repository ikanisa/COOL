import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../shared/widgets/rs_shop_item.dart';
import '../../rayon/models/rs_models.dart';

import '../../providers/rayon_sports_provider.dart';
import '../../widgets/rayon_screen_scaffold.dart';
import '../../widgets/rayon_state_views.dart';

class ClubShopScreen extends ConsumerStatefulWidget {
  const ClubShopScreen({super.key});

  @override
  ConsumerState<ClubShopScreen> createState() => _ClubShopScreenState();
}

class _ClubShopScreenState extends ConsumerState<ClubShopScreen> {
  ProductCategory? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    final shopCatalog = ref.watch(rayonShopCatalogProvider);
    final cartItemCount = ref.watch(rayonCartCountProvider);
    final cartController = ref.read(rayonCartControllerProvider.notifier);
    final paymentRoute = ref.watch(rayonPaymentRouteProvider).valueOrNull;

    return RayonScreenScaffold(
      title: 'Club Shop',
      fallbackLocation: AppRoutes.rayonHome,
      scrollable: false,
      actions: [
        // Cart icon with badge
        Semantics(
          button: true,
          label: 'Shopping cart, $cartItemCount items',
          child: GestureDetector(
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
        ),
      ],
      child: shopCatalog.when(
        data: (shop) {
          final hasMemberDiscount = shop.hasMemberDiscount;
          final categoryOptions = _categoryOptions(shop.products);

          final filtered = _selectedCategory == null
              ? shop.products
              : shop.products
                    .where((p) => p.category == _selectedCategory)
                    .toList();

          return LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth >= 1200
                  ? 4
                  : constraints.maxWidth >= 820
                  ? 3
                  : constraints.maxWidth >= 430
                  ? 2
                  : 1;
              final childAspectRatio = switch (crossAxisCount) {
                4 => 0.9,
                3 => 0.82,
                2 => 0.66,
                _ => 1.08,
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
                            SizedBox(
                              height: 36,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: categoryOptions.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (context, index) {
                                  final category = categoryOptions[index];
                                  final selected =
                                      category.category == _selectedCategory;
                                  return Semantics(
                                    selected: selected,
                                    label: '${category.label} category filter',
                                    child: GestureDetector(
                                      onTap: () => setState(
                                        () => _selectedCategory =
                                            category.category,
                                      ),
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? RsColors.rsBlue
                                              : AppColors.surface2,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          border: Border.all(
                                            color: selected
                                                ? RsColors.rsBlueBorder
                                                : AppColors.border,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              category.icon,
                                              size: 14,
                                              color: selected
                                                  ? Colors.white
                                                  : AppColors.text2,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              category.label,
                                              style: GoogleFonts.barlow(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: selected
                                                    ? Colors.white
                                                    : AppColors.text2,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              '${category.count}',
                                              style: GoogleFonts.dmMono(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: selected
                                                    ? Colors.white70
                                                    : AppColors.text3,
                                              ),
                                            ),
                                          ],
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
                        sliver: filtered.isEmpty
                            ? SliverToBoxAdapter(
                                child: _EmptyFilteredCatalog(
                                  category: _selectedCategory,
                                  onReset: () =>
                                      setState(() => _selectedCategory = null),
                                ),
                              )
                            : SliverGrid(
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
                                    isNew: product.isNew || index == 0,
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
                      child: _CheckoutFooterBar(
                        itemCount: shop.cartItemCount,
                        total: shop.cartTotal,
                        enabled: paymentRoute != null,
                        onTap: () => context.push(
                          '/partners/rayon-sports/shop/checkout',
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

  List<_ShopCategoryOption> _categoryOptions(List<RsProduct> products) {
    final counts = <ProductCategory, int>{};
    for (final product in products) {
      counts.update(product.category, (value) => value + 1, ifAbsent: () => 1);
    }

    final options = counts.entries.toList()
      ..sort((a, b) {
        final countCompare = b.value.compareTo(a.value);
        if (countCompare != 0) {
          return countCompare;
        }
        return a.key.label.compareTo(b.key.label);
      });

    return <_ShopCategoryOption>[
      _ShopCategoryOption(
        label: 'All',
        icon: Icons.shopping_bag_rounded,
        count: products.length,
      ),
      ...options.map(
        (entry) => _ShopCategoryOption(
          label: entry.key.label,
          icon: entry.key.icon,
          category: entry.key,
          count: entry.value,
        ),
      ),
    ];
  }
}


class _CheckoutFooterBar extends StatelessWidget {
  const _CheckoutFooterBar({
    required this.itemCount,
    required this.total,
    required this.enabled,
    required this.onTap,
  });

  final int itemCount;
  final int total;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Checkout cart',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          height: 64,
          decoration: BoxDecoration(
            color: enabled ? RsColors.rsBlue : AppColors.surface2,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: enabled ? RsColors.rsBlueBorder : AppColors.border,
              width: 1.5,
            ),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: RsColors.rsBlue.withValues(alpha: 0.28),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$itemCount items'.toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: Colors.white,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      enabled ? 'READY FOR CHECKOUT' : 'CHECKOUT PENDING',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${NumberFormat.decimalPattern('en').format(total)} RWF',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      fontFamily: GoogleFonts.dmMono().fontFamily,
                      color: enabled ? RsColors.rsGoldLight : AppColors.text2,
                    ),
              ),
              const SizedBox(width: 16),
              Container(
                height: 32,
                width: 1,
                color: Colors.white.withValues(alpha: 0.2),
              ),
              const SizedBox(width: 16),
              Text(
                'CHECKOUT',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: Colors.white,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShopCategoryOption {
  const _ShopCategoryOption({
    required this.label,
    required this.icon,
    required this.count,
    this.category,
  });

  final String label;
  final IconData icon;
  final int count;
  final ProductCategory? category;
}

class _EmptyFilteredCatalog extends StatelessWidget {
  const _EmptyFilteredCatalog({required this.category, required this.onReset});

  final ProductCategory? category;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final categoryLabel = category?.label ?? 'this collection';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No items in $categoryLabel',
            style: GoogleFonts.barlow(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.rsWhite,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Switch to All to see everything',
            style: GoogleFonts.barlow(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: const Text('Show all items'),
            style: TextButton.styleFrom(
              foregroundColor: RsColors.rsGoldLight,
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}
