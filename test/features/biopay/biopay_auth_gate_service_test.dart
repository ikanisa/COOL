import 'package:cool_app/features/biopay/services/biopay_auth_gate_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

class FakeBiopayAuthAdapter implements BiopayAuthAdapter {
  FakeBiopayAuthAdapter({
    this.isSupported = true,
    this.authenticateResult = true,
    this.authenticateError,
  });

  final bool isSupported;
  final bool authenticateResult;
  final Object? authenticateError;

  String? lastLocalizedReason;
  bool? lastBiometricOnly;
  bool? lastSensitiveTransaction;
  bool? lastPersistAcrossBackgrounding;
  int authenticateCalls = 0;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) async {
    authenticateCalls += 1;
    lastLocalizedReason = localizedReason;
    lastBiometricOnly = biometricOnly;
    lastSensitiveTransaction = sensitiveTransaction;
    lastPersistAcrossBackgrounding = persistAcrossBackgrounding;

    final error = authenticateError;
    if (error != null) {
      throw error;
    }

    return authenticateResult;
  }

  @override
  Future<bool> isDeviceSupported() async => isSupported;
}

void main() {
  group('BiopayAuthGateService', () {
    test('authorizes enrollment when device auth succeeds', () async {
      final adapter = FakeBiopayAuthAdapter();
      final service = BiopayAuthGateService(adapter: adapter);

      final result = await service.authorize(BiopayAuthAction.enrollment);

      expect(result.status, BiopayAuthGateStatus.authorized);
      expect(result.isAuthorized, isTrue);
      expect(adapter.authenticateCalls, 1);
      expect(
        adapter.lastLocalizedReason,
        'Confirm your identity before BioPay saves this face enrollment.',
      );
      expect(adapter.lastBiometricOnly, isFalse);
      expect(adapter.lastSensitiveTransaction, isTrue);
      expect(adapter.lastPersistAcrossBackgrounding, isTrue);
    });

    test('returns unavailable when no device auth is configured', () async {
      final service = BiopayAuthGateService(
        adapter: FakeBiopayAuthAdapter(isSupported: false),
      );

      final result = await service.authorize(BiopayAuthAction.revocation);

      expect(result.status, BiopayAuthGateStatus.unavailable);
      expect(
        result.message,
        'Set up Face ID, fingerprint, or a device passcode before using BioPay.',
      );
    });

    test('returns locked out when local auth is locked', () async {
      final service = BiopayAuthGateService(
        adapter: FakeBiopayAuthAdapter(
          authenticateError: const LocalAuthException(
            code: LocalAuthExceptionCode.temporaryLockout,
          ),
        ),
      );

      final result = await service.authorize(BiopayAuthAction.paymentHandoff);

      expect(result.status, BiopayAuthGateStatus.lockedOut);
      expect(
        result.message,
        'Device authentication is locked right now. Unlock your device and try again.',
      );
    });

    test('treats a false auth result as user cancellation', () async {
      final service = BiopayAuthGateService(
        adapter: FakeBiopayAuthAdapter(authenticateResult: false),
      );

      final result = await service.authorize(BiopayAuthAction.paymentHandoff);

      expect(result.status, BiopayAuthGateStatus.canceled);
      expect(
        result.message,
        'BioPay payment handoff was canceled before identity confirmation completed.',
      );
    });
  });
}
