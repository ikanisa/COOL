import 'package:collect_app/shared/utils/collect_share_origin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('native share origin is non-empty and inside the rendered view', (
    tester,
  ) async {
    Rect? origin;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              origin = collectSharePositionOrigin(context);
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    expect(origin, isNotNull);
    expect(origin!.isEmpty, isFalse);
    expect(origin!.left, greaterThanOrEqualTo(0));
    expect(origin!.top, greaterThanOrEqualTo(0));
    expect(origin!.right, lessThanOrEqualTo(tester.view.physicalSize.width));
    expect(origin!.bottom, lessThanOrEqualTo(tester.view.physicalSize.height));
  });
}
