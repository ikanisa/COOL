import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_module.dart';

abstract interface class AuthOtpGateway {
  Future<void> sendWhatsAppOtp({required String phone, String? captchaToken});

  Future<void> verifyWhatsAppOtp({
    required String phone,
    required String otp,
    String? captchaToken,
  });
}

final authOtpGatewayProvider = Provider<AuthOtpGateway?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseAuthOtpGateway(client);
});

class SupabaseAuthOtpGateway implements AuthOtpGateway {
  const SupabaseAuthOtpGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<void> sendWhatsAppOtp({required String phone, String? captchaToken}) {
    return _client.auth.signInWithOtp(
      phone: phone,
      channel: OtpChannel.whatsapp,
      captchaToken: captchaToken,
    );
  }

  @override
  Future<void> verifyWhatsAppOtp({
    required String phone,
    required String otp,
    String? captchaToken,
  }) {
    return _client.auth.verifyOTP(
      phone: phone,
      token: otp,
      type: OtpType.sms,
      captchaToken: captchaToken,
    );
  }
}
