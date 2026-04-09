import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/cool_foundations.dart';

part 'biopay_scanner_shell_parts.dart';

enum BiopayScannerTone { searching, ready, blocked, error }

class BiopayScannerShell extends StatelessWidget {
  const BiopayScannerShell({
    required this.isCameraReady,
    required this.statusLabel,
    required this.helperText,
    required this.tone,
    this.controller,
    this.footer,
    this.sampleCount = 0,
    this.totalSamples = 5,
    this.isEnrollMode = true,
    super.key,
  });

  final CameraController? controller;
  final bool isCameraReady;
  final String statusLabel;
  final String helperText;
  final BiopayScannerTone tone;
  final Widget? footer;
  final int sampleCount;
  final int totalSamples;
  final bool isEnrollMode;

  Color _toneColor() {
    return switch (tone) {
      BiopayScannerTone.searching => const Color(0xFF61616B),
      BiopayScannerTone.ready => const Color(0xFF22C55E),
      BiopayScannerTone.blocked => const Color(0xFFFFC72C),
      BiopayScannerTone.error => const Color(0xFFFF6B6B),
    };
  }

  @override
  Widget build(BuildContext context) {
    final space = context.coolSpace;
    final bottomPad = MediaQuery.viewPaddingOf(context).bottom;
    final toneColor = _toneColor();

    return LayoutBuilder(
      builder: (context, constraints) {
        final frameHeight = (constraints.maxHeight * 0.50).clamp(360.0, 480.0);
        final frameWidth = (constraints.maxWidth - 72).clamp(260.0, 340.0);
        final frameRect = Rect.fromCenter(
          center: Offset(
            constraints.maxWidth / 2,
            constraints.maxHeight * 0.42,
          ),
          width: frameWidth,
          height: frameHeight,
        );

        return Stack(
          children: [
            Positioned.fill(
              child: isCameraReady && controller != null
                  ? CameraPreview(controller!)
                  : const ColoredBox(color: Colors.black),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _BiopayFramePainter(
                    color: toneColor,
                    frameRect: frameRect,
                    isEnrollMode: isEnrollMode,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: frameRect.bottom - 28,
              child: Column(
                children: [
                  _BiopayStatusPill(label: statusLabel),
                  if (isEnrollMode) ...[
                    const SizedBox(height: CoolSpace.x3),
                    _BiopaySampleDots(
                      sampleCount: sampleCount,
                      totalSamples: totalSamples,
                      color: toneColor,
                    ),
                  ],
                ],
              ),
            ),
            Positioned(
              left: space.x5,
              right: space.x5,
              bottom: bottomPad + (footer == null ? 52 : 120),
              child: Text(
                isEnrollMode
                    ? 'KEEP YOUR FACE WITHIN THE OVAL'
                    : 'KEEP THE FACE CENTERED IN THE OVAL',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.48),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3.0,
                ),
              ),
            ),
            if (footer != null)
              Positioned(
                left: space.x5,
                right: space.x5,
                bottom: bottomPad + space.x4,
                child: footer!,
              ),
          ],
        );
      },
    );
  }
}
