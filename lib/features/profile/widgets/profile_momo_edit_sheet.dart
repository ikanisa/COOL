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
  final MomoRecipientType? momoRouteType;
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
  }

  @override
  void dispose() {
    _numberController.dispose();
    _codeController.dispose();
    super.dispose();
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

    String? numErr;
    if (hasNumber) {
      numErr = PhoneValidator.validateMomoNumberForCountry(number, country);
    }

    String? codeErr;
    if (hasCode) {
      codeErr = PhoneValidator.validateMomoCode(code, country: country);
    }

    if (numErr != null || codeErr != null) {
      setState(() {
        _numberError = numErr;
        _codeError = codeErr;
        if (numErr != null) {
          _selectedRouteType = MomoRecipientType.phoneNumber;
        } else if (codeErr != null && country.supportsMomoCode) {
          _selectedRouteType = MomoRecipientType.code;
        }
      });
      return;
    }

    final selectedRouteType = country.supportsMomoCode
        ? _selectedRouteType
        : MomoRecipientType.phoneNumber;
    final resolvedRouteType = _resolveRouteTypeForSave(
      country: country,
      selectedRouteType: selectedRouteType,
      hasNumber: hasNumber,
      hasCode: hasCode,
    );

    final result = ProfileMomoEditResult(
      countryCode: country.isoCode,
      momoNumber: number,
      momoCode: code.isEmpty ? null : code,
      momoRouteType: resolvedRouteType,
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

  MomoRecipientType? _resolveRouteTypeForSave({
    required CoolCountry country,
    required MomoRecipientType selectedRouteType,
    required bool hasNumber,
    required bool hasCode,
  }) {
    if (!country.supportsMomoCode) {
      return hasNumber ? MomoRecipientType.phoneNumber : null;
    }
    if (hasNumber && hasCode) {
      return selectedRouteType;
    }
    if (hasNumber) {
      return MomoRecipientType.phoneNumber;
    }
    if (hasCode) {
      return MomoRecipientType.code;
    }
    return null;
  }

  bool get _showNumberEntry =>
      !widget.country.supportsMomoCode ||
      _selectedRouteType == MomoRecipientType.phoneNumber;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final l10n = context.l10n;
    final country = widget.country;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final showNumberEntry = _showNumberEntry;
    final activeController = showNumberEntry
        ? _numberController
        : _codeController;
    final activeSemanticLabel = showNumberEntry
        ? l10n.momoNumberLabel
        : l10n.merchantCode;
    final activeSemanticHint = showNumberEntry
        ? l10n.profileEnterMomoNumber
        : l10n.profileEnterMerchantCode;
    final activeHintText = showNumberEntry
        ? country.phoneExampleHint()
        : (country.momoCodeExample ?? '12345');
    final activeKeyboardType = showNumberEntry
        ? TextInputType.phone
        : TextInputType.number;
    final activeError = showNumberEntry ? _numberError : _codeError;
    final content = SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        22,
        widget.showSheetChrome ? 12 : 16,
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
                  borderRadius: BorderRadius.circular(CoolRadii.pill),
                ),
              ),
            ),
            const SizedBox(height: CoolSpace.x5),
            Text(
              l10n.profileEditMomoInfo,
              style: context.coolText.display(
                null,
                color: colors.primaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: CoolSpace.x5),
          ],

          if (country.supportsMomoCode) ...[
            MomoRouteTypeSelector(
              value: _selectedRouteType,
              onChanged: (value) {
                setState(() {
                  _selectedRouteType = value;
                  _numberError = null;
                  _codeError = null;
                });
              },
              phoneLabel: l10n.number,
              codeLabel: l10n.code,
            ),
            const SizedBox(height: CoolSpace.x4),
          ],

          AnimatedSwitcher(
            duration: CoolMotion.standard,
            switchInCurve: CoolMotion.enterCurve,
            switchOutCurve: CoolMotion.exitCurve,
            transitionBuilder: (child, animation) {
              final slide = Tween<Offset>(
                begin: const Offset(0.0, 0.08),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: slide, child: child),
              );
            },
            child: _MomoProfileInputCard(
              key: ValueKey<MomoRecipientType?>(
                country.supportsMomoCode ? _selectedRouteType : null,
              ),
              semanticLabel: activeSemanticLabel,
              semanticHint: activeSemanticHint,
              controller: activeController,
              keyboardType: activeKeyboardType,
              hintText: activeHintText,
              onChanged: (value) {
                setState(() {
                  if (showNumberEntry) {
                    _numberError = null;
                  } else {
                    _codeError = null;
                  }
                });
              },
            ),
          ),

          if (activeError != null) ...[
            const SizedBox(height: CoolSpace.x2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: CoolSpace.x2),
              child: Text(
                activeError,
                style: context.coolText.mobiLabel(color: colors.danger),
              ),
            ),
          ],

          const SizedBox(height: CoolSpace.x6),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.buttonPrimaryBackground,
                foregroundColor: colors.accentForeground,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(CoolRadii.xs),
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
                      style: context.coolText.manrope(
                        null,
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
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(CoolRadii.lg),
        ),
      ),
      child: SafeArea(top: false, child: content),
    );
  }
}

class _MomoProfileInputCard extends StatelessWidget {
  const _MomoProfileInputCard({
    required this.semanticLabel,
    required this.semanticHint,
    required this.controller,
    required this.keyboardType,
    required this.hintText,
    required this.onChanged,
    super.key,
  });

  final String semanticLabel;
  final String semanticHint;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final isDark = theme.brightness == Brightness.dark;

    return Semantics(
      textField: true,
      label: semanticLabel,
      hint: semanticHint,
      child: Container(
        constraints: const BoxConstraints(minHeight: 118),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? <Color>[colors.cardSurfaceStrong, colors.cardSurface]
                : const <Color>[Color(0xFFFDFEFF), Color(0xFFF6F9FF)],
          ),
          borderRadius: BorderRadius.circular(CoolRadii.xxl),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            textInputAction: TextInputAction.done,
            cursorColor: colors.accent,
            style: context.coolText
                .heroNumber(color: colors.primaryText)
                .copyWith(fontSize: 28, letterSpacing: -0.7, height: 1.0),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: context.coolText
                  .heroNumber(
                    color: colors.tertiaryText.withValues(alpha: 0.68),
                  )
                  .copyWith(fontSize: 28, letterSpacing: -0.7, height: 1.0),
              isCollapsed: true,
              isDense: true,
              filled: false,
              fillColor: Colors.transparent,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
            ),
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}
