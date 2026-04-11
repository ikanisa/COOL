import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_market.dart';
import '../../../core/config/country_catalog.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
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

  String _type = 'saving';
  String _frequency = 'monthly';
  bool _useCustomMomo = false;
  MomoRecipientType _customMomoRouteType = MomoRecipientType.phoneNumber;
  bool _isSubmitting = false;

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
      return _frequency; // daily, weekly, or monthly
    }
    // community private is always one_off (handled via visibility=private default)
    // community public can be one_off or recurring
    return _frequency;
  }

  Future<void> _submit() async {
    if (_isSubmitting) {
      return;
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Gate: require verified phone before creating a group.
    if (!await requireVerifiedUser(context, ref)) {
      return;
    }
    if (!mounted) {
      return;
    }

    final user = ref.read(authProvider).user;
    if (user == null) {
      CoolToast.error(context, 'Verification completed but profile missing.');
      return;
    }

    // Determine MoMo route values
    MomoRecipientType? routeType;
    String? recipientValue;
    if (_useCustomMomo) {
      routeType = _customMomoRouteType;
      recipientValue = _customMomoRouteType == MomoRecipientType.code
          ? _momoCodeController.text.trim()
          : _momoNumberController.text.trim();
      if (recipientValue.isEmpty) {
        recipientValue = null;
      }
    } else {
      routeType = user.effectiveMomoRouteType;
      recipientValue = user.momoRecipientValue.trim();
      if (recipientValue.isEmpty) {
        recipientValue = null;
      }
    }

    setState(() => _isSubmitting = true);
    try {
      final group = await ref
          .read(groupRepositoryProvider)
          .createGroup(
            creator: user,
            name: _nameController.text,
            visibility: 'private',
            type: _type,
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
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final country = AppMarket.country;

    // Frequency: saving = recurring (picker), community = always one_off
    // (all user-created groups are private; community private = one_off)
    final showFrequencyPicker = _type == 'saving';

    // Force community to one_off
    if (_type == 'community' && _frequency != 'one_off') {
      _frequency = 'one_off';
    }

    return CoreDetailScaffold(
      title: Text(
        context.l10n.groupsCreateNewTitle,
        style: context.coolText.displayCondensed(
          theme.textTheme.headlineSmall,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        context.l10n.groupsCreateNewSubtitle,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colors.secondaryText,
        ),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: space.x6),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Group Name (required) ─────────────────────────────
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
              SizedBox(height: space.x4),

              // ── Description (optional) ────────────────────────────
              CoolTextField(
                label: 'Description (optional)',
                hint: 'What is this group for?',
                controller: _descriptionController,
                maxLines: 3,
              ),
              SizedBox(height: space.x5),

              // ── Type ──────────────────────────────────────────────
              const GroupSectionLabel(label: 'TYPE'),
              SizedBox(height: space.x2),
              GroupOptionRow(
                firstLabel: 'Saving',
                firstSelected: _type == 'saving',
                onFirstTap: () => setState(() {
                  _type = 'saving';
                  _frequency = 'monthly'; // savings default to monthly
                }),
                secondLabel: 'Community',
                secondSelected: _type == 'community',
                onSecondTap: () => setState(() {
                  _type = 'community';
                  _frequency = 'one_off'; // community defaults to one_off
                }),
              ),
              SizedBox(height: space.x5),

              // ── Frequency ─────────────────────────────────────────
              if (showFrequencyPicker) ...[
                const GroupSectionLabel(label: 'FREQUENCY'),
                SizedBox(height: space.x2),
                GroupFrequencyPicker(
                  options: const ['daily', 'weekly', 'monthly'],
                  selected: _frequency,
                  onSelected: (freq) => setState(() => _frequency = freq),
                ),
                SizedBox(height: space.x5),
              ],

              // ── Target Amount (optional) ──────────────────────────
              CoolTextField(
                label: 'Target Amount — ${country.currencyCode} (optional)',
                hint: 'e.g. 500,000',
                controller: _targetAmountController,
                keyboardType: TextInputType.number,
              ),
              SizedBox(height: space.x4),

              // ── Contribution Amount (optional) ────────────────────
              CoolTextField(
                label:
                    'Contribution Amount — ${country.currencyCode} (optional)',
                hint: 'e.g. 10,000',
                controller: _contributionAmountController,
                keyboardType: TextInputType.number,
              ),
              SizedBox(height: space.x5),

              // ── MoMo Receive Route ────────────────────────────────
              GroupMomoRouteSection(
                useCustom: _useCustomMomo,
                routeType: _customMomoRouteType,
                momoNumberController: _momoNumberController,
                momoCodeController: _momoCodeController,
                supportsMomoCode: country.supportsMomoCode,
                onToggleCustom: (value) =>
                    setState(() => _useCustomMomo = value),
                onRouteTypeChanged: (type) =>
                    setState(() => _customMomoRouteType = type),
              ),
              SizedBox(height: space.x6),

              // ── Submit ────────────────────────────────────────────
              CoolButton(
                label: 'CREATE GROUP',
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
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return null;
    }
    final value = int.tryParse(digits);
    if (value == null || value <= 0) {
      return null;
    }
    return value;
  }
}
