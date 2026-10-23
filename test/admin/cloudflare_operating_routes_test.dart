import 'package:collect_app/admin/cloudflare_admin_app.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cloudflare_core_fixtures.dart';
import 'cloudflare_core_pages_test.dart' show pumpCore;
import 'cloudflare_operating_repository_test.dart' show operatingResponse;

void main() {
  testWidgets('create, edit and request history are registered real routes', (
    tester,
  ) async {
    final calls = <String>[];
    final container = await pumpCore(
      tester,
      (request) async {
        calls.add(request.url.path);
        if (request.url.path == '/api/admin/operations/requests') {
          return operatingResponse({'rows': [], 'total': 0});
        }
        if (request.url.path == '/api/admin/operations/groups/$coreId') {
          return operatingResponse({
            'resource_type': 'groups',
            'resource': {
              'id': coreId,
              'version': 2,
              'title': 'Example group',
              'slug': 'example-group',
              'collection_type': 'ikimina',
              'status': 'draft',
              'visibility': 'private',
              'is_platform_sponsored': 0,
              'description': '',
            },
            'current_actor_id': coreId,
            'can_manage': true,
            'related': {'memberships': [], 'payees': [], 'accounts': []},
            'related_truncated': false,
          });
        }
        return operatingResponse({'rows': [], 'total': 0});
      },
      permissions: [
        'overview.read',
        'collections.create',
        ...CloudflareCoreArea.values.map((area) => area.permission),
        ...CloudflareOperation.values.map((action) => action.permission),
      ],
    );
    final router = container.read(cloudflareAdminRouterProvider);
    router.go('/admin/groups/new');
    await tester.pumpAndSettle();
    expect(find.text('Group name'), findsOneWidget);
    expect(find.text('Draft'), findsOneWidget);
    expect(find.text('Active'), findsNothing);
    router.go('/admin/groups/$coreId/edit');
    await tester.pumpAndSettle();
    expect(find.text('Edit group'), findsOneWidget);
    expect(find.text('Example group'), findsOneWidget);
    expect(tester.takeException(), isNull);
    router.go('/admin/requests');
    await tester.pumpAndSettle();
    expect(find.text('Your recent requests'), findsOneWidget);
    expect(
      find.text('No requests are recorded for your account on this page.'),
      findsOneWidget,
    );
    expect(calls, contains('/api/admin/operations/groups/$coreId'));
    expect(calls, contains('/api/admin/operations/requests'));
    container.read(cloudflareAdminSessionProvider.notifier).clear();
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'read-only deep create and edit links cannot load mutation forms',
    (tester) async {
      var detailCalls = 0;
      final container = await pumpCore(tester, (request) async {
        if (request.url.path.contains('/operations/')) detailCalls++;
        return operatingResponse({'rows': [], 'total': 0});
      });
      final router = container.read(cloudflareAdminRouterProvider);
      for (final path in [
        '/admin/groups/new',
        '/admin/groups/$coreId/edit',
        '/admin/ledger-accounts/$coreId/edit',
      ]) {
        router.go(path);
        await tester.pumpAndSettle();
        expect(find.text('Review change'), findsNothing);
      }
      expect(detailCalls, 0);
      container.read(cloudflareAdminSessionProvider.notifier).clear();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
