// Local synthetic controller/widget qualification only; no live credentials,
// native installation, PostgreSQL deployment or MDM/provider action.
import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/admin_burimunsi_api.dart';
import 'package:collect_app/admin/core/admin_pending_attempt_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'admin_burimunsi_test.dart' as existing;

const accountId = 'b3000000-0000-4000-8000-000000000001';
const installationId = 'b3000000-0000-4000-8000-000000000002';
const grantId = 'b3000000-0000-4000-8000-000000000003';

Map<String, dynamic> nativeDirectory({bool issued = false}) => {
  'contractVersion': 1,
  'collectionId': existing.group,
  'configured': true,
  'scopeVersion': 1,
  'scopeEnabled': false,
  'accounts': [
    {
      'principalId': existing.staff.principalId,
      'accountId': issued ? accountId : null,
      'phone': '+250780000002',
      'name': 'QA Staff',
      'role': 'staff',
      'capabilities': ['records.read'],
      'approvalVersion': 1,
      'version': issued ? 1 : 0,
      'credentialVersion': issued ? 1 : 0,
      'approved': true,
      'active': issued,
      'removed': false,
    },
  ],
  'grants': <dynamic>[],
};

class ProvisioningApi extends existing.FakeBuriApi
    implements AdminBuriMunsiProvisioningApi {
  ProvisioningApi() {
    directory = const BuriOperatorDirectory(
      collectionId: existing.group,
      configured: true,
      team: [existing.staff],
      approvals: [],
    );
  }
  Map<String, dynamic> native = nativeDirectory();
  final outcomes = <String, Map<String, dynamic>>{};
  int submits = 0, checks = 0, cancels = 0, deliveries = 0;
  bool loseCommitResponse = false,
      failBeforeCommit = false,
      pinSupplied = false;
  Completer<void>? waitForCommit;
  @override
  Future<BuriProvisioningDirectory> loadBuriProvisioning({
    String? collectionId,
  }) async => BuriProvisioningDirectory.parse(native);
  @override
  Future<Map<String, dynamic>> submitBuriProvisioning(
    BuriProvisioningIntent intent,
    Object fence, {
    String? pin,
  }) async {
    submits++;
    pinSupplied = pin != null;
    await waitForCommit?.future;
    if (failBeforeCommit) {
      throw const AdminAccountException('Synthetic unavailable response.');
    }
    final receipt = <String, dynamic>{
      'contractVersion': 1,
      'collectionId': intent.collectionId,
      'requestId': intent.requestId,
      'operation': intent.operation,
      'principalId': intent.principalId,
      'accountId': intent.accountId ?? accountId,
      'accountVersion':
          intent.expectedAccountVersion +
          (intent.operation == 'set_pin' ? 1 : 0),
      'credentialVersion': 1,
      'approvalVersion': intent.approvalVersion,
      'scopeVersion': intent.scopeVersion,
      'applied': true,
      if (intent.operation != 'set_pin') ...{
        'grantId': intent.grantId ?? grantId,
        'installationId': intent.installationId,
        'profile': intent.profile,
        'grantVersion': intent.expectedGrantVersion! + 1,
        'active': intent.operation == 'grant_installation',
        'deliveryExpiresAt': intent.operation == 'grant_installation'
            ? DateTime.now().millisecondsSinceEpoch + 900000
            : null,
      },
    };
    outcomes[intent.requestId] = receipt;
    if (intent.operation == 'set_pin') native = nativeDirectory(issued: true);
    if (loseCommitResponse) {
      throw const AdminAccountException('Synthetic lost COMMIT response.');
    }
    return receipt;
  }

  @override
  Future<Map<String, dynamic>?> lookupBuriProvisioning(
    BuriProvisioningIntent intent,
    Object fence,
  ) async {
    checks++;
    return outcomes[intent.requestId];
  }

  @override
  Future<Map<String, dynamic>> cancelBuriProvisioning(
    BuriProvisioningIntent intent,
    Object fence,
  ) async {
    cancels++;
    return outcomes.putIfAbsent(
      intent.requestId,
      () => {
        'contractVersion': 1,
        'collectionId': intent.collectionId,
        'requestId': intent.requestId,
        'operation': 'cancelled',
        'applied': false,
      },
    );
  }

  @override
  Future<BuriNativeDelivery> loadBuriDelivery(
    BuriProvisioningIntent intent,
    Object fence,
  ) async {
    deliveries++;
    return BuriNativeDelivery.parse({
      'contractVersion': 1,
      'collectionId': intent.collectionId,
      'requestId': intent.requestId,
      'installationId': intent.installationId,
      'profile': intent.profile,
      'grantVersion': intent.expectedGrantVersion! + 1,
      'expiresAt': DateTime.now().millisecondsSinceEpoch + 900000,
      'installationToken': 'c' * 64,
    }, intent);
  }
}

class DynamicScopeApi extends ProvisioningApi
    implements AdminBuriMunsiScopeApi {
  final reads = <String>[];
  @override
  Future<List<BuriScopeChoice>> loadBuriScopes() async => const [
    BuriScopeChoice(existing.group, 'First existing group'),
    BuriScopeChoice('second-existing-group', 'Second existing group'),
  ];
  @override
  Future<BuriOperatorDirectory> loadBuriDirectory({
    String? collectionId,
  }) async {
    reads.add(collectionId!);
    return BuriOperatorDirectory(
      collectionId: collectionId,
      configured: true,
      team: const [existing.staff],
      approvals: const [],
    );
  }

  @override
  Future<BuriProvisioningDirectory> loadBuriProvisioning({
    String? collectionId,
  }) async => BuriProvisioningDirectory.parse({
    ...native,
    'collectionId': collectionId,
  });
}

BuriProvisioningIntent pinIntent() => BuriProvisioningIntent(
  collectionId: existing.group,
  principalId: existing.staff.principalId,
  scopeVersion: 1,
  approvalVersion: 1,
  expectedAccountVersion: 0,
  operation: 'set_pin',
  reason: 'Owner approved native setup',
);
BuriProvisioningIntent grantIntent() => BuriProvisioningIntent(
  collectionId: existing.group,
  principalId: existing.staff.principalId,
  scopeVersion: 1,
  approvalVersion: 1,
  expectedAccountVersion: 1,
  accountId: accountId,
  operation: 'grant_installation',
  installationId: installationId,
  profile: 'staff',
  expectedGrantVersion: 0,
  reason: 'Owner approved installation',
);
BuriProvisioningCoordinator coordinator(
  ProvisioningApi api,
  MemoryAdminPendingAttemptStorage memory,
) => BuriProvisioningCoordinator(
  api: api,
  store: existing.store(memory),
  collectionId: existing.group,
);

void main() {
  testWidgets(
    'shared Admin selects an actual group before loading scoped provisioning',
    (tester) async {
      final api = DynamicScopeApi(),
          memory = MemoryAdminPendingAttemptStorage();
      await existing.mount(tester, api, memory);
      expect(api.reads, isEmpty);
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Second existing group').last);
      await tester.pumpAndSettle();
      expect(api.reads, ['second-existing-group']);
      expect(find.text('Set native PIN'), findsOneWidget);
      expect(api.submits, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'restoration pins an unresolved original group without retargeting or auto-dispatch',
    (tester) async {
      final api = DynamicScopeApi()..failBeforeCommit = true,
          memory = MemoryAdminPendingAttemptStorage();
      final original = pinIntent();
      final first = coordinator(api, memory);
      await expectLater(
        first.submit(original, pin: '8492'),
        throwsA(isA<AdminAccountException>()),
      );
      first.store.dispose();
      expect(api.submits, 1);
      await existing.mount(tester, api, memory);
      expect(api.reads, [existing.group]);
      expect(api.submits, 1);
      final selector = tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>).first,
      );
      expect(selector.initialValue, existing.group);
      expect(selector.onChanged, isNull);
      expect(memory.values, isNotEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  test(
    'PIN is a transient submit argument, absent from all retained intent fields',
    () async {
      final api = ProvisioningApi()..loseCommitResponse = true;
      final memory = MemoryAdminPendingAttemptStorage(), intent = pinIntent();
      final controller = coordinator(api, memory);
      await expectLater(
        controller.submit(intent, pin: '8492'),
        throwsA(isA<AdminAccountException>()),
      );
      expect(api.pinSupplied, true);
      expect(api.submits, 1);
      final stored = jsonEncode(memory.values);
      expect(stored.contains('8492'), false);
      expect(intent.checkpoint.containsKey('pin'), false);
      for (final key in ['pin', 'installationToken', 'password']) {
        expect(
          () => BuriProvisioningCoordinator.schema.canonical({
            ...intent.checkpoint,
            key: '8492',
          }),
          throwsFormatException,
        );
      }
      final restored = coordinator(api, memory);
      expect(restored.pending.single.requestId, intent.requestId);
      expect(api.submits, 1);
      expect(await restored.check(restored.pending.single), true);
      expect(restored.pending, isEmpty);
      expect(api.submits, 1);
      expect(api.checks, 1);
    },
  );
  test(
    'unknown PIN request blocks a new key, can settle without re-entering or retaining the PIN',
    () async {
      final api = ProvisioningApi()..failBeforeCommit = true;
      final memory = MemoryAdminPendingAttemptStorage();
      final controller = coordinator(api, memory), original = pinIntent();
      await expectLater(
        controller.submit(original, pin: '8492'),
        throwsA(isA<AdminAccountException>()),
      );
      await expectLater(
        controller.submit(pinIntent(), pin: '7316'),
        throwsA(isA<AdminAccountException>()),
      );
      expect(api.submits, 1);
      expect(await controller.check(original), false);
      await controller.cancel(original);
      expect(api.cancels, 1);
      expect(controller.pending, isEmpty);
      expect(jsonEncode(memory.values).contains('8492'), false);
    },
  );
  test(
    'commit/cancel race retains committed grant and protected delivery; reload only checks original',
    () async {
      final api = ProvisioningApi()..loseCommitResponse = true;
      final memory = MemoryAdminPendingAttemptStorage(), intent = grantIntent();
      final first = coordinator(api, memory);
      await expectLater(
        first.submit(intent),
        throwsA(isA<AdminAccountException>()),
      );
      final restored = coordinator(api, memory),
          original = coordinator(api, memory).pending.single;
      final pending = restored.pending.single;
      await restored.cancel(pending);
      expect(restored.receipt(pending)?['operation'], 'grant_installation');
      expect(restored.pending, hasLength(1));
      expect(original.requestId, intent.requestId);
      final delivery = await restored.delivery(pending);
      expect(delivery.toString(), 'BuriNativeDelivery(protected)');
      expect(api.deliveries, 1);
      expect(
        jsonEncode(memory.values).contains(delivery.installationToken),
        false,
      );
      restored.closeDelivery(pending);
      expect(restored.pending, isEmpty);
      expect(api.submits, 1);
    },
  );
  test(
    'rotation fences late responses and blocks secret delivery on another authority',
    () async {
      final api = ProvisioningApi()..waitForCommit = Completer<void>();
      final memory = MemoryAdminPendingAttemptStorage();
      final controller = coordinator(api, memory);
      final future = controller.submit(grantIntent());
      api.buriAuthorityFence = Object();
      api.waitForCommit!.complete();
      await expectLater(future, throwsA(isA<AdminAccountException>()));
      expect(controller.pending, isEmpty);
      expect(memory.values, isNotEmpty);
      expect(api.deliveries, 0);
    },
  );
  test(
    'another installation or principal receipt cannot clear an original checkpoint',
    () async {
      final api = ProvisioningApi()..loseCommitResponse = true;
      final memory = MemoryAdminPendingAttemptStorage();
      final controller = coordinator(api, memory);
      final intent = grantIntent();
      await expectLater(
        controller.submit(intent),
        throwsA(isA<AdminAccountException>()),
      );
      api.outcomes[intent.requestId]!['installationId'] = accountId;
      await expectLater(controller.check(intent), throwsFormatException);
      expect(controller.pending, hasLength(1));
      expect(memory.values, isNotEmpty);
    },
  );
  testWidgets(
    'owner PIN form is obscured and creates only a nonsecret original-request checkpoint',
    (tester) async {
      final api = ProvisioningApi()..loseCommitResponse = true;
      final memory = MemoryAdminPendingAttemptStorage();
      await existing.mount(tester, api, memory);
      final setup = find.byKey(const Key('buri-set-native-pin'));
      await tester.ensureVisible(setup);
      await tester.tap(setup);
      await tester.pumpAndSettle();
      final pin = find.byKey(const Key('buri-native-pin')),
          confirmation = find.byKey(const Key('buri-native-pin-confirm'));
      expect(
        tester
            .widget<TextField>(
              find.descendant(of: pin, matching: find.byType(TextField)),
            )
            .obscureText,
        true,
      );
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: confirmation,
                matching: find.byType(TextField),
              ),
            )
            .obscureText,
        true,
      );
      await tester.enterText(pin, '8492');
      await tester.enterText(confirmation, '8492');
      await tester.tap(find.widgetWithText(FilledButton, 'Set PIN'));
      await tester.pumpAndSettle();
      expect(api.submits, 1);
      expect(jsonEncode(memory.values).contains('8492'), false);
      expect(find.text('Native setup needs confirmation'), findsOneWidget);
      expect(find.text('Submit original request'), findsNothing);
      await existing.capture(tester, 'buri-native-provisioning-recovery');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'compact enlarged native setup keeps form actions reachable without layout errors',
    (tester) async {
      final api = ProvisioningApi()..native = nativeDirectory(issued: true);
      await existing.mount(
        tester,
        api,
        MemoryAdminPendingAttemptStorage(),
        narrow: true,
      );
      final setup = find.byKey(const Key('buri-grant-installation'));
      await tester.ensureVisible(setup);
      await tester.pumpAndSettle();
      expect(setup, findsOneWidget);
      expect(tester.takeException(), isNull);
      await existing.capture(tester, 'buri-native-provisioning-compact');
    },
  );
  testWidgets(
    'token delivery is masked, never journalled and closes across an owner fence change',
    (tester) async {
      final api = ProvisioningApi()..native = nativeDirectory(issued: true);
      final memory = MemoryAdminPendingAttemptStorage();
      await existing.mount(tester, api, memory);
      final field = find.byKey(const Key('buri-installation-id'));
      await tester.ensureVisible(field);
      await tester.enterText(field, installationId);
      final grant = find.byKey(const Key('buri-grant-installation'));
      await tester.ensureVisible(grant);
      await tester.tap(grant);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm grant'));
      await tester.pumpAndSettle();
      expect(find.text('Native grant delivery'), findsOneWidget);
      expect(find.text('PIN not issued'), findsNothing);
      await tester.ensureVisible(find.text('Open protected delivery'));
      await tester.tap(find.text('Open protected delivery'));
      await tester.pumpAndSettle();
      expect(find.text('Protected installation delivery'), findsOneWidget);
      final secret = find.widgetWithText(TextField, 'Installation token');
      expect(tester.widget<TextField>(secret).obscureText, true);
      expect(
        tester
            .widget<TextField>(secret)
            .controller
            .toString()
            .contains('c' * 64),
        false,
      );
      expect(jsonEncode(memory.values).contains('c' * 64), false);
      api.buriAuthorityFence = Object();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('Protected installation delivery'), findsNothing);
      expect(api.submits, 1);
      expect(api.deliveries, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
