import 'dart:async';
import 'dart:io';

import 'package:cool_app/core/config/country_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Keep widget tests deterministic and offline. Without this, the large
  // GoogleFonts surface area in the app can cause slow or unstable test runs.
  GoogleFonts.config.allowRuntimeFetching = false;
  await CoolCountryCatalog.initialize(
    await File('assets/countries.json').readAsString(),
  );

  await testMain();
}
