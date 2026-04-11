import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/country_catalog.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/money_formatters.dart';
import '../../../core/utils/phone_validator.dart';
import '../../../core/utils/user_error.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_metric_row.dart';
import '../../../shared/widgets/cool_section_card.dart';
import '../../../shared/widgets/cool_expandable_section.dart';
import '../../../shared/widgets/core_detail_scaffold.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/cool_text_field.dart';
import '../models/group.dart';
import '../providers/groups_provider.dart';
import '../widgets/group_form_widgets.dart';

class GroupSettingsScreen extends ConsumerStatefulWidget {
  const GroupSettingsScreen({required this.groupId, super.key});

  final String groupId;

  @override
  ConsumerState<GroupSettingsScreen> createState() =>
      _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends ConsumerState<GroupSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _targetAmountController = TextEditingController();
  final _contributionAmountController = TextEditingController();
  final _momoNumberController = TextEditingController();
  final _momoCodeController = TextEditingController();

  bool _seeded = false;
  bool _isSaving = false;
  String _frequency = 'monthly';
  MomoRecipientType _routeType = MomoRecipientType.phoneNumber;

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

  void _seedFromGroup(Group group) {
    if (_seeded) {
      return;
    }

    _seeded = true;
    _nameController.text = group.name;
    _descriptionController.text = group.description ?? '';
    _targetAmountController.text = group.targetAmount > 0
        ? formatWholeMoneyAmount(group.targetAmount)
        : '';
    _contributionAmountController.text = (group.monthlyContribution ?? 0) > 0
        ? formatWholeMoneyAmount(group.monthlyContribution ?? 0)
        : '';
    _frequency = group.frequency?.trim().isNotEmpty == true
        ? group.frequency!.trim().toLowerCase()
        : (group.type == 'saving' ? 'monthly' : 'one_off');
    _routeType = group.momoRouteType == 'code'
        ? MomoRecipientType.code
        : MomoRecipientType.phoneNumber;
    if (_routeType == MomoRecipientType.code) {
      _momoCodeController.text = group.momoNumber ?? '';
    } else {
      _momoNumberController.text = group.momoNumber ?? '';
    }
  }

  Future<void> _save(Group group) async {
    if (_isSaving) {
      return;
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final recipient = _routeType == MomoRecipientType.code
        ? _momoCodeController.text.trim()
        : _momoNumberController.text.trim();
    final country = CoolCountryCatalog.resolve(country: group.country);
    final routeValidationError = group.type == 'saving'
        ? null
        : _validateRoute(
            routeType: _routeType,
            recipientValue: recipient,
            country: country,
          );
    if (routeValidationError != null) {
      CoolToast.error(context, routeValidationError);
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref
          .read(groupRepositoryProvider)
          .updateGroupSavingsSettings(
            groupId: group.id ?? '',
            name: _nameController.text,
            description: _descriptionController.text,
            targetAmount: _parseAmount(_targetAmountController.text) ?? 0,
            monthlyContribution:
                _parseAmount(_contributionAmountController.text) ?? 0,
            frequency: _frequency,
            customMomoRouteType: _routeType,
            customRecipientValue: recipient,
          );
      ref.read(groupsRefreshTickProvider.notifier).state++;
      if (!mounted) {
        return;
      }
      context.pop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      CoolToast.error(context, describeUserFacingError(error));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupAsync = ref.watch(groupDetailProvider(widget.groupId));
    final accessAsync = ref.watch(groupAccessProvider(widget.groupId));

    return groupAsync.when(
      loading: () => const CoreDetailScaffold(
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => CoreDetailScaffold(
        child: CoolEmptyView(
          icon: CoolIcons.groupOff,
          title: context.l10n.groupSettings,
          message:
              'We could not load this group right now. Check your connection and try again.',
        ),
      ),
      data: (group) {
        if (group == null) {
          return CoreDetailScaffold(
            child: CoolEmptyView(
              icon: CoolIcons.groupOff,
              title: context.l10n.groupSettings,
              message: 'This group is no longer available.',
            ),
          );
        }

        final country = CoolCountryCatalog.resolve(country: group.country);
        _seedFromGroup(group);

        final access = accessAsync.valueOrNull;
        final canManage = access?.canManageSettings ?? false;
        final frequencyOptions = group.type == 'saving'
            ? const <String>['daily', 'weekly', 'monthly']
            : const <String>['one_off'];

        if (!frequencyOptions.contains(_frequency)) {
          _frequency = frequencyOptions.first;
        }

        return CoreDetailScaffold(
          title: Text(
            group.name,
            style: context.coolText.displayCondensed(
              Theme.of(context).textTheme.headlineSmall,
              fontWeight: FontWeight.w800,
            ),
          ),
          actions: canManage
              ? <Widget>[
                  IconButton(
                    onPressed: _isSaving ? null : () => _save(group),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(CoolIcons.check),
                  ),
                  const SizedBox(width: CoolSpace.x2),
                ]
              : null,
          child: accessAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => CoolEmptyView(
              icon: CoolIcons.lock,
              title: context.l10n.groupSettings,
              message:
                  'We could not verify your access to this group. Try again in a moment.',
            ),
            data: (snapshot) {
              if (snapshot == null || !snapshot.canManageSettings) {
                return CoolEmptyView(
                  icon: Icons.lock_outline_rounded,
                  title: context.l10n.groupSettings,
                  message:
                      'You do not have permission to change these settings.',
                );
              }

              return Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.only(bottom: CoolSpace.x7),
                  children: [
                    CoolTextField(
                      label: context.l10n.groupNameLabel,
                      hint: context.l10n.groupNameHint,
                      controller: _nameController,
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        final trimmed = value?.trim() ?? '';
                        if (trimmed.isEmpty) {
                          return context.l10n.groupNameRequired;
                        }
                        if (trimmed.length < 3) {
                          return context.l10n.groupNameMinimumThreeCharacters;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: CoolSpace.x3),
                    CoolTextField(
                      label: context.l10n.groupDescriptionOptionalLabel,
                      hint: context.l10n.groupDescriptionHint,
                      controller: _descriptionController,
                      maxLines: 3,
                    ),
                    const SizedBox(height: CoolSpace.x5),
                    CoolExpandableSection(
                      header: context.l10n.groupFrequencySection,
                      initiallyExpanded:
                          group.targetAmount > 0 ||
                          (group.monthlyContribution ?? 0) > 0,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CoolTextField(
                            label: context.l10n
                                .groupSettingsTargetAmountOptionalLabel(
                                  country.currencyCode,
                                ),
                            hint: context.l10n.groupSettingsTargetAmountHint,
                            controller: _targetAmountController,
                            keyboardType: TextInputType.number,
                            inputFormatters: const [
                              GroupedThousandsInputFormatter(),
                            ],
                            validator: _validateOptionalAmount,
                          ),
                          const SizedBox(height: CoolSpace.x3),
                          CoolTextField(
                            label: context.l10n
                                .groupSettingsContributionAmountOptionalLabel(
                                  country.currencyCode,
                                ),
                            hint: context
                                .l10n
                                .groupSettingsContributionAmountHint,
                            controller: _contributionAmountController,
                            keyboardType: TextInputType.number,
                            inputFormatters: const [
                              GroupedThousandsInputFormatter(),
                            ],
                            validator: _validateOptionalAmount,
                          ),
                          const SizedBox(height: CoolSpace.x3),
                          GroupFrequencyPicker(
                            options: frequencyOptions,
                            selected: _frequency,
                            onSelected: (value) =>
                                setState(() => _frequency = value),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x5),
                    if (group.type == 'saving') ...[
                      // Savings groups use a centralized MoMo code.
                      // Show read-only — managed by admin via app_config.
                      _CentralizedMomoNotice(momoCode: group.momoNumber ?? ''),
                    ] else
                      GroupMomoRouteSection(
                        routeType: _routeType,
                        momoNumberController: _momoNumberController,
                        momoCodeController: _momoCodeController,
                        supportsMomoCode: country.supportsMomoCode,
                        momoNumberValidator: (value) {
                          if (_routeType != MomoRecipientType.phoneNumber) {
                            return null;
                          }
                          return PhoneValidator.validateMomoNumberForCountry(
                            value ?? '',
                            country,
                          );
                        },
                        momoCodeValidator: (value) {
                          if (_routeType != MomoRecipientType.code) {
                            return null;
                          }
                          return PhoneValidator.validateMomoCode(
                            value ?? '',
                            country: country,
                            required: true,
                          );
                        },
                        onRouteTypeChanged: (value) =>
                            setState(() => _routeType = value),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  int? _parseAmount(String raw) {
    return parseWholeMoneyAmount(raw, allowZero: true);
  }

  String? _validateOptionalAmount(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }

    final amount = _parseAmount(trimmed);
    if (amount == null) {
      return 'Enter a valid amount.';
    }
    if (amount < 0) {
      return 'Amount cannot be negative.';
    }
    return null;
  }

  String? _validateRoute({
    required MomoRecipientType routeType,
    required String recipientValue,
    required CoolCountry country,
  }) {
    return switch (routeType) {
      MomoRecipientType.phoneNumber =>
        PhoneValidator.validateMomoNumberForCountry(recipientValue, country),
      MomoRecipientType.code => PhoneValidator.validateMomoCode(
        recipientValue,
        country: country,
        required: true,
      ),
    };
  }
}

class _CentralizedMomoNotice extends StatelessWidget {
  const _CentralizedMomoNotice({required this.momoCode});

  final String momoCode;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final l10n = context.l10n;

    return CoolSectionCard(
      sectionLabel: l10n.groupSettingsMomoCollectionCodeLabel,
      children: [
        CoolMetricRow.mono(
          label: l10n.momoCode,
          value: momoCode.isNotEmpty ? momoCode : '—',
        ),
        Text(
          l10n.groupSettingsMomoSetByAdmin,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.tertiaryText),
        ),
      ],
    );
  }
}
