import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../../core/theme/rs_colors.dart';
import '../models/rs_models.dart';

import '../providers/rayon_sports_provider.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_screen_background.dart';
import '../../../../shared/widgets/cool_toast.dart';
import '../../../../shared/widgets/cool_button.dart';
import '../widgets/rayon_state_views.dart';
import '../widgets/partner_navigation.dart';

part '../widgets/shop_hero_banner.dart';
part '../widgets/shop_search_categories.dart';
part '../widgets/shop_trending.dart';
part '../widgets/shop_product_cards.dart';
part '../widgets/shop_checkout_footer.dart';

// ─────────────────────────────────────────────────────────
// Gikundiro Shop — Screenshot-matched rewrite
// ─────────────────────────────────────────────────────────

class ClubShopScreen extends ConsumerStatefulWidget {
  const ClubShopScreen({super.key});

  @override
  ConsumerState<ClubShopScreen> createState() => _ClubShopScreenState();
}

class _ClubShopScreenState extends ConsumerState<ClubShopScreen> {
  ProductCategory? _selectedCategory;
  late final TextEditingController _searchController;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController()
      ..addListener(() {
        final next = _searchController.text.trim().toLowerCase();
        if (next != _searchQuery) setState(() => _searchQuery = next);
      });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final shopCatalog = ref.watch(rayonShopCatalogProvider);
    final cartItemCount = ref.watch(rayonCartCountProvider);
    final cartController = ref.read(rayonCartControllerProvider.notifier);
    final paymentRoute = ref.watch(rayonPaymentRouteProvider).valueOrNull;

    return Scaffold(
      backgroundColor: colors.appBackground,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 84,
        flexibleSpace: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.appBackground.withValues(alpha: 0.88),
            border: Border(
              bottom: BorderSide(color: colors.border.withValues(alpha: 0.8)),
            ),
          ),
        ),
        leading: buildPartnerBackButton(
          context,
          fallbackLocation: AppRoutes.rayonHome,
          color: Colors.white,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'GIKUNDIRO',
              style: context.coolText.rayonCondensed(
                const TextStyle(fontSize: 18),
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            Text(
              'SHOP',
              style: context.coolText.rayonCondensed(
                const TextStyle(fontSize: 16),
                fontWeight: FontWeight.w900,
                color: RsColors.rsNavyLight,
              ),
            ),
            Text(
              'OFFICIAL MERCHANDISE',
              style: GoogleFonts.dmMono(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: colors.secondaryText,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        actions: [
          // Refresh icon
          GestureDetector(
            onTap: () {
              ref.invalidate(rayonShopProductsProvider);
              ref.invalidate(rayonUserMembershipProvider);
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.cardSurfaceStrong.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(CoolRadii.md),
                border: Border.all(color: colors.borderStrong),
              ),
              child: const Icon(
                Icons.refresh_rounded,
                color: Colors.white70,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Cart icon with badge
          Semantics(
            button: true,
            label: 'Shopping cart, $cartItemCount items',
            child: GestureDetector(
              onTap: cartItemCount > 0
                  ? () => context.push(AppRoutes.rayonShopCheckout)
                  : null,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.cardSurfaceStrong.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(CoolRadii.md),
                  border: Border.all(color: colors.borderStrong),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(
                      Icons.shopping_bag_outlined,
                      color: Colors.white70,
                      size: 20,
                    ),
                    if (cartItemCount > 0)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: RsColors.rsRed,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$cartItemCount',
                            style: GoogleFonts.dmMono(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: CoolScreenBackground(
        primaryColor: RsColors.rsRed,
        secondaryColor: RsColors.rsGold,
        child: SafeArea(
          top: false,
          child: shopCatalog.when(
            data: (shop) {
              final hasMemberDiscount = shop.hasMemberDiscount;
              final allProducts = shop.products;

              // Filter + search
              final filtered = _selectedCategory == null
                  ? allProducts
                  : allProducts
                        .where((p) => p.category == _selectedCategory)
                        .toList();
              final searched = _searchQuery.isEmpty
                  ? filtered
                  : filtered.where((p) {
                      final haystack = [
                        p.name,
                        p.description,
                        p.category.label,
                        p.collection ?? '',
                        p.badgeLabel ?? '',
                      ].join(' ').toLowerCase();
                      return haystack.contains(_searchQuery);
                    }).toList();

              final featuredProduct = allProducts.isNotEmpty
                  ? allProducts.first
                  : null;

              return Stack(
                children: [
                  CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      // ── 1. Hero Banner ──
                      if (featuredProduct != null)
                        SliverToBoxAdapter(
                          child: _HeroBanner(
                            product: featuredProduct,
                            onShopNow: () => context.push(
                              '${AppRoutes.rayonShop}/product/${featuredProduct.id}',
                            ),
                          ),
                        ),

                      // ── 2. Search Bar ──
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(18, 24, 18, 0),
                        sliver: SliverToBoxAdapter(
                          child: _ShopSearchBar(controller: _searchController),
                        ),
                      ),

                      // ── 3. Category Filter Chips ──
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
                        sliver: SliverToBoxAdapter(
                          child: _CategoryChips(
                            products: allProducts,
                            selected: _selectedCategory,
                            onSelect: (cat) =>
                                setState(() => _selectedCategory = cat),
                          ),
                        ),
                      ),

                      // ── 4. TRENDING NOW ──
                      if (_searchQuery.isEmpty &&
                          _selectedCategory == null &&
                          allProducts.length >= 2)
                        SliverToBoxAdapter(
                          child: _TrendingNow(
                            products: allProducts.take(4).toList(),
                            hasMemberDiscount: hasMemberDiscount,
                            onProductTap: (p) => context.push(
                              '${AppRoutes.rayonShop}/product/${p.id}',
                            ),
                          ),
                        ),

                      // ── 5. SHOP BY COLLECTION ──
                      if (_searchQuery.isEmpty && _selectedCategory == null)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(18, 32, 18, 0),
                          sliver: SliverToBoxAdapter(
                            child: _ShopByCollection(),
                          ),
                        ),

                      // ── 6. ALL PRODUCTS heading ──
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(18, 32, 18, 16),
                        sliver: SliverToBoxAdapter(
                          child: Text(
                            'ALL PRODUCTS',
                            style: context.coolText.rayonCondensed(
                              const TextStyle(fontSize: 28),
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),

                      // ── Featured product card ──
                      if (searched.isNotEmpty &&
                          _searchQuery.isEmpty &&
                          _selectedCategory == null)
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          sliver: SliverToBoxAdapter(
                            child: _FeaturedProductCard(
                              product: searched.first,
                              hasMemberDiscount: hasMemberDiscount,
                              onTap: () => context.push(
                                '${AppRoutes.rayonShop}/product/${searched.first.id}',
                              ),
                            ),
                          ),
                        ),

                      // ── 2-column product grid ──
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                        sliver: searched.isEmpty
                            ? SliverToBoxAdapter(
                                child: _EmptyState(
                                  query: _searchQuery,
                                  category: _selectedCategory,
                                  onReset: () => setState(() {
                                    _selectedCategory = null;
                                    _searchController.clear();
                                  }),
                                ),
                              )
                            : SliverGrid(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    // Skip first if we already show featured
                                    final offset =
                                        (_searchQuery.isEmpty &&
                                            _selectedCategory == null)
                                        ? 1
                                        : 0;
                                    final realIndex = index + offset;
                                    if (realIndex >= searched.length) {
                                      return const SizedBox.shrink();
                                    }
                                    final product = searched[realIndex];
                                    return _ProductGridCard(
                                      product: product,
                                      hasMemberDiscount: hasMemberDiscount,
                                      onTap: () => context.push(
                                        '${AppRoutes.rayonShop}/product/${product.id}',
                                      ),
                                      onAddToCart: () =>
                                          cartController.addToCart(product.id),
                                    );
                                  },
                                  childCount:
                                      (_searchQuery.isEmpty &&
                                          _selectedCategory == null)
                                      ? (searched.length - 1).clamp(
                                          0,
                                          searched.length,
                                        )
                                      : searched.length,
                                ),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      mainAxisSpacing: 16,
                                      crossAxisSpacing: 14,
                                      childAspectRatio: 0.56,
                                    ),
                              ),
                      ),

                      // Bottom padding for checkout bar
                      SliverToBoxAdapter(
                        child: SizedBox(height: shop.hasItems ? 100 : 32),
                      ),
                    ],
                  ),

                  // ── Checkout footer ──
                  if (shop.hasItems)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _CheckoutFooter(
                        itemCount: shop.cartItemCount,
                        total: shop.cartTotal,
                        enabled: paymentRoute != null,
                        onTap: () => context.push(AppRoutes.rayonShopCheckout),
                      ),
                    ),
                ],
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
        ),
      ),
    );
  }
}
