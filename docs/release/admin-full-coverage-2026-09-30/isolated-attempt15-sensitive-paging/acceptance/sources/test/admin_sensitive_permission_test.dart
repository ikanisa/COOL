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

import 'admin_action_session_test.dart' as sdk;
import 'support/admin_read_fixture.dart';

const _privateReply = 'SYNTHETIC_PRIVATE_REPLY_FOR_ACTOR_A';
const _authorized = AdminIdentity(
  userId: sdk.actor,
  displayName: 'Synthetic operator',
  roles: ['admin'],
  permissions: ['transactions.read', 'sms.raw.reveal'],
);

void main() {
  late SupabaseClient client;
  late ProviderContainer container;
  late Future<http.Response> Function() reveal;
  late List<http.Request> writes;
  final identity = StateProvider<AdminIdentity?>((_) => _authorized);
  var disposed = false;
  setUp(() async {
    disposed = false;
    writes = [];
    reveal = () async => sdk.response({'ok': true, 'message': _privateReply});
    client = SupabaseClient(
      'https://synthetic.invalid',
      'synthetic-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        http.Response response;
        if (request.url.path.endsWith('/verify')) {
          final values = (jsonDecode(request.body)['token'] as String).split(
            '|',
          );
          response = sdk.response(sdk.authReceipt(values[0], values[1]));
        } else if (request.url.path.endsWith(
          '/admin_get_collect_transaction',
        )) {
          response = sdk.response({
            ...adminDetailFixture('admin_get_collect_transaction', sdk.target),
            'raw_sms_id': sdk.target,
          });
        } else if (request.url.path.endsWith('/admin_reveal_raw_sms')) {
          writes.add(request);
          response = await reveal();
        } else {
          throw StateError('Unexpected synthetic request');
        }
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
    );
    await sdk.session(client, 'sensitive-session-a');
    container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(client),
        adminIdentityProvider.overrideWith((ref) async => ref.watch(identity)),
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
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> page(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: AdminCollectTransactionDetailPage(id: 'momo:${sdk.target}'),
          ),
        ),
      ),
    );
    await network(tester);
    expect(find.text('Select an accountable purpose'), findsOneWidget);
    await tester.ensureVisible(find.text('Internal audit evidence'));
    await tester.tap(find.text('Internal audit evidence'));
    await network(tester);
  }

  testWidgets('raw SMS reveal binds exact purpose and current actor bearer', (
    tester,
  ) async {
    final token = client.auth.currentSession!.accessToken;
    await page(tester);
    await tester.ensureVisible(find.text('Reveal protected evidence'));
    await tester.tap(find.text('Reveal protected evidence'));
    await network(tester);
    expect(writes, hasLength(1));
    expect(writes.single.headers['Authorization'], 'Bearer $token');
    expect(jsonDecode(writes.single.body), {
      'p_sms_id': sdk.target,
      'p_reason': 'Internal audit evidence',
    });
    expect(find.text(_privateReply), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('raw SMS permission A-B-A cannot reveal an old private reply', (
    tester,
  ) async {
    final began = Completer<void>(), release = Completer<http.Response>();
    reveal = () {
      began.complete();
      return release.future;
    };
    await page(tester);
    await tester.ensureVisible(find.text('Reveal protected evidence'));
    await tester.tap(find.text('Reveal protected evidence'));
    await tester.runAsync(() => began.future);
    // Observe both provider transitions without rebuilding the widget. A
    // returned capability must not restore authority to the prior request.
    container.read(identity.notifier).state = const AdminIdentity(
      userId: sdk.actor,
      displayName: 'Synthetic operator',
      roles: ['admin'],
      permissions: ['transactions.read'],
    );
    await container.read(adminIdentityProvider.future);
    container.read(identity.notifier).state = _authorized;
    await container.read(adminIdentityProvider.future);
    release.complete(sdk.response({'ok': true, 'message': _privateReply}));
    await network(tester);
    expect(writes, hasLength(1));
    expect(find.text(_privateReply), findsNothing);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
}
