import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_market.dart';
import '../../../core/config/country_catalog.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/phone_validator.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_scaffold.dart';
import '../../../shared/widgets/cool_text_field.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/momo_route_type_selector.dart';
import '../../auth/models/user_profile.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/biopay_enrollment_draft.dart';
import '../providers/biopay_providers.dart';

class BiopayRegisterScreen extends ConsumerStatefulWidget {
  const BiopayRegisterScreen({super.key});

  @override
  ConsumerState<BiopayRegisterScreen> createState() =>
      _BiopayRegisterScreenState();
}

class _BiopayRegisterScreenState extends ConsumerState<BiopayRegisterScreen> {
  late final TextEditingController _momoNumberController;
  late final TextEditingController _momoCodeController;
  late MomoRecipientType _selectedRouteType;

  String? _numberError;
  String? _codeError;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    final country = _resolveCountry(user);
    final localNumber = _toLocalNumber(user?.momoNumber ?? '', country);
    final momoCode = country.supportsMomoCode
        ? user?.momoCode?.trim() ?? ''
        : '';

    _momoNumberController = TextEditingController(text: localNumber);
    _momoCodeController = TextEditingController(text: momoCode);
    _selectedRouteType = _resolveRouteType(
      country: country,
      preferredRouteType: user?.effectiveMomoRouteType,
      number: localNumber,
      code: momoCode,
    );
  }

  @override
  void dispose() {
    _momoNumberController.dispose();
    _momoCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final activeProfile = ref.watch(biopayProfileProvider);
    final modelIssue = ref.watch(biopayModelAssetIssueProvider).valueOrNull;
    final country = _resolveCountry(user);
    final hasActiveEnrollment = activeProfile.valueOrNull?.active ?? false;
    final usesCodeRoute =
        country.supportsMomoCode &&
        _selectedRouteType == MomoRecipientType.code;

    return CoolScreenScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Register My Face',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.15, end: 0),
          if (hasActiveEnrollment) ...[
            SizedBox(height: space.x4),
            const _RegisterNoticeCard(
              icon: Icons.verified_rounded,
              title: 'Face ID already registered',
              message: 'Continuing will replace the current face scan.',
            ),
          ],
          SizedBox(height: space.x5),
          if (country.supportsMomoCode) ...[
            const _FieldLabel(label: 'Receive With'),
            SizedBox(height: space.x3),
            MomoRouteTypeSelector(
              value: _selectedRouteType,
              phoneLabel: 'Number',
              codeLabel: 'Code',
              onChanged: (value) {
                setState(() {
                  _selectedRouteType = value;
                  _numberError = null;
                  _codeError = null;
                });
              },
            ),
            SizedBox(height: space.x5),
          ],
          CoolCard(
            variant: CoolCardVariant.outline,
            cardPadding: CoolCardPadding.lg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FieldLabel(label: usesCodeRoute ? 'MoMo Code' : 'MoMo Number'),
                SizedBox(height: space.x3),
                if (usesCodeRoute)
                  CoolTextField(
                    hint: country.momoCodeExample ?? '123456',
                    controller: _momoCodeController,
                    keyboardType: TextInputType.number,
                    prefixIcon: Icons.tag_rounded,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) {
                      if (_codeError != null) {
                        setState(() => _codeError = null);
                      }
                    },
                  )
                else
                  CoolTextField(
                    hint: country.phoneExampleHint(),
                    controller: _momoNumberController,
                    keyboardType: TextInputType.phone,
                    prefixIcon: Icons.phone_iphone_rounded,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) {
                      if (_numberError != null) {
                        setState(() => _numberError = null);
                      }
                    },
                  ),
                if (!usesCodeRoute && _numberError != null) ...[
                  SizedBox(height: space.x2),
                  _FieldError(message: _numberError!),
                ],
                if (usesCodeRoute && _codeError != null) ...[
                  SizedBox(height: space.x2),
                  _FieldError(message: _codeError!),
                ],
              ],
            ),
          ),
          if (modelIssue != null) ...[
            SizedBox(height: space.x4),
            _RegisterNoticeCard(
              icon: Icons.warning_amber_rounded,
              title: 'Face capture unavailable',
              message: modelIssue,
              isWarning: true,
            ),
          ],
          SizedBox(height: space.x5),
          CoolButton(
                label: hasActiveEnrollment ? 'Update Face Scan' : 'Continue',
                icon: Icons.arrow_forward_rounded,
                isLoading: _isSubmitting,
                onTap: modelIssue != null ? null : _saveRouteAndContinue,
              )
              .animate()
              .fadeIn(delay: 250.ms, duration: 400.ms)
              .scale(begin: const Offset(0.95, 0.95)),
        ],
      ),
    );
  }

  Future<void> _saveRouteAndContinue() async {
    if (_isSubmitting) {
      return;
    }

    if (!await _ensureSession()) {
      if (mounted) {
        CoolToast.error(context, 'BioPay could not open a secure session.');
      }
      return;
    }

    final authState = ref.read(authProvider);
    final user = authState.user;
    final country = _resolveCountry(user);
    final number = _momoNumberController.text.trim();
    final code = country.supportsMomoCode
        ? _momoCodeController.text.trim()
        : '';
    final usesCodeRoute =
        country.supportsMomoCode &&
        _selectedRouteType == MomoRecipientType.code;

    final numberError = usesCodeRoute
        ? null
        : PhoneValidator.validateMomoNumberForCountry(number, country);
    final codeError = usesCodeRoute
        ? PhoneValidator.validateMomoCode(
            code,
            country: country,
            required: true,
          )
        : null;

    setState(() {
      _numberError = numberError;
      _codeError = codeError;
    });

    if (numberError != null || codeError != null) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final routeType = usesCodeRoute
          ? MomoRecipientType.code
          : MomoRecipientType.phoneNumber;
      final recipientValue = usesCodeRoute
          ? country.normalizeMerchantCode(code)
          : country.normalizeNationalPhone(number);

      if (!mounted) {
        return;
      }

      final draft = BiopayEnrollmentDraft(
        displayName: _resolveDisplayName(authState),
        routeType: routeType,
        recipientValue: recipientValue,
        countryCode: country.isoCode,
        consentVersion: 'biopay-v1',
      );

      await context.push(
        AppRoutes.biopayScanLocation(mode: 'enroll'),
        extra: draft,
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<bool> _ensureSession() async {
    final authState = ref.read(authProvider);
    if (authState.session != null) {
      return true;
    }

    await ref.read(authProvider.notifier).signInAnonymously();
    return ref.read(authProvider).session != null;
  }

  CoolCountry _resolveCountry(UserProfile? user) {
    return CoolCountryCatalog.resolve(
      country: user?.country ?? AppMarket.countryCode,
      phone: user?.momoNumber,
      providerId: user?.momoProvider,
    );
  }

  String _toLocalNumber(String rawNumber, CoolCountry country) {
    final trimmed = rawNumber.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    try {
      return country.normalizeNationalPhone(trimmed);
    } catch (_) {
      return trimmed;
    }
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
    if (preferredRouteType == MomoRecipientType.code &&
        code.trim().isNotEmpty) {
      return MomoRecipientType.code;
    }
    if (preferredRouteType == MomoRecipientType.phoneNumber &&
        number.trim().isNotEmpty) {
      return MomoRecipientType.phoneNumber;
    }
    if (code.trim().isNotEmpty && number.trim().isEmpty) {
      return MomoRecipientType.code;
    }
    return MomoRecipientType.phoneNumber;
  }

  String _resolveDisplayName(AuthState authState) {
    final existingProfileName =
        ref.read(biopayProfileProvider).valueOrNull?.displayName.trim() ?? '';
    if (existingProfileName.isNotEmpty) {
      return existingProfileName;
    }

    final user = authState.user;
    final officialName = user?.officialName?.trim() ?? '';
    if (officialName.isNotEmpty) {
      return officialName;
    }
    final fullName = user?.fullName.trim() ?? '';
    if (fullName.isNotEmpty) {
      return fullName;
    }
    final metadata = Map<String, dynamic>.from(
      authState.session?.user.userMetadata ?? const <String, dynamic>{},
    );
    for (final candidate in <String?>[
      metadata['full_name']?.toString(),
      metadata['name']?.toString(),
    ]) {
      final trimmed = candidate?.trim() ?? '';
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return 'BioPay User';
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.labelMedium?.copyWith(
        color: colors.secondaryText,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    );
  }
}

class _RegisterNoticeCard extends StatelessWidget {
  const _RegisterNoticeCard({
    required this.icon,
    required this.title,
    required this.message,
    this.isWarning = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final tone = isWarning ? colors.warning : colors.accent;

    return CoolCard(
      variant: CoolCardVariant.outline,
      borderColor: tone.withValues(alpha: 0.35),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(CoolRadii.md),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: tone, size: 20),
          ),
          const SizedBox(width: CoolSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: CoolSpace.x1),
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.secondaryText,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldError extends StatelessWidget {
  const _FieldError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Text(
      message,
      style: theme.textTheme.bodySmall?.copyWith(
        color: colors.danger,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
