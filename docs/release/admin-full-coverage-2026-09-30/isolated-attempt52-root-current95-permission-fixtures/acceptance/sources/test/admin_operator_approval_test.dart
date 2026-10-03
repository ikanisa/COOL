import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/admin/core/admin_action_contracts.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_operator_approval.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_action_session_test.dart' as auth;
import 'admin_platform_access_test.dart' as legacy;

Map<String, dynamic> _fixture({
  String target = legacy.target,
  String provider = 'email',
  String mode = 'email',
  String? status,
  bool approved = false,
  bool granted = false,
}) => {
  'contract_version': 1,
  'user_id': target,
  'provider': provider,
  'mode': mode,
  'identity_masked': provider == 'email'
      ? 'o***@***'
      : provider == 'whatsapp'
      ? '+***4002'
      : null,
  'approved_at': approved || status != null ? '2026-09-02T10:00:00Z' : null,
  'expires_at': null,
  'status': status ?? (approved ? 'approved' : 'not_approved'),
  'approved': approved,
  'role_granted': granted,
  'admin_access': approved && granted,
  'access_status': approved && granted
      ? 'active'
      : granted
      ? 'approval_required'
      : approved
      ? 'approved'
      : 'revoked',
};

class _EmailAccess extends legacy.AccessRepository {
  String provider = 'email', mode = 'email';
  String? status;
  Object? readError, writeError;
  Completer<Map<String, dynamic>>? readGate;
  @override
  Future<Map<String, dynamic>> action(
    String rpcName,
    Map<String, dynamic> params,
  ) async {
    calls.add((rpcName, Map.of(params)));
    if (rpcName == 'admin_get_operator_approval_v1') {
      if (readError != null) throw readError!;
      if (readGate != null) return readGate!.future;
      return _fixture(
        target: params['p_user_id'] as String,
        provider: provider,
        mode: mode,
        status: status,
        approved: approved,
        granted: granted,
      );
    }
    if (mutationGate != null) await mutationGate!.future;
    if (writeError != null) throw writeError!;
    if (invalidReceipt) return {'ok': true};
    if (rpcName == 'admin_approve_email_operator_v1') {
      approved = true;
      status = null;
      return {'ok': true, 'status': 'approved', 'user_id': params['p_user_id']};
    }
    if (rpcName == 'admin_revoke_email_operator_v1') {
      approved = granted = false;
      status = 'revoked';
      return {'ok': true, 'status': 'revoked', 'user_id': params['p_user_id']};
    }
    if (rpcName == 'admin_set_user_access') {
      granted = params['p_active'] == true;
      return {'ok': true, 'status': granted ? 'active' : 'revoked'};
    }
    throw StateError('Unexpected synthetic RPC');
  }
}

Future<void> _approve(
  WidgetTester tester, {
  String reason = 'Synthetic reviewed approval',
}) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Approve email'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextField, 'Verified operator email'),
    ' OPERATOR@Collect.Example ',
  );
  await tester.enterText(find.widgetWithText(TextField, 'Reason'), reason);
  await tester.pump();
  await tester.tap(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Approve email'),
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
  test(
    'exact server operator states bind target and distinguish providers',
    () {
      for (final row in [
        _fixture(),
        _fixture(approved: true),
        _fixture(approved: true, granted: true),
        _fixture(provider: 'whatsapp', mode: 'transition', approved: true),
        _fixture(provider: 'whatsapp', status: 'legacy_disabled'),
        _fixture(status: 'pending_verification'),
        _fixture(status: 'expired'),
        _fixture(status: 'identity_changed'),
        _fixture(status: 'revoked'),
        _fixture(provider: 'unapproved'),
      ]) {
        final parsed = AdminOperatorApproval.parse(
          row,
          targetUserId: legacy.target,
        );
        expect(
          parsed.legacyControls,
          row['provider'] == 'whatsapp' && row['mode'] == 'transition',
        );
        expect(parsed.approved, row['status'] == 'approved');
      }
    },
  );
  test(
    'operator evidence rejects extra fields, full destination and incoherent access',
    () {
      for (final mutation in <void Function(Map<String, dynamic>)>[
        (r) => r['private_email'] = 'PRIVATE_CANARY@example.com',
        (r) => r.remove('mode'),
        (r) => r['contract_version'] = 1.0,
        (r) => r['user_id'] = legacy.operatorId,
        (r) => r['identity_masked'] = 'PRIVATE_CANARY@example.com',
        (r) => r['status'] = 'unknown',
        (r) => r['admin_access'] = true,
        (r) => r['access_status'] = 'active',
        (r) => r['approved'] = true,
        (r) => r['approved_at'] = '2026-02-30T00:00:00Z',
        (r) => r['approved_at'] = '2026-09-02T10:00:00',
      ]) {
        final row = _fixture();
        mutation(row);
        expect(
          () => AdminOperatorApproval.parse(row, targetUserId: legacy.target),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'email action receipts require exact target, normalized email and bounded reason',
    () {
      for (final operation in [
        'admin_approve_email_operator_v1',
        'admin_revoke_email_operator_v1',
      ]) {
        final approve = operation == 'admin_approve_email_operator_v1';
        final request = {
          'p_user_id': legacy.target,
          'p_reason': 'Synthetic approval review',
          if (approve) 'p_email': 'operator@collect.example',
        };
        final response = {
          'ok': true,
          'status': approve ? 'approved' : 'revoked',
          'user_id': legacy.target,
        };
        validateAdminActionReceipt(operation, request, response);
        for (final bad in [
          {...response, 'user_id': legacy.operatorId},
          {...response, 'status': 'queued'},
          {...response, 'email': 'PRIVATE_CANARY@example.com'},
          {'ok': true},
        ]) {
          expect(
            () => validateAdminActionReceipt(operation, request, bad),
            throwsFormatException,
          );
        }
        for (final reason in ['short', 'x' * 501]) {
          expect(
            () => validateAdminActionReceipt(operation, {
              ...request,
              'p_reason': reason,
            }, response),
            throwsFormatException,
          );
        }
      }
    },
  );
  testWidgets(
    'email account has email controls and masked identity; activation stays separate',
    (tester) async {
      final repo = _EmailAccess();
      await legacy.mount(tester, repo);
      expect(find.text('Email: o***@***'), findsOneWidget);
      expect(find.text('Approve WhatsApp'), findsNothing);
      expect(find.text('Activate Admin'), findsNothing);
      await _approve(tester);
      await tester.pumpAndSettle();
      expect(repo.mutations.single.$1, 'admin_approve_email_operator_v1');
      expect(repo.mutations.single.$2, {
        'p_user_id': legacy.target,
        'p_email': 'operator@collect.example',
        'p_reason': 'Synthetic reviewed approval',
      });
      expect(repo.granted, isFalse);
      expect(find.byTooltip('Awaiting activation'), findsOneWidget);
      expect(find.textContaining('Africa/Kigali'), findsOneWidget);
      await legacy.confirm(tester, 'Activate Admin');
      await tester.pumpAndSettle();
      expect(repo.mutations.last.$1, 'admin_set_user_access');
      expect(find.byTooltip('Active'), findsOneWidget);
    },
  );
  testWidgets(
    'email dialog enforces email keyboard, minimum reason and invalid input',
    (tester) async {
      final repo = _EmailAccess();
      await legacy.mount(tester, repo);
      await tester.tap(find.text('Approve email'));
      await tester.pumpAndSettle();
      final email = find.widgetWithText(TextField, 'Verified operator email');
      expect(
        tester.widget<TextField>(email).keyboardType,
        TextInputType.emailAddress,
      );
      final submit = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      );
      await tester.enterText(email, 'operator@collect.example');
      await tester.enterText(find.widgetWithText(TextField, 'Reason'), 'short');
      await tester.pump();
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      await tester.enterText(email, 'operator@');
      await tester.enterText(
        find.widgetWithText(TextField, 'Reason'),
        'Synthetic approved reason',
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.mutations, isEmpty);
    },
  );
  testWidgets('email approval revocation uses new target-bound service', (
    tester,
  ) async {
    final repo = _EmailAccess()
      ..approved = true
      ..granted = true;
    await legacy.mount(tester, repo);
    await tester.tap(find.text('Revoke approval'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Reason'),
      'Synthetic revocation',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Revoke approval'));
    await tester.pumpAndSettle();
    expect(repo.mutations.single.$1, 'admin_revoke_email_operator_v1');
    expect(repo.approved || repo.granted, isFalse);
  });
  testWidgets(
    'legacy-disabled account offers email approval without WhatsApp mutation',
    (tester) async {
      final repo = _EmailAccess()
        ..provider = 'whatsapp'
        ..status = 'legacy_disabled';
      await legacy.mount(tester, repo);
      expect(find.byTooltip('Legacy sign in disabled'), findsOneWidget);
      expect(find.text('Approve WhatsApp'), findsNothing);
      expect(find.text('Approve email'), findsOneWidget);
      expect(find.textContaining('must verify its email'), findsOneWidget);
    },
  );
  testWidgets('read denied and unavailable states never fall back to legacy', (
    tester,
  ) async {
    for (final (error, message) in [
      (
        const PostgrestException(message: 'PRIVATE_CANARY', code: '42501'),
        'Platform access is denied for this Admin session.',
      ),
      (
        const PostgrestException(message: 'PRIVATE_CANARY', code: 'PGRST202'),
        'Operator approval service is unavailable.',
      ),
      (
        const FormatException('PRIVATE_CANARY'),
        'Platform access could not be loaded.',
      ),
    ]) {
      final repo = _EmailAccess()..readError = error;
      await legacy.mount(tester, repo);
      expect(find.text(message), findsOneWidget);
      expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
      expect(repo.calls.single.$1, 'admin_get_operator_approval_v1');
      expect(find.byType(FilledButton), findsNothing);
    }
  });
  testWidgets(
    'write denial preserves approval and gives safe verification guidance',
    (tester) async {
      final repo = _EmailAccess()
        ..writeError = const PostgrestException(
          message: 'PRIVATE_CANARY',
          code: '42501',
        );
      await legacy.mount(tester, repo);
      await _approve(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('Change denied.'), findsOneWidget);
      expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
      expect(repo.approved, isFalse);
      expect(find.textContaining('Email approved.'), findsNothing);
    },
  );
  testWidgets(
    'email cutover while legacy approval is open avoids a legacy write',
    (tester) async {
      final repo = _EmailAccess()
        ..provider = 'whatsapp'
        ..mode = 'transition';
      await legacy.mount(tester, repo);
      await tester.tap(find.text('Approve WhatsApp'));
      await tester.pumpAndSettle();
      repo.mode = 'email';
      await tester.enterText(
        find.widgetWithText(TextField, 'Verified WhatsApp number'),
        '+250788984002',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Reason'),
        'Synthetic approved review',
      );
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Approve WhatsApp'),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.mutations, isEmpty);
      expect(find.textContaining('Change not confirmed'), findsOneWidget);
      expect(find.text('Approve WhatsApp'), findsNothing);
    },
  );
  testWidgets('lost manage permission dismisses intent before email mutation', (
    tester,
  ) async {
    final repo = _EmailAccess();
    await legacy.mount(tester, repo);
    await tester.tap(find.text('Approve email'));
    await tester.pumpAndSettle();
    repo.identity = const AdminIdentity(
      userId: legacy.operatorId,
      displayName: 'Synthetic',
      roles: [],
      permissions: ['admin_users.read'],
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AdminPlatformAccessPanel)),
    );
    container.invalidate(adminIdentityProvider);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(repo.mutations, isEmpty);
  });
  testWidgets(
    'disposed pending approval read cannot publish private evidence',
    (tester) async {
      final repo = _EmailAccess()..readGate = Completer<Map<String, dynamic>>();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminAuthUserIdProvider.overrideWithValue(legacy.operatorId),
            adminRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: AdminPlatformAccessPanel(userId: legacy.target),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpWidget(const SizedBox.shrink());
      repo.readGate!.complete(_fixture(approved: true, granted: true));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Active'), findsNothing);
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      '${brightness.name} email approval at 320px 2x remains readable',
      (tester) async {
        final repo = _EmailAccess()..approved = true;
        await legacy.mount(
          tester,
          repo,
          width: 320,
          scale: 2,
          brightness: brightness,
        );
        expect(find.text('Email: o***@***'), findsOneWidget);
        expect(find.text('Activate Admin'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets('${brightness.name} synthetic email approval capture', (
      tester,
    ) async {
      final key = GlobalKey();
      await legacy.mount(
        tester,
        _EmailAccess()..approved = true,
        width: 1440,
        boundary: key,
        brightness: brightness,
      );
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('COLLECT_CAPTURE_OPERATIONS')) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'docs/release/collect-codex-goal-2026-09-30/email-operator/email-approval-${brightness.name}-synthetic.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
  group('pinned SDK operator approval', () {
    late SupabaseClient client;
    late AdminRepository repository;
    late Future<Object?> Function(http.Request) respond;
    final requests = <http.Request>[];
    setUp(() async {
      requests.clear();
      client = SupabaseClient(
        'https://synthetic.invalid',
        'synthetic-public',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/verify')) {
            final token = (jsonDecode(request.body) as Map)['token'] as String;
            return http.Response(
              jsonEncode(
                auth.authReceipt(token.split('|').first, token.split('|').last),
              ),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          if (request.url.path.endsWith('/logout')) {
            return http.Response('{}', 200, request: request);
          }
          requests.add(request);
          return http.Response(
            jsonEncode(await respond(request)),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      await auth.session(client, 'operator-a');
      repository = AdminRepository(client);
    });
    tearDown(() => client.dispose());
    test('versioned masked read is one exact target-bound request', () async {
      respond = (_) async => _fixture(target: auth.target);
      final data = await repository.action('admin_get_operator_approval_v1', {
        'p_user_id': auth.target,
      });
      expect(data['identity_masked'], 'o***@***');
      expect(
        requests.single.url.path,
        '/rest/v1/rpc/admin_get_operator_approval_v1',
      );
      expect(jsonDecode(requests.single.body), {'p_user_id': auth.target});
    });
    test(
      'malformed read never certifies legacy or exposes full email',
      () async {
        respond = (_) async => {
          ..._fixture(target: auth.target),
          'identity_masked': 'PRIVATE_CANARY@example.com',
        };
        await expectLater(
          repository.action('admin_get_operator_approval_v1', {
            'p_user_id': auth.target,
          }),
          throwsFormatException,
        );
        expect(requests, hasLength(1));
      },
    );
    for (final rpc in [
      'admin_get_operator_approval_v1',
      'admin_approve_email_operator_v1',
      'admin_revoke_email_operator_v1',
    ]) {
      test('$rpc fences same-owner replacement while pending', () async {
        final entered = Completer<void>(), release = Completer<void>();
        respond = (_) async {
          entered.complete();
          await release.future;
          return rpc == 'admin_get_operator_approval_v1'
              ? _fixture(target: auth.target)
              : {
                  'ok': true,
                  'status': rpc == 'admin_approve_email_operator_v1'
                      ? 'approved'
                      : 'revoked',
                  'user_id': auth.target,
                };
        };
        final pending = repository.action(rpc, {
          'p_user_id': auth.target,
          if (rpc != 'admin_get_operator_approval_v1')
            'p_reason': 'Synthetic approval review',
          if (rpc == 'admin_approve_email_operator_v1')
            'p_email': 'operator@collect.example',
        });
        final assertion = expectLater(
          pending,
          throwsA(isA<AdminSessionChanged>()),
        );
        await entered.future;
        await auth.session(client, 'operator-b');
        release.complete();
        await assertion;
        expect(requests, hasLength(1));
      });
    }
  });
}
