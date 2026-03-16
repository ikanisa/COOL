import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../features/partners/rayon/models/rs_models.dart';

class RsShopItem extends StatelessWidget {
  const RsShopItem({
    required this.product,
    required this.onAddToCart,
    this.hasMemberDiscount = false,
    this.discountPct = 0,
    this.isNew = false,
    this.quantity = 0,
    this.onRemoveFromCart,
    super.key,
  });

  final RsProduct product;
  final VoidCallback onAddToCart;
  final bool hasMemberDiscount;
  final double discountPct;
  final bool isNew;
  final int quantity;
  final VoidCallback? onRemoveFromCart;

  @override
  Widget build(BuildContext context) {
    final showDiscount = hasMemberDiscount && discountPct > 0;
    final discountedPrice = showDiscount
        ? (product.price * (1 - discountPct / 100)).round()
        : product.price;
    final heroBadge = product.badgeLabel?.trim().isNotEmpty == true
        ? product.badgeLabel!.trim().toUpperCase()
        : (isNew ? 'NEW' : null);

    return Semantics(
      label:
          '${product.name}.'
          '${NumberFormat.decimalPattern('en').format(discountedPrice)} RWF. '
          '${quantity > 0 ? '$quantity in cart.' : ''}',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 20,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 88,
                decoration: BoxDecoration(
                  color: _imageBackgroundFor(product),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (product.imageUrl?.trim().isNotEmpty == true)
                        Image.network(
                          product.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              _EmojiHero(product: product),
                        )
                      else
                        _EmojiHero(product: product),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.04),
                              Colors.black.withValues(alpha: 0.18),
                            ],
                          ),
                        ),
                      ),
                      if (showDiscount)
                        Positioned(
                          left: 10,
                          top: 10,
                          child: _Badge(
                            label:
                                '-${discountPct.toStringAsFixed(discountPct.truncateToDouble() == discountPct ? 0 : 1)}%',
                            background: AppColors.rsBlue,
                            foreground: AppColors.rsWhite,
                          ),
                        ),
                      if (heroBadge != null)
                        Positioned(
                          right: 10,
                          top: 10,
                          child: _Badge(
                            label: heroBadge,
                            background: AppColors.rsGold,
                            foreground: AppColors.bg,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (product.collection?.trim().isNotEmpty == true) ...[
                Text(
                  product.collection!.trim().toUpperCase(),
                  style: GoogleFonts.barlow(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: AppColors.text3,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.barlow(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.rsWhite,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                product.description.isEmpty
                    ? product.category.label
                    : product.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.barlow(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text2,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _MetaPill(label: product.category.label),
                  if (product.availableSizes.isNotEmpty)
                    _MetaPill(label: '${product.availableSizes.length} sizes'),
                ],
              ),
              const Spacer(),
              if (showDiscount) ...[
                Text(
                  _formatRwf(product.price),
                  style: GoogleFonts.dmMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text3,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(height: 2),
              ],
              Text(
                _formatRwf(discountedPrice),
                style: GoogleFonts.dmMono(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.rsGoldLight,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (quantity > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.rsBlueGlow,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'x$quantity',
                        style: GoogleFonts.dmMono(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.rsWhite,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.rsBlue,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: onAddToCart,
                            borderRadius: BorderRadius.circular(12),
                            child: Center(
                              child: Text(
                                'ADD TO CART',
                                style: GoogleFonts.barlowCondensed(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.rsWhite,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (quantity > 0 && onRemoveFromCart != null) ...[
                    const SizedBox(width: 8),
                    _IconPill(
                      icon: Icons.remove_rounded,
                      onTap: onRemoveFromCart!,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmojiHero extends StatelessWidget {
  const _EmojiHero({required this.product});

  final RsProduct product;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(product.imageEmoji, style: const TextStyle(fontSize: 42)),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.barlowCondensed(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}

class _IconPill extends StatelessWidget {
  const _IconPill({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.surface3,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.rsBlueBorder),
        ),
        child: Icon(icon, size: 18, color: AppColors.rsWhite),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface3,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        style: GoogleFonts.barlow(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: AppColors.text2,
        ),
      ),
    );
  }
}

Color _imageBackgroundFor(RsProduct product) {
  return Color.alphaBlend(
    Colors.white.withValues(alpha: 0.04),
    product.bgColor,
  );
}

String _formatRwf(int amount) {
  return '${NumberFormat.decimalPattern('en').format(amount)} RWF';
}
