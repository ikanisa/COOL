import 'package:cool_app/shared/widgets/share_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  group('ShareCard', () {
    testWidgets('renders title, subtitle, and action labels', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ShareCard(
            title: 'Share this match',
            subtitle: 'Invite friends to the fixture',
            shareUrl: 'https://cool.app/match/123',
          ),
        ),
      );

      expect(find.text('Share this match'), findsOneWidget);
      expect(find.text('Invite friends to the fixture'), findsOneWidget);
      expect(find.text('QR / Share'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Contacts'), findsOneWidget);
    });

    testWidgets('stays stable in narrow layouts', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _wrap(
          const SizedBox(
            width: 220,
            child: ShareCard(
              title: 'Share this match',
              subtitle: 'Invite friends to the fixture',
              shareUrl: 'https://cool.app/match/123',
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('QR / Share'), findsOneWidget);
      expect(find.text('Contacts'), findsOneWidget);
    });
  });
}
