import '../../core/cloudflare/collect_cloudflare_types.dart';

String authErrorMessage(Object error, String method) {
  if (error is CollectOtpDeliveryUnknownException) {
    return 'Delivery could not be confirmed. If a code arrives, enter it here before requesting another.';
  }
  const failed = 'Sign-in failed. Try again.';
  const securityFailed = 'Security verification could not finish. Try again.';
  final unavailable =
      '$method sign-in is unavailable right now. Try again later.';
  final codeMethod = method == 'Email' ? 'email' : method;
  final invalidCode =
      'That $codeMethod code is invalid or expired. Request a fresh code and try again.';
  if (error is CollectAuthException) {
    if (error.code == 'guest_upgrade_unknown' ||
        error.code == 'guest_upgrade_busy') {
      return 'Your account verification was not confirmed. Check the existing verification before requesting or entering another code.';
    }
    if (error.code == 'identity_already_exists') {
      return 'This email address or phone number already has an account. Choose Use another account to sign in to it. Accounts are kept separate.';
    }
    if (error.code == 'guest_otp_rejected') {
      return 'That verification code was rejected. Check the code or request a fresh one.';
    }
    if (error.code == 'google_use_email_sign_in') {
      return 'Use email sign-in to verify this Google account’s email address.';
    }
    if (error.code == 'google_popup_blocked') {
      return 'Allow the sign-in window in your browser, then try Google again.';
    }
    if (error.code?.startsWith('google_') == true ||
        error.code == 'invalid_google_sign_in') {
      return 'Google sign-in could not finish. Try again or use another sign-in method.';
    }
    if (error.statusCode == '429' || error.code == 'auth_rate_limited') {
      return 'Too many sign-in attempts. Try again later.';
    }
    if (error.code?.startsWith('captcha_') ?? false) {
      return error.statusCode == '503'
          ? 'Security verification is unavailable right now. Try again later.'
          : securityFailed;
    }
    if (error.statusCode == '503' ||
        error.code == 'auth_transport_unavailable') {
      return unavailable;
    }
    if (const {
      'invalid_credentials',
      'invalid_challenge',
    }.contains(error.code)) {
      return invalidCode;
    }
    return failed;
  }
  final text = error.toString().toLowerCase();
  if (text.contains('token has expired') ||
      text.contains('invalid') ||
      text.contains('otp')) {
    return invalidCode;
  }
  if (text.contains('network') ||
      text.contains('socket') ||
      text.contains('connection')) {
    return 'Network connection failed. Check your connection and try again.';
  }
  if (text.contains('captcha')) {
    return securityFailed;
  }
  if (text.contains('unavailable')) {
    return unavailable;
  }
  return failed;
}
