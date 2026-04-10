import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_market.dart';
import '../../../core/config/country_catalog.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/phone_validator.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../auth/models/user_profile.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/widgets/require_verified_user.dart';
import '../models/biopay_enrollment_draft.dart';
import '../providers/biopay_providers.dart';
import '../widgets/biopay_surface.dart';

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
    final colors = context.coolSemanticColors;
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final activeProfile = ref.watch(biopayProfileProvider);
    final modelIssue = ref.watch(biopayModelAssetIssueProvider).valueOrNull;
    final country = _resolveCountry(user);
    final hasActiveEnrollment = activeProfile.valueOrNull?.active ?? false;
    final supportsCode = country.supportsMomoCode;
    final usesCodeRoute =
        supportsCode && _selectedRouteType == MomoRecipientType.code;

    return BiopayLightScaffold(
      topPadding: CoolSpace.x2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BiopayTopBar(
            title: 'Face ID Setup',
            onBack: () {
              if (context.canPop()) {
                context.pop();
                return;
              }
              context.go(AppRoutes.biopayHome);
            },
          ),
          const SizedBox(height: CoolSpace.x6),
          Text(
            'Link your face\nto your MoMo.',
            style: context.coolText.headline(
              Theme.of(context).textTheme.displayMedium,
              color: colors.primaryText,
              fontWeight: FontWeight.w900,
              letterSpacing: -2.2,
              height: 0.98,
            ),
          ),
          if (hasActiveEnrollment) ...[
            const SizedBox(height: CoolSpace.x4),
            _InlineNotice(
              color: colors.success,
              text: 'Face ID already linked. A new scan will replace it.',
            ),
          ],
          if (modelIssue != null) ...[
            const SizedBox(height: CoolSpace.x4),
            _InlineNotice(color: colors.danger, text: modelIssue),
          ],
          const SizedBox(height: CoolSpace.x6),
          if (supportsCode) ...[
            BiopaySegmentedControl(
              labels: const ['Number', 'Code'],
              selectedIndex: _selectedRouteType == MomoRecipientType.phoneNumber
                  ? 0
                  : 1,
              onSelected: (index) {
                setState(() {
                  _selectedRouteType = index == 0
                      ? MomoRecipientType.phoneNumber
                      : MomoRecipientType.code;
                  _numberError = null;
                  _codeError = null;
                });
              },
            ),
            const SizedBox(height: CoolSpace.x4),
          ],
          _BiopayInputField(
            label: usesCodeRoute ? 'Merchant Code' : 'MoMo Number',
            controller: usesCodeRoute
                ? _momoCodeController
                : _momoNumberController,
            keyboardType: TextInputType.number,
            errorText: usesCodeRoute ? _codeError : _numberError,
            onChanged: () {
              if (_numberError != null || _codeError != null) {
                setState(() {
                  _numberError = null;
                  _codeError = null;
                });
              }
            },
          ),
          const SizedBox(height: CoolSpace.x8),
          BiopayPrimaryButton(
            label: hasActiveEnrollment
                ? 'Update Enrollment'
                : 'Start Enrollment',
            isLoading: _isSubmitting,
            onTap: modelIssue != null ? null : _saveRouteAndContinue,
          ),
        ],
      ),
    );
  }

  Future<void> _saveRouteAndContinue() async {
    if (_isSubmitting) {
      return;
    }

    // Gate: require verified phone before face registration.
    final authState = ref.read(authProvider);
    final allowProfileRestoreFallback =
        authState.session != null &&
        authState.user == null &&
        authState.profileRestoreState == AuthProfileRestoreState.missing;
    if (!allowProfileRestoreFallback &&
        !await requireVerifiedUser(context, ref)) {
      return;
    }

    if (!await _ensureSession()) {
      if (mounted) {
        CoolToast.error(context, 'BioPay could not open a secure session.');
      }
      return;
    }

    final refreshedAuthState = ref.read(authProvider);
    final user = refreshedAuthState.user;
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
        displayName: _resolveDisplayName(refreshedAuthState),
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

class _BiopayInputField extends StatelessWidget {
  const _BiopayInputField({
    required this.label,
    required this.controller,
    required this.keyboardType,
    required this.onChanged,
    this.errorText,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final VoidCallback onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BiopaySectionCard(
          height: 136,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BiopayFieldLabel(label: label),
              const SizedBox(height: CoolSpace.x5),
              TextField(
                controller: controller,
                keyboardType: keyboardType,
                onChanged: (_) => onChanged(),
                style: context.coolText.headline(
                  Theme.of(context).textTheme.displaySmall,
                  color: colors.primaryText,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.4,
                ),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: '',
                  hintStyle: TextStyle(color: colors.tertiaryText),
                ),
              ),
            ],
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: CoolSpace.x2),
          Text(
            errorText!,
            style: context.coolText.mono(
              Theme.of(context).textTheme.bodyMedium,
              color: colors.danger,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: CoolSpace.x4,
        vertical: CoolSpace.x3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(CoolRadii.sm),
      ),
      child: Text(
        text,
        style: context.coolText.mono(
          Theme.of(context).textTheme.bodyMedium,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
