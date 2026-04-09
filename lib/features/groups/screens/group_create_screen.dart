import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/country_catalog.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_text_field.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../auth/models/user_profile.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/groups_provider.dart';

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
  final _monthlyContributionController = TextEditingController();

  String _visibility = 'private';
  String _type = 'saving';
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _targetAmountController.dispose();
    _monthlyContributionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) {
      return;
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final user = ref.read(authProvider).user;
    if (user == null) {
      CoolToast.error(context, 'Complete your profile first.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final group = await ref.read(groupRepositoryProvider).createGroup(
        creator: user,
        name: _nameController.text,
        visibility: _visibility,
        type: _type,
        description: _descriptionController.text,
        targetAmount: _parseAmount(_targetAmountController.text),
        monthlyContribution: _parseAmount(_monthlyContributionController.text),
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
      CoolToast.error(context, error.toString());
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
    final user = ref.watch(authProvider).user;
    final routeLabel = _walletRouteLabel(user);

    return Scaffold(
      backgroundColor: colors.appBackground,
      appBar: AppBar(
        backgroundColor: colors.appBackground,
        elevation: 0,
        title: Text(context.l10n.groupsCreateNewTitle),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(space.x4, space.x3, space.x4, space.x6),
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
                CoolTextField(
                  label: context.l10n.groupDescriptionLabel,
                  hint: 'What is this group for?',
                  controller: _descriptionController,
                  maxLines: 3,
                ),
                SizedBox(height: space.x4),
                const _SectionLabel(label: 'TYPE'),
                SizedBox(height: space.x2),
                _OptionRow(
                  firstLabel: 'Saving',
                  firstSelected: _type == 'saving',
                  onFirstTap: () => setState(() => _type = 'saving'),
                  secondLabel: 'Community',
                  secondSelected: _type == 'community',
                  onSecondTap: () => setState(() => _type = 'community'),
                ),
                SizedBox(height: space.x4),
                const _SectionLabel(label: 'VISIBILITY'),
                SizedBox(height: space.x2),
                _OptionRow(
                  firstLabel: 'Private',
                  firstSelected: _visibility == 'private',
                  onFirstTap: () => setState(() => _visibility = 'private'),
                  secondLabel: 'Public',
                  secondSelected: _visibility == 'public',
                  onSecondTap: () => setState(() => _visibility = 'public'),
                ),
                SizedBox(height: space.x4),
                CoolTextField(
                  label: 'Target Amount (RWF)',
                  hint: 'Optional',
                  controller: _targetAmountController,
                  keyboardType: TextInputType.number,
                ),
                SizedBox(height: space.x4),
                CoolTextField(
                  label: 'Monthly Contribution (RWF)',
                  hint: 'Optional',
                  controller: _monthlyContributionController,
                  keyboardType: TextInputType.number,
                ),
                SizedBox(height: space.x4),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(space.x4),
                  decoration: BoxDecoration(
                    color: colors.cardSurface,
                    borderRadius: BorderRadius.circular(CoolRadii.md),
                    border: Border.all(color: colors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PAYMENT ROUTE',
                        style: text.mobiLabel(color: colors.tertiaryText),
                      ),
                      SizedBox(height: space.x1),
                      Text(
                        routeLabel,
                        style: text.display(
                          null,
                          color: colors.primaryText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: space.x2),
                      Text(
                        user?.hasMomoRecipient == true
                            ? 'New contributions will point members to this route.'
                            : 'No wallet route is configured yet. You can still create the group, but members will not get a prefilled payment route until you set up MoMo in Settings.',
                        style: text.mobiLabel(color: colors.secondaryText),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: space.x6),
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

  String _walletRouteLabel(UserProfile? user) {
    if (user == null || user.hasMomoRecipient != true) {
      return 'No route configured';
    }

    final routeType = user.effectiveMomoRouteType == MomoRecipientType.code
        ? 'Code'
        : 'Phone';
    return '$routeType · ${user.momoRecipientValue}';
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

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.firstLabel,
    required this.firstSelected,
    required this.onFirstTap,
    required this.secondLabel,
    required this.secondSelected,
    required this.onSecondTap,
  });

  final String firstLabel;
  final bool firstSelected;
  final VoidCallback onFirstTap;
  final String secondLabel;
  final bool secondSelected;
  final VoidCallback onSecondTap;

  @override
  Widget build(BuildContext context) {
    final space = context.coolSpace;
    return Row(
      children: [
        Expanded(
          child: _OptionChip(
            label: firstLabel,
            selected: firstSelected,
            onTap: onFirstTap,
          ),
        ),
        SizedBox(width: space.x2),
        Expanded(
          child: _OptionChip(
            label: secondLabel,
            selected: secondSelected,
            onTap: onSecondTap,
          ),
        ),
      ],
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
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: CoolSpace.x3),
        decoration: BoxDecoration(
          color: selected ? colors.accent : colors.cardSurface,
          borderRadius: BorderRadius.circular(CoolRadii.md),
          border: Border.all(
            color: selected ? colors.accent : colors.border,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label.toUpperCase(),
          style: text.mobiLabel(
            color: selected ? colors.accentForeground : colors.primaryText,
          ).copyWith(fontWeight: FontWeight.w800, letterSpacing: 1.0),
        ),
      ),
    );
  }
}
