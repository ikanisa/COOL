import 'dart:async';

import 'package:collect_app/gateway/gateway_app.dart';
import 'package:collect_app/gateway/gateway_platform.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<Object?, Object?> status() => {
  'enrollment': 'not_enrolled',
  'emergency_paused': true,
  'configured': false,
  'send_sms_permission': false,
  'read_phone_state_permission': false,
  'network_connected': false,
  'network_validated': false,
  'sim_ready': false,
  'telephony_in_service': false,
  'subscription_selected': false,
  'outcome_unknown_attempts': 0,
  'framework_sent_attempts': 0,
  'delivery_callback_attempts': 0,
  'reason_code': 'gateway_not_enrolled',
};

class FakeGateway implements GatewayPlatform {
  Future<GatewaySnapshot>? initial;
  bool failInitialization = false;
  int pauses = 0, health = 0, reconciliation = 0, provisions = 0;
  int dispatchAllowances = 0;
  final state = GatewaySnapshot.fromMap(status());
  @override
  Future<GatewaySnapshot> initialize() async {
    if (failInitialization) {
      throw StateError('private synthetic token recipient message');
    }
    return await (initial ?? Future.value(state));
  }

  @override
  Future<GatewaySnapshot> refresh() async => state;
  @override
  Future<GatewaySnapshot> pause() async {
    pauses++;
    return state;
  }

  @override
  Future<GatewaySnapshot> allowGovernedDispatch() async {
    dispatchAllowances++;
    return state;
  }

  @override
  Future<GatewaySnapshot> requestPermissions() async => state;
  @override
  Future<GatewaySnapshot> heartbeat() async {
    health++;
    return state;
  }

  @override
  Future<GatewaySnapshot> reconcile() async {
    reconciliation++;
    return state;
  }

  @override
  Future<Map<Object?, Object?>> identity() async => {
    'contract_version': 1,
    'installation_id': '00000000-0000-0000-0000-000000000001',
    'key_sha256': 'a' * 64,
    'signing_certificate_sha256': 'b' * 64,
    'public_key_spki_base64': 'synthetic public identity only',
  };
  @override
  Future<GatewaySnapshot> provisionEnrollment(
    Map<String, Object?> document,
  ) async {
    provisions++;
    return state;
  }
}

void main() {
  test('strict native observations never coerce booleans or numbers', () {
    for (final entry in (<String, Object>{
      'send_sms_permission': 1,
      'framework_sent_attempts': '0',
      'enrollment': 'demo',
      'reason_code': 'raw backend private error',
    }).entries) {
      expect(
        () => GatewaySnapshot.fromMap(status()..[entry.key] = entry.value),
        throwsFormatException,
      );
    }
  });
  test('unknown keys and oversized aggregates fail closed', () {
    expect(
      () => GatewaySnapshot.fromMap(status()..['raw_sms'] = 'forbidden'),
      throwsFormatException,
    );
    expect(
      () =>
          GatewaySnapshot.fromMap(status()..['outcome_unknown_attempts'] = 101),
      throwsFormatException,
    );
  });
  test('delivery and network evidence contradictions fail closed', () {
    expect(
      () =>
          GatewaySnapshot.fromMap(status()..['delivery_callback_attempts'] = 1),
      throwsFormatException,
    );
    expect(
      () => GatewaySnapshot.fromMap(status()..['network_validated'] = true),
      throwsFormatException,
    );
    expect(
      () => GatewaySnapshot.fromMap(status()..['sim_ready'] = true),
      throwsFormatException,
    );
  });
  test('unknown attempts remain independent from framework sent evidence', () {
    final result = GatewaySnapshot.fromMap(
      status()
        ..['outcome_unknown_attempts'] = 2
        ..['framework_sent_attempts'] = 3
        ..['delivery_callback_attempts'] = 1,
    );
    expect(result.pendingAttempts, 2);
    expect(result.frameworkSentAttempts, 3);
    expect(result.deliveryCallbacksObserved, 1);
  });
  testWidgets(
    'initial offline installation disables all network operations and exposes no send override',
    (tester) async {
      final platform = FakeGateway();
      await tester.pumpWidget(CollectGatewayApp(platform: platform));
      await tester.pumpAndSettle();
      expect(find.text('Owner enrollment required'), findsOneWidget);
      expect(find.byTooltip('Back'), findsNothing);
      expect(find.text('Emergency pause is on'), findsOneWidget);
      expect(find.text('Resume sending'), findsNothing);
      expect(find.text('Send SMS'), findsNothing);
      expect(platform.health, 0);
      expect(platform.reconciliation, 0);
      final health = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Record connection health'),
      );
      expect(health.onPressed, isNull);
    },
  );
  testWidgets('emergency pause remains reachable during loading', (
    tester,
  ) async {
    final pending = Completer<GatewaySnapshot>();
    final platform = FakeGateway()..initial = pending.future;
    await tester.pumpWidget(CollectGatewayApp(platform: platform));
    await tester.pump();
    await tester.tap(find.text('Emergency pause'));
    await tester.pump();
    expect(platform.pauses, 1);
    pending.complete(platform.state);
    await tester.pumpAndSettle();
  });
  testWidgets(
    'initial native failure keeps emergency pause and redacts private errors',
    (tester) async {
      final platform = FakeGateway()..failInitialization = true;
      await tester.pumpWidget(CollectGatewayApp(platform: platform));
      await tester.pumpAndSettle();
      expect(find.textContaining('private synthetic'), findsNothing);
      expect(
        find.text(
          'Gateway status is unavailable. Check observations before allowing dispatch.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Emergency pause'));
      await tester.pumpAndSettle();
      expect(platform.pauses, 1);
    },
  );
  testWidgets(
    'narrow layout and large text keep independent observations readable',
    (tester) async {
      tester.view.resetPhysicalSize();
      tester.view.physicalSize = const Size(320, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: GatewayHome(platform: FakeGateway()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Internet validated'), findsOneWidget);
      expect(find.text('SIM selected'), findsOneWidget);
    },
  );
  testWidgets(
    'public enrollment UI has no body, recipient or arbitrary host controls',
    (tester) async {
      final platform = FakeGateway();
      await tester.pumpWidget(CollectGatewayApp(platform: platform));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Public identity and enrollment'));
      await tester.tap(find.text('Public identity and enrollment'));
      await tester.pumpAndSettle();
      expect(find.text('Enroll this installation'), findsOneWidget);
      expect(find.text('Copy public identity'), findsOneWidget);
      expect(find.text('Owner enrollment document'), findsOneWidget);
      expect(find.text('Message body'), findsNothing);
      expect(find.text('Recipient'), findsNothing);
      expect(find.text('Backend URL'), findsNothing);
      await tester.enterText(
        find.byType(TextField),
        '{"contract_version":1,"device_id":"manual-bogus"}',
      );
      await tester.tap(find.text('Apply document'));
      await tester.pump();
      expect(platform.provisions, 0);
    },
  );
}
