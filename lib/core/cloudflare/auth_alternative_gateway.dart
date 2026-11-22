import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cloudflare_module.dart';
import 'google_auth_browser.dart';
import 'auth_otp_gateway.dart';

/// Build-time availability is explicit and defaults to unavailable until the
/// corresponding backend provider is configured and verified.
final collectGoogleAuthEnabledProvider = Provider<bool>((ref) {
  return const bool.fromEnvironment(
    'COLLECT_GOOGLE_AUTH_ENABLED',
    defaultValue: false,
  );
});

abstract interface class AuthAlternativeGateway {
  bool get googleSignInAvailable;
  Future<CollectOtpRequestReceipt> sendEmailOtp({required String email});
  Future<void> verifyEmailOtp({required String email, required String otp});
  Future<void> signInWithGoogle();
  void cancelGoogleSignIn();
}

abstract interface class AuthGuestGateway {
  bool get guestSignInAvailable;
  bool get isGuest;
  CollectGuestUpgradeStatus? get pendingGuestUpgrade;
  Future<void> signInAsGuest();
  Future<void> reconcileGuestUpgrade();
  Future<void> leaveGuest();
}

final authAlternativeGatewayProvider = Provider<AuthAlternativeGateway?>((ref) {
  final client = ref.watch(collectBackendClientProvider);
  if (client == null) return null;
  final gateway = CollectAuthAlternativeGateway(
    client,
    googleSignInEnabled: ref.watch(collectGoogleAuthEnabledProvider),
  );
  ref.onDispose(gateway.cancelGoogleSignIn);
  return gateway;
});

final class CollectAuthAlternativeGateway
    implements
        AuthAlternativeGateway,
        AuthOtpCancellationGateway,
        AuthGuestGateway {
  CollectAuthAlternativeGateway(
    this._client, {
    this.googleSignInEnabled = false,
  });

  @override
  bool get googleSignInAvailable => googleSignInEnabled && !isGuest;
  final bool googleSignInEnabled;
  final CollectCloudflareClient _client;
  final _browser = GoogleAuthBrowser();

  @override
  bool get guestSignInAvailable => _client.auth.anonymousSignInAvailable;
  @override
  bool get isGuest => _client.auth.currentGuest != null;
  @override
  CollectGuestUpgradeStatus? get pendingGuestUpgrade =>
      _client.auth.pendingGuestUpgrade;
  @override
  Future<void> signInAsGuest() async {
    await _client.auth.signInAnonymously();
  }

  @override
  Future<void> reconcileGuestUpgrade() async {
    await _client.auth.reconcileGuestUpgrade();
  }

  @override
  Future<void> leaveGuest() => _client.auth.signOut();

  @override
  void cancelOtpSignIn() => _client.auth.cancelOtpSignIn();

  @override
  Future<CollectOtpRequestReceipt> sendEmailOtp({required String email}) =>
      _client.auth.signInWithOtp(email: email);

  @override
  Future<void> verifyEmailOtp({required String email, required String otp}) =>
      _client.auth.verifyOTP(
        email: email,
        token: otp,
        type: CollectOtpType.email,
      );

  @override
  Future<void> signInWithGoogle() {
    if (!googleSignInAvailable) {
      return Future.error(
        const CollectAuthException(
          'Google sign-in is unavailable.',
          code: 'google_unavailable',
        ),
      );
    }
    return _client.auth.signInWithGoogle(authorize: _browser.authorize);
  }

  @override
  void cancelGoogleSignIn() {
    _client.auth.cancelGoogleSignIn();
    _browser.cancel();
  }
}
