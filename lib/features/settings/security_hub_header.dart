import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../shared/widgets/collect_components.dart';

/// Security's measured DESK-015 / LIVE-013 header adapter. The dotted field is
/// drawn here; private reference pixels and source incident workflows stay out
/// of the product. Light/high contrast use the target's legible canvas roles.
class SecurityHubHeader extends StatelessWidget {
  const SecurityHubHeader({required this.onBack, super.key});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final titleStyle = Theme.of(context).textTheme.headlineMedium!.copyWith(
      color: colors.textPrimary,
      fontWeight: CollectTypography.weightBold,
    );
    return CustomPaint(
      painter: _SecurityDottedWave(
        canvas: colors.canvas,
        upper: dark ? colors.surfaceReadable : colors.surfaceRaised,
        dark: dark,
      ),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              tooltip: 'Back',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                foregroundColor: colors.textPrimary,
                backgroundColor: colors.canvas.withValues(alpha: 0.72),
                side: BorderSide(color: colors.border),
              ),
            ),
          ),
          const SizedBox(height: 104),
          Semantics(
            header: true,
            headingLevel: 1,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ExcludeSemantics(
                    child: Icon(
                      CollectIcons.shield,
                      color: colors.textPrimary,
                      size: 28,
                    ),
                  ),
                  CollectSpacing.gapW12,
                  Flexible(
                    child: Text(
                      'Security',
                      textAlign: TextAlign.center,
                      style: titleStyle,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityDottedWave extends CustomPainter {
  const _SecurityDottedWave({
    required this.canvas,
    required this.upper,
    required this.dark,
  });

  final Color canvas;
  final Color upper;
  final bool dark;

  // Repeated teal dot sample (43,67,66) from DESK-015's x35..350/y65..220
  // region. A rendered sample, not an exported native colour token.
  static const _sourceDot = Color(0xFF2B4342);

  @override
  void paint(Canvas drawing, Size size) {
    const inset = CollectSpacing.screenCompact;
    final bounds = Rect.fromLTRB(
      -inset,
      -inset,
      size.width + inset,
      size.height,
    );
    drawing.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [upper, upper, canvas],
          stops: const [0, 0.35, 1],
        ).createShader(bounds),
    );
    final dotPaint = Paint();
    const pitch = 10.0;
    for (var row = -2; row * pitch < size.height; row++) {
      final y = row * pitch;
      final fade = math.pow(1 - (y / size.height).clamp(0.0, 1.0), 1.6);
      for (var col = -2; col * pitch < size.width + inset; col++) {
        final x = col * pitch + math.sin(row * 0.16) * 9;
        final wave = (math.sin(x / 70 + y / 58) + 1) / 2;
        final radius = 0.5 + wave * 1.05;
        dotPaint.color = _sourceDot.withValues(
          alpha: (fade * (dark ? 0.92 : 0.16)).toDouble(),
        );
        drawing.drawCircle(Offset(x, y), radius, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_SecurityDottedWave oldDelegate) =>
      oldDelegate.canvas != canvas ||
      oldDelegate.upper != upper ||
      oldDelegate.dark != dark;
}
