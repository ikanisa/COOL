import 'dart:async';

import 'package:collect_app/admin/core/admin_roster_dialog.dart';
import 'package:collect_app/admin/core/admin_roster_import.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/admin_roster_fixture.dart';
import 'support/test_capture_paths.dart';

const captureRosterEvidence = bool.fromEnvironment('CAPTURE_ROSTER_EVIDENCE');
const captureRecoveryEvidence = bool.fromEnvironment(
  'CAPTURE_ROSTER_RECOVERY_EVIDENCE',
);

class StatusDialogGateway extends FakeRosterGateway {
  int reads = 0;
  @override
  Future<Object?> read(String importId) async {
    reads++;
    return {
      'contract_version': 1,
      'ok': true,
      'import_id': importId,
      'state': 'preview_ready',
      'expires_at': latest!['expires_at'],
      'preview': latest,
      'commit': null,
      'error_code': null,
    };
  }
}

void main() {
  if (captureRosterEvidence || captureRecoveryEvidence) {
    final previousComparator = goldenFileComparator;
    setUpAll(() {
      goldenFileComparator = LocalFileComparator(
        collectTestCaptureFile('feature-revoked.png').uri,
      );
    });
    tearDownAll(() => goldenFileComparator = previousComparator);
  }
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  Future<void> show(
    WidgetTester tester,
    AdminRosterDraft draft, {
    double scale = 1,
    double keyboardInset = 0,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: CollectTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboardInset),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAdminRosterImport(context, draft),
              child: const Text('Import'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    final target = find.text(label);
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> fillReason(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('roster-reason')));
    await tester.enterText(
      find.byKey(const Key('roster-reason')),
      'Compared all rows against original source',
    );
  }

  testWidgets(
    'feature revocation hides private rows and shows actionable close state',
    (tester) async {
      final gateway = FakeRosterGateway();
      final draft = AdminRosterDraft(gateway, collectionId: rosterCollectionId);
      await draft.prepare(
        () async => AdminRosterUpload.pasted('Private Alice'),
      );
      await show(tester, draft);
      await fillReason(tester);
      gateway.onReview = (_) async =>
          throw const AdminRosterRequestError('roster_feature_disabled');
      await tap(tester, 'Save reviewed rows');
      expect(find.text('Roster unavailable'), findsOneWidget);
      expect(find.textContaining('currently disabled'), findsOneWidget);
      expect(find.text('Row 1'), findsNothing);
      expect(find.byKey(const Key('roster-reason')), findsNothing);
      expect(draft.initialPreview, isNull);
      if (captureRecoveryEvidence) {
        await expectLater(
          find.byType(AlertDialog),
          matchesGoldenFile(
            collectTestCaptureFile('feature-revoked.png').uri,
          ),
        );
      }
      await tap(tester, 'Close');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'terminal review limit disables retry and requires an explicit saved status check',
    (tester) async {
      final gateway = StatusDialogGateway();
      final draft = AdminRosterDraft(gateway, collectionId: rosterCollectionId);
      await draft.prepare(() async => AdminRosterUpload.pasted('Roster'));
      await show(tester, draft, scale: 2);
      await fillReason(tester);
      gateway.onReview = (_) async =>
          throw const AdminRosterRequestError('roster_revision_limit');
      await tap(tester, 'Save reviewed rows');
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Retry saved review'),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('review limit'), findsOneWidget);
      await tap(tester, 'Check saved import status');
      expect(gateway.reads, 1);
      expect(gateway.reviews, hasLength(1));
      expect(draft.canSaveReview, false);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'page26 edits persist on return and commit requires saved review plus all-pages affirmation',
    (tester) async {
      final gateway = FakeRosterGateway()..count = 31;
      final draft = AdminRosterDraft(gateway);
      await draft.prepare(() async => AdminRosterUpload.pasted('Roster'));
      await show(tester, draft);
      await tester.enterText(
        find.byKey(const Key('roster-title')),
        'New private group',
      );
      await fillReason(tester);
      expect(find.text('Row 26'), findsNothing);
      await tap(tester, 'Next rows');
      expect(find.text('Row 26'), findsOneWidget);
      expect(find.text('Row 31'), findsOneWidget);
      final row26 = find.byKey(
        const ValueKey('roster-$rosterRevisionId-25-member_name'),
      );
      await tester.ensureVisible(row26);
      await tester.enterText(row26, 'Corrected Member 26');
      await tap(tester, 'Previous rows');
      await tap(tester, 'Next rows');
      expect(
        tester.widget<TextFormField>(row26).initialValue,
        'Corrected Member 26',
      );
      if (captureRosterEvidence) {
        await tester.ensureVisible(row26);
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(AlertDialog),
          matchesGoldenFile(
            collectTestCaptureFile('roster-page-2-light.png').uri,
          ),
        );
      }
      await tap(tester, 'Save reviewed rows');
      expect(gateway.reviews.single['p_rows'], hasLength(31));
      expect(
        (gateway.reviews.single['p_rows'] as List)[25]['member_name'],
        'Corrected Member 26',
      );
      final commit = find.widgetWithText(
        FilledButton,
        'Create group and add members',
      );
      expect(tester.widget<FilledButton>(commit).onPressed, isNull);
      await tester.ensureVisible(find.byKey(const Key('roster-affirm')));
      await tester.tap(find.byKey(const Key('roster-affirm')));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(commit).onPressed, isNotNull);
      await tester.tap(commit);
      await tester.pumpAndSettle();
      expect(gateway.commits.single['p_mode'], 'create');
      expect(gateway.commits.single.containsKey('p_rows'), false);
      expect(find.byType(AdminRosterImportDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'existing group retry requires status check and retains exact payload after null ACK',
    (tester) async {
      final gateway = StatusDialogGateway();
      final draft = AdminRosterDraft(gateway, collectionId: rosterCollectionId);
      await draft.prepare(() async => AdminRosterUpload.pasted('Roster'));
      await show(tester, draft);
      await fillReason(tester);
      expect(find.byKey(const Key('roster-title')), findsNothing);
      await tap(tester, 'Save reviewed rows');
      await tester.ensureVisible(find.byKey(const Key('roster-affirm')));
      await tester.tap(find.byKey(const Key('roster-affirm')));
      await tester.pumpAndSettle();
      gateway.onCommit = (params) async => gateway.commits.length == 1
          ? null
          : commitFixture(params, replayed: true);
      await tap(tester, 'Add members');
      expect(find.byType(AdminRosterImportDialog), findsOneWidget);
      expect(find.text('Retry same submission'), findsOneWidget);
      expect(find.textContaining('outcome is unknown'), findsOneWidget);
      if (captureRecoveryEvidence) {
        await tester.ensureVisible(find.textContaining('outcome is unknown'));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(AlertDialog),
          matchesGoldenFile(
            collectTestCaptureFile('uncertain-submission.png').uri,
          ),
        );
      }
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Retry same submission'),
            )
            .onPressed,
        isNull,
      );
      await tap(tester, 'Check saved import status');
      expect(gateway.reads, 1);
      expect(gateway.commits, hasLength(1));
      await tap(tester, 'Retry same submission');
      expect(gateway.commits.first, gateway.commits.last);
      expect(gateway.commits.first['p_collection_id'], rosterCollectionId);
      expect(find.byType(AdminRosterImportDialog), findsNothing);
    },
  );
  testWidgets(
    'account/session invalidation immediately hides source, rows and text while extraction waits',
    (tester) async {
      final gateway = FakeRosterGateway();
      final draft = AdminRosterDraft(gateway);
      await show(tester, draft);
      await tester.enterText(
        find.byKey(const Key('roster-title')),
        'Secret group',
      );
      await fillReason(tester);
      await tester.ensureVisible(find.byKey(const Key('roster-source')));
      await tester.enterText(
        find.byKey(const Key('roster-source')),
        'Private Alice,Private MoMo,0788100000',
      );
      final response = Completer<Object?>();
      gateway.onPrepare = (_) => response.future;
      await tester.tap(find.text('Prepare preview'));
      await tester.pump();
      gateway.invalidate();
      await tester.pump();
      expect(find.text('Sign-in changed'), findsOneWidget);
      expect(find.byKey(const Key('roster-source')), findsNothing);
      expect(find.byKey(const Key('roster-title')), findsNothing);
      response.complete(previewFixture(gateway.body!));
      await tester.pumpAndSettle();
      expect(find.text('Row 1'), findsNothing);
      expect(draft.rows, isEmpty);
      await tap(tester, 'Close');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('AI source confidence remains visible after saving human edits', (
    tester,
  ) async {
    final gateway = FakeRosterGateway();
    final draft = AdminRosterDraft(gateway, collectionId: rosterCollectionId);
    await draft.prepare(
      () async => AdminRosterUpload.fromBytes(
        'scan.pdf',
        'pdf',
        Uint8List.fromList([1, 2, 3]),
        aiConsent: true,
      ),
    );
    await show(tester, draft);
    await fillReason(tester);
    await tap(tester, 'Save reviewed rows');
    expect(
      find.text(
        'Initial extraction confidence: 71% · verify against the source',
      ),
      findsNWidgets(2),
    );
    await tap(tester, 'Original AI extraction receipt');
    expect(find.textContaining('roster-ai-extraction-v1'), findsOneWidget);
    await tap(tester, 'Discard draft');
  });
  testWidgets(
    'keyboard traversal and Escape keep the explicit-discard draft recoverable',
    (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = FakeRosterGateway();
      final draft = AdminRosterDraft(gateway);
      await show(tester, draft, scale: 1.4, keyboardInset: 240);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AdminRosterImportDialog), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('roster-title')));
      await tester.enterText(
        find.byKey(const Key('roster-title')),
        'Keyboard group',
      );
      await tap(tester, 'Discard draft');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    '320px and 2x text retain reachable fields, errors, review and discard actions',
    (tester) async {
      tester.view.physicalSize = const Size(320, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = FakeRosterGateway();
      final draft = AdminRosterDraft(gateway);
      await show(tester, draft, scale: 2);
      await tap(tester, 'Prepare preview');
      expect(find.text('Use 3 to 120 characters.'), findsOneWidget);
      expect(find.text('Use 8 to 500 characters.'), findsOneWidget);
      expect(
        tester
            .renderObject<RenderParagraph>(
              find.text('Use 3 to 120 characters.'),
            )
            .didExceedMaxLines,
        false,
      );
      expect(
        tester
            .renderObject<RenderParagraph>(
              find.text('Use 8 to 500 characters.'),
            )
            .didExceedMaxLines,
        false,
      );
      if (captureRosterEvidence) {
        await tester.ensureVisible(find.text('Use 3 to 120 characters.'));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(AlertDialog),
          matchesGoldenFile(
            collectTestCaptureFile('roster-compact-2x-errors.png').uri,
          ),
        );
      }
      expect(tester.takeException(), isNull);
      await tap(tester, 'Discard draft');
      expect(tester.takeException(), isNull);
    },
  );
}
