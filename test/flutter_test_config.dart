import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Keep widget tests deterministic and offline. Without this, the large
  // GoogleFonts surface area in the app can cause slow or unstable test runs.
  GoogleFonts.config.allowRuntimeFetching = false;

  await testMain();
}
