import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';

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

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return widget.fallback ?? _BrandedErrorFallback(
        onRetry: _retry,
      );
    }

    // Override ErrorWidget.builder within this subtree.
    ErrorWidget.builder = (FlutterErrorDetails details) {
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
    };

    return widget.child;
  }

  void _retry() {
    setState(() {
      _hasError = false;
    });
    widget.onRetry?.call();
  }
}

/// Branded fallback UI shown when an error is caught.
class _BrandedErrorFallback extends StatelessWidget {
  const _BrandedErrorFallback({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                size: 40,
                color: AppColors.red,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Something went wrong',
              style: GoogleFonts.dmSans(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'An unexpected error occurred.\nPlease try again.',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                color: AppColors.text2,
                height: 1.5,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(
                  'Retry',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.accent,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
