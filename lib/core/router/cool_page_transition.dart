import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

typedef CoolPageBuilder =
    CustomTransitionPage<dynamic> Function({
      required BuildContext context,
      required GoRouterState state,
      required Widget child,
    });

/// Reusable "Cool" page transition: 300ms fade plus subtle scale.
CustomTransitionPage<T> coolPageTransition<T>({
  required BuildContext context,
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurveTween(curve: Curves.easeOut).animate(animation),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      );
    },
    transitionDuration: const Duration(milliseconds: 300),
  );
}
