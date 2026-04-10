import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_market.dart';
import '../../../core/config/country_catalog.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_glass_header_surface.dart';
import '../../../shared/widgets/cool_screen_background.dart';
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
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final text = context.coolText;
    final country = AppMarket.country;

    // Frequency: saving = recurring (picker), community = always one_off
    // (all user-created groups are private; community private = one_off)
    final showFrequencyPicker = _type == 'saving';

    // Force community to one_off
    if (_type == 'community' && _frequency != 'one_off') {
      _frequency = 'one_off';
    }

    return CoolScreenBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          toolbarHeight: 84,
          flexibleSpace: const CoolGlassHeaderSurface(),
          title: Text(context.l10n.groupsCreateNewTitle),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              space.x4,
              space.x3,
              space.x4,
              space.x6,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.groupsCreateNewSubtitle,
                    style: text.mobiLabel(color: colors.secondaryText),
                  ),
                  SizedBox(height: space.x4),

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
                  _MomoRouteCard(
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

// ═══════════════════════════════════════════════════════════════════════
// MOMO ROUTE CARD (matches BioPay-style segmented control from screenshot)
// ═══════════════════════════════════════════════════════════════════════

class _MomoRouteCard extends StatelessWidget {
  const _MomoRouteCard({
    required this.useCustom,
    required this.routeType,
    required this.momoNumberController,
    required this.momoCodeController,
    required this.supportsMomoCode,
    required this.onToggleCustom,
    required this.onRouteTypeChanged,
  });

  final bool useCustom;
  final MomoRecipientType routeType;
  final TextEditingController momoNumberController;
  final TextEditingController momoCodeController;
  final bool supportsMomoCode;
  final ValueChanged<bool> onToggleCustom;
  final ValueChanged<MomoRecipientType> onRouteTypeChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final text = context.coolText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toggle
        InkWell(
          onTap: () => onToggleCustom(!useCustom),
          borderRadius: BorderRadius.circular(CoolRadii.md),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: space.x2),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: CoolMotion.quick,
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: useCustom
                        ? colors.accent.withValues(alpha: 0.86)
                        : colors.cardSurfaceStrong.withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(CoolRadii.xs),
                    border: Border.all(
                      color: useCustom
                          ? colors.accentStrong.withValues(alpha: 0.75)
                          : colors.borderStrong.withValues(alpha: 0.75),
                      width: 1.2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: useCustom
                      ? Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: colors.accentForeground,
                        )
                      : null,
                ),
                SizedBox(width: space.x3),
                Expanded(
                  child: Text(
                    'USE DIFFERENT MOMO FOR THIS GROUP',
                    style: text
                        .mobiLabel(color: colors.primaryText)
                        .copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),

        if (useCustom) ...[
          SizedBox(height: space.x3),
          // Segmented control (NUMBER / CODE) — BioPay-style
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
                  child: GroupSegmentTab(
                    label: 'NUMBER',
                    selected: routeType == MomoRecipientType.phoneNumber,
                    onTap: () =>
                        onRouteTypeChanged(MomoRecipientType.phoneNumber),
                  ),
                ),
                if (supportsMomoCode)
                  Expanded(
                    child: GroupSegmentTab(
                      label: 'CODE',
                      selected: routeType == MomoRecipientType.code,
                      onTap: () => onRouteTypeChanged(MomoRecipientType.code),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: space.x3),

          // Input field card
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
                  style: text
                      .mobiLabel(color: colors.tertiaryText)
                      .copyWith(
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
      ],
    );
  }
}

