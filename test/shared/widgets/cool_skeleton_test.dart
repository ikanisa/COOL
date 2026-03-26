import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/shared/widgets/cool_skeleton.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('CoolSkeleton', () {
    testWidgets('renders with default dimensions', (tester) async {
      await tester.pumpWidget(_wrap(const CoolSkeleton()));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CoolSkeleton), findsOneWidget);
    });

    testWidgets('card constructor renders full width', (tester) async {
      await tester.pumpWidget(_wrap(const CoolSkeleton.card()));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CoolSkeleton), findsOneWidget);
    });
  });

  group('CoolSkeletonList', () {
    testWidgets('renders specified number of items', (tester) async {
      await tester.pumpWidget(_wrap(const CoolSkeletonList(itemCount: 4)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CoolSkeleton), findsNWidgets(4));
    });
  });

  group('CoolSkeletonRow', () {
    testWidgets('renders horizontal list', (tester) async {
      await tester.pumpWidget(_wrap(const CoolSkeletonRow(itemCount: 3)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CoolSkeleton), findsNWidgets(3));
    });
  });
}
