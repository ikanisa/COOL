part of 'biopay_scanner_shell.dart';

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
  const _BiopayFramePainter({required this.color, required this.frameRect});

  final Color color;
  final Rect frameRect;

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPath = Path()
      ..addRect(Offset.zero & size)
      ..fillType = PathFillType.evenOdd;

    final cutout = Path();
    cutout.addOval(frameRect);

    overlayPath.addPath(cutout, Offset.zero);
    canvas.drawPath(
      overlayPath,
      Paint()..color = Colors.black.withValues(alpha: 0.58),
    );

    final borderPaint = Paint()
      ..color = color.withValues(alpha: 0.84)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2;

    canvas.drawOval(frameRect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _BiopayFramePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.frameRect != frameRect;
  }
}
