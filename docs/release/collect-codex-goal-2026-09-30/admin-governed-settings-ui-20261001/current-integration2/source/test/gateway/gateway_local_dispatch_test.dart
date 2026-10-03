import 'dart:async';
import 'dart:convert';

import 'package:collect_app/gateway/gateway_app.dart';
import 'package:collect_app/gateway/gateway_platform.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'gateway_safety_test.dart' show status;

GatewaySnapshot _snapshot({
  String enrollment = 'pending',
  bool configured = true,
  bool paused = true,
}) => GatewaySnapshot.fromMap(
  status()
    ..['enrollment'] = enrollment
    ..['configured'] = configured
    ..['emergency_paused'] = paused,
);

class _LocalIntentGateway implements GatewayPlatform {
  _LocalIntentGateway(this.state);

  GatewaySnapshot state;
  Future<GatewaySnapshot>? initialResult;
  Future<GatewaySnapshot>? allowanceResult;
  Future<GatewaySnapshot>? healthResult;
  Future<GatewaySnapshot>? reconciliationResult;
  final calls = <String>[];

  @override
  Future<GatewaySnapshot> initialize() async {
    calls.add('initialize');
    return await (initialResult ?? Future.value(state));
  }

  @override
  Future<GatewaySnapshot> refresh() async {
    calls.add('status');
    return state;
  }

  @override
  Future<GatewaySnapshot> pause() async {
    calls.add('pause');
    state = _snapshot();
    return state;
  }

  @override
  Future<GatewaySnapshot> allowGovernedDispatch() async {
    calls.add('allowGovernedDispatch');
    if (allowanceResult != null) return await allowanceResult!;
    state = _snapshot(paused: false);
    return state;
  }

  @override
  Future<GatewaySnapshot> requestPermissions() async {
    calls.add('requestPermissions');
    return state;
  }

  @override
  Future<GatewaySnapshot> heartbeat() async {
    calls.add('heartbeat');
    return await (healthResult ?? Future.value(state));
  }

  @override
  Future<GatewaySnapshot> reconcile() async {
    calls.add('reconcile');
    return await (reconciliationResult ?? Future.value(state));
  }

  @override
  Future<Map<Object?, Object?>> identity() async {
    calls.add('identity');
    return {
      'contract_version': 1,
      'installation_id': '00000000-0000-0000-0000-000000000001',
      'key_sha256': 'a' * 64,
      'signing_certificate_sha256': 'b' * 64,
      'public_key_spki_base64': 'synthetic public identity only',
    };
  }

  @override
  Future<GatewaySnapshot> provisionEnrollment(
    Map<String, Object?> document,
  ) async {
    calls.add('provisionEnrollment');
    state = _snapshot();
    return state;
  }
}

Finder get _allowButton =>
    find.widgetWithText(OutlinedButton, 'Allow governed dispatch');

OutlinedButton _allowWidget(WidgetTester tester) =>
    tester.widget<OutlinedButton>(_allowButton);

Future<void> _open(WidgetTester tester, _LocalIntentGateway platform) async {
  await tester.pumpWidget(CollectGatewayApp(platform: platform));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native local intent sends no arguments and preserves status shape',
    () async {
      const channel = MethodChannel('collect/gateway.v1');
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return status()
          ..['enrollment'] = 'pending'
          ..['configured'] = true
          ..['emergency_paused'] = false;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final result = await const NativeGatewayPlatform()
          .allowGovernedDispatch();
      expect(calls, hasLength(1));
      expect(calls.single.method, 'allowGovernedDispatch');
      expect(calls.single.arguments, isNull);
      expect(result.paused, isFalse);
      expect(result.configured, isTrue);
      expect(result.enrollment, GatewayEnrollment.pending);
      expect(result.sendPermission, isFalse);
      expect(result.frameworkSentAttempts, 0);
    },
  );

  test('local-intent reply does not relax the exact native snapshot', () async {
    const channel = MethodChannel('collect/gateway.v1');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => status()..['dispatch_permit'] = true,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await expectLater(
      const NativeGatewayPlatform().allowGovernedDispatch(),
      throwsFormatException,
    );
  });

  for (final enrollment in ['pending', 'active', 'paused']) {
    testWidgets(
      '$enrollment installation requires one explicit local allowance',
      (tester) async {
        final platform = _LocalIntentGateway(_snapshot(enrollment: enrollment));
        await _open(tester, platform);
        expect(platform.calls, ['initialize']);
        expect(_allowWidget(tester).onPressed, isNotNull);
        expect(
          find.textContaining('server mode, limits and device controls'),
          findsOneWidget,
        );
        expect(find.text('Send SMS'), findsNothing);
        expect(find.text('Resume sending'), findsNothing);
        expect(find.text('New receipt sending is unavailable.'), findsNothing);
        if (enrollment == 'pending') {
          expect(
            find.text(
              'Enrollment document installed; device authority is unknown',
            ),
            findsOneWidget,
          );
          expect(find.text('Active device identity'), findsNothing);
        }
        await _tap(tester, 'Allow governed dispatch');
        await tester.pumpAndSettle();
        expect(platform.calls, ['initialize', 'allowGovernedDispatch']);
        expect(find.text('Local pause is off'), findsOneWidget);
        expect(_allowWidget(tester).onPressed, isNull);
        expect(find.text('Outcome unknown: 0'), findsOneWidget);
      },
    );
  }

  for (final enrollment in ['not_enrolled', 'revoked', 'unknown']) {
    testWidgets('$enrollment observations cannot allow local dispatch', (
      tester,
    ) async {
      final platform = _LocalIntentGateway(_snapshot(enrollment: enrollment));
      await _open(tester, platform);
      expect(_allowWidget(tester).onPressed, isNull);
      await _tap(tester, 'Allow governed dispatch');
      expect(platform.calls, ['initialize']);
      final pause = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Emergency pause'),
      );
      expect(pause.onPressed, isNotNull);
    });
  }

  testWidgets('unconfigured enrollment cannot clear pause', (tester) async {
    final platform = _LocalIntentGateway(_snapshot(configured: false));
    await _open(tester, platform);
    expect(_allowWidget(tester).onPressed, isNull);
    expect(
      find.text(
        'Install an enrollment document matching this installation before allowing governed dispatch.',
      ),
      findsOneWidget,
    );
    expect(platform.calls, ['initialize']);
  });

  testWidgets('already allowed observations never trigger another allowance', (
    tester,
  ) async {
    final platform = _LocalIntentGateway(_snapshot(paused: false));
    await _open(tester, platform);
    expect(_allowWidget(tester).onPressed, isNull);
    await _tap(tester, 'Refresh observations');
    await tester.pumpAndSettle();
    expect(platform.calls, ['initialize', 'status']);
    expect(find.text('Local pause is off'), findsOneWidget);
  });

  testWidgets('installing matching enrollment never implicitly clears pause', (
    tester,
  ) async {
    final platform = _LocalIntentGateway(
      _snapshot(enrollment: 'not_enrolled', configured: false),
    );
    await _open(tester, platform);
    await _tap(tester, 'Public identity and enrollment');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      jsonEncode({
        'contract_version': 1,
        'device_id': '00000000-0000-0000-0000-000000000002',
        'installation_id': '00000000-0000-0000-0000-000000000001',
        'key_sha256': 'a' * 64,
        'signing_certificate_sha256': 'b' * 64,
      }),
    );
    await tester.tap(find.text('Apply document'));
    await tester.pumpAndSettle();
    expect(platform.calls, ['initialize', 'identity', 'provisionEnrollment']);
    expect(find.text('Emergency pause is on'), findsOneWidget);
    expect(
      find.text('Enrollment document installed; device authority is unknown'),
      findsOneWidget,
    );
    expect(_allowWidget(tester).onPressed, isNotNull);
    await _tap(tester, 'Allow governed dispatch');
    await tester.pumpAndSettle();
    expect(platform.calls.last, 'allowGovernedDispatch');
    expect(find.text('Local pause is off'), findsOneWidget);
  });

  testWidgets('unknown initial observation has no enabled local allowance', (
    tester,
  ) async {
    final initial = Completer<GatewaySnapshot>();
    final platform = _LocalIntentGateway(_snapshot())
      ..initialResult = initial.future;
    await tester.pumpWidget(CollectGatewayApp(platform: platform));
    await tester.pump();
    expect(_allowButton, findsNothing);
    expect(platform.calls, ['initialize']);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Emergency pause'),
          )
          .onPressed,
      isNotNull,
    );
    initial.complete(platform.state);
    await tester.pumpAndSettle();
    expect(_allowWidget(tester).onPressed, isNotNull);
    expect(platform.calls, ['initialize']);
  });

  testWidgets(
    'rapid repeat activation sends one intent while waiting for receipt',
    (tester) async {
      final receipt = Completer<GatewaySnapshot>();
      final platform = _LocalIntentGateway(_snapshot())
        ..allowanceResult = receipt.future;
      await _open(tester, platform);
      await tester.ensureVisible(_allowButton);
      await tester.tap(_allowButton);
      await tester.tap(_allowButton);
      await tester.pump();
      expect(platform.calls, ['initialize', 'allowGovernedDispatch']);
      expect(_allowWidget(tester).onPressed, isNull);
      expect(find.text('Emergency pause is on'), findsOneWidget);
      receipt.complete(_snapshot(paused: false));
      await tester.pumpAndSettle();
      expect(find.text('Local pause is off'), findsOneWidget);
      expect(platform.calls, ['initialize', 'allowGovernedDispatch']);
    },
  );

  testWidgets('failed allowance is redacted and requires fresh observations', (
    tester,
  ) async {
    final receipt = Completer<GatewaySnapshot>();
    final platform = _LocalIntentGateway(_snapshot())
      ..allowanceResult = receipt.future;
    await _open(tester, platform);
    await _tap(tester, 'Allow governed dispatch');
    receipt.completeError(StateError('private synthetic enrollment digest'));
    await tester.pumpAndSettle();
    expect(find.textContaining('private synthetic'), findsNothing);
    expect(
      find.text(
        'Gateway status is unavailable. Check observations before allowing dispatch.',
      ),
      findsOneWidget,
    );
    expect(_allowWidget(tester).onPressed, isNull);
    expect(platform.calls, ['initialize', 'allowGovernedDispatch']);
    await _tap(tester, 'Check again');
    await tester.pumpAndSettle();
    expect(_allowWidget(tester).onPressed, isNotNull);
    expect(platform.calls, ['initialize', 'allowGovernedDispatch', 'status']);
  });

  for (final operation in ['health', 'reconcile']) {
    testWidgets('emergency pause wins over late $operation observations', (
      tester,
    ) async {
      final pending = Completer<GatewaySnapshot>();
      final platform = _LocalIntentGateway(_snapshot(paused: false));
      if (operation == 'health') {
        platform.healthResult = pending.future;
      } else {
        platform.reconciliationResult = pending.future;
      }
      await _open(tester, platform);
      await _tap(
        tester,
        operation == 'health'
            ? 'Record connection health'
            : 'Reconcile pending evidence',
      );
      expect(_allowWidget(tester).onPressed, isNull);
      await _tap(tester, 'Emergency pause');
      expect(find.text('Emergency pause is on'), findsOneWidget);
      expect(_allowWidget(tester).onPressed, isNull);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      pending.complete(_snapshot(paused: false));
      await tester.pumpAndSettle();
      expect(find.text('Emergency pause is on'), findsOneWidget);
      expect(find.text('Local pause is off'), findsNothing);
      expect(_allowWidget(tester).onPressed, isNotNull);
      expect(platform.calls, [
        'initialize',
        operation == 'health' ? 'heartbeat' : 'reconcile',
        'pause',
      ]);
    });
  }

  testWidgets('new emergency pause also wins over a late allowance receipt', (
    tester,
  ) async {
    final pending = Completer<GatewaySnapshot>();
    final platform = _LocalIntentGateway(_snapshot())
      ..allowanceResult = pending.future;
    await _open(tester, platform);
    await _tap(tester, 'Allow governed dispatch');
    await _tap(tester, 'Emergency pause');
    expect(_allowWidget(tester).onPressed, isNull);
    pending.complete(_snapshot(paused: false));
    await tester.pumpAndSettle();
    expect(find.text('Emergency pause is on'), findsOneWidget);
    expect(find.text('Local pause is off'), findsNothing);
    expect(_allowWidget(tester).onPressed, isNotNull);
    expect(platform.calls, ['initialize', 'allowGovernedDispatch', 'pause']);
  });

  testWidgets(
    'old network failure does not replace a successful emergency pause',
    (tester) async {
      final pending = Completer<GatewaySnapshot>();
      final platform = _LocalIntentGateway(_snapshot(paused: false))
        ..healthResult = pending.future;
      await _open(tester, platform);
      await _tap(tester, 'Record connection health');
      await _tap(tester, 'Emergency pause');
      pending.completeError(StateError('private synthetic network response'));
      await tester.pumpAndSettle();
      expect(find.text('Emergency pause is on'), findsOneWidget);
      expect(
        find.textContaining('Gateway status is unavailable.'),
        findsNothing,
      );
      expect(find.textContaining('private synthetic'), findsNothing);
      expect(_allowWidget(tester).onPressed, isNotNull);
    },
  );

  testWidgets(
    'allowance receipt after widget removal never mutates disposed UI',
    (tester) async {
      final pending = Completer<GatewaySnapshot>();
      final platform = _LocalIntentGateway(_snapshot())
        ..allowanceResult = pending.future;
      await _open(tester, platform);
      await _tap(tester, 'Allow governed dispatch');
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete(_snapshot(paused: false));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(platform.calls, ['initialize', 'allowGovernedDispatch']);
    },
  );

  testWidgets('narrow large-text local intent stays readable and named', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    try {
      final platform = _LocalIntentGateway(_snapshot());
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: GatewayHome(platform: platform),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(_allowButton);
      expect(tester.takeException(), isNull);
      expect(
        tester.getSemantics(_allowButton).getSemanticsData().label,
        contains('Allow governed dispatch'),
      );
      expect(_allowWidget(tester).onPressed, isNotNull);
      expect(platform.calls, ['initialize']);
    } finally {
      semantics.dispose();
    }
  });
}
