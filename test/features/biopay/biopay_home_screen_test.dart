import 'package:cool_app/features/biopay/providers/biopay_providers.dart';
import 'package:cool_app/features/biopay/screens/biopay_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_bootstrap.dart';

void main() {
  testWidgets('shows model asset warning when BioPay model is unavailable', (
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
        child: const MaterialApp(home: BiopayHomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

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
