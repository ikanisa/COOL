import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../../core/theme/rs_colors.dart';
import '../models/rs_models.dart';

import '../../providers/rayon_sports_provider.dart';
import '../../../../shared/widgets/cool_screen_background.dart';
import '../../../../shared/widgets/cool_toast.dart';
import '../../widgets/rayon_state_views.dart';
import '../../widgets/partner_navigation.dart';

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
                color: RsColors.rsBlueLight,
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
              child: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
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
                    const Icon(Icons.shopping_bag_outlined, color: Colors.white70, size: 20),
                    if (cartItemCount > 0)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: RsColors.rsBlue,
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
        primaryColor: RsColors.rsBlue,
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
              : allProducts.where((p) => p.category == _selectedCategory).toList();
          final searched = _searchQuery.isEmpty
              ? filtered
              : filtered.where((p) {
                  final haystack = [
                    p.name, p.description, p.category.label,
                    p.collection ?? '', p.badgeLabel ?? '',
                  ].join(' ').toLowerCase();
                  return haystack.contains(_searchQuery);
                }).toList();

          final featuredProduct = allProducts.isNotEmpty ? allProducts.first : null;

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
                      child: _SearchBar(controller: _searchController),
                    ),
                  ),

                  // ── 3. Category Filter Chips ──
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
                    sliver: SliverToBoxAdapter(
                      child: _CategoryChips(
                        products: allProducts,
                        selected: _selectedCategory,
                        onSelect: (cat) => setState(() => _selectedCategory = cat),
                      ),
                    ),
                  ),

                  // ── 4. TRENDING NOW ──
                  if (_searchQuery.isEmpty && _selectedCategory == null && allProducts.length >= 2)
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
                                    (_searchQuery.isEmpty && _selectedCategory == null)
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
                              childCount: (_searchQuery.isEmpty &&
                                          _selectedCategory == null)
                                  ? (searched.length - 1).clamp(0, searched.length)
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
                  left: 0, right: 0, bottom: 0,
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
                    // SHOP NOW button (white filled)
                    GestureDetector(
                      onTap: onShopNow,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(CoolRadii.pill),
                        ),
                        child: Text(
                          'SHOP NOW',
                          style: context.coolText.rayonCondensed(
                            const TextStyle(fontSize: 16),
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                      ),
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

// ═══════════════════════════════════════════════════════════
// Section 2  — Search Bar
// ═══════════════════════════════════════════════════════════

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(CoolRadii.lg),
        border: Border.all(color: colors.borderStrong),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: colors.secondaryText, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
              decoration: InputDecoration(
                hintText: 'SEARCH THE COLLECTION...',
                hintStyle: GoogleFonts.dmMono(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colors.secondaryText,
                  letterSpacing: 0.8,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Section 3  — Category Filter Chips
// ═══════════════════════════════════════════════════════════

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.products,
    required this.selected,
    required this.onSelect,
  });

  final List<RsProduct> products;
  final ProductCategory? selected;
  final ValueChanged<ProductCategory?> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    // Build unique categories in order
    final seen = <ProductCategory>{};
    final categories = <ProductCategory>[];
    for (final p in products) {
      if (seen.add(p.category)) categories.add(p.category);
    }

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final isAll = index == 0;
          final isSelected = isAll
              ? selected == null
              : selected == categories[index - 1];
          final label = isAll ? 'ALL' : categories[index - 1].label.toUpperCase();
          final icon = isAll
              ? Icons.auto_awesome_rounded
              : categories[index - 1].icon;

          return GestureDetector(
            onTap: () => onSelect(isAll ? null : categories[index - 1]),
            child: AnimatedContainer(
              duration: CoolMotion.quick,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                gradient: isSelected
                    ? const LinearGradient(
                        colors: [Color(0xFF1552A0), Color(0xFF0B2A63)],
                      )
                    : LinearGradient(
                        colors: [
                          colors.cardSurfaceStrong.withValues(alpha: 0.9),
                          colors.cardSurface.withValues(alpha: 0.7),
                        ],
                      ),
                borderRadius: BorderRadius.circular(CoolRadii.pill),
                border: Border.all(
                  color: isSelected
                      ? RsColors.rsBlueBorder
                      : colors.borderStrong,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: isSelected ? Colors.white : colors.secondaryText),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: context.coolText.rayon(
                      const TextStyle(fontSize: 14),
                      fontWeight: FontWeight.w800,
                      color: isSelected ? Colors.white : colors.primaryText,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Section 4  — TRENDING NOW
// ═══════════════════════════════════════════════════════════

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
          // Header row
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
                          color: RsColors.rsBlueLight,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right_rounded,
                          size: 18, color: RsColors.rsBlueLight),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Horizontal carousel
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
    final salePrice = hasMemberDiscount ? product.discountedPrice(10) : product.price;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 220,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image area
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: colors.cardSurfaceStrong,
                  borderRadius: BorderRadius.circular(CoolRadii.lg),
                  border: Border.all(color: colors.borderStrong.withValues(alpha: 0.5)),
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
                    // Favorite star
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
                        child: const Icon(Icons.star_rounded,
                            size: 20, color: RsColors.rsBlueLight),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Product name
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
            // Price
            Text(
              '${_fmt(salePrice)} RWF',
              style: GoogleFonts.dmMono(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: RsColors.rsBlueLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Section 5  — SHOP BY COLLECTION
// ═══════════════════════════════════════════════════════════

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
        // Collection card
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

// ═══════════════════════════════════════════════════════════
// Section 6a — Featured Product Card (full-width)
// ═══════════════════════════════════════════════════════════

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
    final salePrice = hasMemberDiscount ? product.discountedPrice(10) : product.price;
    final rating = _ratingFor(product);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 260,
        decoration: BoxDecoration(
          color: context.coolSemanticColors.cardSurfaceStrong,
          borderRadius: BorderRadius.circular(CoolRadii.lg),
          border: Border.all(
            color: context.coolSemanticColors.borderStrong.withValues(alpha: 0.5),
          ),
          image: product.imageUrl != null
              ? DecorationImage(
                  image: NetworkImage(product.imageUrl!),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: Stack(
          children: [
            // Bottom gradient
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
            // Badge
            Positioned(
              top: 14,
              left: 14,
              child: _BlueBadge(
                label: product.badgeLabel?.toUpperCase() ?? 'OFFICIAL',
              ),
            ),
            // Bottom info
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
                            const Icon(Icons.star_rounded,
                                size: 14, color: RsColors.rsBlueLight),
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
                            Text(
                              product.category.label.toUpperCase(),
                              style: GoogleFonts.dmMono(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white60,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Price column
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _fmt(salePrice),
                        style: context.coolText.rayonCondensed(
                          const TextStyle(fontSize: 28),
                          fontWeight: FontWeight.w900,
                          color: RsColors.rsBlueLight,
                        ),
                      ),
                      Text(
                        'RWF',
                        style: GoogleFonts.dmMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: RsColors.rsBlueLight.withValues(alpha: 0.7),
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
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Section 6b — Product Grid Card (2-column)
// ═══════════════════════════════════════════════════════════

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
    final salePrice = hasMemberDiscount ? product.discountedPrice(10) : product.price;
    final showStrikethrough = hasMemberDiscount && salePrice != product.price;
    final rating = _ratingFor(product);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: colors.cardSurfaceStrong,
                borderRadius: BorderRadius.circular(CoolRadii.lg),
                border: Border.all(color: colors.borderStrong.withValues(alpha: 0.5)),
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
                      child: Text(product.imageEmoji,
                          style: const TextStyle(fontSize: 40)),
                    ),
                  // Badge
                  if (product.badgeLabel != null || product.isNew)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: _BlueBadge(
                        label: (product.badgeLabel ?? 'NEW').toUpperCase(),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Name
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
          // Sale price
          Text(
            _fmt(salePrice),
            style: GoogleFonts.dmMono(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: RsColors.rsBlueLight,
            ),
          ),
          const SizedBox(height: 2),
          // Original price + rating row
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
              const Icon(Icons.star_rounded,
                  size: 12, color: RsColors.rsBlueLight),
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
              color: RsColors.rsBlueLight.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Shared Widgets
// ═══════════════════════════════════════════════════════════

class _BlueBadge extends StatelessWidget {
  const _BlueBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: RsColors.rsBlue,
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(CoolRadii.lg),
        border: Border.all(color: colors.borderStrong),
      ),
      child: Column(
        children: [
          Icon(Icons.storefront_outlined, size: 40, color: colors.secondaryText),
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
            style: GoogleFonts.inter(fontSize: 13, color: colors.secondaryText),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onReset,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: RsColors.rsBlueBorder),
                borderRadius: BorderRadius.circular(CoolRadii.pill),
              ),
              child: Text(
                'SHOW ALL',
                style: context.coolText.rayon(
                  const TextStyle(fontSize: 13),
                  fontWeight: FontWeight.w800,
                  color: RsColors.rsBlueLight,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Checkout Footer
// ═══════════════════════════════════════════════════════════

class _CheckoutFooter extends StatelessWidget {
  const _CheckoutFooter({
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
    final colors = context.coolSemanticColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(18, 0, 18, 24),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        decoration: BoxDecoration(
          gradient: enabled
              ? const LinearGradient(
                  colors: [Color(0xFF103B79), Color(0xFF0A285B)],
                )
              : LinearGradient(
                  colors: [
                    colors.cardSurfaceStrong.withValues(alpha: 0.92),
                    colors.cardSurface.withValues(alpha: 0.84),
                  ],
                ),
          borderRadius: BorderRadius.circular(CoolRadii.md),
          border: Border.all(
            color: enabled ? RsColors.rsBlueBorder : colors.borderStrong,
            width: 1.5,
          ),
          boxShadow: enabled
              ? CoolShadows.floating(
                  Theme.of(context).brightness,
                  strength: 0.45,
                )
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$itemCount ITEMS',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: enabled ? Colors.white : colors.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    enabled ? 'READY FOR CHECKOUT' : 'CHECKOUT PENDING',
                    style: GoogleFonts.dmMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: enabled
                          ? Colors.white.withValues(alpha: 0.6)
                          : colors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${_fmt(total)} RWF',
              style: GoogleFonts.dmMono(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: enabled ? RsColors.rsGoldLight : colors.secondaryText,
              ),
            ),
            const SizedBox(width: 16),
            Container(height: 28, width: 1, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(width: 16),
            Text(
              'CHECKOUT',
              style: context.coolText.rayon(
                const TextStyle(fontSize: 14),
                fontWeight: FontWeight.w800,
                color: enabled ? Colors.white : colors.primaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════

String _fmt(int amount) => NumberFormat.decimalPattern('en').format(amount);

double _ratingFor(RsProduct product) {
  // Derive a stable visual rating based on product name hash
  final hash = product.name.hashCode.abs();
  return 4.0 + (hash % 11) / 10.0; // 4.0 – 5.0
}
