part of 'qr_scanner_screen.dart';

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay({required this.mode, required this.scanWindow});

  final QrScanMode mode;
  final Rect scanWindow;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final radii = context.coolRadii;
    final accentColor = mode == QrScanMode.ticket
        ? Colors.white
        : colors.accent;
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
    final text = context.coolText;
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
          if (result.matchTitle != null ||
              result.seatType != null ||
              result.ticketId != null) ...[
            SizedBox(height: space.x4),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(space.x3 + 2),
              decoration: BoxDecoration(
                color: colors.inputSurface,
                borderRadius: BorderRadius.circular(radii.sm),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (result.matchTitle != null)
                    Text(
                      result.matchTitle!,
                      style: textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.primaryText,
                      ),
                    ),
                  if (result.seatType != null) ...[
                    SizedBox(height: space.x1),
                    Text(
                      result.seatType!.toUpperCase(),
                      style: text.mono(
                        textTheme.labelSmall,
                        fontWeight: FontWeight.w700,
                        color: colors.accent,
                      ),
                    ),
                  ],
                  if (result.ticketId != null) ...[
                    SizedBox(height: space.x1),
                    Text(
                      'Ticket: ${result.ticketId}',
                      style: text.mono(
                        textTheme.labelSmall,
                        fontWeight: FontWeight.w600,
                        color: colors.tertiaryText,
                      ),
                    ),
                  ],
                  if ((result.pointsAwarded ?? 0) > 0) ...[
                    SizedBox(height: space.x1),
                    Text(
                      '+${result.pointsAwarded} attendance points',
                      style: textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.accent,
                      ),
                    ),
                  ],
                ],
              ),
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
