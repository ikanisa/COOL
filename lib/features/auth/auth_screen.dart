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
  bool _googlePending = false;
  int _googleAttempt = 0;
  AuthAlternativeGateway? _activeGoogleGateway;

  String get _normalizedEmail => _email.text.trim().toLowerCase();
  bool get _validIdentity => _useEmail
      ? _normalizedEmail.length <= 254 &&
            RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_normalizedEmail)
      : _whatsAppAvailable && _normalizedPhoneOrNull != null;
  bool get _whatsAppAvailable =>
      ref.read(authOtpGatewayProvider)?.whatsAppSignInAvailable ?? false;
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
    if (_submitting || !_validIdentity) {
      return false;
    }
    return !_otpSent || _otpComplete;
  }

  bool get _canResend =>
      _otpSent && !_submitting && _resendRemaining == 0 && _validIdentity;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    final whatsAppAvailable = otpGateway?.whatsAppSignInAvailable ?? false;
    final alternativeGateway = ref.watch(authAlternativeGatewayProvider);
    final googleAvailable = alternativeGateway?.googleSignInAvailable ?? false;
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
                        googlePending: _googlePending,
                      ),
                      CollectSpacing.gap24,
                      if (!_googlePending)
                        AuthInputPanel(
                          otpSent: _otpSent,
                          phoneController: _phone,
                          emailController: _email,
                          useEmail: _useEmail,
                          enabled: !_submitting,
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
                          googleAvailable: googleAvailable,
                          onSwitch: _submitting ? null : _switchMethod,
                          onGoogle: _submitting || !googleAvailable
                              ? null
                              : _signInWithGoogle,
                        ),
                      ],
                    ],
                  ),
                ),
                AuthActionDock(
                  key: _authActionDockKey,
                  otpSent: _otpSent,
                  useEmail: _useEmail,
                  googlePending: _googlePending,
                  onCancelGoogle: _cancelGoogle,
                  submitting: _submitting,
                  resendRemaining: _resendRemaining,
                  canSubmit: _canSubmit,
                  canResend: _canResend,
                  onSubmit: _canSubmit ? () => _submit() : null,
                  onAnotherNumber: _submitting
                      ? null
                      : () => setState(() {
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
    _authMethod = _useEmail ? 'Email' : 'WhatsApp';
    if (_useEmail) {
      await _submitEmail();
      return;
    }
    final otpGateway = ref.read(authOtpGatewayProvider);
    if (otpGateway == null || !otpGateway.whatsAppSignInAvailable) {
      _showAuthError(StateError('WhatsApp sign-in is unavailable.'));
      return;
    }
    setState(() => _error = null);
    try {
      final phone = _normalizedPhoneOrNull;
      if (phone == null) {
        throw const FormatException(
          'Enter a valid Rwanda WhatsApp phone number.',
        );
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
      await otpGateway.verifyWhatsAppOtp(phone: phone, otp: _otp.text);
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
    if (_submitting || (_useEmail && !_whatsAppAvailable)) return;
    setState(() {
      _useEmail = !_useEmail;
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
      builder: (context) => AuthPhoneConfirmationSheet(phone: phone),
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
        throw const FormatException(
          'Enter a valid Rwanda WhatsApp phone number.',
        );
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
      _error = _safeAuthErrorMessage(error);
      _errorTitle = error is CollectOtpDeliveryUnknownException
          ? 'Delivery not confirmed'
          : 'Authentication failed';
      _submitting = false;
      if (error is CollectOtpDeliveryUnknownException) {
        _otpSent = true;
      } else if (discardPendingCode) {
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
}
