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

/// SMS uses the self-hosted Auth send hook and its independently qualified
/// transport. It never silently falls back to WhatsApp (or vice versa).
final collectSmsAuthEnabledProvider = Provider<bool>((ref) {
  return const bool.fromEnvironment(
    'COLLECT_SMS_AUTH_ENABLED',
    defaultValue: false,
  );
});

abstract interface class AuthSmsOtpGateway {
  bool get smsSignInAvailable;
  Future<CollectOtpRequestReceipt> requestSmsOtpReceipt({
    required String phone,
    String? captchaToken,
  });
  Future<void> verifySmsOtp({
    required String phone,
    required String otp,
    String? captchaToken,
  });
}

abstract interface class AuthOtpCancellationGateway {
  void cancelOtpSignIn();
}

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
          smsSignInEnabled: ref.watch(collectSmsAuthEnabledProvider),
        );
});

class CollectAuthOtpGateway
    implements
        AuthOtpGateway,
        AuthOtpRequestReceiptGateway,
        AuthSmsOtpGateway,
        AuthOtpCancellationGateway {
  const CollectAuthOtpGateway(
    this._client, {
    bool whatsAppSignInEnabled = false,
    bool smsSignInEnabled = false,
  }) : whatsAppSignInAvailable = whatsAppSignInEnabled,
       smsSignInAvailable = smsSignInEnabled;

  @override
  final bool whatsAppSignInAvailable;

  @override
  final bool smsSignInAvailable;

  final CollectCloudflareClient _client;

  @override
  void cancelOtpSignIn() => _client.auth.cancelOtpSignIn();

  @override
  Future<CollectOtpRequestReceipt> requestSmsOtpReceipt({
    required String phone,
    String? captchaToken,
  }) {
    if (!smsSignInAvailable) {
      return Future.error(
        const CollectAuthException(
          'SMS sign-in is unavailable.',
          code: 'sms_unavailable',
          statusCode: '503',
        ),
      );
    }
    return _client.auth.signInWithOtp(
      phone: phone,
      channel: CollectOtpChannel.sms,
      captchaToken: captchaToken,
    );
  }

  @override
  Future<void> verifySmsOtp({
    required String phone,
    required String otp,
    String? captchaToken,
  }) {
    if (!smsSignInAvailable) {
      return Future.error(
        const CollectAuthException(
          'SMS sign-in is unavailable.',
          code: 'sms_unavailable',
          statusCode: '503',
        ),
      );
    }
    return _client.auth.verifyOTP(
      phone: phone,
      token: otp,
      type: CollectOtpType.sms,
      channel: CollectOtpChannel.sms,
      captchaToken: captchaToken,
    );
  }

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
      channel: CollectOtpChannel.whatsapp,
      captchaToken: captchaToken,
    );
  }
}
