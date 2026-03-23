import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/cool_foundations.dart';
import '../../core/theme/rs_colors.dart';
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
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    final theme = Theme.of(context);
    final showDiscount = hasMemberDiscount && discountPct > 0;
    final discountedPrice = showDiscount
        ? product.discountedPrice(discountPct)
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
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.commerceSurface,
              colors.cardSurfaceStrong.withValues(alpha: 0.96),
            ],
          ),
          borderRadius: BorderRadius.circular(radii.md),
          border: Border.all(
            color: RsColors.rsBlueBorder.withValues(alpha: 0.72),
          ),
          boxShadow: CoolShadows.floating(theme.brightness, strength: 0.3),
        ),
        child: Padding(
          padding: EdgeInsets.all(space.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 80,
                decoration: BoxDecoration(
                  color: _imageBackgroundFor(product, colors),
                  borderRadius: BorderRadius.circular(radii.sm),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radii.sm),
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
                              colors.shadowColor.withValues(alpha: 0.04),
                              colors.shadowColor.withValues(alpha: 0.18),
                            ],
                          ),
                        ),
                      ),
                      if (showDiscount)
                        Positioned(
                          left: space.x2,
                          top: space.x2,
                          child: _Badge(
                            label:
                                '-${discountPct.toStringAsFixed(discountPct.truncateToDouble() == discountPct ? 0 : 1)}%',
                            background: RsColors.rsBlue,
                            foreground: RsColors.rsWhite,
                          ),
                        ),
                      if (heroBadge != null)
                        Positioned(
                          right: space.x2,
                          top: space.x2,
                          child: _Badge(
                            label: heroBadge,
                            background: RsColors.rsGold,
                            foreground: colors.primaryText,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: space.x2),
              if (product.collection?.trim().isNotEmpty == true) ...[
                Text(
                  product.collection!.trim().toUpperCase(),
                  style: text.rayon(
                    theme.textTheme.labelSmall,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: colors.tertiaryText,
                  ),
                ),
                SizedBox(height: space.x1),
              ],
              Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.rayonCondensed(
                  theme.textTheme.titleSmall,
                  fontWeight: FontWeight.w800,
                  color: RsColors.rsWhite,
                  height: 1.05,
                ),
              ),
              SizedBox(height: space.x1),
              Text(
                product.description.isEmpty
                    ? product.category.label
                    : product.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.rayon(
                  theme.textTheme.labelSmall,
                  fontWeight: FontWeight.w700,
                  color: colors.secondaryText,
                  height: 1.2,
                ),
              ),
              SizedBox(height: space.x2),
              Wrap(
                spacing: space.x1 + 2,
                runSpacing: space.x1 + 2,
                children: [
                  _MetaPill(label: product.category.label),
                  if (product.availableSizes.isNotEmpty)
                    _MetaPill(label: '${product.availableSizes.length} sizes'),
                ],
              ),
              SizedBox(height: space.x2),
              Wrap(
                spacing: space.x1 + 2,
                runSpacing: space.x1 + 2,
                children: [
                  const _TrustFlag(
                    icon: Icons.verified_outlined,
                    label: 'Official seller',
                  ),
                  _TrustFlag(
                    icon: showDiscount
                        ? Icons.local_offer_outlined
                        : Icons.inventory_2_outlined,
                    label: showDiscount ? 'Member offer' : 'Direct fulfilment',
                  ),
                ],
              ),
              SizedBox(height: space.x2),
              if (showDiscount) ...[
                Text(
                  _formatRwf(product.price),
                  style: text
                      .mono(
                        theme.textTheme.labelSmall,
                        fontWeight: FontWeight.w700,
                        color: colors.tertiaryText,
                      )
                      .copyWith(decoration: TextDecoration.lineThrough),
                ),
                SizedBox(height: space.x1 / 2),
              ],
              Text(
                _formatRwf(discountedPrice),
                style: text.mono(
                  theme.textTheme.labelLarge,
                  fontWeight: FontWeight.w700,
                  color: RsColors.rsGoldLight,
                ),
              ),
              SizedBox(height: space.x2),
              Row(
                children: [
                  if (quantity > 0) ...[
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: space.x2,
                        vertical: space.x1 + 2,
                      ),
                      decoration: BoxDecoration(
                        color: RsColors.rsBlueGlow,
                        borderRadius: BorderRadius.circular(radii.sm),
                        border: Border.all(color: RsColors.rsBlueBorder),
                      ),
                      child: Text(
                        'x$quantity',
                        style: text.mono(
                          theme.textTheme.labelSmall,
                          fontWeight: FontWeight.w700,
                          color: RsColors.rsWhite,
                        ),
                      ),
                    ),
                    SizedBox(width: space.x2),
                  ],
                  Expanded(
                    child: SizedBox(
                      height: CoolTapTargets.minimum,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RsColors.rsGoldGradient,
                          borderRadius: BorderRadius.circular(radii.sm),
                        ),
                        child: Material(
                          type: MaterialType.transparency,
                          child: InkWell(
                            onTap: onAddToCart,
                            borderRadius: BorderRadius.circular(radii.sm),
                            child: Center(
                              child: Text(
                                quantity > 0 ? 'ADD MORE' : 'ADD TO BAG',
                                style: text.rayonCondensed(
                                  theme.textTheme.labelLarge,
                                  fontWeight: FontWeight.w700,
                                  color: colors.primaryText,
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
                    SizedBox(width: space.x2),
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
    final text = context.coolText;
    final theme = Theme.of(context);
    return Center(
      child: Text(
        product.imageEmoji,
        style: text.rayonCondensed(
          theme.textTheme.displaySmall,
          fontWeight: FontWeight.w800,
        ),
      ),
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
    final text = context.coolText;
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: space.x2, vertical: space.x1),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radii.pill),
      ),
      child: Text(
        label,
        style: text.rayonCondensed(
          theme.textTheme.labelLarge,
          fontWeight: FontWeight.w700,
          color: foreground == colors.primaryText
              ? colors.primaryText
              : foreground,
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
    final colors = context.coolSemanticColors;
    final radii = context.coolRadii;
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radii.sm),
      child: Ink(
        width: CoolTapTargets.minimum,
        height: CoolTapTargets.minimum,
        decoration: BoxDecoration(
          color: colors.overlaySurface,
          borderRadius: BorderRadius.circular(radii.sm),
          border: Border.all(color: RsColors.rsBlueBorder),
        ),
        child: Icon(icon, size: 18, color: RsColors.rsWhite),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: space.x2, vertical: space.x1),
      decoration: BoxDecoration(
        color: colors.overlaySurface,
        borderRadius: BorderRadius.circular(radii.pill),
        border: Border.all(color: colors.borderStrong),
      ),
      child: Text(
        label,
        style: text.rayon(
          theme.textTheme.labelSmall,
          fontWeight: FontWeight.w700,
          color: colors.secondaryText,
        ),
      ),
    );
  }
}

class _TrustFlag extends StatelessWidget {
  const _TrustFlag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: space.x2,
        vertical: space.x1 + 1,
      ),
      decoration: BoxDecoration(
        color: colors.overlaySurface,
        borderRadius: BorderRadius.circular(radii.pill),
        border: Border.all(color: colors.borderStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.secondaryText),
          SizedBox(width: space.x1 + 1),
          Text(
            label,
            style: text.rayon(
              theme.textTheme.labelSmall,
              fontWeight: FontWeight.w700,
              color: colors.primaryText,
            ),
          ),
        ],
      ),
    );
  }
}

Color _imageBackgroundFor(RsProduct product, CoolSemanticColors colors) {
  return Color.alphaBlend(
    colors.highlightColor.withValues(alpha: 0.06),
    product.bgColor,
  );
}

String _formatRwf(int amount) {
  return '${NumberFormat.decimalPattern('en').format(amount)} RWF';
}
