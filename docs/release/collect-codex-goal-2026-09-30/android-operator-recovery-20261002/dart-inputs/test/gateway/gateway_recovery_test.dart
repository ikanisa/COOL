import 'dart:async';
import 'package:collect_app/gateway/gateway_app.dart';
import 'package:collect_app/gateway/gateway_recovery_platform.dart';
import 'package:collect_app/gateway/gateway_recovery_page.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'gateway_safety_test.dart' show FakeGateway;

Map<Object?, Object?> recovery({
  String operation = 'none',
  String state = 'idle',
  String phase = 'idle',
  bool? key,
  int count = 0,
  String? sha,
  int? files,
  String? reason,
}) => {
  'contract_version': 1,
  'operation': operation,
  'state': state,
  'phase': phase,
  'completed_files': count,
  'manifest_sha256': sha,
  'files': files,
  'key_validated': key,
  'inactive': operation == 'restore',
  'requires_re_enrollment': operation == 'restore',
  'reason_code': reason,
};
GatewayRecoveryStatus parsed(Map<Object?, Object?> map) =>
    GatewayRecoveryStatus.fromMap(map);

class FakeRecovery implements GatewayRecoveryPlatform {
  GatewayRecoveryStatus current = parsed(recovery());
  Completer<GatewayRecoveryStatus>? pending;
  int exports = 0, restores = 0, cancels = 0;
  String? submittedHash;
  @override
  Future<GatewayRecoveryStatus> status() async => current;
  @override
  Future<GatewayRecoveryStatus> export() {
    exports++;
    current = parsed(
      recovery(operation: 'export', state: 'working', phase: 'picker'),
    );
    pending = Completer();
    return pending!.future;
  }

  @override
  Future<GatewayRecoveryStatus> restore(String sha) {
    restores++;
    submittedHash = sha;
    current = parsed(
      recovery(
        operation: 'restore',
        state: 'working',
        phase: 'reading',
        sha: sha,
      ),
    );
    pending = Completer();
    return pending!.future;
  }

  @override
  Future<GatewayRecoveryStatus> cancel() async {
    cancels++;
    current = parsed(
      recovery(
        operation: current.operation,
        state: 'cancelled',
        phase: 'cancelled',
        reason: 'gateway_recovery_cancelled',
      ),
    );
    pending?.complete(current);
    pending = null;
    return current;
  }

  void finish({bool key = false}) {
    current = parsed(
      recovery(
        operation: current.operation,
        state: 'complete',
        phase: 'complete',
        count: 12,
        files: 12,
        sha: 'a' * 64,
        key: current.operation == 'restore' ? key : null,
      ),
    );
    pending!.complete(current);
    pending = null;
  }
}

Future<void> open(WidgetTester tester, FakeRecovery fake) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: CollectTheme.light(),
      darkTheme: CollectTheme.dark(),
      home: GatewayRecoveryPage(platform: fake),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String label) async {
  final f = find.text(label);
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('closed recovery DTO denies malformed fields and activation claims', () {
    final good = recovery(
      operation: 'restore',
      state: 'complete',
      phase: 'complete',
      count: 1,
      files: 1,
      sha: 'a' * 64,
      key: false,
    );
    expect(parsed(good).keyValidated, isFalse);
    expect(parsed(good).inactive, isTrue);
    for (final entry in {
      'contract_version': 2,
      'completed_files': '1',
      'files': 0,
      'key_validated': 1,
      'inactive': false,
      'requires_re_enrollment': false,
      'manifest_sha256': 'A' * 64,
      'state': 'active',
      'reason_code': 'private credential text',
      'phase': 'sending',
    }.entries) {
      expect(
        () => parsed({...good, entry.key: entry.value}),
        throwsFormatException,
      );
    }
    expect(
      () => parsed({...good, 'sender_active': true}),
      throwsFormatException,
    );
    expect(
      () => parsed({...good, 'key_validated': null}),
      throwsFormatException,
    );
    expect(
      () => parsed({
        ...good,
        'operation': 'export',
        'inactive': false,
        'requires_re_enrollment': false,
      }),
      throwsFormatException,
    );
  });
  test(
    'native maintenance uses separate strict channel and original trusted fingerprint',
    () async {
      const channel = MethodChannel('collect/gateway.recovery.v1');
      const active = MethodChannel('collect/gateway.v1');
      final calls = <MethodCall>[];
      var signingCalls = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(active, (_) async {
        signingCalls++;
        throw StateError('unexpected');
      });
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return recovery(
          operation: call.method == 'restore'
              ? 'restore'
              : call.method == 'export'
              ? 'export'
              : 'none',
          state: call.method == 'restore' || call.method == 'export'
              ? 'complete'
              : 'idle',
          phase: call.method == 'restore' || call.method == 'export'
              ? 'complete'
              : 'idle',
          sha: call.method == 'restore' || call.method == 'export'
              ? 'a' * 64
              : null,
          files: call.method == 'restore' || call.method == 'export' ? 0 : null,
          key: call.method == 'restore' ? false : null,
        );
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      addTearDown(() => messenger.setMockMethodCallHandler(active, null));
      const platform = NativeGatewayRecoveryPlatform();
      await platform.status();
      await platform.export();
      await platform.restore('a' * 64);
      await platform.cancel();
      expect(calls.map((x) => x.method), [
        'status',
        'export',
        'restore',
        'cancel',
      ]);
      expect(calls[0].arguments, isNull);
      expect(calls[1].arguments, isNull);
      expect(calls[2].arguments, {'manifest_sha256': 'a' * 64});
      expect(signingCalls, 0);
      expect(() => platform.restore('A' * 64), throwsFormatException);
      expect(calls, hasLength(4));
    },
  );
  test('native start refuses mismatched operation response', () async {
    const channel = MethodChannel('collect/gateway.recovery.v1');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => recovery());
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await expectLater(
      const NativeGatewayRecoveryPlatform().export(),
      throwsFormatException,
    );
  });
  testWidgets(
    'recovery route remains accessible after ordinary signing initialization fails',
    (tester) async {
      final fake = FakeRecovery();
      final gateway = FakeGateway()..failInitialization = true;
      await tester.pumpWidget(
        CollectGatewayApp(platform: gateway, recoveryPlatform: fake),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'Journal recovery');
      await tester.pumpAndSettle();
      expect(find.text('Preserve gateway evidence'), findsOneWidget);
      expect(fake.exports, 0);
      expect(fake.restores, 0);
      expect(gateway.provisions, 0);
      expect(gateway.dispatchAllowances, 0);
    },
  );
  testWidgets(
    'export blocks duplicate work and reports verified hash without resuming',
    (tester) async {
      final fake = FakeRecovery();
      await open(tester, fake);
      await tap(tester, 'Export journal archive');
      await tester.pump(const Duration(milliseconds: 550));
      expect(fake.exports, 1);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Export journal archive'),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.text('Choose an archive location in the Android file picker.'),
        findsOneWidget,
      );
      fake.finish();
      await tester.pumpAndSettle();
      expect(find.text('Archive exported and read back'), findsOneWidget);
      expect(find.text('12 ciphertext files'), findsOneWidget);
      expect(find.text('a' * 64), findsOneWidget);
      expect(find.text('Activate sender'), findsNothing);
    },
  );
  testWidgets(
    'trusted lowercase digest gates restore and opaque output stays explicit',
    (tester) async {
      final fake = FakeRecovery();
      await open(tester, fake);
      final button = find.widgetWithText(
        OutlinedButton,
        'Restore inactive evidence',
      );
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'A' * 64);
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'a' * 64);
      await tester.pump();
      await tap(tester, 'Restore inactive evidence');
      expect(fake.submittedHash, 'a' * 64);
      fake.finish();
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Opaque ciphertext retained; contents are not validated',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Sender authority remains inactive'),
        findsOneWidget,
      );
      expect(fake.restores, 1);
    },
  );
  testWidgets('validated restore remains inactive and requires re-enrollment', (
    tester,
  ) async {
    final fake = FakeRecovery();
    await open(tester, fake);
    await tester.enterText(find.byType(TextField), 'a' * 64);
    await tester.pump();
    await tap(tester, 'Restore inactive evidence');
    fake.finish(key: true);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Validated with the existing storage key'),
      findsOneWidget,
    );
    expect(find.textContaining('re-enrollment is required'), findsOneWidget);
    expect(find.text('Allow governed dispatch'), findsNothing);
  });
  testWidgets(
    'picker cancellation retains evidence and permits a later explicit operation',
    (tester) async {
      final fake = FakeRecovery();
      await open(tester, fake);
      await tap(tester, 'Export journal archive');
      await tap(tester, 'Cancel recovery');
      await tester.pumpAndSettle();
      expect(fake.cancels, 1);
      expect(fake.exports, 1);
      expect(
        find.textContaining('partial evidence remains in private quarantine'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Export journal archive'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
  testWidgets('closing the page cancels pending native maintenance', (
    tester,
  ) async {
    final fake = FakeRecovery();
    await open(tester, fake);
    await tap(tester, 'Export journal archive');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(fake.cancels, 1);
    expect(fake.exports, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'narrow large-text recovery remains scrollable with labeled controls',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fake = FakeRecovery();
      await tester.pumpWidget(
        MaterialApp(
          theme: CollectTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2),
            ),
            child: GatewayRecoveryPage(platform: fake),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(TextField));
      expect(find.text('Trusted manifest SHA256'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
