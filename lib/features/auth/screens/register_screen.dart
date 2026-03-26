import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_market.dart';
import '../../../core/config/country_catalog.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/phone_validator.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
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
    final colors = context.coolSemanticColors;
    final radii = context.coolRadii;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    final authState = ref.watch(authProvider);
    final selectedCountry = _country;

    return Scaffold(
      backgroundColor: colors.appBackground,
      appBar: AppBar(
        automaticallyImplyLeading: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          tooltip: context.l10n.back,
          icon: Icon(Icons.arrow_back_rounded, color: colors.primaryText),
        ),
      ),
      body: CoolScreenBackground(
        primaryColor: colors.accent,
        secondaryColor: colors.info,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(space.x5, space.x3, space.x5, 96),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Finish setup',
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colors.primaryText,
                    height: 1.1,
                  ),
                ),
                SizedBox(height: space.x3),
                Text(
                  'Choose your default payout route.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colors.secondaryText,
                  ),
                ),
                SizedBox(height: space.x6),

                if (widget.phone.isNotEmpty) ...[
                  _VerifiedPhoneCard(phoneNumber: widget.phone),
                  SizedBox(height: space.x6),
                ],
                CoolCard(
                  padding: EdgeInsets.all(space.x4),
                  useGradient: false,
                  backgroundColor: colors.info.withValues(alpha: 0.08),
                  borderColor: colors.info.withValues(alpha: 0.18),
                  borderRadius: radii.lg,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.badge_outlined, color: colors.info, size: 20),
                      SizedBox(width: space.x3),
                      Expanded(
                        child: Text(
                          'Add name later in Profile.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.primaryText,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: space.x5),

                // ── Market (fixed to Rwanda) ──────────────────────────
                Text(
                  'Market',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colors.secondaryText,
                  ),
                ),
                SizedBox(height: space.x2),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: space.x3,
                    vertical: space.x3,
                  ),
                  decoration: BoxDecoration(
                    color: colors.cardSurface,
                    borderRadius: BorderRadius.all(Radius.circular(radii.sm)),
                    border: Border.all(color: colors.border),
                  ),
                  child: Row(
                    children: [
                      Text(
                        selectedCountry.flagEmoji,
                        style: theme.textTheme.titleSmall?.copyWith(height: 1),
                      ),
                      SizedBox(width: space.x2),
                      Text(
                        '${selectedCountry.name} ${selectedCountry.dialCode}',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: colors.primaryText,
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: space.x5),

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
                      padding: EdgeInsets.only(top: space.x2),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: space.x2,
                          vertical: space.x1,
                        ),
                        decoration: BoxDecoration(
                          color: colors.accent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.all(
                            Radius.circular(radii.xs),
                          ),
                        ),
                        child: Text(
                          label,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.accent,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                SizedBox(height: space.x4),
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
                      padding: EdgeInsets.symmetric(vertical: space.x1),
                      child: Row(
                        children: [
                          Text(
                            'Optional details',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colors.secondaryText,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            _showOptionalDetails
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            color: colors.tertiaryText,
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
                        SizedBox(height: space.x2),
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
                        SizedBox(height: space.x4),
                        Text(
                          'Default receive route',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.secondaryText,
                          ),
                        ),
                        SizedBox(height: space.x2),
                        MomoRouteTypeSelector(
                          value: _selectedMomoRouteType,
                          onChanged: (value) {
                            setState(() {
                              _selectedMomoRouteType = value;
                              _errorText = null;
                            });
                          },
                        ),
                        SizedBox(height: space.x2),
                        const SizedBox.shrink(),
                      ],
                    ],
                  ),
                  secondChild: const SizedBox.shrink(),
                ),
                SizedBox(height: space.x6),

                // ── Error text ─────────────────────────────────────────
                if (_errorText != null) ...[
                  Text(
                    _errorText!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colors.danger,
                    ),
                  ),
                  SizedBox(height: space.x3),
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
    final colors = context.coolSemanticColors;
    final radii = context.coolRadii;
    final space = context.coolSpace;
    final theme = Theme.of(context);

    return CoolCard(
      padding: EdgeInsets.all(space.x3),
      useGradient: false,
      backgroundColor: colors.accent.withValues(alpha: 0.08),
      borderColor: colors.accent,
      borderRadius: radii.sm,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_rounded, size: 18, color: colors.accent),
          SizedBox(width: space.x2),
          Expanded(
            child: Text(
              'Verified: $phoneNumber',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
                color: colors.accent,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
