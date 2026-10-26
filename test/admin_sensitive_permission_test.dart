import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'admin_action_session_test.dart' as sdk;
import 'support/admin_read_fixture.dart';

const _privateReply = 'SYNTHETIC_PRIVATE_REPLY_FOR_ACTOR_A';
const _authorized = AdminIdentity(
  userId: sdk.actor,
  displayName: 'Synthetic operator',
  roles: ['admin'],
  permissions: ['payments.read', 'sms.raw.reveal', 'admin_users.read'],
);

void main() {
  late CollectCloudflareClient client;
  late ProviderContainer container;
  late Future<http.Response> Function() reveal;
  late Future<http.Response> Function() approval;
  late List<http.Request> writes;
  Future<AdminIdentity?>? identityReply;
  final identity = StateProvider<AdminIdentity?>((_) => _authorized);
  var disposed = false;
  setUp(() async {
    disposed = false;
    identityReply = null;
    writes = [];
    reveal = () async => sdk.response({'ok': true, 'message': _privateReply});
    approval = () async => sdk.response({
      'contract_version': 1,
      'user_id': sdk.target,
      'provider': 'whatsapp',
      'mode': 'transition',
      'identity_masked': '+***5302',
      'approved_at': null,
      'expires_at': null,
      'status': 'not_approved',
      'approved': false,
      'role_granted': false,
      'admin_access': false,
      'access_status': 'revoked',
    });
    client = CollectCloudflareClient(
      'https://synthetic.invalid',
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
        } else if (request.url.path.endsWith(
          '/admin_get_operator_approval_v1',
        )) {
          response = await approval();
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
        collectBackendClientProvider.overrideWithValue(client),
        adminIdentityProvider.overrideWith((ref) {
          final current = ref.watch(identity);
          return identityReply ?? Future.value(current);
        }),
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
    // Allow asynchronous Cloudflare client replies to complete outside widget fake time.
    for (var attempt = 0; attempt < 40; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
    }
    expect(find.byType(LinearProgressIndicator), findsNothing);
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
      permissions: ['payments.read'],
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

  testWidgets('raw SMS identity refresh hides evidence and reveal controls', (
    tester,
  ) async {
    await page(tester);
    await tester.ensureVisible(find.text('Reveal protected evidence'));
    await tester.tap(find.text('Reveal protected evidence'));
    await network(tester);
    expect(find.text(_privateReply), findsOneWidget);
    final pending = Completer<AdminIdentity?>();
    identityReply = pending.future;
    container.invalidate(adminIdentityProvider);
    expect(container.read(adminIdentityProvider).isLoading, isTrue);
    await tester.pump();
    await tester.pump();
    expect(find.text(_privateReply), findsNothing);
    expect(find.text('Reveal protected evidence'), findsNothing);
    pending.complete(_authorized);
    await network(tester);
    expect(find.text(_privateReply), findsNothing);
    expect(find.text('Select an accountable purpose'), findsOneWidget);
    expect(writes, hasLength(1));
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('raw SMS role change clears evidence and resets its purpose', (
    tester,
  ) async {
    await page(tester);
    await tester.ensureVisible(find.text('Reveal protected evidence'));
    await tester.tap(find.text('Reveal protected evidence'));
    await network(tester);
    expect(find.text(_privateReply), findsOneWidget);
    container.read(identity.notifier).state = const AdminIdentity(
      userId: sdk.actor,
      displayName: 'Synthetic operator',
      roles: ['group_admin'],
      permissions: ['payments.read', 'sms.raw.reveal'],
    );
    // Allow asynchronous Cloudflare client replies to complete outside widget fake time.
    await tester.runAsync(
      () => container
          .read(
            adminDetailRecordProvider((
              rpc: 'admin_get_collect_transaction',
              id: 'momo:${sdk.target}',
            )).future,
          )
          .timeout(const Duration(seconds: 10)),
    );
    await network(tester);
    expect(find.text(_privateReply), findsNothing);
    // Provider completion and FutureBuilder's next rendered frame are separate.
    // The original linear-progress wait did not cover the detail loading panel.
    for (
      var attempt = 0;
      attempt < 100 &&
          find.text('Reveal protected evidence').evaluate().isEmpty;
      attempt++
    ) {
      expect(find.text(_privateReply), findsNothing);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
    expect(find.text('Reveal protected evidence'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Reveal protected evidence'),
    );
    expect(button.onPressed, isNull);
    expect(writes, hasLength(1));
    await finish(tester);
  });

  Future<void> approvalPage(WidgetTester tester) async {
    await container.read(adminIdentityProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: AdminPlatformAccessPanel(userId: sdk.target),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'approval capability A-B-A rejects the old lookup after restore',
    (tester) async {
      final began = Completer<void>(), release = Completer<http.Response>();
      final currentReply = approval;
      var reads = 0;
      approval = () {
        if (++reads == 1) {
          began.complete();
          return release.future;
        }
        return currentReply();
      };
      await approvalPage(tester);
      await tester.runAsync(() => began.future);
      container.read(identity.notifier).state = const AdminIdentity(
        userId: sdk.actor,
        displayName: 'Synthetic operator',
        roles: ['admin'],
        permissions: [],
      );
      await container.read(adminIdentityProvider.future);
      container.read(identity.notifier).state = _authorized;
      await container.read(adminIdentityProvider.future);
      await network(tester);
      release.complete(
        sdk.response({
          'contract_version': 1,
          'user_id': sdk.target,
          'provider': 'whatsapp',
          'mode': 'transition',
          'identity_masked': '+***9999',
          'approved_at': adminReadDate,
          'expires_at': null,
          'status': 'approved',
          'approved': true,
          'role_granted': true,
          'admin_access': true,
          'access_status': 'active',
        }),
      );
      await network(tester);
      expect(reads, 2);
      expect(find.text('WhatsApp: +***5302'), findsOneWidget);
      expect(find.text('WhatsApp: +***9999'), findsNothing);
      expect(find.byTooltip('Active'), findsNothing);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets('approval identity refresh hides returned status while pending', (
    tester,
  ) async {
    await approvalPage(tester);
    await network(tester);
    expect(find.text('WhatsApp: +***5302'), findsOneWidget);
    final pending = Completer<AdminIdentity?>();
    identityReply = pending.future;
    container.invalidate(adminIdentityProvider);
    expect(container.read(adminIdentityProvider).isLoading, isTrue);
    await tester.pump();
    await tester.pump();
    expect(find.text('WhatsApp: +***5302'), findsNothing);
    expect(find.text('Platform Admin'), findsNothing);
    pending.complete(_authorized);
    await network(tester);
    expect(find.text('WhatsApp: +***5302'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
}
