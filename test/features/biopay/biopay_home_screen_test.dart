import 'package:cool_app/core/theme/app_theme.dart';
import 'package:cool_app/features/biopay/providers/biopay_providers.dart';
import 'package:cool_app/features/biopay/screens/biopay_home_screen.dart';
import 'package:cool_app/features/biopay/screens/biopay_register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_bootstrap.dart';

void main() {
  testWidgets('renders the BioPay payment hub', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        builder: (context, widget) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: widget!,
        ),
        home: const BiopayHomeScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('BioPay Hub'), findsOneWidget);
    expect(find.text('HOW DO YOU'), findsOneWidget);
    expect(find.text('WANT TO PAY?'), findsOneWidget);
    expect(find.text('FACE\nSCAN'), findsOneWidget);
    expect(find.text('NFC\nSCAN'), findsOneWidget);
    expect(find.text('QR\nSCAN'), findsOneWidget);
  });

  testWidgets('register screen shows model asset warning when unavailable', (
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
        child: MaterialApp(
          theme: AppTheme.dark,
          builder: (context, widget) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: widget!,
          ),
          home: const BiopayRegisterScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Model asset required'), findsOneWidget);
    expect(
      find.text('BioPay face model is not bundled in this build yet.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'BioPay is scaffolded in the app but currently disabled by app configuration.',
      ),
      findsNothing,
    );
  });
}
