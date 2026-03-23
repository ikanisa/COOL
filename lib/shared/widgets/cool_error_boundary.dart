import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';

/// Widget-level error boundary that catches synchronous build errors
/// in its subtree and displays a recovery UI instead of the red error screen.
///
/// Wraps a [child] widget tree and intercepts [FlutterError]s to show a
/// branded error view with an optional retry callback.
///
/// ```dart
/// CoolErrorBoundary(
///   onError: (error, stack) => crashlytics.recordError(error, stack),
///   onRetry: () => ref.invalidate(someProvider),
///   child: const ExpensiveWidget(),
/// )
/// ```
class CoolErrorBoundary extends StatefulWidget {
  const CoolErrorBoundary({
    required this.child,
    this.onError,
    this.onRetry,
    this.fallback,
    super.key,
  });

  /// The widget subtree to protect.
  final Widget child;

  /// Called when an error occurs. Use this for logging (e.g. Crashlytics).
  final void Function(Object error, StackTrace? stack)? onError;

  /// Called when the user taps the retry button. Triggers a rebuild.
  final VoidCallback? onRetry;

  /// Custom fallback widget. If null, a default branded error view is shown.
  final Widget? fallback;

  @override
  State<CoolErrorBoundary> createState() => _CoolErrorBoundaryState();
}

class _CoolErrorBoundaryState extends State<CoolErrorBoundary> {
  bool _hasError = false;
  late ErrorWidgetBuilder _previousErrorWidgetBuilder;
  bool _restoreScheduled = false;

  @override
  void dispose() {
    if (identical(ErrorWidget.builder, _handleErrorWidget)) {
      ErrorWidget.builder = _previousErrorWidgetBuilder;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return widget.fallback ?? _BrandedErrorFallback(onRetry: _retry);
    }

    _installErrorWidgetBuilderForFrame();

    return widget.child;
  }

  void _retry() {
    setState(() {
      _hasError = false;
    });
    widget.onRetry?.call();
  }

  void _installErrorWidgetBuilderForFrame() {
    final currentBuilder = ErrorWidget.builder;
    if (!identical(currentBuilder, _handleErrorWidget)) {
      _previousErrorWidgetBuilder = currentBuilder;
      ErrorWidget.builder = _handleErrorWidget;
    }
    if (_restoreScheduled) {
      return;
    }
    _restoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreScheduled = false;
      if (identical(ErrorWidget.builder, _handleErrorWidget)) {
        ErrorWidget.builder = _previousErrorWidgetBuilder;
      }
    });
  }

  Widget _handleErrorWidget(FlutterErrorDetails details) {
    // Schedule state update after this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_hasError) {
        setState(() {
          _hasError = true;
        });
        widget.onError?.call(details.exception, details.stack);
        if (kDebugMode) {
          debugPrint('[CoolErrorBoundary] Caught: ${details.exception}');
        }
      }
    });

    // Return a transparent placeholder during the frame where the error
    // is first caught (the real fallback is shown on the next build).
    return const SizedBox.shrink();
  }
}

/// Branded fallback UI shown when an error is caught.
class _BrandedErrorFallback extends StatelessWidget {
  const _BrandedErrorFallback({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CoolSpace.x8,
          vertical: CoolSpace.x10,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colors.danger.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.warning_amber_rounded,
                size: 40,
                color: colors.danger,
              ),
            ),
            const SizedBox(height: CoolSpace.x5),
            Text(
              'Something went wrong',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.primaryText,
              ),
            ),
            const SizedBox(height: CoolSpace.x2),
            Text(
              'An unexpected error occurred',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.secondaryText,
                height: 1.5,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: CoolSpace.x6),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(
                  'Retry',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(foregroundColor: colors.accent),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
