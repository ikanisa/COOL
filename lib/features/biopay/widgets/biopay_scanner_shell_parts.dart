part of 'biopay_scanner_shell.dart';

class _BiopayStatusPill extends StatelessWidget {
  const _BiopayStatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
      padding: const EdgeInsets.symmetric(
        horizontal: CoolSpace.x5,
        vertical: CoolSpace.x3,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(CoolRadii.xl),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
        ),
      ),
    );
  }
}

class _BiopaySampleDots extends StatelessWidget {
  const _BiopaySampleDots({
    required this.sampleCount,
    required this.totalSamples,
    required this.color,
  });

  final int sampleCount;
  final int totalSamples;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(totalSamples, (index) {
        final filled = index < sampleCount;
        return AnimatedContainer(
          duration: CoolMotion.quick,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: filled ? color : Colors.white.withValues(alpha: 0.18),
            shape: BoxShape.circle,
            boxShadow: filled
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
        );
      }),
    );
  }
}

class _BiopayFramePainter extends CustomPainter {
  const _BiopayFramePainter({
    required this.color,
    required this.frameRect,
    required this.isEnrollMode,
  });

  final Color color;
  final Rect frameRect;
  final bool isEnrollMode;

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPath = Path()
      ..addRect(Offset.zero & size)
      ..fillType = PathFillType.evenOdd;

    final cutout = Path();
    if (isEnrollMode) {
      cutout.addRRect(
        RRect.fromRectAndRadius(
          frameRect,
          Radius.circular(frameRect.width / 2),
        ),
      );
    } else {
      cutout.addRRect(
        RRect.fromRectAndRadius(frameRect, const Radius.circular(32)),
      );
    }

    overlayPath.addPath(cutout, Offset.zero);
    canvas.drawPath(
      overlayPath,
      Paint()..color = Colors.black.withValues(alpha: 0.58),
    );

    final borderPaint = Paint()
      ..color = color.withValues(alpha: isEnrollMode ? 0.72 : 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = isEnrollMode ? 4 : 2.2;

    if (isEnrollMode) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          frameRect,
          Radius.circular(frameRect.width / 2),
        ),
        borderPaint,
      );
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(frameRect, const Radius.circular(32)),
        borderPaint,
      );
      _drawCornerGuides(canvas);
    }
  }

  void _drawCornerGuides(Canvas canvas) {
    const length = 34.0;
    const radius = 20.0;
    final guidePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    void corner(Offset origin, bool left, bool top) {
      final path = Path();
      path.moveTo(origin.dx, origin.dy + (top ? length : -length));
      path.lineTo(origin.dx, origin.dy + (top ? radius : -radius));
      path.quadraticBezierTo(
        origin.dx,
        origin.dy,
        origin.dx + (left ? radius : -radius),
        origin.dy,
      );
      path.lineTo(origin.dx + (left ? length : -length), origin.dy);
      canvas.drawPath(path, guidePaint);
      final arcRect = Rect.fromCircle(center: origin, radius: radius);
      canvas.drawArc(
        arcRect,
        top ? (left ? 3.14159 : -1.57079) : (left ? 1.57079 : 0),
        1.57079,
        false,
        guidePaint,
      );
    }

    corner(frameRect.topLeft, true, true);
    corner(frameRect.topRight, false, true);
    corner(frameRect.bottomLeft, true, false);
    corner(frameRect.bottomRight, false, false);
  }

  @override
  bool shouldRepaint(covariant _BiopayFramePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.frameRect != frameRect ||
        oldDelegate.isEnrollMode != isEnrollMode;
  }
}
