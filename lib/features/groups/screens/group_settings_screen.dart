import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/country_catalog.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/user_error.dart';
import '../../../shared/widgets/core_detail_scaffold.dart';
import '../../../shared/widgets/cool_text_field.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../models/group.dart';
import '../providers/groups_provider.dart';

class GroupSettingsScreen extends ConsumerStatefulWidget {
  const GroupSettingsScreen({required this.groupId, super.key});

  final String groupId;

  @override
  ConsumerState<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
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
        ? group.targetAmount.toString()
        : '';
    _contributionAmountController.text = (group.monthlyContribution ?? 0) > 0
        ? (group.monthlyContribution ?? 0).toString()
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
      await ref.read(groupRepositoryProvider).updateGroupSavingsSettings(
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
              fontWeight: FontWeight.w900,
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
                          return 'Enter a group name.';
                        }
                        if (trimmed.length < 3) {
                          return 'Use at least 3 characters.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: CoolSpace.x4),
                    CoolTextField(
                      label: 'Description (optional)',
                      hint: 'What is this group for?',
                      controller: _descriptionController,
                      maxLines: 3,
                    ),
                    const SizedBox(height: CoolSpace.x5),
                    CoolTextField(
                      label:
                          'Target Amount — ${country.currencyCode} (optional)',
                      hint: 'e.g. 500,000',
                      controller: _targetAmountController,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: CoolSpace.x4),
                    CoolTextField(
                      label:
                          'Contribution Amount — ${country.currencyCode} (optional)',
                      hint: 'e.g. 10,000',
                      controller: _contributionAmountController,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: CoolSpace.x5),
                    const _SectionLabel(label: 'FREQUENCY'),
                    const SizedBox(height: CoolSpace.x2),
                    _FrequencyPicker(
                      options: frequencyOptions,
                      selected: _frequency,
                      onSelected: (value) => setState(() => _frequency = value),
                    ),
                    const SizedBox(height: CoolSpace.x5),
                    _RouteCard(
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
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return null;
    }
    final value = int.tryParse(digits);
    if (value == null || value < 0) {
      return null;
    }
    return value;
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.routeType,
    required this.momoNumberController,
    required this.momoCodeController,
    required this.supportsMomoCode,
    required this.onRouteTypeChanged,
  });

  final MomoRecipientType routeType;
  final TextEditingController momoNumberController;
  final TextEditingController momoCodeController;
  final bool supportsMomoCode;
  final ValueChanged<MomoRecipientType> onRouteTypeChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final text = context.coolText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: colors.cardSurface,
            borderRadius: BorderRadius.circular(CoolRadii.sm),
            boxShadow: CoolShadows.ambientFloat(strength: 0.3),
          ),
          padding: const EdgeInsets.all(6),
          child: Row(
            children: [
              Expanded(
                child: _SegmentTab(
                  label: 'NUMBER',
                  selected: routeType == MomoRecipientType.phoneNumber,
                  onTap: () => onRouteTypeChanged(MomoRecipientType.phoneNumber),
                ),
              ),
              if (supportsMomoCode)
                Expanded(
                  child: _SegmentTab(
                    label: 'CODE',
                    selected: routeType == MomoRecipientType.code,
                    onTap: () => onRouteTypeChanged(MomoRecipientType.code),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: space.x3),
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: space.x5,
            vertical: space.x4,
          ),
          decoration: BoxDecoration(
            color: colors.cardSurface,
            borderRadius: BorderRadius.circular(CoolRadii.lg),
            boxShadow: CoolShadows.ambientFloat(strength: 0.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                routeType == MomoRecipientType.code
                    ? 'MERCHANT CODE'
                    : 'MOMO NUMBER',
                style: text.mobiLabel(color: colors.tertiaryText).copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6,
                  fontSize: 11,
                ),
              ),
              SizedBox(height: space.x2),
              TextField(
                controller: routeType == MomoRecipientType.code
                    ? momoCodeController
                    : momoNumberController,
                keyboardType: TextInputType.number,
                style: text.display(
                  Theme.of(context).textTheme.headlineSmall,
                  color: colors.primaryText,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
                decoration: InputDecoration(
                  hintText: routeType == MomoRecipientType.code
                      ? '23456'
                      : '0788123456',
                  hintStyle: text.display(
                    Theme.of(context).textTheme.headlineSmall,
                    color: colors.tertiaryText,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SegmentTab extends StatelessWidget {
  const _SegmentTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: CoolMotion.quick,
        curve: Curves.easeOut,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? colors.cardSurfaceStrong : Colors.transparent,
          borderRadius: BorderRadius.circular(CoolRadii.xs),
          boxShadow: selected ? CoolShadows.ambientFloat(strength: 0.4) : null,
        ),
        child: Text(
          label,
          style: context.coolText.mono(
            Theme.of(context).textTheme.labelLarge,
            color: selected ? colors.accent : colors.secondaryText,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.2,
          ),
        ),
      ),
    );
  }
}

class _FrequencyPicker extends StatelessWidget {
  const _FrequencyPicker({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;

  String _label(String value) {
    return switch (value) {
      'daily' => 'Daily',
      'weekly' => 'Weekly',
      'monthly' => 'Monthly',
      'one_off' => 'One-Off',
      _ => value,
    };
  }

  @override
  Widget build(BuildContext context) {
    final space = context.coolSpace;
    return Row(
      children: options
          .map(
            (option) => Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: option != options.last ? space.x2 : 0,
                ),
                child: _OptionChip(
                  label: _label(option),
                  selected: option == selected,
                  onTap: () => onSelected(option),
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: context.coolText.mobiLabel(
        color: context.coolSemanticColors.tertiaryText,
      ),
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CoolRadii.md),
      child: AnimatedContainer(
        duration: CoolMotion.quick,
        padding: const EdgeInsets.symmetric(vertical: CoolSpace.x3),
        decoration: BoxDecoration(
          color: selected ? colors.accent : colors.cardSurface,
          borderRadius: BorderRadius.circular(CoolRadii.md),
          boxShadow: selected ? null : CoolShadows.ambientFloat(strength: 0.2),
        ),
        alignment: Alignment.center,
        child: Text(
          label.toUpperCase(),
          style: text
              .mobiLabel(
                color: selected ? colors.accentForeground : colors.primaryText,
              )
              .copyWith(fontWeight: FontWeight.w800, letterSpacing: 1.0),
        ),
      ),
    );
  }
}
