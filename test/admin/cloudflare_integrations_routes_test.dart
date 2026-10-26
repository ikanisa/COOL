import 'package:collect_app/admin/cloudflare_admin_app.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cloudflare_core_pages_test.dart' show pumpCore;
import 'cloudflare_operating_repository_test.dart' show operatingResponse;

void main() {
  testWidgets('gateway, email and receipt routes preserve real empty results', (
    tester,
  ) async {
    final calls = <String>[];
    final container = await pumpCore(
      tester,
      (request) async {
        calls.add(request.url.path);
        return operatingResponse({
          'rows': [],
          'total': 0,
          if (request.url.path == '/api/admin/email/events') ...{
            'limit': 25,
            'offset': 0,
          },
        });
      },
      permissions: [
        'overview.read',
        'gateway.read',
        'email.read',
        'payments.read',
      ],
    );
    final router = container.read(cloudflareAdminRouterProvider);
    for (final entry in {
      '/admin/gateway': 'No enrolled devices',
      '/admin/email': 'No email events',
      '/admin/member-receipts': 'No matching receipts',
    }.entries) {
      router.go(entry.key);
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    router.go('/admin/gateway/new');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/admin/gateway');
    expect(find.text('Reason for device change'), findsNothing);
    expect(calls.toSet(), {
      '/api/admin/gateway/devices',
      '/api/admin/gateway/receipts',
      '/api/admin/email/events',
    });
    container.read(cloudflareAdminSessionProvider.notifier).clear();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('missing integration read permissions block route transport', (
    tester,
  ) async {
    var calls = 0;
    final container = await pumpCore(tester, (_) async {
      calls++;
      return operatingResponse({'rows': [], 'total': 0});
    }, permissions: ['overview.read']);
    final router = container.read(cloudflareAdminRouterProvider);
    for (final path in [
      '/admin/gateway',
      '/admin/member-receipts',
      '/admin/email',
    ]) {
      router.go(path);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/admin');
    }
    expect(calls, 0);
    container.read(cloudflareAdminSessionProvider.notifier).clear();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
