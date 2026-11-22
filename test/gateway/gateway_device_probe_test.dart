import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/gateway_device_probe.dart';
import 'package:collect_app/gateway/gateway_platform.dart';

class _ProbePlatform implements GatewayPlatform {
  final calls = <String>[];
  bool configured = false;
  bool paused = true;
  bool changeIdentity = false;
  bool changeAttempt = false;
  String? invalidKeyEncoding;
  int identities = 0;
  GatewaySnapshot snapshot([int pending = 0]) => GatewaySnapshot(
    enrollment: GatewayEnrollment.notEnrolled,
    paused: paused,
    configured: configured,
    sendPermission: false,
    phonePermission: false,
    networkConnected: true,
    networkValidated: false,
    simReady: false,
    telephonyInService: false,
    subscriptionSelected: false,
    pendingAttempts: pending,
    frameworkSentAttempts: 0,
    deliveryCallbacksObserved: 0,
    reasonCode: 'gateway_not_enrolled',
  );
  @override
  Future<GatewaySnapshot> initialize() async {
    calls.add('initialize');
    return snapshot();
  }

  @override
  Future<GatewaySnapshot> refresh() async {
    calls.add('status');
    return snapshot(changeAttempt ? 1 : 0);
  }

  @override
  Future<Map<Object?, Object?>> identity() async {
    calls.add('identity');
    return {
      'contract_version': 1,
      'installation_id': changeIdentity && identities++ > 0
          ? '20000000-0000-0000-0000-000000000001'
          : '10000000-0000-0000-0000-000000000001',
      'key_sha256': sha256.convert([1, 2, 3]).toString(),
      'signing_certificate_sha256': List.filled(64, 'a').join(),
      'public_key_spki_base64': invalidKeyEncoding ?? base64Encode([1, 2, 3]),
    };
  }

  // Calling any live/permission/enrollment seam makes these synthetic tests fail.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Forbidden probe operation ${invocation.memberName}');
}

void main() {
  test(
    'invalid public-key encoding is bounded and errors remain redacted',
    () async {
      for (final encoded in [
        'private-placeholder%',
        List.filled(2049, 'a').join(),
      ]) {
        final platform = _ProbePlatform()..invalidKeyEncoding = encoded;
        await expectLater(
          observeGatewayWithoutSending(platform),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'redacted reason',
              'gateway_probe_identity_invalid',
            ),
          ),
        );
        expect(platform.calls, ['initialize', 'identity', 'identity']);
      }
    },
  );
  test(
    'probe uses only local methods and redacts identity with independent flags',
    () async {
      final platform = _ProbePlatform();
      final report = await observeGatewayWithoutSending(platform);
      expect(platform.calls, ['initialize', 'identity', 'identity', 'status']);
      expect(report['network_connected'], isTrue);
      expect(report['network_validated'], isFalse);
      expect(report['send_sms_permission'], isFalse);
      expect(report['physical_acceptance'], isFalse);
      expect(report['backend_calls'], 0);
      expect(report.keys, isNot(contains('installation_id')));
      expect(report.keys, isNot(contains('public_key_spki_base64')));
      expect(report.keys, isNot(contains('key_sha256')));
    },
  );
  test(
    'configured and unpaused builds refuse before identity or status',
    () async {
      for (final platform in [
        _ProbePlatform()..configured = true,
        _ProbePlatform()..paused = false,
      ]) {
        await expectLater(
          observeGatewayWithoutSending(platform),
          throwsFormatException,
        );
        expect(platform.calls, ['initialize']);
      }
    },
  );
  test('changed identity refuses before status without any replay', () async {
    final platform = _ProbePlatform()..changeIdentity = true;
    await expectLater(
      observeGatewayWithoutSending(platform),
      throwsFormatException,
    );
    expect(platform.calls, ['initialize', 'identity', 'identity']);
  });
  test(
    'a changed attempt counter remains a failure without mutating the journal',
    () async {
      final platform = _ProbePlatform()..changeAttempt = true;
      await expectLater(
        observeGatewayWithoutSending(platform),
        throwsFormatException,
      );
      expect(platform.calls, ['initialize', 'identity', 'identity', 'status']);
    },
  );
}
