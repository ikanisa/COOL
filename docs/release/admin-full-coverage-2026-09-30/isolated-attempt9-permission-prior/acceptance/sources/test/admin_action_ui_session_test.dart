import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_action_session_test.dart' as fixture;
import 'support/admin_read_fixture.dart';

void main() {
  late SupabaseClient client;
  late ProviderContainer container;
  late Future<http.Response> Function() retry;
  late int retryCalls;
  final identityState = StateProvider<AdminIdentity?>(
    (_) => const AdminIdentity(
      userId: fixture.actor,
      displayName: 'Synthetic operator',
      roles: ['admin'],
      permissions: ['notifications.read', 'notifications.manage'],
    ),
  );
  var disposed = false;
  setUp(() async {
    retryCalls = 0;
    disposed = false;
    retry = () async =>
        fixture.response({'ok': true, 'status': 'queued', 'delivery_count': 1});
    client = SupabaseClient(
      'https://synthetic.invalid',
      'synthetic-publishable',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        http.Response result;
        if (request.url.path.endsWith('/verify')) {
          final values = (jsonDecode(request.body)['token'] as String).split(
            '|',
          );
          result = fixture.response(fixture.authReceipt(values[0], values[1]));
        } else if (request.url.path.endsWith('/admin_retry_notification')) {
          retryCalls++;
          result = await retry();
        } else {
          result = fixture.response({
            ...adminDetailFixture('admin_get_notification', fixture.target),
            'id': fixture.target,
            'title': 'Synthetic notification',
            'status': 'failed',
            'type': 'group_update',
            'retryable_count': 1,
            'delivery_statuses': 'failed: 1',
          });
        }
        return http.Response.bytes(
          result.bodyBytes,
          result.statusCode,
          headers: result.headers,
          request: request,
        );
      }),
    );
    await fixture.session(client, 'session-a');
    container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(client),
        adminIdentityProvider.overrideWith(
          (ref) async => ref.watch(identityState),
        ),
      ],
    );
  });
  tearDown(() async {
    if (!disposed) container.dispose();
    await client.dispose();
  });

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    disposed = true;
  }

  Future<void> network(WidgetTester tester) async {
    // PostgREST decodes via its actual background JSON worker; allow that
    // worker to finish outside the widget test's fake clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> page(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: AdminDetailPage(
              title: 'Notification',
              rpcName: 'admin_get_notification',
              id: fixture.target,
            ),
          ),
        ),
      ),
    );
    await network(tester);
    expect(
      find.byTooltip('Retry failed delivery'),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .join(' | '),
    );
    await tester.tap(find.byTooltip('Retry failed delivery'));
    await network(tester);
    await tester.enterText(
      find.byType(TextField),
      'Checked recipient and failed delivery',
    );
    await network(tester);
  }

  testWidgets('same-user login during reason dialog dispatches no retry', (
    tester,
  ) async {
    await page(tester);
    await tester.runAsync(() => fixture.session(client, 'session-b'));
    await network(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(retryCalls, 0);
    expect(find.text('Failed delivery returned to queue'), findsNothing);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  testWidgets(
    'permission revocation in the same session clears an open reason dialog',
    (tester) async {
      await page(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      container.read(identityState.notifier).state = const AdminIdentity(
        userId: fixture.actor,
        displayName: 'Synthetic operator',
        roles: ['admin'],
        permissions: ['notifications.read'],
      );
      await network(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(retryCalls, 0);
      expect(find.text('Failed delivery returned to queue'), findsNothing);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );
  testWidgets('late retry success from an old session is suppressed', (
    tester,
  ) async {
    final release = Completer<http.Response>();
    retry = () => release.future;
    await page(tester);
    await tester.tap(find.text('Retry delivery'));
    await network(tester);
    expect(retryCalls, 1);
    await tester.runAsync(() => fixture.session(client, 'session-b'));
    await network(tester);
    release.complete(
      fixture.response({'ok': true, 'status': 'queued', 'delivery_count': 1}),
    );
    await network(tester);
    expect(find.text('Failed delivery returned to queue'), findsNothing);
    expect(container.read(adminRealtimeTickProvider), 0);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  testWidgets('wrong retry ACK never produces success feedback', (
    tester,
  ) async {
    retry = () async =>
        fixture.response({'ok': true, 'status': 'sent', 'delivery_count': 1});
    await page(tester);
    await tester.tap(find.text('Retry delivery'));
    await network(tester);
    expect(retryCalls, 1);
    expect(find.text('Failed delivery returned to queue'), findsNothing);
    expect(find.textContaining('not acknowledged'), findsOneWidget);
    expect(container.read(adminRealtimeTickProvider), 0);
    await finish(tester);
  });
  testWidgets(
    'valid retry receipt refreshes once and acknowledges queue only',
    (tester) async {
      await page(tester);
      await tester.tap(find.text('Retry delivery'));
      await network(tester);
      expect(retryCalls, 1);
      expect(find.text('Failed delivery returned to queue'), findsOneWidget);
      expect(container.read(adminRealtimeTickProvider), 1);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );
}
