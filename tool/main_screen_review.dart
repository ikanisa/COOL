import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'main_store_preview.dart' as preview;

/// Local browser review only; never imported by a production entry point.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb ||
      kReleaseMode ||
      !const bool.fromEnvironment('COLLECT_SCREEN_REVIEW')) {
    throw StateError('Screen review requires an explicit debug web build.');
  }
  // Keep labels available to the reviewer and browser checks from first paint.
  // The handle lasts for this isolated page and is released with its engine.
  WidgetsBinding.instance.ensureSemantics();
  await preview.main();
}
