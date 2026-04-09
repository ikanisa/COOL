part of 'qr_scanner_screen.dart';

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay({required this.mode, required this.scanWindow});

  final QrScanMode mode;
  final Rect scanWindow;

  @override
  Widget build(BuildContext context) {
    final radii = context.coolRadii;
    final accentColor = mode == QrScanMode.ticket
        ? Colors.white
        : const Color(0xFFFFC72C);
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
            child: Stack(
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

class _MomoScannerStatusPill extends StatelessWidget {
  const _MomoScannerStatusPill({required this.label});

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
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
        ),
      ),
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

class _TicketResultSheet extends StatelessWidget {
  const _TicketResultSheet({required this.result, required this.onDismiss});

  final _TicketScanResult result;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final textTheme = Theme.of(context).textTheme;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    return Container(
      decoration: BoxDecoration(
        color: colors.elevatedBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(radii.lg)),
      ),
      padding: EdgeInsets.fromLTRB(
        space.x5 + 2,
        space.x4,
        space.x5 + 2,
        space.x8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colors.borderStrong,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(height: space.x5),
          Text(result.isValid ? '✅' : '❌', style: textTheme.displaySmall),
          SizedBox(height: space.x3),
          Text(
            result.isValid ? 'Valid Ticket' : 'Invalid Ticket',
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: result.isValid ? colors.accent : colors.danger,
            ),
          ),
          if (result.message != null) ...[
            SizedBox(height: space.x1 + 2),
            Text(
              result.message!,
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(color: colors.secondaryText),
            ),
          ],
          SizedBox(height: space.x5),
          CoolButton(
            label: 'Scan Another',
            variant: CoolButtonVariant.secondary,
            onTap: onDismiss,
          ),
        ],
      ),
    );
  }
}
