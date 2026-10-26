import 'dart:async';

import 'package:collect_app/admin/admin_app.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _signedIn = StateProvider<bool>((ref) => true);

class _DeferredSignOut extends AdminEvidenceRepository {
  final started = Completer<void>();
  final completion = Completer<void>();

  @override
  Future<void> signOut() {
    started.complete();
    return completion.future;
  }
}

void main() {
  testWidgets('Auth sign-out can unmount the shell before logout completes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _DeferredSignOut();
    final container = ProviderContainer(
      overrides: [
        collectBackendClientProvider.overrideWithValue(null),
        adminAuthGuardProvider.overrideWith(
          (ref) => AdminAuthGuard(isAuthorized: ref.watch(_signedIn)),
        ),
        adminAuthUserIdProvider.overrideWith(
          (ref) => ref.watch(_signedIn)
              ? '00000000-0000-0000-0000-00000000e001'
              : null,
        ),
        adminRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CollectAdminApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Operator menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pump();
    expect(repository.started.isCompleted, isTrue);

    // The actual SDK broadcasts signed-out before its Future returns. Rebuild
    // the real router while the callback is suspended, disposing its WidgetRef.
    container.read(_signedIn.notifier).state = false;
    await tester.pumpAndSettle();
    expect(find.text('Collect admin login'), findsOneWidget);
    repository.completion.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Collect admin login'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
