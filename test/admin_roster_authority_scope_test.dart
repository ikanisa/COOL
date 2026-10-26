import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/admin/core/admin_roster_dialog.dart';
import 'package:collect_app/admin/core/admin_roster_import.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import 'admin_action_session_test.dart' as auth;
import 'support/admin_roster_fixture.dart';

class _Repository extends AdminRepository {
  _Repository(super.client, this.gateway);
  final FakeRosterGateway gateway;
  int opened = 0;
  @override
  AdminRosterGateway openRosterImport() {
    opened++;
    return gateway;
  }
}

const _identity = AdminIdentity(
  userId: auth.actor,
  displayName: 'Synthetic roster operator',
  roles: ['admin'],
  permissions: ['collections.moderate', 'users.read'],
);

void main() {
  late CollectCloudflareClient client;
  late ProviderContainer container;
  late FakeRosterGateway gateway;
  late _Repository repository;
  late StateProvider<AdminRepositoryBase> repositoryState;
  final identityState = StateProvider<AdminIdentity?>((_) => _identity);
  final delayedIdentity = StateProvider<Future<AdminIdentity?>?>((_) => null);
  var done = 0;
  var disposed = false;

  setUp(() async {
    done = 0;
    disposed = false;
    gateway = FakeRosterGateway();
    client = CollectCloudflareClient(
      'https://synthetic.invalid',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/verify')) {
          final values = (jsonDecode(request.body)['token'] as String).split(
            '|',
          );
          return auth.response(auth.authReceipt(values[0], values[1]));
        }
        return auth.response({});
      }),
    );
    await auth.session(client, rosterSessionA);
    repository = _Repository(client, gateway);
    repositoryState = StateProvider((_) => repository);
    container = ProviderContainer(
      overrides: [
        collectBackendClientProvider.overrideWithValue(client),
        adminRepositoryProvider.overrideWith(
          (ref) => ref.watch(repositoryState),
        ),
        adminIdentityProvider.overrideWith((ref) {
          final identity = ref.watch(identityState);
          return ref.watch(delayedIdentity) ?? Future.value(identity);
        }),
      ],
    );
  });
  tearDown(() async {
    if (!disposed) container.dispose();
    await client.dispose();
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> page(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: CollectTheme.light(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                ref.watch(adminIdentityProvider);
                return TextButton(
                  onPressed: () => createAdminAssistedGroup(
                    context,
                    ref,
                    onDone: () => done++,
                  ),
                  child: const Text('Open assisted roster'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<AdminRosterDraft> opened(WidgetTester tester) async {
    await page(tester);
    await tester.tap(find.text('Open assisted roster'));
    await settle(tester);
    return tester
        .widget<AdminRosterImportDialog>(find.byType(AdminRosterImportDialog))
        .draft;
  }

  Future<AdminRosterDraft> privateEditor(WidgetTester tester) async {
    final draft = await opened(tester);
    await draft.prepare(
      () async => AdminRosterUpload.pasted('Synthetic private original'),
    );
    await settle(tester);
    await tester.enterText(
      find.byKey(const Key('roster-title')),
      'Private authority group',
    );
    await tester.enterText(
      find.byKey(const Key('roster-reason')),
      'Private authority reason',
    );
    expect(draft.rows, isNotEmpty);
    return draft;
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    disposed = true;
    await tester.pump();
  }

  for (final denied in [
    const AdminIdentity(
      userId: auth.actor,
      displayName: 'Denied operator',
      roles: ['admin'],
      permissions: ['users.read'],
    ),
    const AdminIdentity(
      userId: auth.actor,
      displayName: 'Denied operator',
      roles: ['admin'],
      permissions: ['collections.moderate'],
    ),
  ]) {
    testWidgets(
      'direct production helper denies missing ${denied.permissions.single} counterpart',
      (tester) async {
        container.read(identityState.notifier).state = denied;
        await page(tester);
        await tester.tap(find.text('Open assisted roster'));
        await settle(tester);
        expect(repository.opened, 0);
        expect(find.byType(AdminRosterImportDialog), findsNothing);
        expect(done, 0);
        await finish(tester);
      },
    );
  }

  testWidgets(
    'valid production roster ACK survives gateway disposal and reaches host once',
    (tester) async {
      final draft = await privateEditor(tester);
      await draft.saveReview('Compared all synthetic source rows');
      await settle(tester);
      draft.affirm(true);
      await tester.pump();
      await tester.tap(find.text('Create group and add members'));
      await settle(tester);
      expect(gateway.commits, hasLength(1));
      expect(gateway.disposed, isTrue);
      expect(done, 1);
      expect(find.byType(AdminRosterImportDialog), findsNothing);
      expect(
        find.textContaining('Assisted group created with 2 members'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  for (final change in ['permission', 'role', 'repository', 'session']) {
    testWidgets(
      'production roster clears private editor after same-owner $change loss',
      (tester) async {
        final draft = await privateEditor(tester);
        if (change == 'permission') {
          container.read(identityState.notifier).state = const AdminIdentity(
            userId: auth.actor,
            displayName: 'Synthetic roster operator',
            roles: ['admin'],
            permissions: ['users.read'],
          );
        } else if (change == 'role') {
          container.read(identityState.notifier).state = const AdminIdentity(
            userId: auth.actor,
            displayName: 'Synthetic roster operator',
            roles: ['observer'],
            permissions: ['collections.moderate', 'users.read'],
          );
        } else if (change == 'repository') {
          container.read(repositoryState.notifier).state = _Repository(
            client,
            FakeRosterGateway(),
          );
        } else {
          await tester.runAsync(() => auth.session(client, rosterSessionB));
        }
        await settle(tester);
        expect(find.byType(AdminRosterImportDialog), findsNothing);
        expect(find.text('Private authority group'), findsNothing);
        expect(draft.rows, isEmpty);
        expect(gateway.disposed, isTrue);
        expect(gateway.commits, isEmpty);
        expect(done, 0);
        expect(tester.takeException(), isNull);
        await finish(tester);
      },
    );
  }

  testWidgets(
    'retained AsyncData during refresh cannot keep a private roster dialog authorized',
    (tester) async {
      final draft = await privateEditor(tester);
      final pending = Completer<AdminIdentity?>();
      container.read(delayedIdentity.notifier).state = pending.future;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      final loading = container.read(adminIdentityProvider);
      expect(loading.isLoading, isTrue);
      expect(
        loading.valueOrNull,
        isNotNull,
        reason: 'Exercise the retained-data loading condition',
      );
      await tester.pumpAndSettle();
      expect(find.byType(AdminRosterImportDialog), findsNothing);
      expect(draft.rows, isEmpty);
      expect(gateway.disposed, isTrue);
      pending.complete(_identity);
      await settle(tester);
      expect(find.byType(AdminRosterImportDialog), findsNothing);
      expect(done, 0);
      await finish(tester);
    },
  );

  testWidgets(
    'permission A-B-A between frames cannot resurrect an owned roster draft',
    (tester) async {
      final draft = await privateEditor(tester);
      container.read(identityState.notifier).state = const AdminIdentity(
        userId: auth.actor,
        displayName: 'Synthetic roster operator',
        roles: ['admin'],
        permissions: ['users.read'],
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      container.read(identityState.notifier).state = _identity;
      await settle(tester);
      expect(find.byType(AdminRosterImportDialog), findsNothing);
      expect(draft.rows, isEmpty);
      expect(gateway.disposed, isTrue);
      expect(done, 0);
      await finish(tester);
    },
  );

  testWidgets(
    'late roster preview after loading revocation cannot repopulate private state',
    (tester) async {
      final draft = await opened(tester);
      final response = Completer<Object?>();
      gateway.onPrepare = (_) => response.future;
      final pendingPrepare = draft.prepare(
        () async => AdminRosterUpload.pasted('Late private synthetic original'),
      );
      await tester.pump();
      final identity = Completer<AdminIdentity?>();
      container.read(delayedIdentity.notifier).state = identity.future;
      await settle(tester);
      expect(gateway.disposed, isTrue);
      response.complete(previewFixture(gateway.body!));
      await pendingPrepare;
      identity.complete(_identity);
      await settle(tester);
      expect(draft.rows, isEmpty);
      expect(draft.preview, isNull);
      expect(find.byType(AdminRosterImportDialog), findsNothing);
      expect(done, 0);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );
}
