import 'dart:async';

import 'package:collect_app/admin/core/admin_automatic_gateway_models.dart';
import 'package:collect_app/admin/core/admin_automatic_gateway_view.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_automatic_gateway_models_test.dart' as fixture;

const identity = AdminIdentity(
  userId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  displayName: 'Synthetic operator',
  roles: ['platform_owner'],
  permissions: ['notifications.read', 'system_health.read'],
);

class Sessions extends AdminSessionController {
  Sessions() : super(null) {
    change(1);
  }
  void change(int generation) => state = (
    key: (userId: identity.userId, sessionId: 'synthetic-$generation'),
    generation: generation,
  );
}

class Repository extends AdminEvidenceRepository {
  Repository()
    : data = fixture.automaticFixture('late-contradictory-observation');
  Map<String, dynamic> data;
  Object? error;
  Completer<Map<String, dynamic>>? first;
  int reads = 0;
  @override
  Future<Map<String, dynamic>> automaticReceiptEvidence(
    String id, {
    int limit = 20,
    AdminAutomaticHistoryCursor? before,
  }) async {
    reads++;
    if (error != null) throw error!;
    if (reads == 1 && first != null) return first!.future;
    return data;
  }
}

Future<ProviderContainer> mount(
  WidgetTester tester,
  Repository repository, {
  AdminIdentity actor = identity,
  Sessions? sessions,
  DateTime Function()? clock,
  double width = 1440,
}) async {
  tester.view.physicalSize = Size(width, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      adminRepositoryProvider.overrideWithValue(repository),
      adminIdentityProvider.overrideWith((_) async => actor),
      adminAuthSessionScopeProvider.overrideWith((_) => sessions ?? Sessions()),
      adminClockProvider.overrideWithValue(
        clock ?? () => DateTime.parse(repository.data['checked_at'] as String),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: CollectTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminAutomaticReceiptCard(
              receiptId: repository.data['receipt_id'] as String,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  for (final width in [1440.0, 390.0]) {
    testWidgets(
      'actual multipart contradiction and historical ACK render at width $width',
      (tester) async {
        await mount(tester, Repository(), width: width);
        expect(find.text('Recorded state: uncertain'), findsOneWidget);
        expect(find.text('Historical archive acknowledgement'), findsOneWidget);
        expect(find.textContaining('conflicting observations'), findsOneWidget);
        expect(
          find.textContaining('do not establish carrier delivery'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'lack of independent health permission prevents the backend read',
    (tester) async {
      final repository = Repository();
      await mount(
        tester,
        repository,
        actor: const AdminIdentity(
          userId: 'actor',
          displayName: 'Limited reviewer',
          roles: ['admin'],
          permissions: ['notifications.read'],
        ),
      );
      expect(repository.reads, 0);
      expect(
        find.text('Automatic send evidence access required'),
        findsOneWidget,
      );
    },
  );
  testWidgets('expired evidence is hidden until a fresh read', (tester) async {
    final repository = Repository();
    var now = DateTime.parse(repository.data['checked_at'] as String);
    await mount(tester, repository, clock: () => now);
    now = now.add(const Duration(seconds: 60));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Automatic evidence expired'), findsOneWidget);
    expect(find.text('Recorded state: uncertain'), findsNothing);
  });
  for (final error in [
    const PostgrestException(message: 'denied', code: '42501'),
    UnsupportedError('missing service'),
    const FormatException('private fixture'),
  ]) {
    testWidgets(
      'read failure does not disclose internal detail: ${error.runtimeType}',
      (tester) async {
        await mount(tester, Repository()..error = error);
        expect(find.textContaining('could not be authorized'), findsOneWidget);
        expect(find.textContaining('private fixture'), findsNothing);
        expect(find.text('Recorded state: uncertain'), findsNothing);
      },
    );
  }
  testWidgets(
    'a late reply from the original session cannot replace a current read',
    (tester) async {
      final repository = Repository()
        ..first = Completer<Map<String, dynamic>>();
      final sessions = Sessions();
      await mount(tester, repository, sessions: sessions);
      final old = repository.data;
      repository.data = fixture.automaticFixture(
        'current-receipt-before-automatic-grant',
      );
      sessions.change(2);
      await tester.pumpAndSettle();
      repository.first!.complete(old);
      await tester.pumpAndSettle();
      expect(find.text('No automatic attempt recorded'), findsOneWidget);
      expect(find.text('Recorded state: uncertain'), findsNothing);
      expect(repository.reads, 2);
    },
  );
}
