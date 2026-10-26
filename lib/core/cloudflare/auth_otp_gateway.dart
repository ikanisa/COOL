import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cloudflare_module.dart';

/// Enable only for releases whose WhatsApp delivery provider has been configured
/// and verified. Availability is independent of a fixture or an identity value.
final collectWhatsAppAuthEnabledProvider = Provider<bool>((ref) {
  return const bool.fromEnvironment(
    'COLLECT_WHATSAPP_AUTH_ENABLED',
    defaultValue: false,
  );
});

abstract interface class AuthOtpGateway {
  bool get whatsAppSignInAvailable;
  Future<void> sendWhatsAppOtp({required String phone, String? captchaToken});

  Future<void> verifyWhatsAppOtp({
    required String phone,
    required String otp,
    String? captchaToken,
  });
}

abstract interface class AuthOtpRequestReceiptGateway {
  Future<CollectOtpRequestReceipt> requestWhatsAppOtpReceipt({
    required String phone,
    String? captchaToken,
  });
}

final authOtpGatewayProvider = Provider<AuthOtpGateway?>((ref) {
  final client = ref.watch(collectBackendClientProvider);
  return client == null
      ? null
      : CollectAuthOtpGateway(
          client,
          whatsAppSignInEnabled: ref.watch(collectWhatsAppAuthEnabledProvider),
        );
});

class CollectAuthOtpGateway
    implements AuthOtpGateway, AuthOtpRequestReceiptGateway {
  const CollectAuthOtpGateway(
    this._client, {
    bool whatsAppSignInEnabled = false,
  }) : whatsAppSignInAvailable = whatsAppSignInEnabled;

  @override
  final bool whatsAppSignInAvailable;

  final CollectCloudflareClient _client;

  @override
  Future<void> sendWhatsAppOtp({
    required String phone,
    String? captchaToken,
  }) async {
    await requestWhatsAppOtpReceipt(phone: phone, captchaToken: captchaToken);
  }

  @override
  Future<CollectOtpRequestReceipt> requestWhatsAppOtpReceipt({
    required String phone,
    String? captchaToken,
  }) {
    if (!whatsAppSignInAvailable) {
      return Future.error(
        const CollectAuthException(
          'WhatsApp sign-in is unavailable.',
          code: 'whatsapp_unavailable',
          statusCode: '503',
        ),
      );
    }
    return _client.auth.signInWithOtp(
      phone: phone,
      channel: CollectOtpChannel.whatsapp,
      captchaToken: captchaToken,
    );
  }

  @override
  Future<void> verifyWhatsAppOtp({
    required String phone,
    required String otp,
    String? captchaToken,
  }) {
    if (!whatsAppSignInAvailable) {
      return Future.error(
        const CollectAuthException(
          'WhatsApp sign-in is unavailable.',
          code: 'whatsapp_unavailable',
          statusCode: '503',
        ),
      );
    }
    return _client.auth.verifyOTP(
      phone: phone,
      token: otp,
      type: CollectOtpType.sms,
      captchaToken: captchaToken,
    );
  }
}
