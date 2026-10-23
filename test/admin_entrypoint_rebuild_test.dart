import 'package:collect_app/admin/admin_app.dart';
import 'package:collect_app/admin/admin_router.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _signedIn = StateProvider<bool>((ref) => false);

void main() {
  testWidgets('dedicated Admin Auth rebuild keeps the operator entrypoint', (
    tester,
  ) async {
    // The production build must preserve this default on configured Admin
    // origins as well as the canonical domain. The real browser companion
    // runs OTP/session reconstruction at a random loopback origin.
    expect(publicLandingHome, isFalse);
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
        adminRepositoryProvider.overrideWithValue(
          const AdminEvidenceRepository(),
        ),
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
    expect(find.text('Collect admin login'), findsOneWidget);
    container.read(_signedIn.notifier).state = true;
    await tester.pumpAndSettle();
    expect(
      container
          .read(adminRouterProvider)
          .routeInformationProvider
          .value
          .uri
          .path,
      '/admin',
    );
    expect(find.text('Collect admin login'), findsNothing);
    expect(
      find.text('Rwanda MoMo contributions, clearly recorded.'),
      findsNothing,
    );
    container.read(_signedIn.notifier).state = false;
    await tester.pumpAndSettle();
    expect(find.text('Collect admin login'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
