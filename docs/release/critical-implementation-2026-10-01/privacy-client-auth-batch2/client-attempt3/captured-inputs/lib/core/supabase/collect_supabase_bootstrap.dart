import 'package:supabase_flutter/supabase_flutter.dart';

import '../startup/collect_startup_controller.dart';

/// Supabase sets its singleton initialized flag before awaiting Auth storage.
/// A rejected initializer is retryable only after the actual client is disposed;
/// otherwise a retry could return a partially initialized singleton.
Future<SupabaseClient> initializeCollectSupabase(
  Future<Supabase> Function() initialize,
) async {
  try {
    return (await initialize()).client;
  } catch (_) {
    var retryAllowed = false;
    try {
      final partial = Supabase.instance;
      if (partial.isInitialized) {
        await partial.dispose();
        retryAllowed = !partial.isInitialized;
      }
    } catch (_) {
      // Unknown or failed cleanup requires restarting the process.
    }
    throw CollectStartupFailure(retryAllowed: retryAllowed);
  }
}
