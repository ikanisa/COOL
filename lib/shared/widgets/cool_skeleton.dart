import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';

/// A shimmer-effect skeleton placeholder used during loading states.
///
/// Provides a pulsing gradient animation that indicates content is loading.
/// Respects reduced-motion preference via [MediaQuery.disableAnimationsOf].
class CoolSkeleton extends StatefulWidget {
  const CoolSkeleton({
    this.width,
    this.height = 16,
    this.borderRadius = 8,
    super.key,
  });

  /// Creates a skeleton shaped like a card (full width, rounded, taller).
  const CoolSkeleton.card({super.key})
    : width = double.infinity,
      height = 120,
      borderRadius = 28;

  /// Creates a skeleton shaped like a horizontal list item card.
  const CoolSkeleton.listCard({super.key})
    : width = 180,
      height = 200,
      borderRadius = 28;

  /// Creates a skeleton shaped like a line of text.
  const CoolSkeleton.line({double? width, super.key})
    : width = width ?? 120,
      height = 12,
      borderRadius = 6;

  final double? width;
  final double height;
  final double borderRadius;

  @override
  State<CoolSkeleton> createState() => _CoolSkeletonState();
}

class _CoolSkeletonState extends State<CoolSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    if (reduceMotion) {
      return ExcludeSemantics(
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: colors.cardSurface,
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
        ),
      );
    }

    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              gradient: LinearGradient(
                begin: Alignment(-1.0 + 2.0 * _controller.value, 0),
                end: Alignment(1.0 + 2.0 * _controller.value, 0),
                colors: <Color>[
                  colors.cardSurface,
                  colors.cardSurfaceStrong,
                  colors.cardSurface,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A column of skeleton lines used as a loading placeholder for lists.
class CoolSkeletonList extends StatelessWidget {
  const CoolSkeletonList({this.itemCount = 3, this.spacing = 12, super.key});

  final int itemCount;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        itemCount,
        (i) => Padding(
          padding: EdgeInsets.only(bottom: i < itemCount - 1 ? spacing : 0),
          child: const CoolSkeleton.card(),
        ),
      ),
    );
  }
}

/// A horizontal row of skeleton cards used for horizontal scroll loading.
class CoolSkeletonRow extends StatelessWidget {
  const CoolSkeletonRow({this.itemCount = 3, this.spacing = 12, super.key});

  final int itemCount;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 210,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: itemCount,
        separatorBuilder: (context, index) => SizedBox(width: spacing),
        itemBuilder: (context, index) => const CoolSkeleton.listCard(),
      ),
    );
  }
}
