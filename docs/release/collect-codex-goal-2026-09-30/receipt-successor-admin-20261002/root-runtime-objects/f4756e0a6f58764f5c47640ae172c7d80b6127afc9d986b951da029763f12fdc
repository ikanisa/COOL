import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_models.dart';
import 'package:collect_app/admin/core/admin_runtime.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_host.dart';
import 'support/successor_fixture.dart';

class SessionFixture extends AdminSessionController {
  SessionFixture(SuccessorFixture f) : super(null) {
    state = (key: f.session!, generation: 1);
  }
}

class ReceiptRepositoryFixture extends AdminRepository {
  ReceiptRepositoryFixture(this.fixture) : super(null);
  final SuccessorFixture fixture;
  @override
  Future<Map<String, dynamic>> rpcMap(
    String name, {
    Map<String, dynamic>? params,
    bool automaticRetry = true,
  }) async {
    expect(automaticRetry, isFalse);
    return Map<String, dynamic>.from(
      await fixture.rpc(name, params ?? {}) as Map,
    );
  }
}

void main() {
  testWidgets(
    'actual host uses repository no-retry adapter and current owner gates',
    (tester) async {
      final f = SuccessorFixture();
      final repository = ReceiptRepositoryFixture(f), store = MemoryStore();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminRepositoryProvider.overrideWithValue(repository),
            adminAuthSessionScopeProvider.overrideWith(
              (ref) => SessionFixture(f),
            ),
            adminIdentityProvider.overrideWith(
              (ref) async => AdminIdentity(
                userId: f.session!.userId,
                displayName: 'Synthetic owner',
                roles: ['platform_owner'],
                permissions: [
                  'payments.read',
                  'notifications.read',
                  'system_health.read',
                  'notifications.manage',
                ],
              ),
            ),
            adminClockProvider.overrideWithValue(() => f.now),
            adminReceiptSuccessorStoreProvider.overrideWithValue(store),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: AdminReceiptSuccessorHost(
                  outboxId: f.outbox,
                  sourceSnapshotId: f.source,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        f.calls.map((c) => c.name),
        containsAll([
          'admin_inspect_unarmed_receipt_closure_v1',
          'admin_inspect_receipt_successor_v1',
          'admin_list_receipt_successors_v1',
        ]),
      );
      expect(find.text('Replacement receipt review'), findsOneWidget);
      expect(find.text('Review replacement'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
