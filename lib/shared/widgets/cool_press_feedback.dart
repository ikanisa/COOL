import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/cool_foundations.dart';

/// A universal tactile press-feedback wrapper for any tappable element.
///
/// Provides scale + opacity spring animation on press, inspired by Mobio's
/// "every interactive element responds with physical feedback" principle.
///
/// Usage:
/// ```dart
/// CoolPressFeedback(
///   onTap: () => doSomething(),
///   child: MyWidget(),
/// )
/// ```
class CoolPressFeedback extends StatefulWidget {
  const CoolPressFeedback({
    required this.child,
    required this.onTap,
    this.scaleEnd = 0.97,
    this.opacityEnd = 0.85,
    this.haptic = true,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final VoidCallback onTap;

  /// Scale target on press (1.0 → [scaleEnd]).
  final double scaleEnd;

  /// Opacity target on press (1.0 → [opacityEnd]).
  final double opacityEnd;

  /// Whether to fire haptic feedback on tap.
  final bool haptic;

  /// When false, disables animation and forwards taps without feedback.
  final bool enabled;

  @override
  State<CoolPressFeedback> createState() => _CoolPressFeedbackState();
}

class _CoolPressFeedbackState extends State<CoolPressFeedback>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: CoolMotion.press,
    );
    _scale = Tween<double>(begin: 1.0, end: widget.scaleEnd).animate(
      CurvedAnimation(parent: _controller, curve: CoolMotion.pressCurve),
    );
    _opacity = Tween<double>(begin: 1.0, end: widget.opacityEnd).animate(
      CurvedAnimation(parent: _controller, curve: CoolMotion.pressCurve),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails _) {
    if (widget.enabled) _controller.forward();
  }

  void _handleTapUp(TapUpDetails _) {
    if (widget.enabled) _controller.reverse();
  }

  void _handleTapCancel() {
    if (widget.enabled) _controller.reverse();
  }

  void _handleTap() {
    if (widget.haptic) HapticFeedback.lightImpact();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return GestureDetector(onTap: widget.onTap, child: widget.child);
    }

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: FadeTransition(
        opacity: _opacity,
        child: ScaleTransition(
          scale: _scale,
          child: widget.child,
        ),
      ),
    );
  }
}
