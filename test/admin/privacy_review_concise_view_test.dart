import 'package:collect_app/admin/core/admin_privacy_review_controller.dart';
import 'package:collect_app/admin/core/admin_privacy_review_view.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/privacy_review_fixtures.dart';

void main() {
  for (final width in [320.0, 1440.0]) {
    testWidgets(
      'privacy scope stays available without an action at $width and 2x text',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = PrivacyApiFake();
        final journal = PrivacyJournalFixture();
        final controller = AdminPrivacyReviewController(
          api: api,
          actorId: privacyActor,
          sessionId: privacySession,
          store: journal.store,
          now: () => privacyNow,
          isCurrent: () => true,
          newOperationId: () => privacyOperation,
        );
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: CollectTheme.dark(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: Scaffold(
                body: AdminPrivacyReviewView(controller: controller),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Waiting for approved policy'), findsOneWidget);
          expect(
            find.text(
              'Deletion is paused until a retention and erasure policy is approved. Reviews do not delete accounts or data.',
            ),
            findsOneWidget,
          );
          expect(find.text('Auth access'), findsNothing);
          final reads = api.reads;
          final disclosure = find.text('Privacy review details');
          await tester.ensureVisible(disclosure);
          await tester.pumpAndSettle();
          final tile = find.byKey(const Key('privacy-review-scope-details'));
          final collapsedHeight = tester.getSize(tile).height;
          await tester.tap(disclosure);
          await tester.pump();
          final expandedHeight = tester.getSize(tile).height;
          expect(expandedHeight, greaterThan(collapsedHeight));
          await tester.pump(const Duration(milliseconds: 220));
          expect(tester.getSize(tile).height, expandedHeight);
          for (final value in [
            'Approved retention and erasure policy',
            'Record the policy blocker',
            'Not performed by a review',
            'Unchanged by a review',
            'Not started by a review',
          ]) {
            final fact = find.text(value);
            await tester.ensureVisible(fact);
            await tester.pumpAndSettle();
            expect(fact, findsOneWidget);
          }
          expect(api.reads, reads);
          expect(api.lookups, 0);
          expect(api.writes, isEmpty);
          expect(controller.pending, isNull);
          expect(controller.canStart, isFalse);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
        }
      },
    );
  }
}
