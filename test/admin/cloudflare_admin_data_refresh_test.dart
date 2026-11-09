import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_data_refresh.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/legacy_backend_fixture.dart';

class _Session extends CloudflareAdminSession {
  _Session()
    : super(
        MockClient((_) async => http.Response('', 500)),
        environment: legacyBackendFixtureEnvironment,
      );

  void setUser(CloudflareAdminUser user) => state = AsyncData(user);
}

CloudflareAdminUser _user(DateTime expiresAt) => CloudflareAdminUser(
  id: 'operator',
  email: 'operator@example.test',
  role: AdminAccountRole.admin,
  sessionId: 'same-session',
  expiresAt: expiresAt,
  permissions: const ['collections.manage'],
);

void main() {
  testWidgets('expired or replaced authority cannot emit a saved revision', (
    tester,
  ) async {
    final session = _Session();
    session.setUser(_user(DateTime.now().add(const Duration(hours: 1))));
    final container = ProviderContainer(
      overrides: [cloudflareAdminSessionProvider.overrideWith((_) => session)],
    );
    late WidgetRef ref;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, widgetRef, child) {
            ref = widgetRef;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    final fence = session.authorityFence;
    refreshCloudflareAdminData(ref, fence);
    expect(container.read(cloudflareAdminDataRevisionProvider), 1);

    // Expiry is excluded from authorityKey; a same-key expired user must not
    // emit even before a session-expiry timer has cleared the provider.
    session.setUser(_user(DateTime.now().subtract(const Duration(seconds: 1))));
    await tester.pump();
    refreshCloudflareAdminData(ref, fence);
    expect(container.read(cloudflareAdminDataRevisionProvider), 1);

    // Switching away and back to the exact same public user advances the
    // session generation, so an earlier asynchronous receipt is rejected.
    session.clear();
    await tester.pump();
    session.setUser(_user(DateTime.now().add(const Duration(hours: 1))));
    await tester.pump();
    final prior = container.read(cloudflareAdminDataRevisionProvider);
    refreshCloudflareAdminData(ref, fence);
    expect(container.read(cloudflareAdminDataRevisionProvider), prior);
    refreshCloudflareAdminData(ref, session.authorityFence);
    expect(container.read(cloudflareAdminDataRevisionProvider), prior + 1);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
}
