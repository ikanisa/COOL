import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/country_catalog.dart';
import '../../../core/config/env_config.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/providers/supported_countries_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/phone_validator.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../providers/auth_provider.dart';

/// Screen for entering a phone number to receive a WhatsApp OTP.
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
  String _selectedCountryCode = CoolCountryCatalog.defaultCountry.isoCode;
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
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _errorText = l10n.otpPhoneRequired);
      return;
    }

    // Validate phone number format per selected country.
    final selectedCountry =
        CoolCountryCatalog.byIsoCode(_selectedCountryCode) ??
        CoolCountryCatalog.defaultCountry;
    final validationError = PhoneValidator.validateOtpPhone(
      phone,
      selectedCountry,
    );
    if (validationError != null) {
      setState(() => _errorText = validationError);
      return;
    }

    setState(() => _errorText = null);

    try {
      final locale = Localizations.localeOf(context).languageCode;
      final fullPhone = PhoneValidator.buildOtpE164Phone(
        phone,
        selectedCountry,
      );

      // Determine language from locale (default "en").
      final language = locale == 'fr' ? 'fr' : 'en';

      await ref.read(authProvider.notifier).sendOtp(fullPhone, language);

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
    final countries =
        ref.watch(supportedCountriesProvider).valueOrNull ??
        CoolCountryCatalog.all;
    final selectedCountry =
        CoolCountryCatalog.byIsoCode(_selectedCountryCode, source: countries) ??
        CoolCountryCatalog.defaultCountry;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.go(
            AppRoutes.onboardingLocation(redirect: widget.redirectPath),
          ),
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.text),
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
                      l10n.otpUseWhatsappTitle,
                      style: GoogleFonts.dmSans(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.otpUseWhatsappSubtitle,
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        color: AppColors.text2,
                        height: 1.45,
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ── Combined country + phone input ────────────────
                    Container(
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          // Country code dropdown
                          GestureDetector(
                            onTap: () => _showCountryPicker(context, countries),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
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
                                    selectedCountry.flagEmoji,
                                    style: const TextStyle(fontSize: 18),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    selectedCountry.dialCode,
                                    style: GoogleFonts.dmSans(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.text,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    size: 18,
                                    color: AppColors.text3,
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Phone input
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
                                letterSpacing: 0.5,
                              ),
                              cursorColor: AppColors.accent,
                              decoration: InputDecoration(
                                hintText:
                                    selectedCountry.mobileExampleNational ??
                                        l10n.phoneHint,
                                hintStyle: GoogleFonts.dmSans(
                                  fontSize: 16,
                                  color: AppColors.text3.withValues(alpha: 0.5),
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

  void _showCountryPicker(BuildContext context, List<CoolCountry> countries) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface2,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.8,
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.text3.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: countries.length,
                  itemBuilder: (context, index) {
                    final country = countries[index];
                    return ListTile(
                      leading: Text(
                        country.flagEmoji,
                        style: const TextStyle(fontSize: 22),
                      ),
                      title: Text(
                        '${country.name}  ${country.dialCode}',
                        style: GoogleFonts.dmSans(
                          fontSize: 15,
                          color: AppColors.text,
                        ),
                      ),
                      trailing: _selectedCountryCode == country.isoCode
                          ? const Icon(
                              Icons.check_rounded,
                              color: AppColors.accent,
                            )
                          : null,
                      onTap: () {
                        setState(() => _selectedCountryCode = country.isoCode);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
