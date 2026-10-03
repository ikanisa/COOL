import 'dart:async';
import 'dart:convert';

import 'package:collect_app/gateway/gateway_app.dart';
import 'package:collect_app/gateway/gateway_platform.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'gateway_safety_test.dart' show FakeGateway;

class _DeferredEnrollmentGateway extends FakeGateway {
  final receipt = Completer<GatewaySnapshot>();
  Map<String, Object?>? document;

  @override
  Future<GatewaySnapshot> provisionEnrollment(Map<String, Object?> document) {
    provisions++;
    this.document = Map<String, Object?>.from(document);
    return receipt.future;
  }
}

Future<void> _openEnrollment(WidgetTester tester, FakeGateway platform) async {
  await tester.pumpWidget(CollectGatewayApp(platform: platform));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Public identity and enrollment'));
  await tester.tap(find.text('Public identity and enrollment'));
  await tester.pumpAndSettle();
  expect(find.text('Enroll this installation'), findsOneWidget);
}

Future<String> _document(FakeGateway platform) async {
  final identity = await platform.identity();
  return jsonEncode({
    'contract_version': identity['contract_version'],
    'device_id': '00000000-0000-0000-0000-000000000002',
    'installation_id': identity['installation_id'],
    'key_sha256': identity['key_sha256'],
    'signing_certificate_sha256': identity['signing_certificate_sha256'],
  });
}

Future<void> _exitFrames(WidgetTester tester) async {
  for (final duration in [
    Duration.zero,
    const Duration(milliseconds: 50),
    const Duration(milliseconds: 100),
    const Duration(milliseconds: 250),
  ]) {
    await tester.pump(duration);
    expect(tester.takeException(), isNull);
  }
  expect(find.text('Enroll this installation'), findsNothing);
}

void main() {
  testWidgets('Close preserves editable input through the real exit frames', (
    tester,
  ) async {
    final platform = FakeGateway();
    await _openEnrollment(tester, platform);
    await tester.enterText(find.byType(TextField), 'unfinished local document');
    await tester.tap(find.text('Close'));
    await _exitFrames(tester);
    expect(platform.provisions, 0);
    await tester.ensureVisible(find.text('Public identity and enrollment'));
    await tester.tap(find.text('Public identity and enrollment'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    await tester.tap(find.text('Close'));
    await _exitFrames(tester);
  });

  testWidgets('fast enrollment ACK does not dispose the animating input', (
    tester,
  ) async {
    final platform = FakeGateway();
    await _openEnrollment(tester, platform);
    await tester.enterText(find.byType(TextField), await _document(platform));
    await tester.tap(find.text('Apply document'));
    await _exitFrames(tester);
    expect(platform.provisions, 1);
  });

  testWidgets('delayed ACK leaves one exact enrollment request after exit', (
    tester,
  ) async {
    final platform = _DeferredEnrollmentGateway();
    await _openEnrollment(tester, platform);
    final text = await _document(platform);
    await tester.enterText(find.byType(TextField), text);
    await tester.tap(find.text('Apply document'));
    await _exitFrames(tester);
    expect(platform.provisions, 1);
    expect(platform.document, jsonDecode(text));
    platform.receipt.complete(platform.state);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(platform.provisions, 1);
  });

  testWidgets('late enrollment failure after route removal stays redacted', (
    tester,
  ) async {
    final platform = _DeferredEnrollmentGateway();
    await _openEnrollment(tester, platform);
    await tester.enterText(find.byType(TextField), await _document(platform));
    await tester.tap(find.text('Apply document'));
    await _exitFrames(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    platform.receipt.completeError(
      StateError('private synthetic enrollment receipt'),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('private synthetic'), findsNothing);
    expect(platform.provisions, 1);
  });
}
