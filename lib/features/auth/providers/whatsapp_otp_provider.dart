import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/supabase_client_provider.dart';
import '../../../core/services/whatsapp_otp_service.dart';

export '../../../core/services/whatsapp_otp_service.dart'
    show OtpSendResult, OtpVerifyResult, OtpSendStatus, OtpVerifyStatus;

/// Singleton service provider.
final whatsAppOtpServiceProvider = Provider<WhatsAppOtpService>((ref) {
  return WhatsAppOtpService(client: ref.read(supabaseClientProvider));
});

/// Reactive OTP flow state.
final whatsAppOtpStateProvider =
    AutoDisposeNotifierProvider<WhatsAppOtpNotifier, WhatsAppOtpState>(
      WhatsAppOtpNotifier.new,
    );

enum WhatsAppOtpStep { enterPhone, verifyCode }

class WhatsAppOtpState {
  const WhatsAppOtpState({
    this.step = WhatsAppOtpStep.enterPhone,
    this.phone = '',
    this.isLoading = false,
    this.error,
    this.codeSent = false,
    this.verifyResult,
    this.retryAfterSeconds,
    this.attemptsRemaining,
  });

  final WhatsAppOtpStep step;
  final String phone;
  final bool isLoading;
  final String? error;
  final bool codeSent;
  final OtpVerifyResult? verifyResult;
  final int? retryAfterSeconds;
  final int? attemptsRemaining;

  bool get isVerified => verifyResult?.isVerified ?? false;

  WhatsAppOtpState copyWith({
    WhatsAppOtpStep? step,
    String? phone,
    bool? isLoading,
    String? error,
    bool clearError = false,
    bool? codeSent,
    OtpVerifyResult? verifyResult,
    int? retryAfterSeconds,
    bool clearRetryAfter = false,
    int? attemptsRemaining,
    bool clearAttemptsRemaining = false,
  }) {
    return WhatsAppOtpState(
      step: step ?? this.step,
      phone: phone ?? this.phone,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      codeSent: codeSent ?? this.codeSent,
      verifyResult: verifyResult ?? this.verifyResult,
      retryAfterSeconds: clearRetryAfter
          ? null
          : (retryAfterSeconds ?? this.retryAfterSeconds),
      attemptsRemaining: clearAttemptsRemaining
          ? null
          : (attemptsRemaining ?? this.attemptsRemaining),
    );
  }
}

class WhatsAppOtpNotifier extends AutoDisposeNotifier<WhatsAppOtpState> {
  late final WhatsAppOtpService _service;

  @override
  WhatsAppOtpState build() {
    _service = ref.read(whatsAppOtpServiceProvider);
    return const WhatsAppOtpState();
  }

  void reset() => state = const WhatsAppOtpState();

  void goBackToPhone() => state = WhatsAppOtpState(phone: state.phone);

  Future<void> sendCode(String e164Phone) async {
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      phone: e164Phone,
      clearRetryAfter: true,
      clearAttemptsRemaining: true,
    );

    final result = await _service.sendOtp(e164Phone);

    // Guard against the notifier being disposed during the async gap.
    try {
      if (result.isSent) {
        state = state.copyWith(
          isLoading: false,
          codeSent: true,
          step: WhatsAppOtpStep.verifyCode,
          clearRetryAfter: true,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          error: result.message ?? 'Failed to send OTP',
          retryAfterSeconds: result.retryAfterSeconds,
          clearAttemptsRemaining: true,
        );
      }
    } on StateError catch (_) {
      // Notifier was disposed — ignore.
    }
  }

  Future<OtpVerifyResult> verifyCode(String code) async {
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearAttemptsRemaining: true,
    );

    final result = await _service.verifyOtp(state.phone, code);

    // Guard against the notifier being disposed during the async gap.
    try {
      if (result.isVerified) {
        state = state.copyWith(
          isLoading: false,
          verifyResult: result,
          clearAttemptsRemaining: true,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          error: result.message ?? 'Invalid OTP',
          attemptsRemaining: result.attemptsRemaining,
        );
      }
    } on StateError catch (_) {
      // Notifier was disposed — ignore.
    }

    return result;
  }
}
