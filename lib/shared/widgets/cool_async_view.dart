import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cool_empty_view.dart';
import 'cool_error_view.dart';
import 'cool_skeleton.dart';

/// Generic async-data renderer for Riverpod [AsyncValue].
///
/// Eliminates the repeated `.when(loading:, error:, data:)` pattern found
/// across 20+ screens. Supports customizable loading, error, and empty states.
///
/// ```dart
/// CoolAsyncView<List<Trip>>(
///   value: ref.watch(tripsProvider),
///   builder: (trips) => TripList(trips: trips),
///   emptyCheck: (trips) => trips.isEmpty,
///   emptyMessage: 'No trips yet',
///   onRetry: () => ref.invalidate(tripsProvider),
/// )
/// ```
class CoolAsyncView<T> extends StatelessWidget {
  const CoolAsyncView({
    required this.value,
    required this.builder,
    this.onRetry,
    this.loadingWidget,
    this.errorMessage,
    this.emptyCheck,
    this.emptyWidget,
    this.emptyMessage,
    this.skipLoadingOnRefresh = true,
    super.key,
  });

  /// The [AsyncValue] to render.
  final AsyncValue<T> value;

  /// Builder called when data is available.
  final Widget Function(T data) builder;

  /// Called when the user taps "Try Again" on the error view.
  final VoidCallback? onRetry;

  /// Custom loading widget. Defaults to [CoolSkeletonList].
  final Widget? loadingWidget;

  /// Custom error message. If null, uses the error's toString().
  final String? errorMessage;

  /// Returns true if the data represents an empty state.
  /// If null, no empty-state check is performed.
  final bool Function(T data)? emptyCheck;

  /// Custom empty-state widget. If null, a default [CoolEmptyView] is used.
  final Widget? emptyWidget;

  /// Message for the default empty view. Defaults to "Nothing here yet".
  final String? emptyMessage;

  /// Whether to skip showing the loading state during refresh (show stale
  /// data instead). Defaults to true for smoother UX.
  final bool skipLoadingOnRefresh;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: value.when(
        skipLoadingOnRefresh: skipLoadingOnRefresh,
        loading: () => Semantics(
          container: true,
          liveRegion: true,
          label: 'Loading content',
          child: loadingWidget ?? const CoolSkeletonList(),
        ),
        error: (error, _) => CoolErrorView(
          message: errorMessage ?? _friendlyError(error),
          onRetry: onRetry,
        ),
        data: (data) {
          if (emptyCheck != null && emptyCheck!(data)) {
            return emptyWidget ??
                CoolEmptyView(message: emptyMessage ?? 'Nothing here yet');
          }
          return builder(data);
        },
      ),
    );
  }

  static String _friendlyError(Object error) {
    final raw = error.toString();
    final normalized = raw.toLowerCase();
    // Avoid showing raw SocketException or similar internal errors.
    if (normalized.contains('socketexception') ||
        normalized.contains('failed host lookup')) {
      return 'Unable to connect. Please check your internet connection.';
    }
    // Strip 'Exception: ' prefix for cleaner display.
    if (raw.startsWith('Exception: ')) {
      return raw.substring(11);
    }
    return raw;
  }
}
