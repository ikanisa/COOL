import 'package:local_auth/local_auth.dart';

enum BiopayAuthAction { enrollment, revocation, paymentHandoff }

enum BiopayAuthGateStatus {
  authorized,
  unavailable,
  canceled,
  lockedOut,
  failed,
}

class BiopayAuthGateResult {
  const BiopayAuthGateResult._({required this.status, required this.message});

  const BiopayAuthGateResult.authorized()
    : this._(status: BiopayAuthGateStatus.authorized, message: '');

  const BiopayAuthGateResult.unavailable(String message)
    : this._(status: BiopayAuthGateStatus.unavailable, message: message);

  const BiopayAuthGateResult.canceled(String message)
    : this._(status: BiopayAuthGateStatus.canceled, message: message);

  const BiopayAuthGateResult.lockedOut(String message)
    : this._(status: BiopayAuthGateStatus.lockedOut, message: message);

  const BiopayAuthGateResult.failed(String message)
    : this._(status: BiopayAuthGateStatus.failed, message: message);

  final BiopayAuthGateStatus status;
  final String message;

  bool get isAuthorized => status == BiopayAuthGateStatus.authorized;
}

abstract class BiopayAuthAdapter {
  Future<bool> isDeviceSupported();

  Future<bool> authenticate({
    required String localizedReason,
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  });
}

class LocalAuthBiopayAuthAdapter implements BiopayAuthAdapter {
  LocalAuthBiopayAuthAdapter({LocalAuthentication? localAuthentication})
    : _localAuthentication = localAuthentication ?? LocalAuthentication();

  final LocalAuthentication _localAuthentication;

  @override
  Future<bool> isDeviceSupported() {
    return _localAuthentication.isDeviceSupported();
  }

  @override
  Future<bool> authenticate({
    required String localizedReason,
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) {
    return _localAuthentication.authenticate(
      localizedReason: localizedReason,
      biometricOnly: biometricOnly,
      sensitiveTransaction: sensitiveTransaction,
      persistAcrossBackgrounding: persistAcrossBackgrounding,
    );
  }
}

class BiopayAuthGateService {
  BiopayAuthGateService({BiopayAuthAdapter? adapter})
    : _adapter = adapter ?? LocalAuthBiopayAuthAdapter();

  final BiopayAuthAdapter _adapter;

  Future<BiopayAuthGateResult> authorize(BiopayAuthAction action) async {
    try {
      final supported = await _adapter.isDeviceSupported();
      if (!supported) {
        return const BiopayAuthGateResult.unavailable(
          'Set up Face ID, fingerprint, or a device passcode before using BioPay.',
        );
      }

      final authenticated = await _adapter.authenticate(
        localizedReason: action.localizedReason,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: true,
      );
      if (authenticated) {
        return const BiopayAuthGateResult.authorized();
      }

      return BiopayAuthGateResult.canceled(action.canceledMessage);
    } on LocalAuthException catch (error) {
      return switch (error.code) {
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable ||
        LocalAuthExceptionCode
            .uiUnavailable => const BiopayAuthGateResult.unavailable(
          'Set up Face ID, fingerprint, or a device passcode before using BioPay.',
        ),
        LocalAuthExceptionCode.temporaryLockout ||
        LocalAuthExceptionCode
            .biometricLockout => const BiopayAuthGateResult.lockedOut(
          'Device authentication is locked right now. Unlock your device and try again.',
        ),
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.timeout ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.userRequestedFallback =>
          BiopayAuthGateResult.canceled(action.canceledMessage),
        _ => BiopayAuthGateResult.failed(
          error.description?.trim().isNotEmpty == true
              ? error.description!.trim()
              : action.failureMessage,
        ),
      };
    } catch (_) {
      return BiopayAuthGateResult.failed(action.failureMessage);
    }
  }
}

extension on BiopayAuthAction {
  String get localizedReason => switch (this) {
    BiopayAuthAction.enrollment =>
      'Confirm your identity before BioPay saves this face enrollment.',
    BiopayAuthAction.revocation =>
      'Confirm your identity before BioPay revokes this face enrollment.',
    BiopayAuthAction.paymentHandoff =>
      'Confirm your identity before BioPay opens the MoMo dialer.',
  };

  String get canceledMessage => switch (this) {
    BiopayAuthAction.enrollment =>
      'BioPay enrollment was canceled before identity confirmation completed.',
    BiopayAuthAction.revocation =>
      'BioPay revocation was canceled before identity confirmation completed.',
    BiopayAuthAction.paymentHandoff =>
      'BioPay payment handoff was canceled before identity confirmation completed.',
  };

  String get failureMessage => switch (this) {
    BiopayAuthAction.enrollment =>
      'BioPay could not verify your identity for enrollment. Try again.',
    BiopayAuthAction.revocation =>
      'BioPay could not verify your identity for revocation. Try again.',
    BiopayAuthAction.paymentHandoff =>
      'BioPay could not verify your identity before opening the MoMo dialer. Try again.',
  };
}
