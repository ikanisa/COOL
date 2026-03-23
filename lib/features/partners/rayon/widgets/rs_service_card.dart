import 'package:flutter/material.dart';

import '../../../../core/theme/cool_foundations.dart';
import '../../../../core/theme/rs_colors.dart';

class RsServiceCard extends StatelessWidget {
  const RsServiceCard({
    required this.icon,
    required this.name,
    required this.description,
    required this.count,
    required this.onTap,
    this.isWide = false,
    this.accentColor,
    super.key,
  });

  final IconData icon;
  final String name;
  final String description;
  final String count;
  final VoidCallback onTap;
  final bool isWide;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final lineColor = accentColor ?? RsColors.rsBlue;

    return Semantics(
      button: true,
      label: '$name service',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          splashColor: RsColors.rsBlueGlow,
          highlightColor: RsColors.rsBlueGlow.withValues(alpha: 0.22),
          child: Ink(
            decoration: BoxDecoration(
              color: colors.cardSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.borderStrong),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: lineColor,
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(18),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                  child: isWide
                      ? _WideContent(lineColor: lineColor, card: this)
                      : _TallContent(lineColor: lineColor, card: this),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TallContent extends StatelessWidget {
  const _TallContent({required this.lineColor, required this.card});

  final Color lineColor;
  final RsServiceCard card;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(card.icon, size: 24, color: colors.primaryText),
        const SizedBox(height: 14),
        Text(
          card.name,
          style: GoogleFonts.barlowCondensed(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: RsColors.rsWhite,
            height: 0.95,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          card.description,
          style: GoogleFonts.barlow(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: colors.secondaryText,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          card.count,
          style: GoogleFonts.dmMono(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: lineColor,
          ),
        ),
      ],
    );
  }
}

class _WideContent extends StatelessWidget {
  const _WideContent({required this.lineColor, required this.card});

  final Color lineColor;
  final RsServiceCard card;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Row(
      children: [
        Icon(card.icon, size: 26, color: colors.primaryText),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                card.name,
                style: GoogleFonts.barlowCondensed(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: RsColors.rsWhite,
                  height: 0.95,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                card.description,
                style: GoogleFonts.barlow(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: colors.secondaryText,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                card.count,
                style: GoogleFonts.dmMono(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: lineColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Icon(Icons.arrow_forward_rounded, color: lineColor, size: 20),
      ],
    );
  }
}
