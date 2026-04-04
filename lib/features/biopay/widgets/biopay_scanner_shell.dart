import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/cool_foundations.dart';

enum BiopayScannerTone { searching, ready, blocked, error }

/// Premium biometric scanner shell — Apple Face ID-inspired capture UI.
///
/// Features:
/// - Segmented progress ring around the face oval (enrollment) or continuous
///   pulsing ring (pay mode)
/// - Animated floating status chip at top
/// - Sample capture dots with checkmark fill animations
/// - Privacy badge ("No photos saved")
/// - Green flash overlay on each sample capture
class BiopayScannerShell extends StatefulWidget {
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

  @override
  State<BiopayScannerShell> createState() => _BiopayScannerShellState();
}

class _BiopayScannerShellState extends State<BiopayScannerShell>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _flashController;
  int _previousSampleCount = 0;

  @override
  void initState() {
    super.initState();
    _previousSampleCount = widget.sampleCount;

    // Breathing pulse for the ring glow
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    // Green flash on capture — 0→1→0 in 300ms
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void didUpdateWidget(covariant BiopayScannerShell oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Fire green flash when a new sample is captured
    if (widget.sampleCount > _previousSampleCount &&
        widget.sampleCount <= widget.totalSamples) {
      _previousSampleCount = widget.sampleCount;
      _flashController.forward(from: 0).then((_) {
        if (mounted) {
          _flashController.reverse();
        }
      });
    }

    // Manage pulse — only pulse when searching or ready
    final shouldPulse =
        widget.tone == BiopayScannerTone.searching ||
        widget.tone == BiopayScannerTone.ready;
    if (shouldPulse && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!shouldPulse && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _flashController.dispose();
    super.dispose();
  }

  Color _toneColor(CoolSemanticColors colors) {
    return switch (widget.tone) {
      BiopayScannerTone.searching => const Color(0xFFF0B429),
      BiopayScannerTone.ready => colors.success,
      BiopayScannerTone.blocked => colors.warning,
      BiopayScannerTone.error => colors.danger,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final statusColor = _toneColor(colors);
    final space = context.coolSpace;
    final bottomPad = MediaQuery.viewPaddingOf(context).bottom;

    return Stack(
      children: [
        // ── Camera preview / placeholder ─────────────────────────
        Positioned.fill(
          child: widget.isCameraReady && widget.controller != null
              ? CameraPreview(widget.controller!)
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

        // ── Segmented progress ring overlay ──────────────────────
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                return CustomPaint(
                  painter: _BiometricRingPainter(
                    color: statusColor,
                    pulseValue: _pulseController.value,
                    sampleCount: widget.sampleCount,
                    totalSamples: widget.totalSamples,
                    isEnrollMode: widget.isEnrollMode,
                    tone: widget.tone,
                  ),
                );
              },
            ),
          ),
        ),

        // ── Green flash overlay on capture ───────────────────────
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _flashController,
              builder: (context, _) {
                final opacity = _flashController.value * 0.18;
                if (opacity <= 0) return const SizedBox.shrink();
                return DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.success.withValues(alpha: opacity),
                  ),
                  child: const SizedBox.expand(),
                );
              },
            ),
          ),
        ),

        // ── Floating status chip (top) ───────────────────────────
        Positioned(
          top: space.x4,
          left: space.x5,
          right: space.x5,
          child: _FloatingStatusChip(
            label: widget.statusLabel,
            color: statusColor,
            tone: widget.tone,
          ),
        ),

        // ── Bottom area: dots + privacy + footer ─────────────────
        Positioned(
          left: space.x5,
          right: space.x5,
          bottom: space.x4 + bottomPad,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Sample capture dots (enrollment only)
              if (widget.isEnrollMode) ...[
                _SampleCaptureDots(
                  sampleCount: widget.sampleCount,
                  totalSamples: widget.totalSamples,
                  color: statusColor,
                ),
                SizedBox(height: space.x3),
              ],

              // Helper text
              if (widget.helperText.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: CoolSpace.x4,
                    vertical: CoolSpace.x3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.66),
                    borderRadius: const BorderRadius.all(
                      Radius.circular(CoolRadii.md),
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Text(
                    widget.helperText,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w500,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

              SizedBox(height: space.x3),

              // Privacy badge
              const _PrivacyBadge(),

              // Optional footer (error/permission cards)
              if (widget.footer != null) ...[
                SizedBox(height: space.x3),
                widget.footer!,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Floating Status Chip
// ─────────────────────────────────────────────────────────────────────────────

class _FloatingStatusChip extends StatelessWidget {
  const _FloatingStatusChip({
    required this.label,
    required this.color,
    required this.tone,
  });

  final String label;
  final Color color;
  final BiopayScannerTone tone;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: CoolMotion.quick,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: Container(
        key: ValueKey<String>(label),
        padding: const EdgeInsets.symmetric(
          horizontal: CoolSpace.x5,
          vertical: CoolSpace.x3,
        ),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.pill)),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.15),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6),
                ],
              ),
            ),
            const SizedBox(width: CoolSpace.x3),
            Flexible(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sample Capture Dots
// ─────────────────────────────────────────────────────────────────────────────

class _SampleCaptureDots extends StatelessWidget {
  const _SampleCaptureDots({
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
        final isFilled = index < sampleCount;
        final isCurrent = index == sampleCount;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: _CapturedDot(
            key: ValueKey<int>(index),
            isFilled: isFilled,
            isCurrent: isCurrent,
            color: color,
          ),
        );
      }),
    );
  }
}

class _CapturedDot extends StatelessWidget {
  const _CapturedDot({
    required this.isFilled,
    required this.isCurrent,
    required this.color,
    super.key,
  });

  final bool isFilled;
  final bool isCurrent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;

    return AnimatedContainer(
      duration: CoolMotion.quick,
      curve: Curves.easeOut,
      width: isCurrent ? 28 : 22,
      height: isCurrent ? 28 : 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isFilled
            ? colors.success.withValues(alpha: 0.2)
            : (isCurrent
                  ? color.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.06)),
        border: Border.all(
          color: isFilled
              ? colors.success
              : (isCurrent
                    ? color.withValues(alpha: 0.6)
                    : Colors.white.withValues(alpha: 0.15)),
          width: isCurrent ? 2 : 1.5,
        ),
        boxShadow: isFilled
            ? [
                BoxShadow(
                  color: colors.success.withValues(alpha: 0.3),
                  blurRadius: 8,
                ),
              ]
            : null,
      ),
      child: isFilled
          ? Icon(Icons.check_rounded, size: 14, color: colors.success)
                .animate()
                .scale(
                  begin: const Offset(0, 0),
                  end: const Offset(1, 1),
                  duration: 300.ms,
                  curve: Curves.elasticOut,
                )
                .fadeIn(duration: 150.ms)
          : (isCurrent
                ? Center(
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                    ),
                  )
                : null),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Privacy Badge
// ─────────────────────────────────────────────────────────────────────────────

class _PrivacyBadge extends StatelessWidget {
  const _PrivacyBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CoolSpace.x3,
        vertical: CoolSpace.x1 + 2,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.pill)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_rounded,
            size: 12,
            color: Colors.white.withValues(alpha: 0.45),
          ),
          const SizedBox(width: 6),
          Text(
            'No photos saved',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.45),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Biometric Ring Painter — Segmented progress arcs
// ─────────────────────────────────────────────────────────────────────────────

class _BiometricRingPainter extends CustomPainter {
  const _BiometricRingPainter({
    required this.color,
    required this.pulseValue,
    required this.sampleCount,
    required this.totalSamples,
    required this.isEnrollMode,
    required this.tone,
  });

  final Color color;
  final double pulseValue; // 0.0 → 1.0, drives glow breathing
  final int sampleCount;
  final int totalSamples;
  final bool isEnrollMode;
  final BiopayScannerTone tone;

  @override
  void paint(Canvas canvas, Size size) {
    // ── Oval geometry ──────────────────────────────────────────
    const horizontalInset = 18.0;
    final ovalWidth = size.width - (horizontalInset * 2);
    final ovalHeight = (ovalWidth * 1.52)
        .clamp(size.height * 0.54, size.height * 0.68)
        .toDouble();
    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.40),
      width: ovalWidth,
      height: ovalHeight,
    );

    // ── Darkened mask outside oval ─────────────────────────────
    final fullRect = Path()..addRect(Offset.zero & size);
    final ovalPath = Path()..addOval(ovalRect);
    final mask = Path.combine(PathOperation.difference, fullRect, ovalPath);
    canvas.drawPath(
      mask,
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );

    // ── Pulsing glow ──────────────────────────────────────────
    final glowAlpha = 0.08 + (pulseValue * 0.12);
    final glowWidth = 16.0 + (pulseValue * 8.0);
    final glowPaint = Paint()
      ..color = color.withValues(alpha: glowAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = glowWidth
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowWidth);
    canvas.drawOval(ovalRect, glowPaint);

    if (isEnrollMode && totalSamples > 0) {
      _drawSegmentedRing(canvas, ovalRect);
    } else {
      _drawContinuousRing(canvas, ovalRect);
    }

    // ── Cardinal tick marks ───────────────────────────────────
    _drawTickMarks(canvas, ovalRect);
  }

  void _drawSegmentedRing(Canvas canvas, Rect ovalRect) {
    final segmentCount = totalSamples;
    const gapAngle = 0.08; // radians between segments
    final totalGap = gapAngle * segmentCount;
    final totalArc = 2 * math.pi - totalGap;
    final segmentArc = totalArc / segmentCount;
    const startOffset = -math.pi / 2; // start at 12 o'clock

    for (int i = 0; i < segmentCount; i++) {
      final segStart = startOffset + i * (segmentArc + gapAngle);
      final isFilled = i < sampleCount;
      final isCurrent = i == sampleCount;

      final segColor = isFilled
          ? const Color(0xFF00FF00) // neon green for captured
          : (isCurrent
                ? color // current state color (amber when searching)
                : Colors.white.withValues(alpha: 0.15));

      final strokeWidth = isCurrent ? 4.5 : (isFilled ? 4.0 : 2.5);

      final paint = Paint()
        ..color = segColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(ovalRect, segStart, segmentArc, false, paint);

      // Small glow behind filled segments
      if (isFilled) {
        final fillGlow = Paint()
          ..color = segColor.withValues(alpha: 0.2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
        canvas.drawArc(ovalRect, segStart, segmentArc, false, fillGlow);
      }
    }
  }

  void _drawContinuousRing(Canvas canvas, Rect ovalRect) {
    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;
    canvas.drawOval(ovalRect, borderPaint);
  }

  void _drawTickMarks(Canvas canvas, Rect ovalRect) {
    final cx = ovalRect.center.dx;
    final cy = ovalRect.center.dy;
    final rx = ovalRect.width / 2;
    final ry = ovalRect.height / 2;

    final tickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    // 4 cardinal points: top, right, bottom, left
    const angles = <double>[
      -math.pi / 2, // top
      0, // right
      math.pi / 2, // bottom
      math.pi, // left
    ];

    for (final angle in angles) {
      final cosA = math.cos(angle);
      final sinA = math.sin(angle);

      // Inner point (inside oval edge)
      final innerX = cx + (rx - 10) * cosA;
      final innerY = cy + (ry - 10) * sinA;

      // Outer point (outside oval edge)
      final outerX = cx + (rx + 10) * cosA;
      final outerY = cy + (ry + 10) * sinA;

      canvas.drawLine(
        Offset(innerX, innerY),
        Offset(outerX, outerY),
        tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BiometricRingPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.pulseValue != pulseValue ||
        oldDelegate.sampleCount != sampleCount ||
        oldDelegate.totalSamples != totalSamples ||
        oldDelegate.isEnrollMode != isEnrollMode ||
        oldDelegate.tone != tone;
  }
}
