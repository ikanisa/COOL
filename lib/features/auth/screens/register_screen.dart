import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/app_market.dart';
import '../../../core/config/country_catalog.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/phone_validator.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_text_field.dart';
import '../../../shared/widgets/momo_route_type_selector.dart';
import '../providers/auth_provider.dart';
import '../../../core/l10n/l10n.dart';

/// Profile setup screen shown after OTP verification for new users.
///
/// Collects the base passenger profile and wallet route after OTP verification.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({required this.phone, this.redirectPath, super.key});
  final String phone;
  final String? redirectPath;

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  late final TextEditingController _momoController;
  late final TextEditingController _momoCodeController;
  final _formKey = GlobalKey<FormState>();

  late MomoRecipientType _selectedMomoRouteType;
  String? _errorText;
  bool _showOptionalDetails = false;

  /// Rwanda is the only market.
  CoolCountry get _country => AppMarket.country;

  @override
  void initState() {
    super.initState();
    // Auto-populate MoMo number only for MTN Rwanda numbers.
    final shouldAutoFill = PhoneValidator.shouldAutoPopulateMomo(
      widget.phone,
      _country.isoCode,
    );
    final initialCountry = _country;
    _momoController = TextEditingController(
      text: shouldAutoFill
          ? initialCountry.normalizeNationalPhone(widget.phone)
          : '',
    );
    _momoCodeController = TextEditingController();
    _selectedMomoRouteType = _resolvePreferredRouteType(initialCountry);
  }

  @override
  void dispose() {
    _momoController.dispose();
    _momoCodeController.dispose();
    super.dispose();
  }

  MomoRecipientType _resolvePreferredRouteType(
    CoolCountry country, {
    MomoRecipientType? preferredRouteType,
  }) {
    if (!country.supportsMomoCode) {
      return MomoRecipientType.phoneNumber;
    }

    final hasNumber = _momoController.text.trim().isNotEmpty;
    final hasCode = _momoCodeController.text.trim().isNotEmpty;

    if (preferredRouteType == MomoRecipientType.code && hasCode) {
      return MomoRecipientType.code;
    }
    if (preferredRouteType == MomoRecipientType.phoneNumber && hasNumber) {
      return MomoRecipientType.phoneNumber;
    }
    if (hasCode && !hasNumber) {
      return MomoRecipientType.code;
    }
    return MomoRecipientType.phoneNumber;
  }

  String? _validateMomoNumber(CoolCountry country, String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      if (_selectedMomoRouteType == MomoRecipientType.phoneNumber) {
        return country.supportsMomoCode
            ? 'MoMo number is required for the selected default route'
            : 'MoMo number is required';
      }
      return null;
    }

    return PhoneValidator.validateMomoNumberForCountry(trimmed, country);
  }

  String? _validateMomoCode(CoolCountry country, String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      if (_selectedMomoRouteType == MomoRecipientType.code) {
        return 'MoMo code is required for the selected default route';
      }
      return null;
    }

    return PhoneValidator.validateMomoCode(trimmed, country: country);
  }

  Future<void> _createAccount() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _errorText = null);
    final selectedCountry = _country;

    final profile = await ref
        .read(authProvider.notifier)
        .createProfile(
          AuthProfileData(
            fullName: '',
            momoNumber: _momoController.text.trim(),
            momoCode:
                !selectedCountry.supportsMomoCode ||
                    _momoCodeController.text.trim().isEmpty
                ? null
                : _momoCodeController.text.trim(),
            momoRouteType: selectedCountry.supportsMomoCode
                ? _selectedMomoRouteType
                : MomoRecipientType.phoneNumber,
            momoProvider: selectedCountry.providerId,
            country: AppMarket.countryCode,
            languageCode: AppMarket.languageCode,
            isDriver: false,
            phone: widget.phone.trim().isEmpty ? null : widget.phone.trim(),
          ),
        );

    if (!mounted) return;

    if (profile != null) {
      context.go(widget.redirectPath ?? AppRoutes.profile);
    } else {
      final authState = ref.read(authProvider);
      setState(
        () => _errorText = authState.error ?? 'Failed to create profile',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final selectedCountry = _country;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          tooltip: context.l10n.back,
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.text),
        ),
      ),
      body: CoolScreenBackground(
        primaryColor: AppColors.accent,
        secondaryColor: AppColors.blue,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 96),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create Profile',
                  style: GoogleFonts.dmSans(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Setup your account to',
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text2,
                  ),
                ),
                const SizedBox(height: 24),

                if (widget.phone.isNotEmpty) ...[
                  _VerifiedPhoneCard(phoneNumber: widget.phone),
                  const SizedBox(height: 24),
                ],
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.blueGlow,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: AppColors.blue.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.badge_outlined,
                        color: AppColors.blue,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                           'Your name will be',
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Market (fixed to Rwanda) ──────────────────────────
                Text(
                  'Market',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text2,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Text(
                        selectedCountry.flagEmoji,
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${selectedCountry.name} ${selectedCountry.dialCode}',
                        style: GoogleFonts.dmSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── MOMO Number ────────────────────────────────────────
                CoolTextField(
                  label: context.l10n.mobileMoneyNumber,
                  hint: selectedCountry.phoneExampleHint(),
                  controller: _momoController,
                  keyboardType: TextInputType.phone,
                  prefixIcon: Icons.phone_rounded,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() => _errorText = null),
                  validator: (v) => _validateMomoNumber(selectedCountry, v),
                ),
                // Provider indicator
                Builder(
                  builder: (context) {
                    final label = PhoneValidator.providerLabel(
                      _momoController.text,
                      _country.isoCode,
                    );
                    if (label == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accentGlow,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          label,
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Semantics(
                  button: true,
                  label: _showOptionalDetails
                      ? 'Hide optional details'
                      : 'Show optional details',
                  child: GestureDetector(
                    onTap: () => setState(
                      () => _showOptionalDetails = !_showOptionalDetails,
                    ),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Text(
                            'Optional details',
                            style: GoogleFonts.dmSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text2,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            _showOptionalDetails
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            color: AppColors.text3,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 180),
                  crossFadeState: _showOptionalDetails
                      ? CrossFadeState.showFirst
                      : CrossFadeState.showSecond,
                  firstChild: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (selectedCountry.supportsMomoCode) ...[
                        const SizedBox(height: 8),
                        CoolTextField(
                          label: 'MoMo Code (optional)',
                          hint: selectedCountry.momoCodeExample ?? '123456',
                          controller: _momoCodeController,
                          keyboardType: TextInputType.number,
                          prefixIcon: Icons.tag_rounded,
                          textInputAction: TextInputAction.next,
                          onChanged: (_) => setState(() => _errorText = null),
                          validator: (v) =>
                              _validateMomoCode(selectedCountry, v),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Default receive route',
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        MomoRouteTypeSelector(
                          value: _selectedMomoRouteType,
                          onChanged: (value) {
                            setState(() {
                              _selectedMomoRouteType = value;
                              _errorText = null;
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        const SizedBox.shrink(),
                      ],
                    ],
                  ),
                  secondChild: const SizedBox.shrink(),
                ),
                const SizedBox(height: 24),

                // ── Error text ─────────────────────────────────────────
                if (_errorText != null) ...[
                  Text(
                    _errorText!,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.red,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // ── CTA ────────────────────────────────────────────────
                CoolButton(
                  label: context.l10n.createAccount,
                  onTap: _createAccount,
                  isLoading: authState.isLoading,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VerifiedPhoneCard extends StatelessWidget {
  const _VerifiedPhoneCard({required this.phoneNumber});

  final String phoneNumber;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.accentGlow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 18,
            color: AppColors.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Verified: $phoneNumber',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.accent,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}