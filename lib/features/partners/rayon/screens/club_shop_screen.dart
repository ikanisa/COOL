import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/providers/production_redesign_provider.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../shared/widgets/cool_button.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/rs_shop_item.dart';
import '../models/rs_models.dart';

import '../../providers/rayon_sports_provider.dart';
import '../../widgets/rayon_screen_scaffold.dart';
import '../../widgets/rayon_state_views.dart';
import '../../../../core/l10n/l10n.dart';

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
        final nextValue = _searchController.text.trim().toLowerCase();
        if (nextValue == _searchQuery) {
          return;
        }
        setState(() => _searchQuery = nextValue);
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
    final useProductionRedesign = ref.watch(
      productionRedesignEnabledProvider(
        const ProductionRedesignScope(
          route: ProductionRedesignRoutes.rayonShop,
          partner: 'rayon',
        ),
      ),
    );

    return RayonScreenScaffold(
      title: context.l10n.clubShop,
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
                    color: RsColors.rsWhite,
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
          final searched = _searchQuery.isEmpty
              ? filtered
              : filtered.where((product) {
                  final haystack = [
                    product.name,
                    product.description,
                    product.category.label,
                    product.collection ?? '',
                    product.badgeLabel ?? '',
                  ].join(' ').toLowerCase();
                  return haystack.contains(_searchQuery);
                }).toList();

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
                            if (useProductionRedesign) ...[
                              _ShopCommandCard(
                                searchController: _searchController,
                                itemCount: shop.products.length,
                                categoryCount: categoryOptions.length - 1,
                                hasMemberDiscount: hasMemberDiscount,
                                checkoutReady: paymentRoute != null,
                              ),
                              const SizedBox(height: CoolSpace.x4),
                            ],
                            SizedBox(
                              height: 44,
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
                                        duration: CoolMotion.quick,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: CoolSpace.x4,
                                        ),
                                        constraints: const BoxConstraints(
                                          minHeight: 44,
                                        ),
                                        decoration: BoxDecoration(
                                          gradient: selected
                                              ? const LinearGradient(
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  colors: [
                                                    Color(0xFF15498F),
                                                    Color(0xFF0B2A63),
                                                  ],
                                                )
                                              : LinearGradient(
                                                  begin: Alignment.topCenter,
                                                  end: Alignment.bottomCenter,
                                                  colors: [
                                                    colors.cardSurfaceStrong
                                                        .withValues(alpha: 0.9),
                                                    colors.cardSurface
                                                        .withValues(
                                                          alpha: 0.78,
                                                        ),
                                                  ],
                                                ),
                                          borderRadius: BorderRadius.circular(
                                            CoolRadii.pill,
                                          ),
                                          border: Border.all(
                                            color: selected
                                                ? RsColors.rsBlueBorder
                                                : colors.borderStrong,
                                          ),
                                          boxShadow: selected
                                              ? CoolShadows.floating(
                                                  Theme.of(context).brightness,
                                                  strength: 0.28,
                                                )
                                              : null,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              category.icon,
                                              size: 16,
                                              color: selected
                                                  ? Colors.white
                                                  : colors.primaryText,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              category.label,
                                              style: context.coolText.rayon(
                                                const TextStyle(fontSize: 15),
                                                fontWeight: FontWeight.w800,
                                                color: selected
                                                    ? Colors.white
                                                    : colors.primaryText,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              '${category.count}',
                                              style: GoogleFonts.dmMono(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                                color: selected
                                                    ? Colors.white70
                                                    : colors.secondaryText,
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
                            const SizedBox(height: CoolSpace.x4),
                          ]),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        sliver: searched.isEmpty
                            ? SliverToBoxAdapter(
                                child: _EmptyFilteredCatalog(
                                  category: _selectedCategory,
                                  query: _searchQuery,
                                  onReset: () => setState(() {
                                    _selectedCategory = null;
                                    _searchController.clear();
                                  }),
                                ),
                              )
                            : SliverGrid(
                                delegate: SliverChildBuilderDelegate((
                                  context,
                                  index,
                                ) {
                                  final product = searched[index];
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
                                }, childCount: searched.length),
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
        label: context.l10n.all,
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: 'Checkout cart',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          constraints: const BoxConstraints(minHeight: 78),
          decoration: BoxDecoration(
            gradient: enabled
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF103B79), Color(0xFF0A285B)],
                  )
                : LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
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
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$itemCount items'.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: enabled ? Colors.white : colors.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      enabled ? 'READY FOR CHECKOUT' : 'CHECKOUT PENDING',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: enabled
                            ? Colors.white.withValues(alpha: 0.74)
                            : colors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${NumberFormat.decimalPattern('en').format(total)} RWF',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontFamily: GoogleFonts.dmMono().fontFamily,
                  color: enabled ? RsColors.rsGoldLight : colors.secondaryText,
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
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: enabled ? Colors.white : colors.primaryText,
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
  const _EmptyFilteredCatalog({
    required this.category,
    required this.onReset,
    required this.query,
  });

  final ProductCategory? category;
  final VoidCallback onReset;
  final String query;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final categoryLabel = category?.label ?? 'this collection';

    return CoolCard(
      backgroundColor: colors.cardSurfaceStrong.withValues(alpha: 0.88),
      borderColor: colors.borderStrong,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: colors.commerceSurface,
              borderRadius: BorderRadius.circular(CoolRadii.md),
              border: Border.all(color: colors.borderStrong),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.storefront_outlined,
              size: 28,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x5),
          Text(
            query.isNotEmpty
                ? 'No results for "$query"'
                : 'No items in $categoryLabel',
            style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            query.isNotEmpty
                ? 'Try another product name, collection, or category.'
                : 'Switch to All to see everything',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x5),
          CoolButton(
            onTap: onReset,
            fullWidth: false,
            variant: CoolButtonVariant.secondary,
            icon: Icons.restart_alt_rounded,
            label: context.l10n.showAllItems,
          ),
        ],
      ),
    );
  }
}

class _ShopCommandCard extends StatelessWidget {
  const _ShopCommandCard({
    required this.searchController,
    required this.itemCount,
    required this.categoryCount,
    required this.hasMemberDiscount,
    required this.checkoutReady,
  });

  final TextEditingController searchController;
  final int itemCount;
  final int categoryCount;
  final bool hasMemberDiscount;
  final bool checkoutReady;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CoolCard(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF041B44), Color(0xFF0A2A63), Color(0xFF16458A)],
      ),
      borderColor: RsColors.rsBlueBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Verified commerce',
            style: theme.textTheme.labelLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.72),
              letterSpacing: 0.35,
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
          Text(
            'Official Club Store',
            style: context.coolText.rayonCondensed(
              const TextStyle(fontSize: 32),
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Premium merchandise, disciplined pricing, and direct club fulfilment.',
            style: context.coolText.rayon(
              const TextStyle(fontSize: 15),
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.8),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ShopTrustChip(
                icon: Icons.verified_outlined,
                label: '$itemCount official listings',
              ),
              _ShopTrustChip(
                icon: Icons.category_outlined,
                label: '$categoryCount categories',
              ),
              _ShopTrustChip(
                icon: Icons.local_offer_outlined,
                label: hasMemberDiscount
                    ? 'Member pricing live'
                    : 'Standard pricing',
              ),
              _ShopTrustChip(
                icon: checkoutReady
                    ? Icons.shield_outlined
                    : Icons.timelapse_rounded,
                label: checkoutReady
                    ? 'Checkout route active'
                    : 'Checkout syncing',
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x4),
          TextField(
            controller: searchController,
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
            decoration: InputDecoration(
              hintText: 'Search kits, outerwear, scarves, accessories',
              hintStyle: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.6),
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: Colors.white.withValues(alpha: 0.78),
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.08),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.14),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShopTrustChip extends StatelessWidget {
  const _ShopTrustChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
