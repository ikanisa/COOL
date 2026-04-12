import 'package:cool_app/shared/widgets/cool_async_view.dart';
import 'package:cool_app/shared/widgets/cool_error_view.dart';
import 'package:cool_app/shared/widgets/cool_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CoolAsyncView', () {
    testWidgets('shows skeleton on loading', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoolAsyncView<String>(
              value: const AsyncValue<String>.loading(),
              builder: (data) => Text(data),
            ),
          ),
        ),
      );

      expect(find.byType(CoolSkeletonList), findsOneWidget);
    });

    testWidgets('shows custom loading widget', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoolAsyncView<String>(
              value: const AsyncValue<String>.loading(),
              builder: (data) => Text(data),
              loadingWidget: const CircularProgressIndicator(),
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('announces loading state for assistive tech', (tester) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoolAsyncView<String>(
              value: const AsyncValue<String>.loading(),
              builder: (data) => Text(data),
            ),
          ),
        ),
      );

      expect(find.bySemanticsLabel('Loading content'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('shows error view on error', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoolAsyncView<String>(
              value: AsyncValue<String>.error(
                Exception('Test error'),
                StackTrace.current,
              ),
              builder: (data) => Text(data),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CoolErrorView), findsOneWidget);
      expect(find.text('Test error'), findsOneWidget);
    });

    testWidgets('shows friendly message for network errors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoolAsyncView<String>(
              value: AsyncValue<String>.error(
                Exception('SocketException: OS Error'),
                StackTrace.current,
              ),
              builder: (data) => Text(data),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Unable to connect. Please check your internet connection.'),
        findsOneWidget,
      );
    });

    testWidgets('shows data when available', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoolAsyncView<String>(
              value: const AsyncValue<String>.data('Hello'),
              builder: (data) => Text(data),
            ),
          ),
        ),
      );

      expect(find.text('Hello'), findsOneWidget);
    });

    testWidgets('shows empty view when emptyCheck returns true', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoolAsyncView<List<String>>(
              value: const AsyncValue<List<String>>.data([]),
              builder: (data) => Text('Count: ${data.length}'),
              emptyCheck: (data) => data.isEmpty,
              emptyMessage: 'No items',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No items'), findsOneWidget);
      expect(find.text('Count: 0'), findsNothing);
    });

    testWidgets('calls onRetry when retry tapped', (tester) async {
      var retried = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoolAsyncView<String>(
              value: AsyncValue<String>.error(
                Exception('fail'),
                StackTrace.current,
              ),
              builder: (data) => Text(data),
              onRetry: () => retried = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Retry'));
      expect(retried, true);
    });
  });
}
