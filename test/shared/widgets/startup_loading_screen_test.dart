import 'package:cool_app/core/theme/app_theme.dart';
import 'package:cool_app/shared/widgets/startup_loading_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/google_fonts_test_assets.dart';

void main() {
  setUp(() {
    setUpBundledGoogleFonts();
  });

  tearDown(() {
    tearDownBundledGoogleFonts();
  });

  Widget buildSubject({
    required String statusLabel,
    bool showProgressIndicator = true,
  }) {
    return ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark,
        home: StartupLoadingScreen(
          statusLabel: statusLabel,
          showProgressIndicator: showProgressIndicator,
          logo: const SizedBox(width: 120, height: 120),
        ),
      ),
    );
  }

  testWidgets('shows startup status with a loading indicator by default', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject(statusLabel: 'Preparing startup'));

    expect(find.text('Preparing startup'), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
  });

  testWidgets('can render without the loading indicator', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        statusLabel: 'Connection issue',
        showProgressIndicator: false,
      ),
    );

    expect(find.text('Connection issue'), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
  });
}
