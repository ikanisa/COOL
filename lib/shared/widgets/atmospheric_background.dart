import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/rs_colors.dart';

/// Atmospheric blurred-blob background layer matching the React
/// `AtmosphericBackground` component.
///
/// Usage: Place as the first child in a [Stack] behind all content.
/// ```dart
/// Stack(children: [
///   const AtmosphericBackground(),
///   // ... page content
/// ])
/// ```
class AtmosphericBackground extends StatelessWidget {
  const AtmosphericBackground({super.key, this.showGrid = false});

  /// When true, draws the mobi-grid 24px line pattern on top.
  final bool showGrid;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            // Blob 1: top-left, primary/10, pulsing
            Positioned(
              top: -0.1 * MediaQuery.sizeOf(context).height,
              left: -0.1 * MediaQuery.sizeOf(context).width,
              child: _AnimatedBlob(
                width: MediaQuery.sizeOf(context).width * 0.4,
                height: MediaQuery.sizeOf(context).height * 0.4,
                color: RsColors.rsRed.withValues(alpha: 0.10),
                blurSigma: 60,
                animate: true,
              ),
            ),

            // Blob 2: bottom-right, primary/5, static
            Positioned(
              bottom: -0.1 * MediaQuery.sizeOf(context).height,
              right: -0.1 * MediaQuery.sizeOf(context).width,
              child: _AnimatedBlob(
                width: MediaQuery.sizeOf(context).width * 0.5,
                height: MediaQuery.sizeOf(context).height * 0.5,
                color: RsColors.rsRed.withValues(alpha: 0.05),
                blurSigma: 75,
                animate: false,
              ),
            ),

            // Blob 3: top-right, gold/5, pulsing (delayed)
            Positioned(
              top: 0.2 * MediaQuery.sizeOf(context).height,
              right: 0.1 * MediaQuery.sizeOf(context).width,
              child: _AnimatedBlob(
                width: MediaQuery.sizeOf(context).width * 0.3,
                height: MediaQuery.sizeOf(context).height * 0.3,
                color: RsColors.rsGold.withValues(alpha: 0.05),
                blurSigma: 50,
                animate: true,
                delay: const Duration(seconds: 2),
              ),
            ),

            // Optional mobi-grid overlay
            if (showGrid) const Positioned.fill(child: _MobiGrid()),
          ],
        ),
      ),
    );
  }
}

/// A single blurred circle that optionally pulses opacity.
class _AnimatedBlob extends StatefulWidget {
  const _AnimatedBlob({
    required this.width,
    required this.height,
    required this.color,
    required this.blurSigma,
    required this.animate,
    this.delay = Duration.zero,
  });

  final double width;
  final double height;
  final Color color;
  final double blurSigma;
  final bool animate;
  final Duration delay;

  @override
  State<_AnimatedBlob> createState() => _AnimatedBlobState();
}

class _AnimatedBlobState extends State<_AnimatedBlob>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  Timer? _startDelayTimer;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    _opacity = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (widget.animate && !reduceMotion) {
      if (!_started) {
        if (widget.delay == Duration.zero) {
          _started = true;
          _controller.repeat(reverse: true);
        } else {
          _startDelayTimer ??= Timer(widget.delay, () {
            if (!mounted) {
              return;
            }
            _started = true;
            _controller.repeat(reverse: true);
          });
        }
      } else if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
    } else {
      _startDelayTimer?.cancel();
      _startDelayTimer = null;
      if (_controller.isAnimating) {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _startDelayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = ImageFiltered(
      imageFilter: ImageFilter.blur(
        sigmaX: widget.blurSigma,
        sigmaY: widget.blurSigma,
        tileMode: TileMode.decal,
      ),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
        ),
      ),
    );

    if (!widget.animate) return child;

    return FadeTransition(
      opacity: _started
          ? _opacity
          : const AlwaysStoppedAnimation(0.8),
      child: child,
    );
  }
}

/// Mobi-grid: 24px crosshatch lines at white/8 opacity.
///
/// Matches the React CSS:
/// ```css
/// .mobi-grid {
///   background-image:
///     linear-gradient(rgba(255,255,255,0.08) 1px, transparent 1px),
///     linear-gradient(90deg, rgba(255,255,255,0.08) 1px, transparent 1px);
///   background-size: 24px 24px;
/// }
/// ```
class _MobiGrid extends StatelessWidget {
  const _MobiGrid();

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _MobiGridPainter(),
        size: Size.infinite,
      ),
    );
  }
}

class _MobiGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    const spacing = 24.0;

    // Horizontal lines
    for (var y = 0.0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Vertical lines
    for (var x = 0.0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
