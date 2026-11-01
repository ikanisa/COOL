import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/security/phone_normalizer.dart';
import '../../core/cloudflare/auth_otp_gateway.dart';
import '../../core/cloudflare/auth_alternative_gateway.dart';
import '../../core/cloudflare/collect_cloudflare_types.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import 'widgets/auth_screen_widgets.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen>
    with WidgetsBindingObserver {
  final _phone = TextEditingController();
  final _email = TextEditingController();
  bool _useEmail = true;
  CollectOtpChannel _phoneChannel = CollectOtpChannel.whatsapp;
  bool _googlePending = false;
  int _googleAttempt = 0;
  AuthAlternativeGateway? _activeGoogleGateway;
  AuthOtpGateway? _activeOtpGateway;
  AuthAlternativeGateway? _activeAlternativeGateway;
  bool _verificationUnknown = false;
  AuthGuestGateway? get _guestGateway =>
      _activeAlternativeGateway is AuthGuestGateway
      ? _activeAlternativeGateway as AuthGuestGateway
      : null;

  String get _normalizedEmail => _email.text.trim().toLowerCase();
  bool get _validIdentity => _useEmail
      ? _normalizedEmail.length <= 254 &&
            RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_normalizedEmail)
      : _phoneAvailable && _normalizedPhoneOrNull != null;
  bool get _whatsAppAvailable =>
      ref.read(authOtpGatewayProvider)?.whatsAppSignInAvailable ?? false;
  bool get _smsAvailable {
    final gateway = ref.read(authOtpGatewayProvider);
    return gateway is AuthSmsOtpGateway &&
        (gateway as AuthSmsOtpGateway).smsSignInAvailable;
  }

  bool get _phoneAvailable => _phoneChannel == CollectOtpChannel.sms
      ? _smsAvailable
      : _whatsAppAvailable;
  String get _phoneMethod =>
      _phoneChannel == CollectOtpChannel.sms ? 'SMS' : 'WhatsApp';
  final _otp = TextEditingController();
  final _scrollController = ScrollController();
  final _formViewportController = ScrollController();
  final _authActionDockKey = GlobalKey();
  bool _shortViewportRevealPending = false;
  final _errorNoticeKey = GlobalKey();
  bool _otpSent = false;
  bool _submitting = false;
  Timer? _resendTimer;
  int _resendRemaining = 0;
  String? _error;
  String _errorTitle = 'Authentication failed';
  String _authMethod = 'Email';

  String get _countryCode => '+250';

  String get _phoneForAuth {
    final raw = _phone.text.trim();
    if (raw.startsWith('+') || raw.startsWith('00')) return raw;
    final digits = raw
        .replaceAll(RegExp(r'\D'), '')
        .replaceFirst(RegExp(r'^0+'), '');
    return '$_countryCode$digits';
  }

  String? get _normalizedPhoneOrNull {
    try {
      return PhoneNormalizer.normalizeRwanda(_phone.text);
    } on FormatException {
      return null;
    }
  }

  String get _profileCountryCode => 'RW';

  bool get _otpComplete =>
      _otp.text.replaceAll(RegExp(r'\D'), '').length == AuthOtpEntry.digitCount;

  bool get _canSubmit {
    if (_verificationUnknown) return !_submitting;
    if (_submitting || !_validIdentity) {
      return false;
    }
    return !_otpSent || _otpComplete;
  }

  bool get _canResend =>
      !_verificationUnknown &&
      _otpSent &&
      !_submitting &&
      _resendRemaining == 0 &&
      _validIdentity;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _restoreGuestVerification(),
    );
  }

  @override
  void didChangeMetrics() {
    if (_error == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _revealAuthError();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _activeGoogleGateway?.cancelGoogleSignIn();
    _cancelPendingOtp();
    _email.dispose();
    _phone.dispose();
    _otp.dispose();
    _scrollController.dispose();
    _formViewportController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final otpGateway = ref.watch(authOtpGatewayProvider);
    _activeOtpGateway = otpGateway;
    final whatsAppAvailable = otpGateway?.whatsAppSignInAvailable ?? false;
    final smsAvailable =
        otpGateway is AuthSmsOtpGateway &&
        (otpGateway as AuthSmsOtpGateway).smsSignInAvailable;
    final alternativeGateway = ref.watch(authAlternativeGatewayProvider);
    _activeAlternativeGateway = alternativeGateway;
    final googleAvailable = alternativeGateway?.googleSignInAvailable ?? false;
    final guestGateway = alternativeGateway is AuthGuestGateway
        ? alternativeGateway as AuthGuestGateway
        : null;
    final mediaQuery = MediaQuery.of(context);
    final textScale = mediaQuery.textScaler.scale(1).clamp(1.0, 1.5);
    // The form is inside SafeArea: compare its usable height, not the full
    // window, with the legacy viewport floor before revealing the action dock.
    final availableHeight =
        mediaQuery.size.height -
        mediaQuery.viewInsets.bottom -
        mediaQuery.padding.vertical;
    if (availableHeight < 320 * textScale) {
      _scheduleShortViewportReveal();
    }
    final displayPhone = _maskedPhoneForDisplay(
      _normalizedPhoneOrNull ?? _phoneForAuth,
    );
    return Scaffold(
      backgroundColor: context.collectColors.authCanvas,
      body: DecoratedBox(
        decoration: BoxDecoration(
          color: context.collectColors.authCanvas,
          gradient: CollectRuntimeTokens.overviewBackdrop(
            context.collectColors,
            Theme.of(context).brightness,
            CollectBackdropTone.authentication,
            highContrast: MediaQuery.highContrastOf(context),
          ),
        ),
        child: SafeArea(
          child: CollectFormViewport(
            controller: _formViewportController,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(
                      CollectSpacing.x5,
                      CollectSpacing.x3,
                      CollectSpacing.x5,
                      CollectSpacing.x5,
                    ),
                    children: [
                      const AuthIdentityHeader(),
                      CollectSpacing.gap24,
                      AuthHeadline(
                        otpSent: _otpSent,
                        phone: _useEmail ? _normalizedEmail : displayPhone,
                        useEmail: _useEmail,
                        phoneMethod: _phoneMethod,
                        googlePending: _googlePending,
                      ),
                      CollectSpacing.gap24,
                      if (guestGateway?.isGuest == true) ...[
                        const Text(
                          'You are browsing as a guest. Verify an email address or phone number to create your member account.',
                        ),
                        CollectSpacing.gap16,
                      ],
                      if (!_googlePending)
                        AuthInputPanel(
                          otpSent: _otpSent,
                          phoneController: _phone,
                          emailController: _email,
                          useEmail: _useEmail,
                          phoneMethod: _phoneMethod,
                          enabled: !_submitting && !_verificationUnknown,
                          verificationUnknown: _verificationUnknown,
                          otpController: _otp,
                          error: _error,
                          errorTitle: _errorTitle,
                          errorKey: _errorNoticeKey,
                          resendRemaining: _resendRemaining,
                          countryCode: _countryCode,
                          onPhoneChanged: () => setState(() => _error = null),
                          onOtpChanged: () => setState(() => _error = null),
                        ),
                      if (!_otpSent && !_googlePending) ...[
                        CollectSpacing.gap20,
                        AuthSignInOptions(
                          useEmail: _useEmail,
                          whatsAppAvailable: whatsAppAvailable,
                          smsAvailable: smsAvailable,
                          phoneMethod: _phoneMethod,
                          onSms: _submitting
                              ? null
                              : () => _selectPhoneMethod(CollectOtpChannel.sms),
                          onWhatsApp: _submitting
                              ? null
                              : () => _selectPhoneMethod(
                                  CollectOtpChannel.whatsapp,
                                ),
                          googleAvailable: googleAvailable,
                          onSwitch: _submitting ? null : _switchMethod,
                          onGoogle: _submitting || !googleAvailable
                              ? null
                              : _signInWithGoogle,
                          guestAvailable:
                              guestGateway?.guestSignInAvailable ?? false,
                          isGuest: guestGateway?.isGuest ?? false,
                          onGuest: _submitting ? null : _signInAsGuest,
                          onLeaveGuest: _submitting ? null : _leaveGuest,
                        ),
                      ],
                    ],
                  ),
                ),
                AuthActionDock(
                  key: _authActionDockKey,
                  otpSent: _otpSent,
                  useEmail: _useEmail,
                  phoneMethod: _phoneMethod,
                  googlePending: _googlePending,
                  verificationUnknown: _verificationUnknown,
                  onLeaveGuest: _leaveGuest,
                  onCancelGoogle: _cancelGoogle,
                  submitting: _submitting,
                  resendRemaining: _resendRemaining,
                  canSubmit: _canSubmit,
                  canResend: _canResend,
                  onSubmit: _canSubmit ? () => _submit() : null,
                  onAnotherNumber: _submitting
                      ? null
                      : () => setState(() {
                          _cancelPendingOtp();
                          _resendTimer?.cancel();
                          _otpSent = false;
                          _otp.clear();
                          _resendRemaining = 0;
                          _error = null;
                        }),
                  onResend: _canResend ? () => _resendCode() : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _scheduleShortViewportReveal() {
    if (_shortViewportRevealPending) return;
    _shortViewportRevealPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _shortViewportRevealPending = false;
      if (!mounted) return;
      final actionContext = _authActionDockKey.currentContext;
      if (actionContext != null) {
        // The dock normally sits below the nested form list. When the native
        // keyboard leaves a short viewport, reveal the dock through the outer
        // form scroller while retaining the focused field and its draft.
        unawaited(
          Scrollable.ensureVisible(
            actionContext,
            alignment: 1,
            duration: Duration.zero,
          ),
        );
        return;
      }
      if (_formViewportController.hasClients) {
        final position = _formViewportController.position;
        if (position.pixels < position.maxScrollExtent) {
          _formViewportController.jumpTo(position.maxScrollExtent);
        }
      }
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_verificationUnknown) {
      await _checkGuestVerification();
      return;
    }
    _authMethod = _useEmail ? 'Email' : _phoneMethod;
    if (_useEmail) {
      await _submitEmail();
      return;
    }
    final otpGateway = ref.read(authOtpGatewayProvider);
    if (otpGateway == null || !_phoneAvailable) {
      _showAuthError(StateError('$_phoneMethod sign-in is unavailable.'));
      return;
    }
    setState(() => _error = null);
    try {
      final phone = _normalizedPhoneOrNull;
      if (phone == null) {
        throw const FormatException('Enter a valid Rwanda phone number.');
      }
      if (!_otpSent) {
        FocusManager.instance.primaryFocus?.unfocus();
        final confirmed = await _confirmPhoneNumber(phone);
        if (!mounted || !confirmed) return;
        setState(() => _submitting = true);
        final resendAfterSeconds = await _sendOtp(
          ref.read(authOtpGatewayProvider),
          phone,
        );
        if (!mounted) return;
        setState(() {
          _otpSent = true;
          _submitting = false;
        });
        _startResendCooldown(seconds: resendAfterSeconds);
        return;
      }
      setState(() => _submitting = true);
      if (_phoneChannel == CollectOtpChannel.sms &&
          otpGateway is AuthSmsOtpGateway) {
        await (otpGateway as AuthSmsOtpGateway).verifySmsOtp(
          phone: phone,
          otp: _otp.text,
        );
      } else {
        await otpGateway.verifyWhatsAppOtp(phone: phone, otp: _otp.text);
      }
      if (!mounted) return;
      await ref
          .read(collectRepositoryProvider.notifier)
          .signInWithOtp(
            phone: phone,
            otp: _otp.text,
            countryCode: _profileCountryCode,
          );
      if (!mounted) return;
      context.go(_safePostAuthTarget(context) ?? '/home');
    } catch (error) {
      _showAuthError(error);
    }
  }

  void _switchMethod() {
    if (_submitting ||
        _verificationUnknown ||
        (_useEmail && !_whatsAppAvailable)) {
      return;
    }
    if (_useEmail) {
      _selectPhoneMethod(CollectOtpChannel.whatsapp);
      return;
    }
    _cancelPendingOtp();
    setState(() {
      _useEmail = true;
      _otpSent = false;
      _otp.clear();
      _resendTimer?.cancel();
      _resendRemaining = 0;
      _error = null;
    });
  }

  void _cancelPendingOtp() {
    if (_activeOtpGateway case final AuthOtpCancellationGateway gateway) {
      gateway.cancelOtpSignIn();
    }
    if (_activeAlternativeGateway
        case final AuthOtpCancellationGateway gateway) {
      gateway.cancelOtpSignIn();
    }
  }

  void _selectPhoneMethod(CollectOtpChannel channel) {
    if (_submitting ||
        _verificationUnknown ||
        (channel == CollectOtpChannel.sms
            ? !_smsAvailable
            : !_whatsAppAvailable)) {
      return;
    }
    _cancelPendingOtp();
    setState(() {
      _useEmail = false;
      _phoneChannel = channel;
      _otpSent = false;
      _otp.clear();
      _resendTimer?.cancel();
      _resendRemaining = 0;
      _error = null;
    });
  }

  Future<void> _submitEmail({bool resend = false}) async {
    if (_submitting || !_validIdentity) return;
    _authMethod = 'Email';
    final email = _normalizedEmail;
    final gateway = ref.read(authAlternativeGatewayProvider);
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      if (gateway == null) throw StateError('Email sign-in is unavailable.');
      if (!_otpSent || resend) {
        if (resend) _otp.clear();
        FocusManager.instance.primaryFocus?.unfocus();
        final receipt = await gateway.sendEmailOtp(email: email);
        if (!mounted) return;
        setState(() {
          _otpSent = true;
          _submitting = false;
        });
        _startResendCooldown(seconds: receipt.retryAfterSeconds);
        return;
      }
      await gateway.verifyEmailOtp(email: email, otp: _otp.text);
      if (!mounted) return;
      context.go(_safePostAuthTarget(context) ?? '/home');
    } catch (error) {
      _showAuthError(error, discardPendingCode: resend);
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_submitting) return;
    _authMethod = 'Google';
    final gateway = ref.read(authAlternativeGatewayProvider);
    if (gateway == null || !gateway.googleSignInAvailable) {
      _showAuthError(StateError('Google sign-in is unavailable.'));
      return;
    }
    _activeGoogleGateway = gateway;
    final attempt = ++_googleAttempt;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _googlePending = true;
      _submitting = true;
      _error = null;
    });
    try {
      await gateway.signInWithGoogle();
      if (!mounted || attempt != _googleAttempt) return;
      context.go(_safePostAuthTarget(context) ?? '/home');
    } catch (error) {
      if (!mounted || attempt != _googleAttempt) return;
      setState(() => _googlePending = false);
      if (error is CollectAuthException && error.code == 'google_cancelled') {
        setState(() => _submitting = false);
      } else {
        _showAuthError(error);
      }
    }
  }

  void _cancelGoogle() {
    ++_googleAttempt;
    _activeGoogleGateway?.cancelGoogleSignIn();
    setState(() {
      _googlePending = false;
      _submitting = false;
      _error = null;
    });
  }

  String? _safePostAuthTarget(BuildContext context) {
    final raw = GoRouterState.of(context).uri.queryParameters['next'];
    if (raw == null || raw.isEmpty) return null;
    final target = Uri.tryParse(raw);
    if (target == null ||
        target.hasScheme ||
        target.hasAuthority ||
        !target.path.startsWith('/') ||
        target.path.startsWith('//') ||
        target.path == '/' ||
        target.path == '/auth') {
      return null;
    }
    return target.toString();
  }

  Future<bool> _confirmPhoneNumber(String phone) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: CollectMotion.animationStyle(context),
      builder: (context) =>
          AuthPhoneConfirmationSheet(phone: phone, phoneMethod: _phoneMethod),
    );
    return confirmed ?? false;
  }

  Future<void> _resendCode() async {
    if (_submitting) return;
    if (_useEmail) {
      await _submitEmail(resend: true);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
      _otp.clear();
    });
    try {
      final phone = _normalizedPhoneOrNull;
      if (phone == null) {
        throw const FormatException('Enter a valid Rwanda phone number.');
      }
      final resendAfterSeconds = await _sendOtp(
        ref.read(authOtpGatewayProvider),
        phone,
      );
      if (!mounted) return;
      setState(() => _submitting = false);
      _startResendCooldown(seconds: resendAfterSeconds);
    } catch (error) {
      _showAuthError(error, discardPendingCode: true);
    }
  }

  Future<int> _sendOtp(AuthOtpGateway? otpGateway, String phone) async {
    if (_phoneChannel == CollectOtpChannel.sms) {
      if (otpGateway is! AuthSmsOtpGateway ||
          !(otpGateway as AuthSmsOtpGateway).smsSignInAvailable) {
        throw StateError('SMS sign-in is unavailable.');
      }
      return (await (otpGateway as AuthSmsOtpGateway).requestSmsOtpReceipt(
        phone: phone,
      )).retryAfterSeconds;
    }
    if (otpGateway == null || !otpGateway.whatsAppSignInAvailable) {
      throw StateError('WhatsApp sign-in is unavailable.');
    }
    if (otpGateway case final AuthOtpRequestReceiptGateway receiptGateway) {
      final receipt = await receiptGateway.requestWhatsAppOtpReceipt(
        phone: phone,
      );
      return receipt.retryAfterSeconds;
    }
    await otpGateway.sendWhatsAppOtp(phone: phone);
    return 60;
  }

  String _maskedPhoneForDisplay(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length <= 4) return phone;
    final visible = digits.substring(digits.length - 4);
    if (phone.startsWith('+250') || digits.startsWith('250')) {
      return '+250 *** $visible';
    }
    return '+*** $visible';
  }

  String _safeAuthErrorMessage(Object error) {
    if (error is CollectOtpDeliveryUnknownException) {
      return 'Delivery could not be confirmed. If a code arrives, enter it here before requesting another.';
    }
    final method = _authMethod;
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
            : 'Security verification could not finish. Try again.';
      }
      if (error.statusCode == '503' ||
          error.code == 'auth_transport_unavailable') {
        return '$method sign-in is unavailable right now. Try again later.';
      }
      if (const {
        'invalid_credentials',
        'invalid_challenge',
      }.contains(error.code)) {
        return 'That ${method == 'Email' ? 'email' : method} code is invalid or expired. Request a fresh code and try again.';
      }
      return 'Sign-in failed. Try again.';
    }
    final text = error.toString().toLowerCase();
    if (text.contains('token has expired') ||
        text.contains('invalid') ||
        text.contains('otp')) {
      return 'That ${method == 'Email' ? 'email' : method} code is invalid or expired. Request a fresh code and try again.';
    }
    if (text.contains('network') ||
        text.contains('socket') ||
        text.contains('connection')) {
      return 'Network connection failed. Check your connection and try again.';
    }
    if (text.contains('captcha')) {
      return 'Security verification could not finish. Try again.';
    }
    if (text.contains('unavailable')) {
      return '$method sign-in is unavailable right now. Try again later.';
    }
    return 'Sign-in failed. Try again.';
  }

  void _showAuthError(Object error, {bool discardPendingCode = false}) {
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _verificationUnknown =
          _guestGateway?.pendingGuestUpgrade?.unconfirmed ?? false;
      _error = _safeAuthErrorMessage(error);
      if (_verificationUnknown) {
        _error =
            'Your account verification was not confirmed. Check verification to recover the result without sending another code.';
      }
      _errorTitle = error is CollectOtpDeliveryUnknownException
          ? 'Delivery not confirmed'
          : 'Authentication failed';
      _submitting = false;
      if (error is CollectOtpDeliveryUnknownException) {
        _otpSent = true;
      } else if (discardPendingCode && !_verificationUnknown) {
        _otpSent = false;
        _otp.clear();
        _resendTimer?.cancel();
        _resendRemaining = 0;
      }
    });
    if (error is CollectOtpDeliveryUnknownException) {
      _startResendCooldown(seconds: error.retryAfterSeconds);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealAuthError();
    });
  }

  void _revealAuthError({bool buildOffscreenNotice = true}) {
    if (!mounted || _error == null || !_scrollController.hasClients) return;
    final noticeContext = _errorNoticeKey.currentContext;
    if (noticeContext != null) {
      // Keep the actual error in view, including when enlarged text puts the
      // input panel below the heading. The notice is also a semantic live region.
      unawaited(Scrollable.ensureVisible(noticeContext));
    } else if (buildOffscreenNotice) {
      // The lazy form may not have built its final panel yet. Reveal that panel
      // first, then align the notice using its measured bounds on the next frame.
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _revealAuthError(buildOffscreenNotice: false);
      });
      WidgetsBinding.instance.scheduleFrame();
    }
  }

  void _startResendCooldown({required int seconds}) {
    _resendTimer?.cancel();
    setState(() => _resendRemaining = seconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendRemaining <= 1) {
        timer.cancel();
        setState(() => _resendRemaining = 0);
        return;
      }
      setState(() => _resendRemaining -= 1);
    });
  }

  void _restoreGuestVerification() {
    if (!mounted) return;
    final pending = _guestGateway?.pendingGuestUpgrade;
    if (pending == null) return;
    setState(() {
      _useEmail = pending.email != null;
      _email.text = pending.email ?? '';
      _phone.text = pending.phone ?? '';
      _phoneChannel = pending.channel ?? CollectOtpChannel.whatsapp;
      _otpSent = true;
      _verificationUnknown = pending.unconfirmed;
      if (pending.unconfirmed) {
        _errorTitle = 'Verification not confirmed';
        _error =
            'Check the retained verification before requesting or entering another code.';
      }
    });
    if (!pending.unconfirmed) _startResendCooldown(seconds: 60);
  }

  Future<void> _signInAsGuest() async {
    final gateway = _guestGateway;
    if (_submitting || gateway == null || !gateway.guestSignInAvailable) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await gateway.signInAsGuest();
      if (mounted) context.go('/groups');
    } catch (error) {
      _showAuthError(error);
    }
  }

  Future<void> _checkGuestVerification() async {
    final gateway = _guestGateway;
    if (_submitting || gateway == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await gateway.reconcileGuestUpgrade();
      if (mounted) context.go(_safePostAuthTarget(context) ?? '/home');
    } catch (error) {
      _showAuthError(error);
    }
  }

  Future<void> _leaveGuest() async {
    final gateway = _guestGateway;
    if (_submitting || gateway?.isGuest != true) return;
    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: CollectMotion.animationStyle(context),
      builder: (context) => AlertDialog(
        title: const Text('Use another account?'),
        content: const Text(
          'This closes guest access on this device. Sign in again to the account you want to use. Guest access and other accounts are never merged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _submitting = true);
    Object? failure;
    try {
      await gateway!.leaveGuest();
    } catch (error) {
      failure = error;
    }
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _verificationUnknown = false;
      _otpSent = false;
      _otp.clear();
      _email.clear();
      _phone.clear();
      _error = failure == null
          ? null
          : 'Guest access is closed on this device. Remote sign-out could not be confirmed.';
    });
  }
}
