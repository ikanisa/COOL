import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';

/// A restrained bottom sheet wrapper.
class CoolBottomSheet extends StatelessWidget {
  const CoolBottomSheet({
    required this.child,
    this.padding,
    this.blur = CoolBlur.overlay,
    this.borderRadius = CoolRadii.xxl,
    super.key,
  });

  final Widget child;
  final EdgeInsets? padding;
  final double blur;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final bgColor = colors.overlaySurface.withValues(alpha: 0.96);
    final borderCol = colors.border;

    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(borderRadius)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(borderRadius),
            ),
            border: Border(top: BorderSide(color: borderCol, width: 0.8)),
            boxShadow: CoolShadows.floating(null, strength: 0.7),
          ),
          child: SafeArea(
            child: Padding(
              padding: padding ?? const EdgeInsets.fromLTRB(24, 14, 24, 24),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

Future<T?> showCoolBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  Color? barrierColor,
  bool isScrollControlled = false,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  bool useSafeArea = false,
  RouteSettings? routeSettings,
  AnimationController? transitionAnimationController,
  Offset? anchorPoint,
}) {
  return showModalBottomSheet<T>(
    context: context,
    builder: (ctx) => CoolBottomSheet(child: builder(ctx)),
    backgroundColor: Colors.transparent,
    elevation: 0,
    shape: shape,
    clipBehavior: clipBehavior,
    constraints: constraints,
    barrierColor: barrierColor,
    isScrollControlled: isScrollControlled,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: showDragHandle ?? false,
    useSafeArea: useSafeArea,
    routeSettings: routeSettings,
    transitionAnimationController: transitionAnimationController,
    anchorPoint: anchorPoint,
  );
}
