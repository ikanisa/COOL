part of 'collect_cloudflare_client.dart';

abstract interface class CollectAuthSessionStorage {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

/// Page memory only: no browser storage, cookie, BroadcastChannel or URL token.
final class CollectMemorySessionStorage implements CollectAuthSessionStorage {
  String? _value;
  @override
  Future<String?> read() async => _value;
  @override
  Future<void> write(String value) async {
    _value = value;
  }

  @override
  Future<void> clear() async {
    _value = null;
  }
}

final class CollectAuthClient {
  CollectAuthClient(
    this._client,
    this._storage, {
    required this.surface,
    bool allowAnonymousSignIn = false,
  }) : anonymousSignInAvailable =
           allowAnonymousSignIn &&
           surface == 'member' &&
           _client.supabaseConfiguration != null;
  final CollectCloudflareClient _client;
  final CollectAuthSessionStorage _storage;
  late final _transport = _CollectAuthTransport(_client);
  final String surface;
  final bool anonymousSignInAvailable;
  final _events = StreamController<CollectAuthState>.broadcast(sync: true);
  CollectAuthSession? _session;
  int _generation = 0;
  int _otpGeneration = 0;
  int _googleGeneration = 0;
  int _anonymousGeneration = 0;
  final Map<String, String> _challenges = {};
  final Map<String, CollectOtpChannel?> _challengeChannels = {};
  _CollectGuestUpgrade? _guestUpgrade;
  Timer? _refreshTimer;
  Future<CollectAuthResponse>? _refreshInFlight;
  Future<CollectAuthResponse>? _guestReconcileInFlight;
  Future<void>? _initializationInFlight;
  _CollectInitializationOwner? _initializationOwner;
  Future<void> _storageTail = Future.value();
  bool _disposed = false;
  CollectAuthSession? get currentSession => _session;
  // Guest credentials never become application/member ownership. Existing
  // financial/device consumers continue to see the signed-out public surface.
  CollectAuthUser? get currentUser =>
      _session?.user.isAnonymous == true ? null : _session?.user;
  CollectAuthUser? get currentGuest =>
      _session?.user.isAnonymous == true ? _session?.user : null;
  CollectGuestUpgradeStatus? get pendingGuestUpgrade =>
      currentGuest == null || _guestUpgrade == null
      ? null
      : CollectGuestUpgradeStatus(
          phone: _guestUpgrade!.phone,
          email: _guestUpgrade!.email,
          channel: _guestUpgrade!.channel,
          unconfirmed: _guestUpgrade!.unconfirmed,
        );
  Stream<CollectAuthState> get onAuthStateChange => _events.stream;
  Stream<CollectAuthState> get onAuthStateChangeSync => _events.stream;

  Future<void> initialize() => _restoreSession();

  Future<CollectAuthResponse> signInAnonymously({String? captchaToken}) =>
      _openGuest(captchaToken: captchaToken);

  Future<CollectOtpRequestReceipt> signInWithOtp({
    String? phone,
    String? email,
    CollectOtpChannel? channel,
    bool shouldCreateUser = true,
    String? captchaToken,
  }) => _startOtp(
    phone: phone,
    email: email,
    channel: channel,
    shouldCreateUser: shouldCreateUser,
    captchaToken: captchaToken,
  );

  Future<CollectAuthResponse> verifyOTP({
    String? phone,
    String? email,
    required String token,
    required CollectOtpType type,
    CollectOtpChannel? channel,
    String? captchaToken,
  }) => _verifyOtp(
    phone: phone,
    email: email,
    token: token,
    type: type,
    channel: channel,
    captchaToken: captchaToken,
  );

  void cancelOtpSignIn() => _cancelOtp();

  Future<CollectAuthResponse> reconcileGuestUpgrade() => _checkGuestUpgrade();

  Future<CollectAuthResponse> signInWithGoogle({
    required Future<Map<String, dynamic>> Function(
      Future<Uri> Function(String? returnOrigin) createUrl,
      String state,
      String apiOrigin,
    )
    authorize,
  }) => _authorizeGoogle(authorize: authorize);

  void cancelGoogleSignIn() => _cancelGoogle();

  Future<CollectAuthResponse> refreshSession() => _refreshCurrentSession();

  /// Installs a previously verified response synchronously after its caller's
  /// account fence. It never fetches, refreshes or trusts a browser broadcast.
  Future<CollectAuthResponse> recoverSession(
    String encoded, {
    CollectAuthEvent event = CollectAuthEvent.signedIn,
    void Function()? onInstalled,
  }) =>
      _installRecoveredSession(encoded, event: event, onInstalled: onInstalled);

  Future<void> signOut({
    CollectSignOutScope scope = CollectSignOutScope.local,
  }) => _signOut(scope: scope);

  Future<void> revokeCapturedSession(String accessToken) =>
      _revokeSession(accessToken);

  Future<void> clearLocalSession() => _clearSession();

  void notifyAllSubscribers(CollectAuthEvent event) {
    if (!_disposed) _events.add(CollectAuthState(event, _session));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _client.cancelCaptcha?.call();
    ++_generation;
    ++_otpGeneration;
    _refreshTimer?.cancel();
    _challenges.clear();
    _challengeChannels.clear();
    _session = null;
    await _storageTail.catchError((Object _) {});
    await _events.close();
  }
}
