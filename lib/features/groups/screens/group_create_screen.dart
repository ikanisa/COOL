import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_market.dart';
import '../../../core/config/country_catalog.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/money_formatters.dart';
import '../../../core/utils/phone_validator.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/core_detail_scaffold.dart';
import '../../../shared/widgets/cool_text_field.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../core/utils/user_error.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/widgets/require_verified_user.dart';
import '../providers/groups_provider.dart';
import '../widgets/group_form_widgets.dart';

class GroupCreateScreen extends ConsumerStatefulWidget {
  const GroupCreateScreen({super.key});

  @override
  ConsumerState<GroupCreateScreen> createState() => _GroupCreateScreenState();
}

class _GroupCreateScreenState extends ConsumerState<GroupCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _targetAmountController = TextEditingController();
  final _contributionAmountController = TextEditingController();
  final _momoNumberController = TextEditingController();
  final _momoCodeController = TextEditingController();

  String? _type;
  String? _frequency;
  MomoRecipientType _customMomoRouteType = MomoRecipientType.phoneNumber;
  bool _isSubmitting = false;

  void _setGroupType(String type) {
    setState(() {
      _type = type;
      if (type == 'saving') {
        _frequency = null;
      } else {
        _frequency = null;
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _targetAmountController.dispose();
    _contributionAmountController.dispose();
    _momoNumberController.dispose();
    _momoCodeController.dispose();
    super.dispose();
  }

  /// Derive frequency based on type rules:
  /// - saving: always recurring (daily/weekly/monthly), user must pick one
  /// - community private: always one_off
  /// - community public: can be one_off or recurring
  String get _effectiveFrequency {
    if (_type == 'saving') {
      return _frequency!; // daily, weekly, or monthly
    }
    // community private is always one_off
    return 'one_off';
  }

  Future<void> _submit() async {
    if (_isSubmitting) {
      return;
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_type == null) {
      CoolToast.error(context, context.l10n.groupValidationTypeRequired);
      return;
    }
    if (_type == 'saving' && _frequency == null) {
      CoolToast.error(context, context.l10n.groupValidationFrequencyRequired);
      return;
    }
    final selectedType = _type!;

    if (!await requireVerifiedUser(
      context,
      ref,
      feature: WhatsAppProtectedFeature.groupCreate,
    )) {
      return;
    }
    if (!mounted) {
      return;
    }

    final user = ref.read(authProvider).user;
    if (user == null) {
      CoolToast.error(context, context.l10n.groupCreateProfileMissing);
      return;
    }

    // Determine MoMo route values
    MomoRecipientType? routeType;
    String? recipientValue;
    if (_type == 'community') {
      recipientValue = _customMomoRouteType == MomoRecipientType.code
          ? _momoCodeController.text.trim()
          : _momoNumberController.text.trim();
      if (recipientValue.isEmpty) {
        recipientValue = null;
        routeType = null;
      } else {
        routeType = _customMomoRouteType;
      }
    } else {
      routeType = user.effectiveMomoRouteType;
      recipientValue = user.momoRecipientValue.trim();
      if (recipientValue.isEmpty) {
        recipientValue = null;
        routeType = null;
      }
    }

    final routeValidationError = _validateResolvedRoute(
      routeType: routeType,
      recipientValue: recipientValue,
    );
    if (routeValidationError != null) {
      CoolToast.error(context, routeValidationError);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final group = await ref
          .read(groupRepositoryProvider)
          .createGroup(
            creator: user,
            name: _nameController.text,
            visibility: 'private',
            type: selectedType,
            description: _descriptionController.text,
            targetAmount: _parseAmount(_targetAmountController.text),
            monthlyContribution: _parseAmount(
              _contributionAmountController.text,
            ),
            customMomoRouteType: routeType,
            customRecipientValue: recipientValue,
            frequency: _effectiveFrequency,
          );
      ref.read(groupsRefreshTickProvider.notifier).state++;
      if (!mounted) {
        return;
      }
      CoolToast.success(context, context.l10n.groupCreated);
      context.pop(group.id);
    } catch (error) {
      if (!mounted) {
        return;
      }
      CoolToast.error(context, describeUserFacingError(error));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final space = context.coolSpace;
    final country = AppMarket.country;
    final cur = country.currencyCode;
    final showFrequencyPicker = _type == 'saving';

    // Frequency is enforced at type-change time via setState callbacks below.

    return CoreDetailScaffold(
      title: Text(
        l10n.groupsCreateNewTitle,
        style: context.coolText.displayCondensed(
          theme.textTheme.headlineSmall,
          fontWeight: FontWeight.w800,
        ),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: space.x6),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CoolTextField(
                label: context.l10n.groupNameLabel,
                hint: context.l10n.groupNameHint,
                controller: _nameController,
                textInputAction: TextInputAction.next,
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) return l10n.groupNameRequired;
                  if (trimmed.length < 3) return l10n.groupNameTooShort;
                  return null;
                },
              ),
              SizedBox(height: space.x4),

              CoolTextField(
                label: l10n.groupDescriptionLabel,
                hint: l10n.groupDescriptionHint,
                controller: _descriptionController,
                maxLines: 2,
              ),
              SizedBox(height: space.x4),

              GroupSectionLabel(label: l10n.groupTypeSection),
              SizedBox(height: space.x2),
              GroupOptionRow(
                firstLabel: l10n.saving,
                firstSelected: _type == 'saving',
                onFirstTap: () => _setGroupType('saving'),
                secondLabel: l10n.community,
                secondSelected: _type == 'community',
                onSecondTap: () => _setGroupType('community'),
              ),

              if (showFrequencyPicker) ...[
                SizedBox(height: space.x4),
                GroupSectionLabel(label: l10n.groupFrequencySection),
                SizedBox(height: space.x2),
                GroupFrequencyPicker(
                  options: [
                    l10n.groupDailyLower,
                    l10n.groupWeeklyLower,
                    l10n.groupMonthlyLower,
                  ],
                  selected: _frequency,
                  onSelected: (freq) => setState(() => _frequency = freq),
                ),
              ],

              SizedBox(height: space.x4),
              CoolTextField(
                label: l10n.groupTargetLabel(cur),
                hint: l10n.groupTargetHint,
                controller: _targetAmountController,
                keyboardType: TextInputType.number,
                inputFormatters: const [GroupedThousandsInputFormatter()],
                validator: _validateOptionalAmount,
              ),
              SizedBox(height: space.x4),

              CoolTextField(
                label: l10n.groupContributionLabel(cur),
                hint: l10n.groupContributionHint,
                controller: _contributionAmountController,
                keyboardType: TextInputType.number,
                inputFormatters: const [GroupedThousandsInputFormatter()],
                validator: _validateOptionalAmount,
              ),
              SizedBox(height: space.x4),

              if (_type == 'community') ...[
                GroupMomoRouteSection(
                  routeType: _customMomoRouteType,
                  momoNumberController: _momoNumberController,
                  momoCodeController: _momoCodeController,
                  supportsMomoCode: country.supportsMomoCode,
                  momoNumberValidator: _validateCustomMomoNumber,
                  momoCodeValidator: _validateCustomMomoCode,
                  onRouteTypeChanged: (type) =>
                      setState(() => _customMomoRouteType = type),
                ),
                SizedBox(height: space.x6),
              ] else
                SizedBox(height: space.x2),

              CoolButton(
                label: l10n.groupCreateGroupUpper,
                onTap: _submit,
                isLoading: _isSubmitting,
              ),
            ],
          ),
        ),
      ),
    );
  }

  int? _parseAmount(String raw) {
    return parseWholeMoneyAmount(raw);
  }

  String? _validateOptionalAmount(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }

    final l10n = context.l10n;
    final amount = _parseAmount(trimmed);
    if (amount == null) {
      return l10n.groupValidationAmountInvalid;
    }
    if (amount <= 0) {
      return l10n.groupValidationAmountPositive;
    }
    return null;
  }

  String? _validateCustomMomoNumber(String? value) {
    if (_type != 'community' ||
        _customMomoRouteType != MomoRecipientType.phoneNumber) {
      return null;
    }
    if ((value?.trim().isEmpty ?? true)) {
      return null;
    }
    return PhoneValidator.validateMomoNumberForCountry(
      value ?? '',
      AppMarket.country,
    );
  }

  String? _validateCustomMomoCode(String? value) {
    if (_type != 'community' ||
        _customMomoRouteType != MomoRecipientType.code) {
      return null;
    }
    if ((value?.trim().isEmpty ?? true)) {
      return null;
    }
    return PhoneValidator.validateMomoCode(
      value ?? '',
      country: AppMarket.country,
    );
  }

  String? _validateResolvedRoute({
    required MomoRecipientType? routeType,
    required String? recipientValue,
  }) {
    final recipient = recipientValue?.trim() ?? '';
    if (recipient.isEmpty) {
      return null;
    }
    if (routeType == null) {
      return null;
    }

    return switch (routeType) {
      MomoRecipientType.phoneNumber =>
        PhoneValidator.validateMomoNumberForCountry(
          recipient,
          AppMarket.country,
        ),
      MomoRecipientType.code => PhoneValidator.validateMomoCode(
        recipient,
        country: AppMarket.country,
      ),
    };
  }
}
