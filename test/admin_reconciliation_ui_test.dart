import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:collect_app/admin/admin_app.dart';
import 'package:collect_app/admin/admin_router.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_reconciliation_step_up.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_reconciliation_repository_test.dart' as fixtures;

AdminIdentity _identity({
  String id = fixtures.actorA,
  bool read = true,
  bool write = true,
}) => AdminIdentity(
  userId: id,
  displayName: 'Synthetic operator',
  roles: [if (write) 'platform_owner'],
  permissions: [
    if (read) 'payments.read',
    if (read) 'payment_events.read',
    if (write) 'payments.allocate',
  ],
);
final _actor = StateProvider<AdminIdentity>((ref) => _identity());
final _session = StateProvider<String>((ref) => 'session-a');

class _Repository extends AdminEvidenceRepository {
  int queueCount = 1;
  int queueReads = 0;
  final offsets = <int>[];
  final reviewRequests = <({String? paymentId, int offset})>[];
  List<Map<String, dynamic>> reviews = [];
  Map<String, dynamic> details = fixtures.lineage();
  int approvals = 0;
  int proposals = 0;
  int finalizations = 0;
  Object? failure;
  Completer<Map<String, dynamic>>? detailGate;
  Completer<AdminReconciliationFinalization>? finalizeGate;
  AdminReconciliationFinalization result =
      AdminReconciliationFinalization.fromJson(
        fixtures.finalization(),
        reviewId: fixtures.reviewId,
        paymentId: fixtures.paymentId,
      );
  @override
  Future<AdminRuntimeConfig?> runtimeConfig() async => null;
  @override
  Future<AdminIdentity?> currentIdentity() async => _identity();
  @override
  Future<AdminListResult> list(
    String rpcName, {
    String? search,
    String? status,
    int? limit,
    int? offset,
    String? sortBy,
    String? countryCode,
  }) async {
    if (rpcName != 'admin_list_collect_reconciliations') {
      return const AdminListResult(rows: [], total: 0);
    }
    queueReads++;
    offsets.add(offset ?? 0);
    return AdminListResult(
      rows: [
        for (
          var i = offset ?? 0;
          i < math.min((offset ?? 0) + (limit ?? 25), queueCount);
          i++
        )
          AdminTableRowData(
            id: i == 0
                ? fixtures.paymentId
                : '99920000-0000-4000-8000-${(100 + i).toString().padLeft(12, '0')}',
            title: 'Payment ${i + 1}',
            subtitle: 'Awaiting evidence',
            status: 'review',
            amount: 'RWF 2,500',
          ),
      ],
      total: queueCount,
    );
  }

  @override
  Future<AdminListResult> paymentReconciliationReviews(
    String? paymentId, {
    int limit = 25,
    int offset = 0,
  }) async {
    reviewRequests.add((paymentId: paymentId, offset: offset));
    return AdminListResult.fromJson({
      'rows': reviews.skip(offset).take(limit).toList(),
      'total': reviews.length,
    });
  }

  @override
  Future<Map<String, dynamic>> paymentReconciliationDetail(
    String reviewId, {
    required String paymentId,
  }) async => detailGate == null ? details : detailGate!.future;
  @override
  Future<String> proposePaymentReconciliation(
    Map<String, dynamic> evidence,
  ) async {
    proposals++;
    if (failure != null) throw failure!;
    return fixtures.reviewId;
  }

  @override
  Future<void> approvePaymentReconciliation(
    String reviewId,
    String reason,
  ) async {
    approvals++;
    if (failure != null) throw failure!;
  }

  @override
  Future<AdminReconciliationFinalization> finalizePaymentReconciliation(
    String reviewId, {
    required String paymentId,
  }) async {
    finalizations++;
    if (failure != null) throw failure!;
    return finalizeGate == null ? result : finalizeGate!.future;
  }
}

Future<ProviderContainer> _open(
  WidgetTester tester,
  _Repository repository, {
  AdminIdentity? identity,
  Future<void> Function(String)? stepUp,
  bool route = false,
  Size size = const Size(1200, 950),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      supabaseClientProvider.overrideWithValue(null),
      _actor.overrideWith((_) => identity ?? _identity()),
      adminAuthUserIdProvider.overrideWith((ref) => ref.watch(_actor).userId),
      adminAuthGuardProvider.overrideWithValue(
        const AdminAuthGuard(isAuthorized: true),
      ),
      adminIdentityProvider.overrideWith((ref) async => ref.watch(_actor)),
      adminReconciliationSessionKeyProvider.overrideWith(
        (ref) => '${ref.watch(_actor).userId}/${ref.watch(_session)}',
      ),
      adminRepositoryProvider.overrideWithValue(repository),
      adminClockProvider.overrideWithValue(
        () => DateTime.utc(2026, 9, 30, 8, 12),
      ),
      adminReconciliationStepUpProvider.overrideWithValue(
        stepUp ?? (_) async {},
      ),
    ],
  );
  addTearDown(container.dispose);
  if (route) container.read(adminRouterProvider).go('/admin/reconciliations');
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(
        key: const Key('reconciliation-capture'),
        child: route
            ? const CollectAdminApp()
            : MaterialApp(
                theme: AppTheme.light(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(textScale)),
                  child: child!,
                ),
                home: const Scaffold(body: AdminReconciliationPage()),
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('COLLECT_RECONCILIATION_CAPTURE')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('reconciliation-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(
      'docs/release/reconciliation-ui-2026-09-30/screens/$name.png',
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _tap(WidgetTester tester, String label) async {
  final finder = find.text(label).last;
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> _payment(WidgetTester tester) => _tap(tester, 'Payment 1');
Future<void> _mfa(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextField, 'Authenticator code'),
    '123456',
  );
  await _tap(tester, 'Verify and continue');
}

Future<void> _close(WidgetTester tester) async =>
    tester.pumpWidget(const SizedBox.shrink());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets(
    'actual reconciliation route renders the protected review queue',
    (tester) async {
      await _open(tester, _Repository(), route: true);
      expect(find.text('Payment 1'), findsOneWidget);
      expect(find.text('All evidence reviews'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _close(tester);
    },
  );
  testWidgets('read denial prevents any reconciliation request', (
    tester,
  ) async {
    final repo = _Repository();
    await _open(tester, repo, identity: _identity(read: false));
    expect(find.text('Payment review access required'), findsOneWidget);
    expect(repo.queueReads, 0);
    await _close(tester);
  });
  testWidgets('read-only operator cannot propose or approve', (tester) async {
    final repo = _Repository()
      ..reviews = [fixtures.review(proposer: fixtures.actorB)];
    await _open(tester, repo, identity: _identity(write: false));
    await _payment(tester);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Propose reconciliation'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Approve evidence'),
          )
          .onPressed,
      isNull,
    );
    await _close(tester);
  });
  testWidgets('maker cannot approve own evidence', (tester) async {
    final repo = _Repository()..reviews = [fixtures.review()];
    await _open(tester, repo);
    await _payment(tester);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Approve evidence'),
          )
          .onPressed,
      isNull,
    );
    expect(
      find.text('A different approved operator must review this evidence.'),
      findsOneWidget,
    );
    await _close(tester);
  });
  testWidgets(
    'independent approval requires reason then real step-up callback',
    (tester) async {
      final repo = _Repository()
        ..reviews = [fixtures.review(proposer: fixtures.actorB)];
      var verifications = 0;
      await _open(
        tester,
        repo,
        stepUp: (code) async {
          expect(code, '123456');
          verifications++;
        },
      );
      await _payment(tester);
      await _tap(tester, 'Approve evidence');
      await _tap(tester, 'Approve evidence');
      expect(
        find.text('Use a reason of 10 to 500 characters.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byType(TextFormField),
        'Independently checked statement.',
      );
      await _tap(tester, 'Approve evidence');
      expect(repo.approvals, 0);
      await _mfa(tester);
      expect(verifications, 1);
      expect(repo.approvals, 1);
      expect(find.textContaining('Finalize within 15 minutes'), findsOneWidget);
      await _close(tester);
    },
  );
  testWidgets(
    'missing verified factor is actionable and never submits approval',
    (tester) async {
      final repo = _Repository()
        ..reviews = [
          fixtures.review(
            status: 'approved',
            proposer: fixtures.actorB,
            approver: fixtures.actorA,
          ),
        ];
      await _open(
        tester,
        repo,
        stepUp: (_) async => throw const AdminReconciliationStepUpException(
          'verified_authenticator_required',
          'A verified authenticator is required. Ask the Admin owner for help with the approved MFA setup.',
        ),
      );
      await _payment(tester);
      await _tap(tester, 'Finalize reconciliation');
      await _mfa(tester);
      expect(find.textContaining('Ask the Admin owner'), findsOneWidget);
      expect(repo.finalizations, 0);
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'Authenticator code'),
            )
            .controller!
            .text,
        isEmpty,
      );
      await _close(tester);
    },
  );
  testWidgets('reversed replay never claims a new posted payment', (
    tester,
  ) async {
    final repo = _Repository()
      ..reviews = [
        fixtures.review(
          status: 'approved',
          proposer: fixtures.actorB,
          approver: fixtures.actorA,
        ),
      ]
      ..result = AdminReconciliationFinalization.fromJson(
        fixtures.finalization(status: 'reversed', replayed: true),
        reviewId: fixtures.reviewId,
        paymentId: fixtures.paymentId,
      );
    await _open(tester, repo);
    await _payment(tester);
    await _tap(tester, 'Finalize reconciliation');
    await _mfa(tester);
    expect(find.textContaining('later reversed'), findsOneWidget);
    expect(
      find.text('Reconciled payment posted to the Collect ledger.'),
      findsNothing,
    );
    await _close(tester);
  });
  testWidgets(
    'expired approval disables financial action and explains recovery',
    (tester) async {
      final repo = _Repository()
        ..reviews = [
          fixtures.review(
            status: 'approved',
            proposer: fixtures.actorB,
            approver: fixtures.actorA,
          )..['approved_at'] = '2026-09-30T07:00:00Z',
        ];
      await _open(tester, repo);
      await _payment(tester);
      expect(find.text('Finalize reconciliation'), findsNothing);
      expect(
        find.textContaining('Record a new proposal from the payment queue'),
        findsOneWidget,
      );
      await _close(tester);
    },
  );
  testWidgets('revoked actor error is safe and actionable', (tester) async {
    final repo = _Repository()
      ..reviews = [
        fixtures.review(
          status: 'approved',
          proposer: fixtures.actorB,
          approver: fixtures.actorA,
        ),
      ]
      ..failure = const PostgrestException(
        message: 'reconciliation_actor_unavailable',
        code: '42501',
      );
    await _open(tester, repo);
    await _payment(tester);
    await _tap(tester, 'Finalize reconciliation');
    await _mfa(tester);
    expect(
      find.textContaining('role or sign-in is no longer valid'),
      findsOneWidget,
    );
    await _close(tester);
  });
  testWidgets('shrinking later queue page recovers to previous server page', (
    tester,
  ) async {
    final repo = _Repository()..queueCount = 26;
    await _open(tester, repo);
    await _tap(tester, 'Next payments');
    expect(find.text('Payment 26'), findsOneWidget);
    repo.queueCount = 1;
    await tester.tap(find.byTooltip('Refresh reconciliations'));
    await tester.pumpAndSettle();
    expect(find.text('Payment 1'), findsOneWidget);
    expect(repo.offsets.sublist(repo.offsets.length - 2), [25, 0]);
    expect(find.text('1–1 of 1 payments · Page 1'), findsOneWidget);
    await _close(tester);
  });
  testWidgets('all history and per-payment reviews reach every server page', (
    tester,
  ) async {
    final repo = _Repository()
      ..reviews = [for (var i = 4; i < 30; i++) fixtures.review(index: i)];
    await _open(tester, repo);
    await _payment(tester);
    await _tap(tester, 'Next reviews');
    expect(find.text('STATEMENT-29'), findsOneWidget);
    expect(repo.reviewRequests.last, (
      paymentId: fixtures.paymentId,
      offset: 25,
    ));
    await _tap(tester, 'All evidence reviews');
    await _tap(tester, 'Next reviews');
    expect(repo.reviewRequests.last, (paymentId: null, offset: 25));
    await _close(tester);
  });
  testWidgets('lineage pages all audit records without private metadata', (
    tester,
  ) async {
    final repo = _Repository()..reviews = [fixtures.review()];
    repo.details['audit'] = [
      for (var i = 0; i < 11; i++)
        {
          'id': 'AUDIT-$i',
          'action': 'reconciliation.proposed',
          'metadata': {'reason': 'Reason $i', 'session_id': 'PRIVATE-SESSION'},
        },
    ];
    await _open(tester, repo);
    await _payment(tester);
    await _tap(tester, 'Evidence and audit');
    expect(find.textContaining('AUDIT-10'), findsNothing);
    await _tap(tester, 'Next Audit events');
    expect(find.textContaining('AUDIT-10'), findsOneWidget);
    expect(find.textContaining('PRIVATE-SESSION'), findsNothing);
    await _close(tester);
  });
  for (final sameUser in [false, true]) {
    testWidgets(
      'visible lineage closes on ${sameUser ? 'same-user session' : 'account'} switch',
      (tester) async {
        final repo = _Repository()..reviews = [fixtures.review()];
        repo.details['source_reference'] = 'PRIVATE-OLD-REFERENCE';
        final container = await _open(tester, repo);
        await _payment(tester);
        await _tap(tester, 'Evidence and audit');
        expect(find.textContaining('PRIVATE-OLD-REFERENCE'), findsOneWidget);
        if (sameUser) {
          container.read(_session.notifier).state = 'session-b';
        } else {
          container.read(_actor.notifier).state = _identity(
            id: fixtures.actorB,
          );
        }
        await tester.pump();
        expect(find.textContaining('PRIVATE-OLD-REFERENCE'), findsNothing);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        await _close(tester);
      },
    );
  }
  testWidgets('pending lineage result is discarded after account switch', (
    tester,
  ) async {
    final repo = _Repository()
      ..reviews = [fixtures.review()]
      ..detailGate = Completer<Map<String, dynamic>>();
    final container = await _open(tester, repo);
    await _payment(tester);
    await tester.tap(find.text('Evidence and audit'));
    await tester.pump();
    container.read(_actor.notifier).state = _identity(id: fixtures.actorB);
    await tester.pump();
    repo.detailGate!.complete({
      ...fixtures.lineage(),
      'source_reference': 'PRIVATE-LATE-REFERENCE',
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('PRIVATE-LATE-REFERENCE'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    await _close(tester);
  });
  testWidgets('pending finalization cannot show success to a new session', (
    tester,
  ) async {
    final repo = _Repository()
      ..reviews = [
        fixtures.review(
          status: 'approved',
          proposer: fixtures.actorB,
          approver: fixtures.actorA,
        ),
      ]
      ..finalizeGate = Completer<AdminReconciliationFinalization>();
    final container = await _open(tester, repo);
    await _payment(tester);
    await _tap(tester, 'Finalize reconciliation');
    await tester.enterText(
      find.widgetWithText(TextField, 'Authenticator code'),
      '123456',
    );
    await tester.tap(find.text('Verify and continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    container.read(_session.notifier).state = 'session-b';
    await tester.pump();
    repo.finalizeGate!.complete(repo.result);
    await tester.pumpAndSettle();
    expect(
      find.text('Reconciled payment posted to the Collect ledger.'),
      findsNothing,
    );
    await _close(tester);
  });
  testWidgets('cancelling step-up performs no financial action', (
    tester,
  ) async {
    final repo = _Repository()
      ..reviews = [
        fixtures.review(
          status: 'approved',
          proposer: fixtures.actorB,
          approver: fixtures.actorA,
        ),
      ];
    await _open(tester, repo);
    await _payment(tester);
    await _tap(tester, 'Finalize reconciliation');
    await _tap(tester, 'Cancel');
    expect(repo.finalizations, 0);
    expect(find.byType(AlertDialog), findsNothing);
    await _close(tester);
  });
  testWidgets('pending step-up cannot act after same-user session change', (
    tester,
  ) async {
    final gate = Completer<void>();
    final repo = _Repository()
      ..reviews = [
        fixtures.review(
          status: 'approved',
          proposer: fixtures.actorB,
          approver: fixtures.actorA,
        ),
      ];
    final container = await _open(tester, repo, stepUp: (_) => gate.future);
    await _payment(tester);
    await _tap(tester, 'Finalize reconciliation');
    await tester.enterText(
      find.widgetWithText(TextField, 'Authenticator code'),
      '123456',
    );
    await tester.tap(find.text('Verify and continue'));
    await tester.pump();
    container.read(_session.notifier).state = 'session-b';
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    expect(repo.finalizations, 0);
    expect(find.byType(AlertDialog), findsNothing);
    await _close(tester);
  });
  testWidgets(
    'role revocation hides lineage and a later grant reloads cleanly',
    (tester) async {
      final repo = _Repository()..reviews = [fixtures.review()];
      repo.details['source_reference'] = 'PRIVATE-REVOKED';
      final container = await _open(tester, repo);
      await _payment(tester);
      await _tap(tester, 'Evidence and audit');
      container.read(_actor.notifier).state = _identity(read: false);
      await container.read(adminIdentityProvider.future);
      await tester.pump();
      expect(find.textContaining('PRIVATE-REVOKED'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('Payment review access required'), findsOneWidget);
      container.read(_actor.notifier).state = _identity();
      await tester.pumpAndSettle();
      expect(find.text('Payment 1'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton &&
                    widget.tooltip == 'Refresh reconciliations',
              ),
            )
            .onPressed,
        isNotNull,
      );
      await _close(tester);
    },
  );
  testWidgets('proposal validates evidence and posts only after step-up', (
    tester,
  ) async {
    final repo = _Repository();
    var verifications = 0;
    await _open(
      tester,
      repo,
      stepUp: (_) async {
        verifications++;
      },
    );
    await _payment(tester);
    await _tap(tester, 'Propose reconciliation');
    await _tap(tester, 'Record evidence');
    expect(
      find.text('Enter the verified 64-character evidence hash.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Evidence SHA-256'),
      'a' * 64,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Source reference'),
      'STATEMENT-001',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Evidence time in UTC'),
      '2026-02-30T08:00:00Z',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Review reason'),
      'Independently sourced statement checked.',
    );
    await _tap(tester, 'Record evidence');
    expect(find.text('Use a valid UTC timestamp ending in Z.'), findsOneWidget);
    expect(repo.proposals, 0);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Evidence time in UTC'),
      '2026-09-30T08:00:00Z',
    );
    await _tap(tester, 'Record evidence');
    expect(repo.proposals, 0);
    await _mfa(tester);
    expect(repo.proposals, 1);
    expect(verifications, 1);
    await _close(tester);
  });
  testWidgets('approved reviewer surface has an explicit bounded action', (
    tester,
  ) async {
    final repo = _Repository()
      ..reviews = [
        fixtures.review(
          status: 'approved',
          proposer: fixtures.actorB,
          approver: fixtures.actorA,
        ),
      ];
    await _open(tester, repo);
    await _payment(tester);
    await _capture(tester, 'approved-review-desktop');
    expect(
      find.text(
        'Approval is valid for 15 minutes. Finalize using this sign-in.',
      ),
      findsOneWidget,
    );
    await _close(tester);
  });
  testWidgets('narrow enlarged-text evidence and MFA forms remain usable', (
    tester,
  ) async {
    final repo = _Repository();
    await _open(tester, repo, size: const Size(390, 844), textScale: 2);
    await _payment(tester);
    await _tap(tester, 'Propose reconciliation');
    expect(
      find.widgetWithText(TextFormField, 'Evidence SHA-256'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await _capture(tester, 'evidence-form-narrow-text-200');
    await _tap(tester, 'Cancel');
    await _close(tester);
  });
}
