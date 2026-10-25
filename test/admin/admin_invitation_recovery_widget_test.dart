import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/admin_account_pages.dart';
import 'package:collect_app/admin/core/admin_pending_attempt_store.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _staff = '10000000-0000-4000-8000-000000000002';
const _server = '10000000-0000-4000-8000-000000000003';
AdminInvitationReceipt _receipt({bool unknown = false}) =>
    AdminInvitationReceipt(
      staffId: _staff,
      requestId: _server,
      emailStatus: unknown
          ? AdminInvitationEmailStatus.unknown
          : AdminInvitationEmailStatus.accepted,
      accessStatus: AdminAccountStatus.invited,
      operation: AdminInvitationOperation.invite,
      replayed: false,
      duplicate: false,
    );

class _TeamApi implements AdminAccountApi, AdminInvitationAccountApi {
  int posts = 0, gets = 0, legacyCalls = 0;
  bool unknownLookup = false;
  final sent = <AdminInvitationIntent>[];
  @override
  bool get invitationRecoveryAvailable => true;
  @override
  bool get invitationManagementAuthorized => true;
  @override
  Object get invitationAuthorityFence =>
      (epoch: 1, principal: 'synthetic-owner');
  @override
  Future<AdminAccountTeam> loadTeam() async => const AdminAccountTeam(
    members: [],
    currentEmail: 'info@ikanisa.com',
    canManage: true,
  );
  @override
  Future<AdminInvitationReceipt> submitInvitation(
    AdminInvitationIntent intent, {
    required Object authorityFence,
  }) async {
    expect(authorityFence, invitationAuthorityFence);
    posts++;
    sent.add(intent);
    if (posts == 1) {
      throw AdminInvitationFailure(AdminInvitationOutcome.operationUnknown);
    }
    return _receipt();
  }

  @override
  Future<AdminInvitationLookup> lookupInvitation(
    AdminInvitationIntent intent, {
    required Object authorityFence,
  }) async {
    expect(authorityFence, invitationAuthorityFence);
    gets++;
    expect(intent.requestKey, sent.first.requestKey);
    return unknownLookup
        ? AdminInvitationLookup.found(_receipt(unknown: true))
        : const AdminInvitationLookup.notFound();
  }

  @override
  Future<void> invite(
    String email,
    AdminAccountRole role, {
    String displayName = '',
  }) async {
    legacyCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CloudflareAdminUser _owner() => CloudflareAdminUser(
  id: '10000000-0000-4000-8000-000000000001',
  email: 'info@ikanisa.com',
  role: AdminAccountRole.owner,
  sessionId: 'synthetic-owner-session',
  expiresAt: DateTime.now().add(const Duration(minutes: 20)),
  permissions: const ['admin_users.manage', 'admin_users.read'],
  assuranceLevel: 2,
  mfaAt: DateTime.now().subtract(const Duration(seconds: 1)),
);

Future<void> _mount(
  WidgetTester tester,
  _TeamApi api,
  MemoryAdminPendingAttemptStorage storage, {
  bool compact = false,
}) async {
  final store = AdminPendingAttemptStore(storage: storage)..bind(_owner());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminAccountApiProvider.overrideWithValue(api),
        adminPendingAttemptStoreProvider.overrideWith((ref) => store),
      ],
      child: MaterialApp(
        theme: CollectTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(compact ? 1.3 : 1)),
          child: child!,
        ),
        home: const Scaffold(body: AdminAccountTeamPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _send(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Invite teammate'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('admin-account-email')),
    'teammate@example.test',
  );
  await tester.enterText(
    find.byKey(const Key('admin-account-name')),
    'Synthetic Teammate',
  );
  final send = find.widgetWithText(FilledButton, 'Send invitation');
  await tester.ensureVisible(send);
  await tester.tap(send);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'unknown dialog locks immutable fields; exact GET needs explicit retry confirmation',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _TeamApi(), storage = MemoryAdminPendingAttemptStorage();
      await _mount(tester, api, storage);
      await _send(tester);
      expect(api.posts, 1);
      expect(api.legacyCalls, 0);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('admin-account-email')))
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('admin-account-name')))
            .enabled,
        isFalse,
      );
      expect(find.textContaining('result is unknown'), findsWidgets);
      expect(
        find.widgetWithText(FilledButton, 'Send invitation'),
        findsNothing,
      );
      final check = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Check original request'),
      );
      await tester.ensureVisible(check);
      await tester.tap(check);
      await tester.pumpAndSettle();
      expect(api.gets, 1);
      expect(api.posts, 1);
      final retry = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Retry same request'),
      );
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(find.text('Retry the original invitation?'), findsOneWidget);
      expect(api.posts, 1);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Retry same request').last,
      );
      await tester.pumpAndSettle();
      expect(api.posts, 2);
      expect(api.sent[0].requestKey, api.sent[1].requestKey);
      expect(api.sent[0].body, api.sent[1].body);
      expect(
        find.textContaining('Original invitation accepted for sending'),
        findsWidgets,
      );
      expect(find.textContaining('delivered to'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'closing and same-session reload retain lookup-only recovery on compact enlarged layout',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _TeamApi()..unknownLookup = true;
      final storage = MemoryAdminPendingAttemptStorage();
      await _mount(tester, api, storage, compact: true);
      await _send(tester);
      await tester.ensureVisible(find.widgetWithText(TextButton, 'Close'));
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();
      expect(api.posts, 1);
      expect(
        storage.values.values.single,
        contains(api.sent.single.requestKey),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await _mount(tester, api, storage, compact: true);
      expect(api.posts, 1);
      expect(api.gets, 0);
      final invite = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Invite teammate'),
      );
      expect(invite.onPressed, isNull);
      final check = find.widgetWithText(TextButton, 'Check original request');
      await tester.ensureVisible(check);
      await tester.pumpAndSettle();
      expect(check.hitTestable(), findsOneWidget);
      await tester.tap(check);
      await tester.pumpAndSettle();
      expect(api.gets, 1);
      expect(api.posts, 1);
      expect(
        find.widgetWithText(FilledButton, 'Retry same request'),
        findsNothing,
      );
      expect(
        find.textContaining('Invitation sending is unconfirmed'),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
