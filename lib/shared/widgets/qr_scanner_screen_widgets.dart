part of 'qr_scanner_screen.dart';

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay({required this.scanWindow});

  final Rect scanWindow;

  @override
  Widget build(BuildContext context) {
    final radii = context.coolRadii;
    const accentColor = Color(0xFFFFC72C);
    return Stack(
      children: [
        ColorFiltered(
          colorFilter: ColorFilter.mode(
            Colors.black.withValues(alpha: 0.56),
            BlendMode.srcOut,
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    backgroundBlendMode: BlendMode.dstOut,
                  ),
                ),
              ),
              Positioned.fromRect(
                rect: scanWindow,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(radii.lg),
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned.fromRect(
          rect: scanWindow,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radii.lg),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.24),
                width: 1.4,
              ),
            ),
            child: const Stack(
              children: [
                _CornerMarker(alignment: Alignment.topLeft, color: accentColor),
                _CornerMarker(
                  alignment: Alignment.topRight,
                  color: accentColor,
                ),
                _CornerMarker(
                  alignment: Alignment.bottomLeft,
                  color: accentColor,
                ),
                _CornerMarker(
                  alignment: Alignment.bottomRight,
                  color: accentColor,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CornerMarker extends StatelessWidget {
  const _CornerMarker({required this.alignment, required this.color});

  final Alignment alignment;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isTop = alignment.y < 0;
    final isLeft = alignment.x < 0;

    return Align(
      alignment: alignment,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.only(
            topLeft: isTop && isLeft ? const Radius.circular(22) : Radius.zero,
            topRight: isTop && !isLeft
                ? const Radius.circular(22)
                : Radius.zero,
            bottomLeft: !isTop && isLeft
                ? const Radius.circular(22)
                : Radius.zero,
            bottomRight: !isTop && !isLeft
                ? const Radius.circular(22)
                : Radius.zero,
          ),
          border: Border(
            top: isTop ? BorderSide(color: color, width: 4) : BorderSide.none,
            bottom: !isTop
                ? BorderSide(color: color, width: 4)
                : BorderSide.none,
            left: isLeft ? BorderSide(color: color, width: 4) : BorderSide.none,
            right: !isLeft
                ? BorderSide(color: color, width: 4)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }
}
