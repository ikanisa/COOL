import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../../shared/widgets/atmospheric_background.dart';
import '../../../../shared/widgets/cool_empty_view.dart';
import '../models/rs_models.dart';
import '../../providers/rayon_sports_provider.dart';

/// Product detail screen — matches React `ProductDetailScreen.tsx` 1:1.
///
/// Layout: AtmosphericBackground → frosted header → product image (4:5 aspect
/// with badge + favorite) → category/name/price/rating → feature chips →
/// quantity selector → floating footer (Add to Cart + Buy Now).
class ProductDetailScreen extends ConsumerStatefulWidget {
  const ProductDetailScreen({required this.productId, super.key});

  final String productId;

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  int _quantity = 1;
  bool _isFavorite = false;

  static final _currencyFormat = NumberFormat('#,##0', 'en_US');

  void _increment() => setState(() => _quantity++);
  void _decrement() {
    if (_quantity > 1) setState(() => _quantity--);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final catalog = ref.watch(rayonShopCatalogProvider);
    final products = catalog.valueOrNull?.products ?? <RsProduct>[];

    RsProduct? found;
    for (final p in products) {
      if (p.id == widget.productId) {
        found = p;
        break;
      }
    }

    if (found == null) {
      return Scaffold(
        backgroundColor: colors.appBackground,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shopping_bag_outlined, size: 48,
                  color: Colors.white.withValues(alpha: 0.20)),
              const SizedBox(height: 16),
              Text(
                'PRODUCT NOT FOUND',
                style: context.coolText.mobiLabel(color: Colors.white54),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => context.pop(),
                child: Text(
                  'GO BACK',
                  style: TextStyle(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final product = found;


    return Scaffold(
      backgroundColor: colors.appBackground,
      body: Stack(
        children: [
          const AtmosphericBackground(),

          // ── Scrollable content ──────────────────────────────────
          CustomScrollView(
            slivers: [
              // ── Header ───────────────────────────────────────────
              SliverAppBar(
                pinned: true,
                backgroundColor:
                    colors.appBackground.withValues(alpha: 0.80),
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                leading: _HeaderButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: () => context.pop(),
                ),
                title: Text(
                  'PRODUCT DETAILS',
                  style: context.coolText.mobiLabel(
                    color: Colors.white.withValues(alpha: 0.40),
                  ),
                ),
                centerTitle: true,
                actions: [
                  _HeaderButton(
                    icon: Icons.share_rounded,
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: colors.appBackground,
                        builder: (context) => const Padding(
                          padding: EdgeInsets.all(32),
                          child: CoolEmptyView(
                            message: 'Sharing currently unavailable',
                            icon: Icons.share_rounded,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ),

              // ── Image Section ──────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: AspectRatio(
                    aspectRatio: 4 / 5,
                    child: Stack(
                      children: [
                        // Product image / emoji placeholder
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(40),
                            color: product.imageUrl != null
                                ? null
                                : product.bgColor.withValues(alpha: 0.30),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.10),
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: product.imageUrl != null
                              ? Image.network(
                                  product.imageUrl!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                  errorBuilder: (_, _, _) => _EmojiPlaceholder(
                                    emoji: product.imageEmoji,
                                    bgColor: product.bgColor,
                                  ),
                                )
                              : _EmojiPlaceholder(
                                  emoji: product.imageEmoji,
                                  bgColor: product.bgColor,
                                ),
                        ),

                        // Gradient overlay (bottom)
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(40),
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  colors.appBackground.withValues(alpha: 0.80),
                                  Colors.transparent,
                                ],
                                stops: const [0.0, 0.4],
                              ),
                            ),
                          ),
                        ),

                        // Badge
                        if (product.badgeLabel != null)
                          Positioned(
                            top: 20,
                            left: 20,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: colors.accent,
                                borderRadius: BorderRadius.circular(
                                  CoolRadii.pill,
                                ),
                              ),
                              child: Text(
                                product.badgeLabel!.toUpperCase(),
                                style: context.coolText
                                    .mobiLabel(color: Colors.white)
                                    .copyWith(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.5,
                                    ),
                              ),
                            ),
                          ),

                        // Favorite button
                        Positioned(
                          top: 20,
                          right: 20,
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _isFavorite = !_isFavorite),
                            child: AnimatedContainer(
                              duration: CoolMotion.quick,
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: _isFavorite
                                    ? Colors.red
                                    : Colors.white.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: _isFavorite
                                      ? Colors.red.shade300
                                      : Colors.white.withValues(alpha: 0.20),
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                _isFavorite
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                size: 20,
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

              // ── Info Section ───────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                sliver: SliverList.list(
                  children: [
                    // Category + collection
                    Row(
                      children: [
                        Text(
                          product.category.label.toUpperCase(),
                          style: context.coolText
                              .mobiLabel(color: colors.accent)
                              .copyWith(fontSize: 10),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.20),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Text(
                          (product.collection ?? 'Official Merchandise')
                              .toUpperCase(),
                          style: context.coolText
                              .mobiLabel(
                                color: Colors.white.withValues(alpha: 0.40),
                              )
                              .copyWith(fontSize: 10),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Product name
                    Text(
                      product.name.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -1,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Price + rating
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'PRICE',
                                style: context.coolText.mobiLabel(
                                  color: Colors.white.withValues(alpha: 0.40),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    _currencyFormat.format(product.price),
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w900,
                                      color: colors.accentGold,
                                      fontFamily: 'JetBrains Mono',
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'RWF',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      color: colors.accentGold
                                          .withValues(alpha: 0.60),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Rating pill
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius:
                                BorderRadius.circular(CoolRadii.pill),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.10),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star_rounded,
                                  size: 12, color: colors.accentGold),
                              const SizedBox(width: 4),
                              const Text(
                                '4.9',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Text(
                                '(128)',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white.withValues(alpha: 0.40),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Description
                    if (product.description.isNotEmpty)
                      Text(
                        product.description,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.60),
                          height: 1.6,
                        ),
                      ),
                    const SizedBox(height: 24),

                    // ── Feature chips (2-col) ────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: _FeatureChip(
                            icon: Icons.verified_user_rounded,
                            iconColor: colors.accent,
                            title: 'AUTHENTIC',
                            subtitle: 'GUARANTEED',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _FeatureChip(
                            icon: Icons.local_shipping_rounded,
                            iconColor: colors.accentGold,
                            title: 'FAST SHIP',
                            subtitle: '2-3 DAYS',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // ── Quantity selector ─────────────────────────
                    Text(
                      'SELECT QUANTITY',
                      style: context.coolText.mobiLabel(
                        color: Colors.white.withValues(alpha: 0.40),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        // Stepper
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.10),
                            ),
                          ),
                          padding: const EdgeInsets.all(4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _StepperButton(
                                icon: Icons.remove_rounded,
                                onTap: _decrement,
                              ),
                              SizedBox(
                                width: 48,
                                child: Center(
                                  child: Text(
                                    '$_quantity',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      fontFamily: 'JetBrains Mono',
                                    ),
                                  ),
                                ),
                              ),
                              _StepperButton(
                                icon: Icons.add_rounded,
                                onTap: _increment,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.40),
                                height: 1.4,
                              ),
                              children: [
                                const TextSpan(text: 'Only '),
                                TextSpan(
                                  text: '${product.stock}',
                                  style: TextStyle(
                                    color: colors.accent,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const TextSpan(text: ' units left in stock.'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Bottom padding for floating footer
                    const SizedBox(height: 120),
                  ],
                ),
              ),
            ],
          ),

          // ── Floating footer ────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                24,
                16,
                24,
                16 + MediaQuery.paddingOf(context).bottom,
              ),
              decoration: BoxDecoration(
                color: colors.appBackground.withValues(alpha: 0.80),
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
              ),
              child: ClipRect(
                child: Row(
                  children: [
                    // Add to cart button
                    GestureDetector(
                      onTap: () {
                        final cartCtrl =
                            ref.read(rayonCartControllerProvider.notifier);
                        for (var i = 0; i < _quantity; i++) {
                          cartCtrl.addToCart(product.id);
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Added $_quantity × ${product.name} to cart',
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      child: Container(
                        width: 64,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.10),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.shopping_bag_outlined,
                          size: 24,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Buy Now button
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          final cartCtrl =
                              ref.read(rayonCartControllerProvider.notifier);
                          for (var i = 0; i < _quantity; i++) {
                            cartCtrl.addToCart(product.id);
                          }
                          context.push(AppRoutes.rayonShopCheckout);
                        },
                        child: Container(
                          height: 56,
                          decoration: BoxDecoration(
                            color: colors.accent,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: colors.accent.withValues(alpha: 0.20),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'BUY NOW',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 2.5,
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                            ],
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
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.10),
            ),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 22, color: Colors.white),
        ),
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.40),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 20, color: Colors.white),
      ),
    );
  }
}

class _EmojiPlaceholder extends StatelessWidget {
  const _EmojiPlaceholder({required this.emoji, required this.bgColor});

  final String emoji;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: bgColor.withValues(alpha: 0.15),
      alignment: Alignment.center,
      child: Text(
        emoji,
        style: const TextStyle(fontSize: 80),
      ),
    );
  }
}
