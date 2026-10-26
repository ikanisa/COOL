import 'package:collect_app/admin/core/admin_pending_attempt_store.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/admin/core/cloudflare_admin_operating_pages.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// The existing pumpOperating fixture pattern, with the shipping cookie app's
// explicit no-bearer boundary and isolated in-memory pending request storage.
// The real CloudflareAdminSession/repository continue parsing every MockClient
// response; this helper replaces no DTO, permissions, authority or route logic.
Future<void> pumpShippingTables(
  WidgetTester tester,
  CloudflareAdminRepository repo,
  Widget child, {
  MemoryAdminPendingAttemptStorage? storage,
}) async {
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      collectBackendClientProvider.overrideWithValue(null),
      adminRepositoryProvider.overrideWithValue(repo),
      cloudflareAdminSessionProvider.overrideWith((ref) => repo.session),
      adminPendingAttemptStorageProvider.overrideWithValue(
        storage ?? MemoryAdminPendingAttemptStorage(),
      ),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: child is CloudflareOperatingDetailPage
              ? child
              : SingleChildScrollView(child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> cleanShippingTables(
  WidgetTester tester,
  CloudflareAdminRepository repo,
) async {
  repo.session.clear();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}
