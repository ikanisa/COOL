import 'dart:math';

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

  String get _initials {
    final name = _nameController.text.trim();
    if (name.isEmpty) return '??';
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0].substring(0, min(2, parts[0].length)).toUpperCase();
  }

  Future<void> _createAccount() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _errorText = null);
    final languageCode = Localizations.localeOf(context).languageCode;
    final selectedCountry = await ref
        .read(supportedCountriesRepositoryProvider)
        .resolveCountry(countryCode: _selectedCountryCode, phone: widget.phone);

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
          'Setup Profile',
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

                // ── Avatar preview ─────────────────────────────────────
                _AvatarPreview(initials: _initials),
                const SizedBox(height: 28),

                // ── Full Name ──────────────────────────────────────────
                CoolTextField(
                  label: 'Full Name',
                  hint: 'Jean Baptiste',
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}), // Update initials
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
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${selectedCountry.displayName} · ${selectedCountry.currencyCode}',
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Number route: ${selectedCountry.momoNumberUssdExample ?? selectedCountry.momoUssdTemplate.replaceAll('{recipient}', '91234567').replaceAll('{amount}', '5000')}',
                        style: GoogleFonts.dmMono(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text2,
                        ),
                      ),
                      if (selectedCountry.supportsMomoCode) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Code route: ${selectedCountry.momoCodeUssdExample ?? selectedCountry.momoCodeUssdTemplate!.replaceAll('{recipient}', '123456').replaceAll('{amount}', '5000')}',
                          style: GoogleFonts.dmMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppColors.text2,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        selectedCountry.currencyName,
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: AppColors.text3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── MOMO Number ────────────────────────────────────────
                CoolTextField(
                  label: 'Mobile Money Number',
                  hint: selectedCountry.phoneExampleHint(),
                  controller: _momoController,
                  keyboardType: TextInputType.phone,
                  prefixEmoji: '📱',
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
                if (selectedCountry.supportsMomoCode) ...[
                  const SizedBox(height: 16),
                  CoolTextField(
                    label: 'MoMo Code (optional)',
                    hint: selectedCountry.momoCodeExample ?? '123456',
                    controller: _momoCodeController,
                    keyboardType: TextInputType.number,
                    prefixEmoji: '🏷️',
                    textInputAction: TextInputAction.next,
                    validator: (v) {
                      return PhoneValidator.validateMomoCode(
                        v ?? '',
                        country: selectedCountry,
                      );
                    },
                  ),
                ],
                const SizedBox(height: 24),

                // ── Driver info banner ─────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.blue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.blue),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('📌', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Are you a driver? Add your vehicle type '
                          'to activate mobility features.',
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.blue,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Vehicle type selector ──────────────────────────────
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
                        _vehicleType = _vehicleType == opt.$2 ? null : opt.$2;
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
                          '${opt.$1} ${opt.$2}',
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
    ('🛺', 'Moto Taxi'),
    ('🚗', 'Cab'),
    ('🚛', 'Truck'),
    ('🚐', 'Liffan'),
    ('🚙', 'Other'),
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
          const Text('✅', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Verified WhatsApp number: $phoneNumber',
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

// ── Avatar preview ──────────────────────────────────────────────────────

class _AvatarPreview extends StatelessWidget {
  const _AvatarPreview({required this.initials});
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppColors.accentGradient,
        ),
        alignment: Alignment.center,
        child: Text(
          initials,
          style: GoogleFonts.dmSans(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}
