import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_market.dart';
import '../../../core/config/env_config.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/phone_validator.dart';
import '../../../core/providers/supported_countries_provider.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../providers/auth_provider.dart';

/// Screen for entering a phone number to receive a WhatsApp OTP.
///
/// Any valid global WhatsApp number is accepted.
/// Rwanda local numbers work without a country picker.
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({this.redirectPath, super.key});

  final String? redirectPath;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _phoneController = TextEditingController();
  late final TapGestureRecognizer _termsRecognizer;
  late final TapGestureRecognizer _privacyRecognizer;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _termsRecognizer = TapGestureRecognizer()
      ..onTap = () => _openExternalUrl(EnvConfig.termsOfServiceUrl);
    _privacyRecognizer = TapGestureRecognizer()
      ..onTap = () => _openExternalUrl(EnvConfig.privacyPolicyUrl);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final l10n = context.l10n;
    final input = _phoneController.text.trim();
    if (input.isEmpty) {
      setState(() => _errorText = l10n.otpPhoneRequired);
      return;
    }

    final validationError = PhoneValidator.validateOtpPhone(
      input,
      AppMarket.country,
    );
    if (validationError != null) {
      setState(() => _errorText = validationError);
      return;
    }

    setState(() => _errorText = null);

    try {
      final fullPhone = PhoneValidator.buildOtpE164Phone(
        input,
        AppMarket.country,
      );
      await ref
          .read(authProvider.notifier)
          .sendOtp(fullPhone, AppMarket.languageCode);

      if (!mounted) return;

      final authState = ref.read(authProvider);
      if (authState.error != null) {
        setState(() => _errorText = authState.error);
      } else {
        context.push(
          AppRoutes.otpVerifyLocation(
            phone: fullPhone,
            redirect: widget.redirectPath,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = l10n.otpGenericError);
    }
  }

  Future<void> _openExternalUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (launched || !mounted) {
      return;
    }

    CoolToast.error(context, context.l10n.openLinkError);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final authState = ref.watch(authProvider);
    final countries = ref.watch(supportedCountriesProvider);
    final currentCountry = countries.firstOrNull ?? AppMarket.country;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: context.l10n.back,
          onPressed: () => context.go(
            AppRoutes.onboardingLocation(redirect: widget.redirectPath),
          ),
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.text),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 0, 24, keyboardInset + 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),

                    // ── Title ─────────────────────────────────────────
                    Text(
                      'Enter your number',
                      style: GoogleFonts.dmSans(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'A one-time code will',
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text2,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ── Phone input card ──────────────────────────────
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Semantics(
                        textField: true,
                        label: l10n.phoneLabel,
                        hint: 'Enter your phone number',
                        child: Row(
                          children: [
                            // Country code prefix
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 16,
                              ),
                              decoration: BoxDecoration(
                                border: Border(
                                  right: BorderSide(color: AppColors.border),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    currentCountry.flagEmoji,
                                    style: const TextStyle(fontSize: 18),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    currentCountry.dialCode,
                                    style: GoogleFonts.dmSans(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.text,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Phone number input
                            Expanded(
                              child: TextField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _sendOtp(),
                                style: GoogleFonts.dmSans(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w400,
                                  color: AppColors.text,
                                  letterSpacing: 0.8,
                                ),
                                cursorColor: AppColors.accent,
                                decoration: InputDecoration(
                                  hintText: currentCountry.mobileExampleNational,
                                  hintStyle: GoogleFonts.dmSans(
                                    fontSize: 16,
                                    color: AppColors.text3.withValues(
                                      alpha: 0.5,
                                    ),
                                    letterSpacing: 0.5,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── Error ─────────────────────────────────────────
                    if (_errorText != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _errorText!,
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          color: AppColors.red,
                        ),
                      ),
                    ],

                    const Spacer(),

                    // ── Google Sign In ───────────────────────────────
                    CoolButton(
                      label: 'Continue with Google',
                      onTap: () => ref.read(authProvider.notifier).signInWithGoogle(),
                      isLoading: authState.isLoading,
                      variant: CoolButtonVariant.secondary,
                    ),
                    const SizedBox(height: 12),

                    // ── CTA ───────────────────────────────────────────
                    CoolButton(
                      label: l10n.otpContinue,
                      onTap: _sendOtp,
                      isLoading: authState.isLoading,
                    ),
                    const SizedBox(height: 14),
                    Text.rich(
                      TextSpan(
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          color: AppColors.text3,
                          height: 1.4,
                        ),
                        children: [
                          TextSpan(text: l10n.otpLegalPrefix),
                          TextSpan(
                            text: l10n.termsLabel,
                            style: const TextStyle(color: AppColors.accent),
                            recognizer: _termsRecognizer,
                          ),
                          TextSpan(text: l10n.otpLegalAnd),
                          TextSpan(
                            text: l10n.privacyPolicyLabel,
                            style: const TextStyle(color: AppColors.accent),
                            recognizer: _privacyRecognizer,
                          ),
                          const TextSpan(text: '.'),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}