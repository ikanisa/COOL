import 'package:cool_app/core/theme/app_theme.dart';
import 'package:cool_app/features/biopay/providers/biopay_providers.dart';
import 'package:cool_app/features/biopay/screens/biopay_home_screen.dart';
import 'package:cool_app/features/biopay/screens/biopay_register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_bootstrap.dart';

Widget _wrapBiopayScreen(Widget child, {double textScale = 1.0}) {
  return MaterialApp(
    theme: AppTheme.dark,
    builder: (context, widget) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: true,
        textScaler: TextScaler.linear(textScale),
      ),
      child: widget!,
    ),
    home: child,
  );
}

void main() {
  testWidgets('BioPay home screen remains readable at 2x text scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapBiopayScreen(const BiopayHomeScreen(), textScale: 2.0),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pay & Get Paid\nInstantly'), findsOneWidget);
    expect(find.text('Face Scan'), findsOneWidget);
    expect(find.text('NFC Tap'), findsOneWidget);
    expect(find.text('Get QR'), findsOneWidget);
    expect(find.text('Scan QR'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('BioPay register screen remains readable at 2x text scale', (
    tester,
  ) async {
    final container = createTestContainer(
      overrides: [
        biopayModelAssetIssueProvider.overrideWith(
          (ref) async => 'BioPay face model is not bundled in this build yet.',
        ),
        biopayProfileProvider.overrideWith((ref) async => null),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _wrapBiopayScreen(const BiopayRegisterScreen(), textScale: 2.0),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Face ID Setup'), findsOneWidget);
    expect(find.text('Link your face\nto your MoMo.'), findsOneWidget);
    expect(find.text('MOMO NUMBER'), findsOneWidget);
    expect(find.text('Start Enrollment'), findsOneWidget);
    expect(
      find.text('BioPay face model is not bundled in this build yet.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
