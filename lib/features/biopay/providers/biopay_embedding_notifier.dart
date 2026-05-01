import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/biopay_embedding_service.dart';

/// Singleton lifecycle manager for the [BiopayEmbeddingService].
///
/// Replaces per-screen instantiation with a single persistent model load.
/// The TFLite interpreter (~2.5 MB) is loaded once and shared across all
/// BioPay screens, eliminating 500ms–2s init latency on each screen entry.
///
/// **Usage:**
/// ```dart
/// // Warmup (eagerly from home screen):
/// ref.read(biopayEmbeddingProvider.notifier).warmup();
///
/// // Access the ready service:
/// final service = await ref.read(biopayEmbeddingProvider.future);
/// ```
class BiopayEmbeddingNotifier
    extends AsyncNotifier<BiopayEmbeddingService> {
  @override
  FutureOr<BiopayEmbeddingService> build() async {
    final service = BiopayEmbeddingService();
    final ready = await service.ensureInitialized();

    // Ensure model is disposed when the provider is disposed.
    ref.onDispose(service.dispose);

    if (!ready) {
      throw StateError(
        service.initializationError ??
            'BioPay embedding model could not be initialized.',
      );
    }

    return service;
  }

  /// Pre-load the model in the background.
  ///
  /// Safe to call multiple times — if the model is already loaded or
  /// currently loading, this is a no-op.
  void warmup() {
    // Reading `.future` triggers `build()` if not yet started.
    // Errors are surfaced through the provider's AsyncValue state.
    future.ignore();
  }
}

/// Provides a lazily-initialized, singleton [BiopayEmbeddingService].
///
/// The model loads on first access (or when [warmup] is called).
/// Consumers should watch this provider and handle `loading`/`error` states.
final biopayEmbeddingProvider =
    AsyncNotifierProvider<BiopayEmbeddingNotifier, BiopayEmbeddingService>(
  BiopayEmbeddingNotifier.new,
);
