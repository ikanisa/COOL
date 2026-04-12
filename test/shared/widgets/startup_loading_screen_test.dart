import 'package:cool_app/core/theme/app_theme.dart';
import 'package:cool_app/shared/widgets/cool_screen_background.dart';
import 'package:cool_app/shared/widgets/startup_loading_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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
    bool matchNativeSplash = false,
    Widget? logo,
  }) {
    return MaterialApp(
      theme: AppTheme.dark,
      home: StartupLoadingScreen(
        statusLabel: statusLabel,
        showProgressIndicator: showProgressIndicator,
        matchNativeSplash: matchNativeSplash,
        logo: logo ?? const SizedBox(width: 120, height: 120),
      ),
    );
  }

  testWidgets('renders before ProviderScope exists', (tester) async {
    await tester.pumpWidget(buildSubject(statusLabel: 'Preparing startup'));

    expect(find.text('Preparing startup'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('can match the native splash background exactly', (tester) async {
    await tester.pumpWidget(
      buildSubject(statusLabel: 'Preparing startup', matchNativeSplash: true),
    );

    expect(find.byType(CoolScreenBackground), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox &&
            widget.color == StartupLoadingScreen.nativeSplashBackgroundColor,
      ),
      findsOneWidget,
    );
  });

  testWidgets('animates startup status updates without errors', (tester) async {
    await tester.pumpWidget(buildSubject(statusLabel: 'Preparing startup'));
    await tester.pump(const Duration(milliseconds: 120));

    await tester.pumpWidget(buildSubject(statusLabel: 'Connecting backend'));
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('Connecting backend'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
