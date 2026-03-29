part of '../screens/club_shop_screen.dart';

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
          color: enabled
              ? RsColors.rsRed
              : colors.cardSurfaceStrong.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(CoolRadii.md),
          border: Border.all(
            color: enabled ? RsColors.rsRedBorder : colors.borderStrong,
            width: 1.5,
          ),
          boxShadow: enabled
              ? const [
                  BoxShadow(
                    color: RsColors.rsRedGlow,
                    blurRadius: 16,
                    offset: Offset(0, 4),
                  )
                ]
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
