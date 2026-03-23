import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_market.dart';
import '../../../core/config/env_config.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/phone_validator.dart';
import '../../../core/providers/supported_countries_provider.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../providers/auth_provider.dart';
import '../../../shared/widgets/core_detail_scaffold.dart';

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
    final colors = context.coolSemanticColors;
    final radii = context.coolRadii;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final authState = ref.watch(authProvider);
    final countries = ref.watch(supportedCountriesProvider);
    final currentCountry = countries.firstOrNull ?? AppMarket.country;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return CoreDetailScaffold(
      showGlow: true,
      onBack: () => context.go(
        AppRoutes.onboardingLocation(redirect: widget.redirectPath),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              space.x6,
              0,
              space.x6,
              keyboardInset + space.x6,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: space.x6),

                    // ── Title ─────────────────────────────────────────
                    Text(
                      'Enter your number',
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colors.primaryText,
                        height: 1.1,
                      ),
                    ),
                    SizedBox(height: space.x3),
                    Text(
                      'A one-time code will be sent to your number',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colors.secondaryText,
                        height: 1.4,
                      ),
                    ),
                    SizedBox(height: space.x8),

                    // ── Phone input card ──────────────────────────────
                    CoolCard(
                      useGradient: false,
                      padding: EdgeInsets.zero,
                      backgroundColor: colors.cardSurface,
                      borderRadius: radii.sm,
                      child: Semantics(
                        textField: true,
                        label: l10n.phoneLabel,
                        hint: 'Enter your phone number',
                        child: Row(
                          children: [
                            // Country code prefix
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: space.x3,
                                vertical: space.x4,
                              ),
                              decoration: BoxDecoration(
                                border: Border(
                                  right: BorderSide(color: colors.border),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    currentCountry.flagEmoji,
                                    style: theme.textTheme.titleSmall
                                        ?.copyWith(height: 1),
                                  ),
                                  SizedBox(width: space.x1),
                                  Text(
                                    currentCountry.dialCode,
                                    style: theme.textTheme.bodyLarge
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: colors.primaryText,
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
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: colors.primaryText,
                                  letterSpacing: 0.8,
                                ),
                                cursorColor: colors.accent,
                                decoration: InputDecoration(
                                  hintText:
                                      currentCountry.mobileExampleNational,
                                  hintStyle: theme.textTheme.bodyLarge
                                      ?.copyWith(
                                        color: colors.tertiaryText.withValues(
                                          alpha: 0.5,
                                        ),
                                        letterSpacing: 0.5,
                                      ),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: space.x3,
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
                      SizedBox(height: space.x2),
                      Text(
                        _errorText!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.danger,
                        ),
                      ),
                    ],

                    const Spacer(),

                    // ── CTA ───────────────────────────────────────────
                    CoolButton(
                      label: l10n.otpContinue,
                      onTap: _sendOtp,
                      isLoading: authState.isLoading,
                    ),
                    SizedBox(height: space.x3),
                    Text.rich(
                      TextSpan(
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.tertiaryText,
                          height: 1.4,
                        ),
                        children: [
                          TextSpan(text: l10n.otpLegalPrefix),
                          TextSpan(
                            text: l10n.termsLabel,
                            style: TextStyle(color: colors.accent),
                            recognizer: _termsRecognizer,
                          ),
                          TextSpan(text: l10n.otpLegalAnd),
                          TextSpan(
                            text: l10n.privacyPolicyLabel,
                            style: TextStyle(color: colors.accent),
                            recognizer: _privacyRecognizer,
                          ),
                          const TextSpan(text: '.'),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: space.x6),
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
