part of '../screens/club_shop_screen.dart';

// ═══════════════════════════════════════════════════════════
// Section 2  — Search Bar
// ═══════════════════════════════════════════════════════════

class _ShopSearchBar extends StatelessWidget {
  const _ShopSearchBar({required this.controller});

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
                color: isSelected
                    ? RsColors.rsRed
                    : colors.cardSurfaceStrong.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(CoolRadii.pill),
                border: Border.all(
                  color: isSelected ? RsColors.rsRedBorder : colors.borderStrong,
                ),
                boxShadow: isSelected
                    ? const [
                        BoxShadow(
                          color: RsColors.rsRedGlow,
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        )
                      ]
                    : null,
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
