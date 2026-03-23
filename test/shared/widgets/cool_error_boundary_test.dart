import 'package:cool_app/shared/widgets/cool_error_boundary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CoolErrorBoundary', () {
    testWidgets('shows branded fallback when child build fails', (
      tester,
    ) async {
      final originalBuilder = ErrorWidget.builder;
      addTearDown(() {
        ErrorWidget.builder = originalBuilder;
      });

      await tester.pumpWidget(
        MaterialApp(
          home: CoolErrorBoundary(
            child: Builder(builder: (context) => throw StateError('boom')),
          ),
        ),
      );
      expect(tester.takeException(), isA<StateError>());
      await tester.pump();

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('An unexpected error occurred'), findsOneWidget);
      ErrorWidget.builder = originalBuilder;
    });
  });
}
