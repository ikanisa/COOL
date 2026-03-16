import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/config/country_catalog.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/phone_validator.dart';
import '../../../shared/widgets/momo_route_type_selector.dart';

// ═════════════════════════════════════════════════════════════════════════════
// SIGN OUT DIALOG
// ═════════════════════════════════════════════════════════════════════════════

class ProfileSignOutDialog extends StatelessWidget {
  const ProfileSignOutDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.border),
      ),
      title: Text(
        l10n.signOutAction,
        style: GoogleFonts.dmSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.text,
        ),
      ),
      content: Text(
        l10n.signOutMessage,
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
            l10n.cancelAction,
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
            l10n.signOutAction,
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
    final l10n = context.l10n;
    return AlertDialog(
      backgroundColor: AppColors.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        l10n.deleteAccountQuestion,
        style: GoogleFonts.dmSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.text,
        ),
      ),
      content: Text(
        l10n.deleteAccountMessage,
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
            l10n.cancelAction,
            style: GoogleFonts.dmSans(
              fontWeight: FontWeight.w700,
              color: AppColors.text2,
            ),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            l10n.delete,
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
            child: CupertinoActivityIndicator(radius: 11),
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
    required this.momoRouteType,
  });

  final String countryCode;
  final String momoNumber;
  final String? momoCode;
  final MomoRecipientType momoRouteType;
}

/// Bottom sheet for editing MoMo number and code.
class ProfileMomoEditSheet extends StatefulWidget {
  const ProfileMomoEditSheet({
    required this.currentMomoNumber,
    required this.country,
    this.currentMomoCode,
    this.currentMomoRouteType,
    this.onSubmitted,
    this.showSheetChrome = true,
    super.key,
  });

  final String currentMomoNumber;
  final String? currentMomoCode;
  final MomoRecipientType? currentMomoRouteType;
  final CoolCountry country;
  final Future<void> Function(ProfileMomoEditResult result)? onSubmitted;
  final bool showSheetChrome;

  @override
  State<ProfileMomoEditSheet> createState() => _ProfileMomoEditSheetState();
}

class _ProfileMomoEditSheetState extends State<ProfileMomoEditSheet> {
  late final TextEditingController _numberController;
  late final TextEditingController _codeController;
  late MomoRecipientType _selectedRouteType;
  String? _numberError;
  String? _codeError;
  String? _detectedProvider;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final localNumber = widget.currentMomoNumber.trim().isEmpty
        ? ''
        : () {
            try {
              return widget.country.normalizeNationalPhone(
                widget.currentMomoNumber,
              );
            } catch (_) {
              return widget.currentMomoNumber;
            }
          }();
    _numberController = TextEditingController(text: localNumber);
    _codeController = TextEditingController(
      text: widget.country.supportsMomoCode ? widget.currentMomoCode ?? '' : '',
    );
    _selectedRouteType = _resolveRouteType(
      country: widget.country,
      preferredRouteType: widget.currentMomoRouteType,
      number: localNumber,
      code: _codeController.text,
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
    final label = PhoneValidator.providerLabel(value, widget.country.isoCode);
    if (mounted) setState(() => _detectedProvider = label);
  }

  MomoRecipientType _resolveRouteType({
    required CoolCountry country,
    MomoRecipientType? preferredRouteType,
    required String number,
    required String code,
  }) {
    if (!country.supportsMomoCode) {
      return MomoRecipientType.phoneNumber;
    }

    final hasNumber = number.trim().isNotEmpty;
    final hasCode = code.trim().isNotEmpty;

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

  Future<void> _save() async {
    final number = _numberController.text.trim();
    final country = widget.country;
    final code = country.supportsMomoCode ? _codeController.text.trim() : '';
    final hasCode = code.isNotEmpty;
    final hasNumber = number.isNotEmpty;
    final selectedRouteType = country.supportsMomoCode
        ? _selectedRouteType
        : MomoRecipientType.phoneNumber;

    String? numErr;
    if (hasNumber) {
      numErr = PhoneValidator.validateMomoNumberForCountry(number, country);
    } else if (selectedRouteType == MomoRecipientType.phoneNumber) {
      numErr = country.supportsMomoCode
          ? 'MoMo number required'
          : 'MoMo number is required';
    }

    String? codeErr;
    if (hasCode) {
      codeErr = PhoneValidator.validateMomoCode(code, country: country);
    } else if (country.supportsMomoCode &&
        selectedRouteType == MomoRecipientType.code) {
      codeErr = 'MoMo code required';
    }

    setState(() {
      _numberError = numErr;
      _codeError = codeErr;
    });

    if (numErr != null || codeErr != null) return;

    final result = ProfileMomoEditResult(
      countryCode: country.isoCode,
      momoNumber: number,
      momoCode: code.isEmpty ? null : code,
      momoRouteType: selectedRouteType,
    );

    if (widget.onSubmitted != null) {
      setState(() => _isSubmitting = true);
      try {
        await widget.onSubmitted!(result);
      } finally {
        if (mounted) {
          setState(() => _isSubmitting = false);
        }
      }
      return;
    }

    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final country = widget.country;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final content = SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        22,
        widget.showSheetChrome ? 12 : 18,
        22,
        22 + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showSheetChrome) ...[
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
          ],

          Text(
            l10n.profileEditMomoInfo,
            style: GoogleFonts.dmSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 20),

          Text(
            l10n.momoNumberLabel.toUpperCase(),
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.text3,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Semantics(
            textField: true,
            label: l10n.momoNumberLabel,
            hint: 'Enter MoMo number',
            child: TextField(
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
                  borderSide: const BorderSide(color: AppColors.accent),
                ),
                errorText: _numberError,
              ),
              onChanged: _updateProvider,
            ),
          ),

          if (_detectedProvider != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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

          if (country.supportsMomoCode) ...[
            const SizedBox(height: 20),
            Text(
              l10n.profileMomoCodeOptional,
              style: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.text3,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Semantics(
              textField: true,
              label: l10n.profileMomoCodeOptional,
              hint: 'Enter merchant code',
              child: TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                style: GoogleFonts.dmSans(fontSize: 15, color: AppColors.text),
                cursorColor: AppColors.accent,
                decoration: InputDecoration(
                  hintText: country.momoCodeExample ?? '12345',
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
                    borderSide: const BorderSide(color: AppColors.accent),
                  ),
                  errorText: _codeError,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'DEFAULT RECEIVE ROUTE',
              style: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.text3,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            MomoRouteTypeSelector(
              value: _selectedRouteType,
              onChanged: (value) {
                setState(() {
                  _selectedRouteType = value;
                  _numberError = null;
                  _codeError = null;
                });
              },
            ),
          ],

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CupertinoActivityIndicator(radius: 9),
                    )
                  : Text(
                      l10n.save,
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );

    if (!widget.showSheetChrome) {
      return content;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(top: false, child: content),
    );
  }
}

class ProfileOfficialIdentityEditResult {
  const ProfileOfficialIdentityEditResult({
    required this.officialName,
    required this.officialPhone,
  });

  final String officialName;
  final String officialPhone;
}

class ProfileOfficialIdentityEditSheet extends StatefulWidget {
  const ProfileOfficialIdentityEditSheet({
    required this.currentOfficialName,
    required this.currentOfficialPhone,
    required this.country,
    required this.kycLabel,
    required this.kycValueColor,
    this.kycVerifiedAt,
    this.onSubmitted,
    this.showSheetChrome = true,
    super.key,
  });

  final String currentOfficialName;
  final String currentOfficialPhone;
  final CoolCountry country;
  final String kycLabel;
  final Color kycValueColor;
  final DateTime? kycVerifiedAt;
  final Future<void> Function(ProfileOfficialIdentityEditResult result)?
  onSubmitted;
  final bool showSheetChrome;

  @override
  State<ProfileOfficialIdentityEditSheet> createState() =>
      _ProfileOfficialIdentityEditSheetState();
}

class _ProfileOfficialIdentityEditSheetState
    extends State<ProfileOfficialIdentityEditSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  String? _nameError;
  String? _phoneError;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentOfficialName);
    _phoneController = TextEditingController(text: widget.currentOfficialPhone);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final officialName = _nameController.text.trim();
    final officialPhone = _phoneController.text.trim();
    final hasName = officialName.isNotEmpty;
    final hasPhone = officialPhone.isNotEmpty;

    String? nameError;
    String? phoneError;
    if (hasName != hasPhone) {
      nameError = hasName ? null : 'Name required';
      phoneError = hasPhone ? null : 'Phone required';
    } else if (hasPhone) {
      try {
        widget.country.normalizeNationalPhone(officialPhone);
      } on FormatException catch (error) {
        final message = error.message.toString().trim();
        phoneError = message.isEmpty
            ? 'Invalid phone number'
            : message;
      }
    }

    setState(() {
      _nameError = nameError;
      _phoneError = phoneError;
    });

    if (nameError != null || phoneError != null) {
      return;
    }

    final normalizedPhone = officialPhone.isEmpty
        ? ''
        : widget.country.normalizeNationalPhone(officialPhone);
    final result = ProfileOfficialIdentityEditResult(
      officialName: officialName,
      officialPhone: normalizedPhone,
    );

    if (widget.onSubmitted != null) {
      setState(() => _isSubmitting = true);
      try {
        await widget.onSubmitted!(result);
      } finally {
        if (mounted) {
          setState(() => _isSubmitting = false);
        }
      }
      return;
    }

    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final verifiedAt = widget.kycVerifiedAt == null
        ? null
        : DateFormat.yMMMd().format(widget.kycVerifiedAt!.toLocal());
    final content = SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        22,
        widget.showSheetChrome ? 12 : 18,
        22,
        22 + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showSheetChrome) ...[
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
          ],
          Text(
            'Official identity',
            style: GoogleFonts.dmSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: widget.kycValueColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.verified_user_outlined,
                    size: 20,
                    color: widget.kycValueColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'KYC status',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.kycLabel,
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: widget.kycValueColor,
                        ),
                      ),
                      if (verifiedAt != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Verified on $verifiedAt',
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.text2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.nameLabel.toUpperCase(),
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.text3,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Semantics(
            textField: true,
            label: l10n.nameLabel,
            hint: 'Enter legal name',
            child: TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              style: GoogleFonts.dmSans(fontSize: 15, color: AppColors.text),
              cursorColor: AppColors.accent,
              decoration: InputDecoration(
                hintText: 'Legal name for reports',
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
                  borderSide: const BorderSide(color: AppColors.accent),
                ),
                errorText: _nameError,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.phoneLabel.toUpperCase(),
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.text3,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Semantics(
            textField: true,
            label: l10n.phoneLabel,
            hint: 'Enter phone number',
            child: TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              style: GoogleFonts.dmSans(fontSize: 15, color: AppColors.text),
              cursorColor: AppColors.accent,
              decoration: InputDecoration(
                hintText: widget.country.phoneExampleHint(),
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
                  borderSide: const BorderSide(color: AppColors.accent),
                ),
                errorText: _phoneError,
                helperText:
                    'Use the real phone',
                helperMaxLines: 2,
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CupertinoActivityIndicator(radius: 9),
                    )
                  : Text(
                      l10n.save,
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );

    if (!widget.showSheetChrome) {
      return content;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(top: false, child: content),
    );
  }
}
