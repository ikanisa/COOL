import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/country_catalog.dart';
import '../../../core/providers/supported_countries_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/phone_validator.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_text_field.dart';
import '../providers/auth_provider.dart';

/// Profile setup screen shown after OTP verification for new users.
///
/// Collects full name, MOMO info, optional vehicle type, and creates
/// the user profile via [AuthProvider.createProfile].
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({required this.phone, this.redirectPath, super.key});
  final String phone;
  final String? redirectPath;

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _nameController = TextEditingController();
  late final TextEditingController _momoController;
  late final TextEditingController _momoCodeController;
  final _formKey = GlobalKey<FormState>();

  late String _selectedCountryCode;
  String? _vehicleType;
  String? _errorText;
  bool _showOptionalDetails = false;

  @override
  void initState() {
    super.initState();
    _selectedCountryCode = CoolCountryCatalog.resolve(
      phone: widget.phone,
    ).isoCode;
    // Auto-populate MoMo number only for MTN Rwanda numbers.
    // Other numbers leave MoMo field empty for user to enter.
    final shouldAutoFill = PhoneValidator.shouldAutoPopulateMomo(
      widget.phone,
      _selectedCountryCode,
    );
    _momoController = TextEditingController(
      text: shouldAutoFill ? widget.phone : '',
    );
    _momoCodeController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _momoController.dispose();
    _momoCodeController.dispose();
    super.dispose();
  }

  Future<void> _createAccount() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _errorText = null);
    final languageCode = Localizations.localeOf(context).languageCode;
    final selectedCountry = await ref
        .read(supportedCountriesRepositoryProvider)
        .resolveCountry(
          countryCode: _selectedCountryCode,
          phone: _momoController.text.trim(),
        );

    final profile = await ref
        .read(authProvider.notifier)
        .createProfile(
          AuthProfileData(
            fullName: _nameController.text.trim(),
            momoNumber: selectedCountry.buildE164Phone(_momoController.text),
            momoCode:
                !selectedCountry.supportsMomoCode ||
                    _momoCodeController.text.trim().isEmpty
                ? null
                : selectedCountry.normalizeMerchantCode(
                    _momoCodeController.text,
                  ),
            momoProvider: selectedCountry.providerId,
            country: selectedCountry.isoCode,
            languageCode: languageCode,
            isDriver: _vehicleType != null,
            phone: widget.phone.trim().isEmpty ? null : widget.phone.trim(),
            vehicleType: _vehicleType,
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
    final countries =
        ref.watch(supportedCountriesProvider).valueOrNull ??
        CoolCountryCatalog.all;
    final selectedCountry =
        CoolCountryCatalog.byIsoCode(_selectedCountryCode, source: countries) ??
        CoolCountryCatalog.resolve(phone: widget.phone, source: countries);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: true,
        title: Text(
          'Finish profile',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
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
                const SizedBox(height: 12),

                if (widget.phone.isNotEmpty) ...[
                  _VerifiedPhoneCard(phoneNumber: widget.phone),
                  const SizedBox(height: 16),
                ],
                Text(
                  'Finish setup to start using Cool.',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: AppColors.text2,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 24),

                // ── Full Name ──────────────────────────────────────────
                CoolTextField(
                  label: 'Full Name',
                  hint: 'Jean Baptiste',
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // ── Country ────────────────────────────────────────────
                Text(
                  'Country',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text2,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: selectedCountry.isoCode,
                      dropdownColor: AppColors.surface2,
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppColors.text3,
                      ),
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text,
                      ),
                      items: countries.map((country) {
                        return DropdownMenuItem<String>(
                          value: country.isoCode,
                          child: Text(country.pickerLabel),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }

                        setState(() {
                          _selectedCountryCode = value;
                          final nextCountry =
                              CoolCountryCatalog.byIsoCode(
                                value,
                                source: countries,
                              ) ??
                              CoolCountryCatalog.resolve(
                                country: value,
                                source: countries,
                              );
                          if (!nextCountry.supportsMomoCode) {
                            _momoCodeController.clear();
                          }
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${selectedCountry.displayName} · ${selectedCountry.currencyCode}',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text3,
                  ),
                ),
                const SizedBox(height: 20),

                // ── MOMO Number ────────────────────────────────────────
                CoolTextField(
                  label: 'Mobile Money Number',
                  hint: selectedCountry.phoneExampleHint(),
                  controller: _momoController,
                  keyboardType: TextInputType.phone,
                  prefixIcon: Icons.phone_rounded,
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    return PhoneValidator.validateMomoNumberForCountry(
                      v ?? '',
                      selectedCountry,
                    );
                  },
                ),
                // Provider indicator
                Builder(
                  builder: (context) {
                    final label = PhoneValidator.providerLabel(
                      _momoController.text,
                      _selectedCountryCode,
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
                GestureDetector(
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
                          validator: (v) {
                            return PhoneValidator.validateMomoCode(
                              v ?? '',
                              country: selectedCountry,
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        'Vehicle Type (optional)',
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _vehicleOptions.map((opt) {
                          final isSelected = _vehicleType == opt.$2;
                          return GestureDetector(
                            onTap: () => setState(() {
                              _vehicleType = _vehicleType == opt.$2
                                  ? null
                                  : opt.$2;
                            }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.accentGlow
                                    : AppColors.surface2,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.accent
                                      : AppColors.border,
                                ),
                              ),
                              child: Text(
                                opt.$2,
                                style: GoogleFonts.dmSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: isSelected
                                      ? AppColors.accent
                                      : AppColors.text2,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
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
                  label: 'Create Account',
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

  static const _vehicleOptions = [
    (Icons.two_wheeler_rounded, 'Moto Taxi'),
    (Icons.directions_car_rounded, 'Cab'),
    (Icons.local_shipping_rounded, 'Truck'),
    (Icons.airport_shuttle_rounded, 'Liffan'),
    (Icons.directions_car_filled_rounded, 'Other'),
  ];
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
          const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.accent),
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
