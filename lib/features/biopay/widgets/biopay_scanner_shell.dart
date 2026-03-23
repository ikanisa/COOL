import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_card.dart';

enum BiopayScannerTone { searching, ready, blocked, error }

class BiopayScannerShell extends StatelessWidget {
  const BiopayScannerShell({
    required this.isCameraReady,
    required this.statusLabel,
    required this.helperText,
    required this.tone,
    this.controller,
    this.footer,
    super.key,
  });

  final CameraController? controller;
  final bool isCameraReady;
  final String statusLabel;
  final String helperText;
  final BiopayScannerTone tone;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final space = context.coolSpace;
    final colors = context.coolSemanticColors;
    final statusColor = switch (tone) {
      BiopayScannerTone.searching => const Color(0xFFF0B429),
      BiopayScannerTone.ready => colors.success,
      BiopayScannerTone.blocked => colors.warning,
      BiopayScannerTone.error => colors.danger,
    };

    return Stack(
      children: [
        Positioned.fill(
          child: isCameraReady && controller != null
              ? CameraPreview(controller!)
              : DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [colors.cardSurfaceStrong, colors.appBackground],
                    ),
                  ),
                ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _BiopayScannerOverlayPainter(color: statusColor),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(space.x5, space.x5, space.x5, 0),
            child: Align(
              alignment: Alignment.topLeft,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.48),
                  borderRadius: const BorderRadius.all(
                    Radius.circular(CoolRadii.pill),
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: space.x3,
                    vertical: space.x2,
                  ),
                  child: Text(
                    'Secure camera',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: space.x5,
          right: space.x5,
          bottom: space.x6,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CoolCard(
                backgroundColor: Colors.black.withValues(alpha: 0.66),
                borderColor: Colors.white.withValues(alpha: 0.12),
                useGradient: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: space.x2),
                        Expanded(
                          child: Text(
                            statusLabel,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: space.x2),
                    Text(
                      helperText,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontWeight: FontWeight.w500,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              if (footer != null) ...[SizedBox(height: space.x3), footer!],
            ],
          ),
        ),
      ],
    );
  }
}

class _BiopayScannerOverlayPainter extends CustomPainter {
  const _BiopayScannerOverlayPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPaint = Paint()..color = Colors.black.withValues(alpha: 0.38);
    final fullRect = Path()..addRect(Offset.zero & size);
    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.44),
      width: size.width * 0.62,
      height: size.height * 0.42,
    );
    final ovalPath = Path()..addOval(ovalRect);
    final mask = Path.combine(PathOperation.difference, fullRect, ovalPath);
    canvas.drawPath(mask, overlayPaint);

    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawOval(ovalRect, borderPaint);

    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawOval(ovalRect, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _BiopayScannerOverlayPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
