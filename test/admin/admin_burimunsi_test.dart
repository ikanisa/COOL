// Local controller/widget fixtures only. No live Auth, owner approval, email,
// receiving-device operation or production acceptance is exercised.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/admin_account_pages.dart';
import 'package:collect_app/admin/core/admin_burimunsi_api.dart';
import 'package:collect_app/admin/core/admin_burimunsi_page.dart';
import 'package:collect_app/admin/core/admin_pending_attempt_store.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/admin/shared/admin_theme.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const group = 'buri-widget-qualification';
const owner = BuriSharedOperator(
  adminId: 'f4000000-0000-4000-8000-000000000001',
  principalId: 'f3000000-0000-4000-8000-000000000001',
  email: 'info@ikanisa.com',
  name: 'QA Owner',
  role: 'owner',
);
const staff = BuriSharedOperator(
  adminId: 'f4000000-0000-4000-8000-000000000002',
  principalId: 'f3000000-0000-4000-8000-000000000002',
  email: 'qa-staff@example.invalid',
  name: 'QA Staff',
  role: 'staff',
);
const captureKey = ValueKey('buri-admin-capture');
CloudflareAdminUser user() => CloudflareAdminUser(
  id: owner.adminId,
  email: owner.email,
  role: AdminAccountRole.owner,
  sessionId: 'f5000000-0000-4000-8000-000000000001',
  expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
  permissions: const ['admin_users.manage'],
  usesEmailVerification: true,
  emailVerifiedAt: DateTime.now().toUtc(),
  principalId: owner.principalId,
  financialModel: 'canonical_evidence_ledger',
);

class FakeBuriApi implements AdminAccountApi, AdminBuriMunsiApi {
  @override
  bool buriAvailable = true;
  @override
  bool buriAuthorized = true;
  @override
  Object buriAuthorityFence = Object();
  var directory = const BuriOperatorDirectory(
    collectionId: group,
    configured: true,
    team: [owner, staff],
    approvals: [],
  );
  final posts = <BuriApprovalIntent>[];
  final receipts = <String, Map<String, dynamic>>{};
  int loads = 0, lookups = 0;
  bool loseResponse = false;
  bool canManageTeam = true;
  Completer<void>? pendingPost;
  @override
  Future<AdminAccountTeam> loadTeam() async => AdminAccountTeam(
    members: const [],
    currentEmail: owner.email,
    canManage: canManageTeam,
  );
  @override
  Future<BuriOperatorDirectory> loadBuriDirectory({
    String? collectionId,
  }) async {
    loads++;
    return directory;
  }

  @override
  Future<Map<String, dynamic>> submitBuriApproval(
    BuriApprovalIntent intent,
    Object fence,
  ) async {
    posts.add(intent);
    await pendingPost?.future;
    final receipt = {
      'contractVersion': 1,
      'requestId': intent.requestId,
      'principalId': intent.operator.principalId,
      'version': intent.expectedVersion + 1,
      'active': intent.active,
      'applied': true,
    };
    receipts[intent.requestId] = receipt;
    if (loseResponse) {
      throw const AdminAccountException('Synthetic lost response.');
    }
    return receipt;
  }

  @override
  Future<Map<String, dynamic>?> lookupBuriApproval(
    BuriApprovalIntent intent,
    Object fence,
  ) async {
    lookups++;
    return receipts[intent.requestId];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BuriApprovalIntent intent({String phone = '0780000002'}) => BuriApprovalIntent(
  collectionId: group,
  operator: staff,
  phone: phone,
  role: 'staff',
  capabilities: ['records.read'],
  active: true,
  expectedVersion: 0,
);
AdminPendingAttemptStore store(MemoryAdminPendingAttemptStorage storage) =>
    AdminPendingAttemptStore(storage: storage)..bind(user());

Future<void> mount(
  WidgetTester tester,
  FakeBuriApi api,
  MemoryAdminPendingAttemptStorage storage, {
  bool narrow = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = narrow
      ? const Size(320, 568)
      : const Size(1280, 900);
  final pending = store(storage);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminAccountApiProvider.overrideWithValue(api),
        adminPendingAttemptStoreProvider.overrideWith((_) => pending),
      ],
      child: RepaintBoundary(
        key: captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AdminTheme.adapt(narrow ? AppTheme.dark() : AppTheme.light()),
          builder: narrow
              ? (_, child) => MediaQuery(
                  data: const MediaQueryData(
                    size: Size(320, 568),
                    textScaler: TextScaler.linear(2),
                  ),
                  child: child!,
                )
              : null,
          home: Scaffold(
            body: AdminBuriMunsiPage(onBack: () {}, onVerify: () {}),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['COLLECT_BURI_ADMIN_SCREENSHOTS'];
  if (directory == null || directory.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    expect(
      bytes!.lengthInBytes,
      greaterThan(5000),
      reason: 'The requested UI capture must contain a settled task screen.',
    );
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png').writeAsBytes(bytes.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets('existing Team links to native access only for a manager', (
    tester,
  ) async {
    final api = FakeBuriApi();
    var opened = 0;
    Future<void> team() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [adminAccountApiProvider.overrideWithValue(api)],
          child: MaterialApp(
            theme: AdminTheme.adapt(AppTheme.light()),
            home: Scaffold(
              body: AdminAccountTeamPage(onBuriMunsiAccess: () => opened++),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await team();
    await tester.tap(find.text('BuriMunsi access'));
    expect(opened, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    api.canManageTeam = false;
    await team();
    expect(find.text('BuriMunsi access'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  test(
    'phone normalization and approval capability ceiling preserve leading digits',
    () {
      expect(intent().phone, '+250780000002');
      expect(intent().body['principalId'], staff.principalId);
      expect(
        () => BuriApprovalIntent(
          collectionId: group,
          operator: staff,
          phone: '0780000002',
          role: 'admin',
          capabilities: ['records.read'],
          active: true,
          expectedVersion: 0,
        ),
        throwsFormatException,
      );
      expect(
        () => BuriApprovalIntent(
          collectionId: group,
          operator: staff,
          phone: '0780000002',
          role: 'staff',
          capabilities: ['records.read', 'staff.manage'],
          active: true,
          expectedVersion: 0,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'lost response retains exact intent; restoration never dispatches',
    () async {
      final storage = MemoryAdminPendingAttemptStorage(),
          api = FakeBuriApi()..loseResponse = true;
      final firstStore = store(storage);
      addTearDown(firstStore.dispose);
      final first = BuriApprovalCoordinator(
            api: api,
            store: firstStore,
            collectionId: group,
          ),
          original = intent();
      await expectLater(
        first.submit(original),
        throwsA(isA<AdminAccountException>()),
      );
      expect(api.posts.length, 1);
      expect(first.pending.single.requestId, original.requestId);
      await expectLater(
        first.submit(intent()),
        throwsA(isA<AdminAccountException>()),
      );
      expect(api.posts.length, 1);
      final secondStore = store(storage);
      addTearDown(secondStore.dispose);
      final restored = BuriApprovalCoordinator(
        api: api,
        store: secondStore,
        collectionId: group,
      );
      expect(api.posts.length, 1);
      expect(restored.pending.single.body, original.body);
      expect(await restored.check(restored.pending.single), isTrue);
      expect(api.posts.length, 1);
      expect(restored.pending, isEmpty);
    },
  );
  test(
    'absence permits only an explicit unchanged original submission',
    () async {
      final api = FakeBuriApi()..loseResponse = true,
          pending = store(MemoryAdminPendingAttemptStorage());
      addTearDown(pending.dispose);
      final coordinator = BuriApprovalCoordinator(
        api: api,
        store: pending,
        collectionId: group,
      );
      final original = intent();
      await expectLater(
        coordinator.submit(original),
        throwsA(isA<AdminAccountException>()),
      );
      api.receipts.clear();
      expect(await coordinator.check(original), isFalse);
      expect(api.posts.length, 1);
      api.loseResponse = false;
      await coordinator.submit(original);
      expect(api.posts.length, 2);
      expect(api.posts[0].requestId, api.posts[1].requestId);
      expect(coordinator.pending, isEmpty);
    },
  );
  test(
    'a late response cannot publish or clear pending work across an authority change',
    () async {
      final api = FakeBuriApi()..pendingPost = Completer<void>(),
          pending = store(MemoryAdminPendingAttemptStorage());
      addTearDown(pending.dispose);
      final coordinator = BuriApprovalCoordinator(
        api: api,
        store: pending,
        collectionId: group,
      );
      final submitted = coordinator.submit(intent());
      api.buriAuthorityFence = Object();
      api.pendingPost!.complete();
      await expectLater(submitted, throwsA(isA<AdminAccountException>()));
      expect(coordinator.pending, isEmpty);
      expect(
        pending.restoreFamily(
          family: BuriApprovalCoordinator.family,
          permission: BuriApprovalCoordinator.permission,
          schema: BuriApprovalCoordinator.schema,
        ),
        hasLength(1),
      );
    },
  );
  test(
    'receipt for another principal cannot clear the original approval',
    () async {
      final api = FakeBuriApi()..loseResponse = true,
          pending = store(MemoryAdminPendingAttemptStorage());
      addTearDown(pending.dispose);
      final coordinator = BuriApprovalCoordinator(
        api: api,
        store: pending,
        collectionId: group,
      );
      final original = intent();
      await expectLater(
        coordinator.submit(original),
        throwsA(isA<AdminAccountException>()),
      );
      api.receipts[original.requestId]!['principalId'] = owner.principalId;
      await expectLater(coordinator.check(original), throwsFormatException);
      expect(coordinator.pending, hasLength(1));
    },
  );
  testWidgets(
    'wide operator task uses existing Collect accounts and saves normalized access once',
    (tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final api = FakeBuriApi();
      await mount(tester, api, MemoryAdminPendingAttemptStorage());
      await tester.tap(find.text('QA Staff'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('buri-login-phone')),
        '0780 000 002',
      );
      await tester.pumpAndSettle();
      await capture(tester, 'buri-access-wide-light');
      await tester.ensureVisible(find.byKey(const Key('buri-save-access')));
      await tester.tap(find.byKey(const Key('buri-save-access')));
      await tester.pumpAndSettle();
      expect(api.posts, hasLength(1));
      expect(api.posts.single.operator.principalId, staff.principalId);
      expect(api.posts.single.phone, '+250780000002');
      expect(find.text('BuriMunsi access saved.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'unknown approval survives a page reload without automatic resubmission',
    (tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final api = FakeBuriApi()..loseResponse = true,
          storage = MemoryAdminPendingAttemptStorage();
      await mount(tester, api, storage);
      await tester.tap(find.text('QA Staff'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('buri-login-phone')),
        '0780000002',
      );
      await tester.ensureVisible(find.byKey(const Key('buri-save-access')));
      await tester.tap(find.byKey(const Key('buri-save-access')));
      await tester.pumpAndSettle();
      expect(api.posts, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      await mount(tester, api, storage);
      expect(find.text('Approval needs confirmation'), findsOneWidget);
      expect(api.posts, hasLength(1));
      await tester.ensureVisible(find.text('Check original request'));
      await tester.tap(find.text('Check original request'));
      await tester.pumpAndSettle();
      expect(api.lookups, 1);
      expect(api.posts, hasLength(1));
      expect(find.text('The original approval is confirmed.'), findsOneWidget);
    },
  );
  testWidgets('compact enlarged-text task reflows without overflow', (
    tester,
  ) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await mount(
      tester,
      FakeBuriApi(),
      MemoryAdminPendingAttemptStorage(),
      narrow: true,
    );
    await capture(tester, 'buri-access-narrow-dark-text-2x');
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('buri-login-phone')));
    await tester.pumpAndSettle();
    await capture(tester, 'buri-access-narrow-dark-form-2x');
    await tester.ensureVisible(find.byKey(const Key('buri-save-access')));
    expect(tester.takeException(), isNull);
  });
}
