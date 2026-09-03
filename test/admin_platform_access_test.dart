import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const target = '98400000-0000-4000-8000-000000000002';
const operatorId = '98400000-0000-4000-8000-000000000001';
const manager = AdminIdentity(
  userId: operatorId,
  displayName: '984001',
  roles: ['admin'],
  permissions: ['admin_users.read', 'admin_users.manage'],
);

class AccessRepository extends AdminEvidenceRepository {
  AdminIdentity? identity = manager;
  bool approved = false;
  bool granted = false;
  bool failRead = false;
  bool invalidReceipt = false;
  Completer<void>? mutationGate;
  final calls = <(String, Map<String, dynamic>)>[];
  @override
  Future<AdminIdentity?> currentIdentity() async => identity;
  @override
  Future<Map<String, dynamic>> detail(String rpcName, String id) async => {
    'id': id,
    'public_id': '984002',
    'phone_masked': '+***4002',
    'country_code': 'RW',
    'created_at': '2026-09-02T10:00:00Z',
  };
  @override
  Future<Map<String, dynamic>> action(
    String rpcName,
    Map<String, dynamic> params,
  ) async {
    calls.add((rpcName, Map.of(params)));
    if (rpcName == 'admin_get_whatsapp_approval') {
      if (failRead) throw StateError('Synthetic read failure');
      return {
        'user_id': params['p_user_id'],
        'approved': approved,
        'role_granted': granted,
        'status': approved ? 'approved' : 'not_approved',
        'phone_masked': '+***4002',
      };
    }
    if (mutationGate != null) await mutationGate!.future;
    if (invalidReceipt) return {'ok': true};
    if (rpcName == 'admin_approve_whatsapp') {
      approved = true;
      return {'ok': true, 'status': 'approved', 'user_id': params['p_user_id']};
    }
    if (rpcName == 'admin_revoke_whatsapp_approval') {
      approved = granted = false;
      return {'ok': true, 'status': 'revoked', 'user_id': params['p_user_id']};
    }
    if (rpcName == 'admin_set_user_access') {
      granted = params['p_active'] == true;
      return {'ok': true, 'status': granted ? 'active' : 'revoked'};
    }
    throw StateError('Unexpected RPC $rpcName');
  }

  List<(String, Map<String, dynamic>)> get mutations =>
      calls.where((call) => call.$1 != 'admin_get_whatsapp_approval').toList();
}

Future<void> mount(
  WidgetTester tester,
  AccessRepository repository, {
  String userId = target,
  double width = 390,
  double scale = 1,
  GlobalKey? boundary,
  bool detail = false,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [adminRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RepaintBoundary(
          key: boundary,
          child: Scaffold(
            appBar: AppBar(title: const Text('User 984002')),
            body: detail
                ? const AdminDetailPage(
                    title: 'User detail',
                    rpcName: 'admin_get_user',
                    id: target,
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: AdminPlatformAccessPanel(userId: userId),
                  ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> confirm(WidgetTester tester, String label, {String? phone}) async {
  await tester.tap(find.widgetWithText(FilledButton, label).first);
  await tester.pumpAndSettle();
  if (phone != null) {
    await tester.enterText(
      find.widgetWithText(TextField, 'Verified WhatsApp number'),
      phone,
    );
  }
  await tester.enterText(
    find.widgetWithText(TextField, 'Reason'),
    'Synthetic approved change',
  );
  await tester.pump();
  await tester.tap(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, label),
    ),
  );
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
  testWidgets('member cannot load or mutate platform approval', (tester) async {
    final repo = AccessRepository()
      ..identity = const AdminIdentity(
        userId: operatorId,
        displayName: '984001',
        roles: ['group_admin'],
        permissions: [],
      );
    await mount(tester, repo);
    expect(repo.calls, isEmpty);
    expect(find.text('Platform Admin'), findsNothing);
  });
  testWidgets('read-only operator has no mutation controls', (tester) async {
    final repo = AccessRepository()
      ..identity = const AdminIdentity(
        userId: operatorId,
        displayName: '984001',
        roles: [],
        permissions: ['admin_users.read'],
      );
    await mount(tester, repo);
    expect(find.byTooltip('WhatsApp approval required'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });
  testWidgets('approval then activation are separate confirmed actions', (
    tester,
  ) async {
    final repo = AccessRepository();
    await mount(tester, repo);
    expect(find.text('Activate Admin'), findsNothing);
    await confirm(tester, 'Approve WhatsApp', phone: '+250788984002');
    await tester.pumpAndSettle();
    expect(repo.mutations.single.$1, 'admin_approve_whatsapp');
    expect(repo.mutations.single.$2['p_whatsapp_phone'], '+250788984002');
    expect(repo.granted, isFalse);
    expect(find.byTooltip('Awaiting activation'), findsOneWidget);
    await confirm(tester, 'Activate Admin');
    await tester.pumpAndSettle();
    expect(repo.mutations.last.$1, 'admin_set_user_access');
    expect(repo.mutations.last.$2['p_active'], isTrue);
    expect(find.byTooltip('Active'), findsOneWidget);
  });
  testWidgets('partial phone and missing reason cannot submit approval', (
    tester,
  ) async {
    final repo = AccessRepository();
    await mount(tester, repo);
    await tester.tap(find.text('Approve WhatsApp'));
    await tester.pumpAndSettle();
    final submit = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(FilledButton),
    );
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tester.enterText(
      find.widgetWithText(TextField, 'Verified WhatsApp number'),
      '+2507',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Reason'), 'Review');
    await tester.pump();
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.mutations, isEmpty);
  });
  testWidgets('unknown receipt never shows success', (tester) async {
    final repo = AccessRepository()..invalidReceipt = true;
    await mount(tester, repo);
    await confirm(tester, 'Approve WhatsApp', phone: '+250788984002');
    await tester.pumpAndSettle();
    expect(
      find.text('Change not confirmed. Refresh access before trying again.'),
      findsOneWidget,
    );
    expect(
      find.text('WhatsApp approved. A new sign-in is required.'),
      findsNothing,
    );
    expect(find.text('Activate Admin'), findsNothing);
  });
  testWidgets('changed operator identity aborts before mutation', (
    tester,
  ) async {
    final repo = AccessRepository();
    await mount(tester, repo);
    repo.identity = null;
    await confirm(tester, 'Approve WhatsApp', phone: '+250788984002');
    await tester.pumpAndSettle();
    expect(repo.mutations, isEmpty);
    expect(find.textContaining('Change not confirmed'), findsOneWidget);
  });
  testWidgets('pending request blocks duplicate submission', (tester) async {
    final repo = AccessRepository()
      ..approved = true
      ..mutationGate = Completer<void>();
    await mount(tester, repo);
    await confirm(tester, 'Activate Admin');
    await tester.pump(const Duration(milliseconds: 400));
    expect(repo.mutations.length, 1);
    final activate = find.descendant(
      of: find.byType(AdminPlatformAccessPanel),
      matching: find.widgetWithText(FilledButton, 'Activate Admin'),
    );
    expect(tester.widget<FilledButton>(activate).onPressed, isNull);
    repo.mutationGate!.complete();
    await tester.pumpAndSettle();
    expect(repo.mutations.length, 1);
  });
  testWidgets('self approval and deactivation are unavailable', (tester) async {
    final repo = AccessRepository()
      ..approved = true
      ..granted = true;
    await mount(tester, repo, userId: operatorId);
    expect(find.text('Changes require another Admin.'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('Revoke approval'), findsNothing);
  });
  testWidgets('revocation removes both approval and platform role', (
    tester,
  ) async {
    final repo = AccessRepository()
      ..approved = true
      ..granted = true;
    await mount(tester, repo);
    await tester.tap(find.text('Revoke approval'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Reason'),
      'Synthetic revocation',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Revoke approval'));
    await tester.pumpAndSettle();
    expect(repo.mutations.single.$1, 'admin_revoke_whatsapp_approval');
    expect(repo.approved || repo.granted, isFalse);
  });
  testWidgets('read failure is recoverable without enabling actions', (
    tester,
  ) async {
    final repo = AccessRepository()..failRead = true;
    await mount(tester, repo);
    expect(find.text('Approve WhatsApp'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    repo.failRead = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Approve WhatsApp'), findsOneWidget);
  });
  for (final width in [390.0, 1184.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('platform approval layout ${width.toInt()} at ${scale}x', (
        tester,
      ) async {
        final key = GlobalKey();
        await mount(
          tester,
          AccessRepository()
            ..approved = true
            ..granted = true,
          width: width,
          scale: scale,
          boundary: key,
          detail: true,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Deactivate Admin'), findsOneWidget);
        final directory =
            Platform.environment['COLLECT_ADMIN_ACCESS_CAPTURE_DIR'];
        if (directory != null) {
          await tester.runAsync(() async {
            final image =
                await (key.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(directory).create(recursive: true);
            await File(
              '$directory/platform-admin-${width.toInt()}-${scale}x.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }
}
