import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/country_catalog.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/money_formatters.dart';
import '../../../core/utils/user_error.dart';
import '../../../shared/widgets/core_detail_scaffold.dart';
import '../../../shared/widgets/cool_card.dart';
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
        child: Center(
          child: Icon(
            Icons.group_off_rounded,
            size: 40,
            color: context.coolSemanticColors.tertiaryText,
          ),
        ),
      ),
      data: (group) {
        if (group == null) {
          return CoreDetailScaffold(
            child: Center(
              child: Icon(
                Icons.group_off_rounded,
                size: 40,
                color: context.coolSemanticColors.tertiaryText,
              ),
            ),
          );
        }

        _seedFromGroup(group);

        final access = accessAsync.valueOrNull;
        final canManage = access?.canManageSettings ?? false;
        final country = CoolCountryCatalog.resolve(country: group.country);
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
                        : const Icon(Icons.check_rounded),
                  ),
                  const SizedBox(width: CoolSpace.x2),
                ]
              : null,
          child: accessAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: Icon(
                Icons.lock_outline_rounded,
                size: 40,
                color: context.coolSemanticColors.tertiaryText,
              ),
            ),
            data: (snapshot) {
              if (snapshot == null || !snapshot.canManageSettings) {
                return Center(
                  child: Icon(
                    Icons.lock_outline_rounded,
                    size: 40,
                    color: context.coolSemanticColors.tertiaryText,
                  ),
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
                    const SizedBox(height: CoolSpace.x4),
                    CoolTextField(
                      label: context.l10n.groupDescriptionOptionalLabel,
                      hint: context.l10n.groupDescriptionHint,
                      controller: _descriptionController,
                      maxLines: 3,
                    ),
                    const SizedBox(height: CoolSpace.x5),
                    CoolTextField(
                      label: context.l10n
                          .groupSettingsTargetAmountOptionalLabel(
                            country.currencyCode,
                          ),
                      hint: context.l10n.groupSettingsTargetAmountHint,
                      controller: _targetAmountController,
                      keyboardType: TextInputType.number,
                      inputFormatters: const [GroupedThousandsInputFormatter()],
                    ),
                    const SizedBox(height: CoolSpace.x4),
                    CoolTextField(
                      label: context.l10n
                          .groupSettingsContributionAmountOptionalLabel(
                            country.currencyCode,
                          ),
                      hint: context.l10n.groupSettingsContributionAmountHint,
                      controller: _contributionAmountController,
                      keyboardType: TextInputType.number,
                      inputFormatters: const [GroupedThousandsInputFormatter()],
                    ),
                    const SizedBox(height: CoolSpace.x5),
                    GroupSectionLabel(
                      label: context.l10n.groupFrequencySection,
                    ),
                    const SizedBox(height: CoolSpace.x2),
                    GroupFrequencyPicker(
                      options: frequencyOptions,
                      selected: _frequency,
                      onSelected: (value) => setState(() => _frequency = value),
                    ),
                    const SizedBox(height: CoolSpace.x5),
                    if (group.type == 'saving') ...[
                      // Savings groups use a centralized MoMo code.
                      // Show read-only — managed by admin via app_config.
                      _CentralizedMomoNotice(
                        momoCode: group.momoNumber ?? '',
                      ),
                    ] else
                      GroupMomoRouteSection(
                        routeType: _routeType,
                        momoNumberController: _momoNumberController,
                        momoCodeController: _momoCodeController,
                        supportsMomoCode: country.supportsMomoCode,
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
}

class _CentralizedMomoNotice extends StatelessWidget {
  const _CentralizedMomoNotice({required this.momoCode});

  final String momoCode;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);

    return CoolCard(
      borderRadius: CoolRadii.xl,
      backgroundColor: colors.cardSurfaceStrong,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'COLLECTION CODE',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.tertiaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            momoCode.isNotEmpty ? momoCode : '—',
            style: text.mono(
              theme.textTheme.headlineSmall,
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            'Set by admin for all savings groups.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.tertiaryText,
            ),
          ),
        ],
      ),
    );
  }
}
