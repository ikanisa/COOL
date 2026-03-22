import 'package:flutter/material.dart';

import '../../../core/theme/cool_palette.dart';
import '../models/partner.dart';

class PartnerBrandMark extends StatelessWidget {
  const PartnerBrandMark({
    required this.partner,
    this.width = 120,
    this.height = 56,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    this.showFrame = true,
    super.key,
  });

  final Partner partner;
  final double width;
  final double height;
  final EdgeInsets padding;
  final bool showFrame;

  static const _assetBySlug = <String, String>{
    'urwego': 'assets/images/partners/urwego_logo.png',
    'equity': 'assets/images/partners/equity_logo.png',
    'rayon-sports': 'assets/images/partners/rs_logo.png',
    'rayon_sports_fc': 'assets/images/partners/rs_logo.png',
    'rayon-sports-fc': 'assets/images/partners/rs_logo.png',
    'rayon_sports': 'assets/images/partners/rs_logo.png',
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final image = _buildImage();
    final child = SizedBox(
      width: width,
      height: height,
      child: Padding(padding: padding, child: image),
    );

    if (!showFrame) return child;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: child,
    );
  }

  Widget _buildImage() {
    final assetPath = _assetBySlug[partner.slug];
    if (assetPath != null) {
      return Image.asset(
        assetPath,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, _, _) => _EmojiFallback(emoji: partner.emoji),
      );
    }

    final logoUrl = partner.logoUrl?.trim();
    if (logoUrl != null && logoUrl.isNotEmpty) {
      return Image.network(
        logoUrl,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, _, _) => _EmojiFallback(emoji: partner.emoji),
      );
    }

    return _EmojiFallback(emoji: partner.emoji);
  }
}

class _EmojiFallback extends StatelessWidget {
  const _EmojiFallback({required this.emoji});

  final String emoji;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(emoji, style: const TextStyle(fontSize: 28)));
  }
}
