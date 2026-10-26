import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('bounded loading preserves its full 320px doubled-text content', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 180,
              child: LoadingStatePanel(
                title: 'Checking current Admin permissions',
                message: 'Fetching workspace navigation and queue policies.',
                lines: 4,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    final scrollable = find.descendant(
      of: find.byType(LoadingStatePanel),
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsOneWidget);
    final state = tester.state<ScrollableState>(scrollable);
    expect(state.position.maxScrollExtent, greaterThan(0));
    await tester.drag(scrollable, const Offset(0, -600));
    await tester.pump();
    expect(state.position.pixels, greaterThan(0));
    expect(
      state.position.pixels,
      lessThanOrEqualTo(state.position.maxScrollExtent),
    );
    expect(
      find.text('Fetching workspace navigation and queue policies.'),
      findsOneWidget,
    );
    expect(find.byType(LoadingSkeleton), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
