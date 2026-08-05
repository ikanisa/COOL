import 'dart:async';

import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/env/app_env.dart';
import '../../core/security/phone_normalizer.dart';
import '../../core/supabase/supabase_module.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import 'widgets/auth_screen_widgets.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  final _captchaToken = TextEditingController();
  final _scrollController = ScrollController();
  var _selectedCountry = Country.parse('RW');
  bool _otpSent = false;
  bool _submitting = false;
  Timer? _resendTimer;
  int _resendRemaining = 0;
  String? _error;

  String get _countryCode => '+${_selectedCountry.phoneCode}';

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
      return PhoneNormalizer.normalizeInternational(_phoneForAuth);
    } on FormatException {
      return null;
    }
  }

  bool get _captchaReady {
    final env = ref.read(appEnvProvider);
    return !env.authCaptchaEnabled || _captchaToken.text.trim().isNotEmpty;
  }

  bool get _otpComplete =>
      _otp.text.replaceAll(RegExp(r'\D'), '').length == AuthOtpEntry.digitCount;

  bool get _canSubmit {
    if (_submitting || !_captchaReady || _normalizedPhoneOrNull == null) {
      return false;
    }
    return !_otpSent || _otpComplete;
  }

  bool get _canResend =>
      _otpSent &&
      !_submitting &&
      _resendRemaining == 0 &&
      _captchaReady &&
      _normalizedPhoneOrNull != null;

  @override
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    _captchaToken.dispose();
    _scrollController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final env = ref.watch(appEnvProvider);
    final displayPhone = _maskedPhoneForDisplay(_phoneForAuth);
    final normalizedPhone = _normalizedPhoneOrNull;
    final usesReviewAuth =
        normalizedPhone != null && _isAppReviewAuthPhone(env, normalizedPhone);
    return Scaffold(
      backgroundColor: CollectColors.referenceChromeBlack,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          color: CollectColors.referenceChromeBlack,
        ),
        child: SafeArea(
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
                      phone: displayPhone,
                      usesReviewAuth: usesReviewAuth,
                    ),
                    CollectSpacing.gap24,
                    AuthInputPanel(
                      otpSent: _otpSent,
                      phoneController: _phone,
                      otpController: _otp,
                      captchaController: _captchaToken,
                      env: env,
                      error: _error,
                      resendRemaining: _resendRemaining,
                      countryCode: _countryCode,
                      onCountryTap: _showCountryPicker,
                      onPhoneChanged: () => setState(() => _error = null),
                      onOtpChanged: () => setState(() => _error = null),
                      onCaptchaChanged: () => setState(() => _error = null),
                    ),
                  ],
                ),
              ),
              AuthActionDock(
                otpSent: _otpSent,
                submitting: _submitting,
                resendRemaining: _resendRemaining,
                canSubmit: _canSubmit,
                canResend: _canResend,
                onSubmit: _canSubmit ? () => _submit(env) : null,
                onAnotherNumber: _submitting
                    ? null
                    : () => setState(() {
                        _resendTimer?.cancel();
                        _otpSent = false;
                        _otp.clear();
                        _resendRemaining = 0;
                        _error = null;
                      }),
                onResend: _canResend ? () => _resendCode(env) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit(AppEnv env) async {
    if (_submitting) return;
    setState(() => _error = null);
    try {
      final phone = PhoneNormalizer.normalizeInternational(_phoneForAuth);
      final client = ref.read(supabaseClientProvider);
      final captchaToken = env.authCaptchaEnabled
          ? _captchaToken.text.trim()
          : '';
      if (env.authCaptchaEnabled && captchaToken.isEmpty) {
        throw const FormatException('Complete CAPTCHA verification first.');
      }
      if (!_otpSent) {
        FocusManager.instance.primaryFocus?.unfocus();
        final confirmed = await _confirmPhoneNumber(phone);
        if (!mounted || !confirmed) return;
        setState(() => _submitting = true);
        if (_isAppReviewAuthPhone(env, phone)) {
          setState(() {
            _otpSent = true;
            _submitting = false;
          });
          return;
        }
        await _sendOtp(client, phone, captchaToken);
        if (!mounted) return;
        setState(() {
          _otpSent = true;
          _submitting = false;
        });
        _startResendCooldown();
        return;
      }
      setState(() => _submitting = true);
      if (_isAppReviewAuthPhone(env, phone)) {
        if (_otp.text.trim() != env.appReviewAuthOtp.trim()) {
          throw const FormatException('Invalid Apple reviewer OTP.');
        }
        await ref
            .read(collectRepositoryProvider.notifier)
            .signInForAppReview(phone: phone);
        if (!mounted) return;
        context.go('/home');
        return;
      }
      if (client != null) {
        await client.auth.verifyOTP(
          phone: phone,
          token: _otp.text,
          type: OtpType.sms,
          captchaToken: captchaToken.isEmpty ? null : captchaToken,
        );
      }
      if (!mounted) return;
      await ref
          .read(collectRepositoryProvider.notifier)
          .signInWithOtp(phone: phone, otp: _otp.text);
      if (!mounted) return;
      context.go('/home');
    } catch (error) {
      _showAuthError(error);
    }
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

  bool _isAppReviewAuthPhone(AppEnv env, String phone) {
    if (!env.hasAppReviewAuthConfig) return false;
    try {
      return PhoneNormalizer.normalizeInternational(env.appReviewAuthPhone) ==
          PhoneNormalizer.normalizeInternational(phone);
    } catch (_) {
      return false;
    }
  }

  Future<void> _resendCode(AppEnv env) async {
    setState(() {
      _submitting = true;
      _error = null;
      _otp.clear();
    });
    try {
      final phone = PhoneNormalizer.normalizeInternational(_phoneForAuth);
      final captchaToken = env.authCaptchaEnabled
          ? _captchaToken.text.trim()
          : '';
      if (env.authCaptchaEnabled && captchaToken.isEmpty) {
        throw const FormatException('Complete CAPTCHA verification first.');
      }
      if (_isAppReviewAuthPhone(env, phone)) {
        if (!mounted) return;
        setState(() => _submitting = false);
        return;
      }
      await _sendOtp(ref.read(supabaseClientProvider), phone, captchaToken);
      if (!mounted) return;
      setState(() => _submitting = false);
      _startResendCooldown();
    } catch (error) {
      _showAuthError(error);
    }
  }

  Future<void> _sendOtp(
    SupabaseClient? client,
    String phone,
    String captchaToken,
  ) async {
    if (client == null) {
      throw StateError('WhatsApp sign-in is unavailable.');
    }
    await client.auth.signInWithOtp(
      phone: phone,
      channel: OtpChannel.whatsapp,
      captchaToken: captchaToken.isEmpty ? null : captchaToken,
    );
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
    final text = error.toString().toLowerCase();
    if (text.contains('token has expired') ||
        text.contains('invalid') ||
        text.contains('otp')) {
      return 'That WhatsApp code is invalid or expired. Request a fresh code and try again.';
    }
    if (text.contains('network') ||
        text.contains('socket') ||
        text.contains('connection')) {
      return 'Network connection failed. Check your connection and try again.';
    }
    if (text.contains('captcha')) {
      return 'Complete CAPTCHA verification first.';
    }
    if (text.contains('unavailable')) {
      return 'WhatsApp sign-in is unavailable right now. Try again later.';
    }
    return 'Sign-in failed. Try again.';
  }

  void _showAuthError(Object error) {
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _error = _safeAuthErrorMessage(error);
      _submitting = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(0);
    });
  }

  void _showCountryPicker() {
    final colors = context.collectColors;
    final foreground = colors.onImagePrimary;
    showCountryPicker(
      context: context,
      showPhoneCode: true,
      favorite: const ['RW'],
      searchAutofocus: false,
      useSafeArea: true,
      countryListTheme: CountryListThemeData(
        backgroundColor: CollectColors.referenceContentDark,
        borderRadius: CollectRadius.cardLargeBorder,
        bottomSheetHeight: MediaQuery.sizeOf(context).height * 0.74,
        flagSize: 24,
        textStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: foreground,
          fontWeight: CollectTypography.weightBold,
          letterSpacing: CollectTypography.trackingDefault,
        ),
        searchTextStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: foreground,
          fontWeight: CollectTypography.weightBold,
          letterSpacing: CollectTypography.trackingDefault,
        ),
        inputDecoration: InputDecoration(
          hintText: 'Search country',
          hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: foreground.withValues(alpha: 0.48),
          ),
          prefixIcon: Icon(
            CollectIcons.search,
            color: foreground.withValues(alpha: 0.72),
          ),
          filled: true,
          fillColor: foreground.withValues(alpha: 0.12),
          border: OutlineInputBorder(
            borderRadius: CollectRadius.pillBorder,
            borderSide: BorderSide(color: foreground.withValues(alpha: 0.14)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: CollectRadius.pillBorder,
            borderSide: BorderSide(color: foreground.withValues(alpha: 0.14)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: CollectRadius.pillBorder,
            borderSide: BorderSide(color: colors.focusRing, width: 2),
          ),
        ),
      ),
      onSelect: (country) {
        setState(() {
          _selectedCountry = country;
          _error = null;
        });
      },
    );
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendRemaining = 45);
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
