import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/config/country_catalog.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';

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
        phoneError = message.isEmpty ? 'Invalid phone number' : message;
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
    final colors = context.coolSemanticColors;
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
                  color: colors.borderStrong,
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
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.cardSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.border),
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
                          color: colors.tertiaryText,
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
                            color: colors.secondaryText,
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
              color: colors.tertiaryText,
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
              style: GoogleFonts.dmSans(
                fontSize: 15,
                color: colors.primaryText,
              ),
              cursorColor: colors.accent,
              decoration: InputDecoration(
                hintText: 'Legal name for reports',
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
              color: colors.tertiaryText,
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
              style: GoogleFonts.dmSans(
                fontSize: 15,
                color: colors.primaryText,
              ),
              cursorColor: colors.accent,
              decoration: InputDecoration(
                hintText: widget.country.phoneExampleHint(),
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
                errorText: _phoneError,
                helperText: 'Use the real phone',
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
