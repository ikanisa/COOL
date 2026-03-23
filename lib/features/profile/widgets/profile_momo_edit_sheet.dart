import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/config/country_catalog.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/phone_validator.dart';
import '../../../shared/widgets/momo_route_type_selector.dart';

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
    final colors = context.coolSemanticColors;
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
                  color: colors.borderStrong,
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
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: 20),

          Text(
            l10n.momoNumberLabel.toUpperCase(),
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: colors.tertiaryText,
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
              style: GoogleFonts.dmSans(
                fontSize: 15,
                color: colors.primaryText,
              ),
              cursorColor: colors.accent,
              decoration: InputDecoration(
                hintText: country.phoneExampleHint(),
                hintStyle: GoogleFonts.dmSans(
                  fontSize: 15,
                  color: colors.tertiaryText.withValues(alpha: 0.5),
                ),
                filled: true,
                fillColor: colors.inputSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.accent),
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
                color: colors.contactSurface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _detectedProvider!,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.accent,
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
                color: colors.tertiaryText,
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
                style: GoogleFonts.dmSans(
                  fontSize: 15,
                  color: colors.primaryText,
                ),
                cursorColor: colors.accent,
                decoration: InputDecoration(
                  hintText: country.momoCodeExample ?? '12345',
                  hintStyle: GoogleFonts.dmSans(
                    fontSize: 15,
                    color: colors.tertiaryText.withValues(alpha: 0.5),
                  ),
                  filled: true,
                  fillColor: colors.inputSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colors.accent),
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
                color: colors.tertiaryText,
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
                backgroundColor: colors.buttonPrimaryBackground,
                foregroundColor: colors.accentForeground,
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
        color: colors.overlaySurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(top: false, child: content),
    );
  }
}
