import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 2C: Accessibility – Text Scaling & Touch Target Tests
///
/// Tests that verify:
///  1. Core widgets render without overflow at 2.0× text scale.
///  2. Interactive elements meet the 48dp minimum touch target.
void main() {
  // ─── Helper ───────────────────────────────────────────────────────────────

  Widget wrapInScaffold(Widget child, {double textScale = 1.0}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(body: child),
      ),
    );
  }

  // ─── 1. Text Scaling Tests ──────────────────────────────────────────────

  group('Text scaling @2x', () {
    testWidgets('ElevatedButton renders without overflow at 2x scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapInScaffold(
          Center(
            child: ElevatedButton(
              onPressed: () {},
              child: const Text('Submit'),
            ),
          ),
          textScale: 2.0,
        ),
      );

      expect(find.text('Submit'), findsOneWidget);
      // Ensure no overflow exceptions during pump
    });

    testWidgets('Row of chips does not overflow at 2x scale', (tester) async {
      await tester.pumpWidget(
        wrapInScaffold(
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(
                5,
                (i) => Padding(
                  padding: const EdgeInsets.all(4),
                  child: Chip(label: Text('Chip $i')),
                ),
              ),
            ),
          ),
          textScale: 2.0,
        ),
      );

      expect(find.byType(Chip), findsNWidgets(5));
    });

    testWidgets('ListTile renders without overflow at 2x', (tester) async {
      await tester.pumpWidget(
        wrapInScaffold(
          ListView(
            children: const [
              ListTile(
                leading: Icon(Icons.person),
                title: Text('Long username with many characters'),
                subtitle: Text('user@example.com'),
                trailing: Icon(Icons.chevron_right),
              ),
            ],
          ),
          textScale: 2.0,
        ),
      );

      expect(find.byType(ListTile), findsOneWidget);
    });

    testWidgets('Card with price text wraps at 3x scale', (tester) async {
      await tester.pumpWidget(
        wrapInScaffold(
          Center(
            child: SizedBox(
              width: 200,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Product Name',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '12,500 RWF',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.green[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          textScale: 3.0,
        ),
      );

      expect(find.text('12,500 RWF'), findsOneWidget);
    });
  });

  // ─── 2. Touch Target Sizing Tests ───────────────────────────────────────

  group('Touch target ≥ 48dp', () {
    testWidgets('IconButton meets 48dp minimum', (tester) async {
      await tester.pumpWidget(
        wrapInScaffold(
          Center(
            child: IconButton(
              onPressed: () {},
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back),
            ),
          ),
        ),
      );

      final size = tester.getSize(find.byType(IconButton));
      expect(size.width, greaterThanOrEqualTo(48.0));
      expect(size.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets('ElevatedButton meets 48dp height', (tester) async {
      await tester.pumpWidget(
        wrapInScaffold(
          Center(
            child: SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: () {},
                child: const Text('Action'),
              ),
            ),
          ),
        ),
      );

      final elevatedBtn = find.byType(ElevatedButton);
      final size = tester.getSize(elevatedBtn);
      expect(size.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets('InkWell-wrapped container meets 48dp', (tester) async {
      await tester.pumpWidget(
        wrapInScaffold(
          Center(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {},
                child: Container(
                  width: 48,
                  height: 48,
                  color: Colors.blue,
                  child: const Icon(Icons.add),
                ),
              ),
            ),
          ),
        ),
      );

      final size = tester.getSize(find.byType(InkWell));
      expect(size.width, greaterThanOrEqualTo(48.0));
      expect(size.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets('Switch meets 48dp height', (tester) async {
      await tester.pumpWidget(
        wrapInScaffold(Center(child: Switch(value: true, onChanged: (v) {}))),
      );

      final size = tester.getSize(find.byType(Switch));
      expect(size.height, greaterThanOrEqualTo(48.0));
    });
  });

  // ─── 3. Semantic Label Tests ────────────────────────────────────────────

  group('Semantic labels', () {
    testWidgets('IconButton has tooltip (semantic label)', (tester) async {
      await tester.pumpWidget(
        wrapInScaffold(
          Center(
            child: IconButton(
              onPressed: () {},
              tooltip: 'Settings',
              icon: const Icon(Icons.settings),
            ),
          ),
        ),
      );

      // Tooltip is used as semantic label by Flutter's IconButton
      final semantics = tester.getSemantics(find.byType(IconButton));
      expect(semantics.tooltip, 'Settings');
    });

    testWidgets('Semantics button wrapper is accessible', (tester) async {
      await tester.pumpWidget(
        wrapInScaffold(
          Center(
            child: Semantics(
              button: true,
              label: 'Open menu',
              child: GestureDetector(
                onTap: () {},
                child: Container(
                  width: 48,
                  height: 48,
                  color: Colors.blue,
                  child: const Icon(Icons.menu),
                ),
              ),
            ),
          ),
        ),
      );

      final semantics = tester.getSemantics(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Open menu',
        ),
      );
      expect(semantics.label, 'Open menu');
    });
  });
}
