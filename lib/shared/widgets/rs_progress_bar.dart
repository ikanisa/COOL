import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';

/// Animated progress bar with gradient fill and rounded caps.
///
/// Used across RS initiatives and membership tier progress.
class RsProgressBar extends StatefulWidget {
  const RsProgressBar({
    required this.progress,
    required this.fillColor,
    this.height = 6.0,
    this.animated = true,
    super.key,
  });

  /// Value between 0.0 and 1.0.
  final double progress;

  /// Primary fill colour; the bar uses a subtle gradient
  /// from [fillColor] to a lighter shade on the right.
  final Color fillColor;

  /// Track height in logical pixels.
  final double height;

  /// Whether the fill animates from 0 to [progress] on first render.
  final bool animated;

  @override
  State<RsProgressBar> createState() => _RsProgressBarState();
}

class _RsProgressBarState extends State<RsProgressBar> {
  double _rendered = 0;

  @override
  void initState() {
    super.initState();
    if (widget.animated) {
      // Trigger the expansion after the first frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _rendered = widget.progress.clamp(0, 1));
      });
    } else {
      _rendered = widget.progress.clamp(0, 1);
    }
  }

  @override
  void didUpdateWidget(RsProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) {
      setState(() => _rendered = widget.progress.clamp(0, 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final lighterFill = Color.lerp(widget.fillColor, Colors.white, 0.25)!;

    return Semantics(
      label: 'Progress ${(_rendered * 100).round()} percent',
      value: '${(_rendered * 100).round()}%',
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.height / 2),
        child: Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: colors.overlaySurface,
            borderRadius: BorderRadius.circular(widget.height / 2),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  AnimatedContainer(
                    duration: widget.animated
                        ? const Duration(milliseconds: 600)
                        : Duration.zero,
                    curve: Curves.easeOutCubic,
                    width: constraints.maxWidth * _rendered,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(widget.height / 2),
                      gradient: LinearGradient(
                        colors: [widget.fillColor, lighterFill],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
