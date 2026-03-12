import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/country_catalog.dart';
import '../../../core/config/app_config_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/phone_validator.dart';

// ═════════════════════════════════════════════════════════════════════════════
// LANGUAGE SHEET
// ═════════════════════════════════════════════════════════════════════════════

class ProfileLanguageSheet extends ConsumerWidget {
  const ProfileLanguageSheet({required this.current, super.key});

  final String current;

  static const _fallbackLanguages = [
    _LanguageOption('en', '🇬🇧', 'English'),
    _LanguageOption('fr', '🇫🇷', 'Français'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final langAsync = ref.watch(supportedLanguagesProvider);

    final languages = langAsync.when(
      data: (langs) => langs.isEmpty
          ? _fallbackLanguages
          : langs
                .map(
                  (l) => _LanguageOption(
                    l['code'] ?? 'en',
                    l['flag'] ?? '🏳️',
                    l['name'] ?? '',
                  ),
                )
                .toList(),
      loading: () => _fallbackLanguages,
      error: (_, _) => _fallbackLanguages,
    );

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border2,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              Text(
                'Language',
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 18),

              for (final lang in languages) ...[
                _buildLanguageTile(context, lang),
                if (lang != languages.last)
                  const Divider(color: AppColors.border, height: 1),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageTile(BuildContext context, _LanguageOption lang) {
    final isSelected = current == lang.code;

    return InkWell(
      onTap: () => Navigator.of(context).pop(lang.code),
      borderRadius: BorderRadius.circular(12),
      splashColor: AppColors.accentGlow,
      highlightColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Row(
          children: [
            Text(lang.flag, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                lang.label,
                style: GoogleFonts.dmSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? AppColors.accent : AppColors.text,
                ),
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle_rounded,
                size: 22,
                color: AppColors.accent,
              ),
          ],
        ),
      ),
    );
  }
}

class _LanguageOption {
  const _LanguageOption(this.code, this.flag, this.label);

  final String code;
  final String flag;
  final String label;
}

// ═════════════════════════════════════════════════════════════════════════════
// SIGN OUT DIALOG
// ═════════════════════════════════════════════════════════════════════════════

class ProfileSignOutDialog extends StatelessWidget {
  const ProfileSignOutDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.border),
      ),
      title: Text(
        'Sign Out',
        style: GoogleFonts.dmSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.text,
        ),
      ),
      content: Text(
        'You\'ll need to verify your number again to log back in.',
        style: GoogleFonts.dmSans(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.text2,
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'Cancel',
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.text2,
            ),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            'Sign Out',
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.red,
            ),
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// DELETE ACCOUNT DIALOG
// ═════════════════════════════════════════════════════════════════════════════

class ProfileDeleteAccountDialog extends StatelessWidget {
  const ProfileDeleteAccountDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        'Delete account?',
        style: GoogleFonts.dmSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.text,
        ),
      ),
      content: Text(
        'This permanently removes your account and data.',
        style: GoogleFonts.dmSans(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.text2,
          height: 1.45,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            'Cancel',
            style: GoogleFonts.dmSans(
              fontWeight: FontWeight.w700,
              color: AppColors.text2,
            ),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            'Delete',
            style: GoogleFonts.dmSans(
              fontWeight: FontWeight.w800,
              color: AppColors.red,
            ),
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// BLOCKING PROGRESS DIALOG
// ═════════════════════════════════════════════════════════════════════════════

class ProfileBlockingProgressDialog extends StatelessWidget {
  const ProfileBlockingProgressDialog({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      content: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// MOMO EDIT SHEET
// ═════════════════════════════════════════════════════════════════════════════

/// Result returned from [ProfileMomoEditSheet].
class ProfileMomoEditResult {
  const ProfileMomoEditResult({
    required this.countryCode,
    required this.momoNumber,
    this.momoCode,
  });

  final String countryCode;
  final String momoNumber;
  final String? momoCode;
}

/// Bottom sheet for editing MoMo number and code.
class ProfileMomoEditSheet extends StatefulWidget {
  const ProfileMomoEditSheet({
    required this.currentMomoNumber,
    required this.country,
    required this.availableCountries,
    this.currentMomoCode,
    super.key,
  });

  final String currentMomoNumber;
  final String? currentMomoCode;
  final CoolCountry country;
  final List<CoolCountry> availableCountries;

  @override
  State<ProfileMomoEditSheet> createState() => _ProfileMomoEditSheetState();
}

class _ProfileMomoEditSheetState extends State<ProfileMomoEditSheet> {
  late final TextEditingController _numberController;
  late final TextEditingController _codeController;
  late String _selectedCountryCode;
  String? _numberError;
  String? _codeError;
  String? _detectedProvider;

  CoolCountry get _selectedCountry =>
      CoolCountryCatalog.byIsoCode(
        _selectedCountryCode,
        source: widget.availableCountries,
      ) ??
      widget.country;

  @override
  void initState() {
    super.initState();
    _selectedCountryCode = widget.country.isoCode;
    // Show local format (strip +250) in the input for Rwandan numbers.
    final localNumber = widget.country.isoCode.toUpperCase() == 'RW'
        ? PhoneValidator.toRwandanLocal(widget.currentMomoNumber) ??
              widget.currentMomoNumber
        : widget.currentMomoNumber;
    _numberController = TextEditingController(text: localNumber);
    _codeController = TextEditingController(
      text: widget.country.supportsMomoCode ? widget.currentMomoCode ?? '' : '',
    );
    _updateProvider(localNumber);
  }

  @override
  void dispose() {
    _numberController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _updateProvider(String value) {
    final label = PhoneValidator.providerLabel(value, _selectedCountry.isoCode);
    if (mounted) setState(() => _detectedProvider = label);
  }

  void _save() {
    final number = _numberController.text.trim();
    final country = _selectedCountry;
    final code = country.supportsMomoCode ? _codeController.text.trim() : '';

    final numErr = PhoneValidator.validateMomoNumberForCountry(number, country);
    final codeErr = PhoneValidator.validateMomoCode(code, country: country);

    setState(() {
      _numberError = numErr;
      _codeError = codeErr;
    });

    if (numErr != null || codeErr != null) return;

    Navigator.of(context).pop(
      ProfileMomoEditResult(
        countryCode: country.isoCode,
        momoNumber: number,
        momoCode: code.isEmpty ? null : code,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final country = _selectedCountry;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(22, 12, 22, 22 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border2,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              Text(
                'Edit MoMo Info',
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'This number will be used for Mobile Money payments',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AppColors.text3,
                ),
              ),
              const SizedBox(height: 20),

              Text(
                'COUNTRY',
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text3,
                  letterSpacing: 1.2,
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
                    value: country.isoCode,
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
                    items: widget.availableCountries.map((item) {
                      return DropdownMenuItem<String>(
                        value: item.isoCode,
                        child: Text(item.pickerLabel),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value == null || value == _selectedCountryCode) {
                        return;
                      }
                      setState(() {
                        _selectedCountryCode = value;
                        _numberError = null;
                        _codeError = null;
                      });
                      _updateProvider(_numberController.text);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // MoMo Number
              Text(
                'MOMO NUMBER',
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text3,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _numberController,
                keyboardType: TextInputType.phone,
                style: GoogleFonts.dmSans(fontSize: 15, color: AppColors.text),
                cursorColor: AppColors.accent,
                decoration: InputDecoration(
                  hintText: country.phoneExampleHint(),
                  hintStyle: GoogleFonts.dmSans(
                    fontSize: 15,
                    color: AppColors.text3.withValues(alpha: 0.5),
                  ),
                  prefixText: '${country.dialCode} ',
                  prefixStyle: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text2,
                  ),
                  filled: true,
                  fillColor: AppColors.surface2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.accent),
                  ),
                  errorText: _numberError,
                ),
                onChanged: _updateProvider,
              ),

              // Provider chip
              if (_detectedProvider != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accentGlow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _detectedProvider!,
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ],

              // MoMo Code (if supported)
              if (country.supportsMomoCode) ...[
                const SizedBox(height: 20),
                Text(
                  'MOMO CODE (OPTIONAL)',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text3,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    color: AppColors.text,
                  ),
                  cursorColor: AppColors.accent,
                  decoration: InputDecoration(
                    hintText: country.momoCodeExample ?? '123456',
                    hintStyle: GoogleFonts.dmSans(
                      fontSize: 15,
                      color: AppColors.text3.withValues(alpha: 0.5),
                    ),
                    filled: true,
                    fillColor: AppColors.surface2,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.accent),
                    ),
                    errorText: _codeError,
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Save button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Save',
                    style: GoogleFonts.dmSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
