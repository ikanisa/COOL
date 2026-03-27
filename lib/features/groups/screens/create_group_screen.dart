import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_market.dart';
import '../../../core/config/country_catalog.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_text_field.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/core_app_scaffold.dart';
import '../../auth/providers/auth_provider.dart';
import '../../partners/models/partner.dart';
import '../../partners/providers/partner_provider.dart';
import '../providers/groups_provider.dart';

part '../widgets/create_group_parts.dart';

/// Single-screen group creation — saving or community fund.
class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _targetController = TextEditingController();
  final _monthlyController = TextEditingController();
  late final TextEditingController _momoController;

  String _type = 'saving'; // saving | community
  String _visibility = 'private'; // private | public
  String _frequency = 'monthly';
  String _communityRouteType = 'phone_number';
  Partner? _selectedBankPartner;

  bool get _isSaving => _type == 'saving';

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    final country = AppMarket.country;

    _communityRouteType =
        country.supportsMomoCode && user?.momoCode?.trim().isNotEmpty == true
        ? 'code'
        : 'phone_number';
    _momoController = TextEditingController(
      text: _communityRouteType == 'code'
          ? user?.momoCode?.trim() ?? ''
          : user?.momoNumber.isNotEmpty == true
          ? user!.momoNumber
          : user?.phone ?? '',
    );
    ref.read(groupsProvider.notifier).clearCreateGroupState();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _targetController.dispose();
    _monthlyController.dispose();
    _momoController.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final routeType = _effectiveCommunityRouteType();

    // Validate community MOMO field
    if (!_isSaving) {
      final value = _momoController.text.trim();
      if (value.isEmpty) {
        CoolToast.error(
          context,
          routeType == 'code'
              ? 'A merchant code is required.'
              : 'A MOMO number is required.',
        );
        return;
      }
    }

    final data = GroupCreateData(
      name: _nameController.text.trim(),
      type: _type,
      visibility: _visibility,
      targetAmountRwf:
          int.tryParse(_targetController.text.replaceAll(',', '').trim()) ?? 0,
      monthlyContributionRwf: _isSaving
          ? int.tryParse(_monthlyController.text.replaceAll(',', '').trim())
          : null,
      momoNumber: !_isSaving
          ? _normalizeCommunityRecipient(_momoController.text.trim())
          : null,
      momoRouteType: !_isSaving ? routeType : (_isSaving ? 'code' : null),
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      frequency: _frequency,
      bankPartnerId: _isSaving ? _selectedBankPartner?.id : null,
    );

    final created = await ref.read(groupsProvider.notifier).createGroup(data);

    if (!mounted) return;

    if (created != null && created.id != null) {
      context.go('/groups/${created.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final isCreating = ref.watch(groupsCreateLoadingProvider);
    final createError = ref.watch(groupsCreateErrorProvider);
    final user = ref.watch(authProvider).user;
    final communityCountry = AppMarket.country;
    final activeRouteType = communityCountry.supportsMomoCode
        ? _communityRouteType
        : 'phone_number';
    final hasBankPartner = ref.watch(hasActiveBankPartnerProvider);
    final bankPartnersAsync = ref.watch(bankPartnersProvider);
    final bankPartners = bankPartnersAsync.maybeWhen(
      data: (list) => list,
      orElse: () => <Partner>[],
    );

    // Auto-default to community when no bank partner is available.
    if (!hasBankPartner && _isSaving) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _type = 'community';
            _frequency = 'one_off';
          });
        }
      });
    }

    // Auto-select single bank partner
    if (_isSaving && bankPartners.length == 1 && _selectedBankPartner == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedBankPartner = bankPartners.first);
      });
    }

    return CoreAppScaffold(
      title: 'CREATE GROUP',
      scrollable: false,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── Group type section ──────────────────────────
              const _SectionLabel(label: 'GROUP TYPE'),
              const SizedBox(height: CoolSpace.x3),
              if (hasBankPartner)
                _AdaptiveCardPair(
                  first: _TypeCard(
                    emoji: '🏦',
                    title: context.l10n.groupSaving,
                    subtitle: 'BANK CUSTODIAN',
                    isSelected: _isSaving,
                    onTap: () => setState(() {
                      _type = 'saving';
                      _frequency = 'monthly';
                    }),
                  ),
                  second: _TypeCard(
                    emoji: '💛',
                    title: 'Community',
                    subtitle: 'MOMO TO CREATOR',
                    isSelected: !_isSaving,
                    onTap: () => setState(() {
                      _type = 'community';
                      _frequency = 'one_off';
                    }),
                  ),
                )
              else
                _TypeCard(
                  emoji: '💛',
                  title: 'Community',
                  subtitle: 'MOMO TO CREATOR',
                  isSelected: true,
                  onTap: () {},
                ),
              const SizedBox(height: CoolSpace.x4),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _isSaving
                    ? _InfoBanner(
                        key: const ValueKey('saving'),
                        icon: Icons.shield_outlined,
                        text: 'Bank-held and insured.',
                        color: colors.accent,
                      )
                    : _InfoBanner(
                        key: const ValueKey('community'),
                        icon: Icons.phone_android_rounded,
                        text: communityCountry.supportsMomoCode
                            ? 'Sent to MOMO phone or code.'
                            : 'Sent to your MOMO number.',
                        color: colors.warning,
                      ),
              ),
              const SizedBox(height: CoolSpace.x7),

              // ─── Name + target fields ───────────────────────
              CoolTextField(
                label: 'Group Name',
                hint: 'e.g. Family Save',
                controller: _nameController,
                textInputAction: TextInputAction.next,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Group name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: CoolSpace.x5),
              CoolTextField(
                label: 'Target (RWF)',
                hint: '100,000',
                controller: _targetController,
                keyboardType: TextInputType.number,
                prefixIcon: Icons.flag_rounded,
                textInputAction: TextInputAction.next,
                validator: (v) {
                  final normalized =
                      v?.replaceAll(',', '').trim() ?? '';
                  if (normalized.isEmpty) return null;
                  final amount = int.tryParse(normalized);
                  if (amount != null && amount <= 0) {
                    return 'Amount must be positive';
                  }
                  return null;
                },
              ),
              const SizedBox(height: CoolSpace.x7),

              // ─── Frequency section ──────────────────────────
              const _SectionLabel(label: 'FREQUENCY'),
              const SizedBox(height: CoolSpace.x3),
              Wrap(
                spacing: CoolSpace.x2,
                runSpacing: CoolSpace.x2,
                children: [
                  for (final option in _frequenciesFor(_type))
                    _SelectionChip(
                      label: option.label.toUpperCase(),
                      isSelected: _frequency == option.value,
                      onTap: () =>
                          setState(() => _frequency = option.value),
                    ),
                ],
              ),
              const SizedBox(height: CoolSpace.x7),

              // ─── Community collection route ─────────────────
              if (!_isSaving) ...[
                const _SectionLabel(label: 'COLLECTION ROUTE'),
                const SizedBox(height: CoolSpace.x3),
                Wrap(
                  spacing: CoolSpace.x2,
                  runSpacing: CoolSpace.x2,
                  children: [
                    _SelectionChip(
                      label: 'PHONE NUMBER',
                      isSelected: activeRouteType == 'phone_number',
                      onTap: () => setState(() {
                        _communityRouteType = 'phone_number';
                        _momoController.text =
                            user?.momoNumber.isNotEmpty == true
                            ? user!.momoNumber
                            : user?.phone ?? _momoController.text;
                      }),
                    ),
                    if (communityCountry.supportsMomoCode)
                      _SelectionChip(
                        label: 'MERCHANT CODE',
                        isSelected: activeRouteType == 'code',
                        onTap: () => setState(() {
                          _communityRouteType = 'code';
                          _momoController.text =
                              user?.momoCode?.trim() ?? '';
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: CoolSpace.x4),
                CoolTextField(
                  label: activeRouteType == 'code'
                      ? 'Merchant Code'
                      : 'MOMO Number',
                  hint: activeRouteType == 'code'
                      ? communityCountry.momoCodeExample ?? '123456'
                      : communityCountry.phoneExampleHint(),
                  controller: _momoController,
                  keyboardType: activeRouteType == 'code'
                      ? TextInputType.number
                      : TextInputType.phone,
                  prefixIcon: activeRouteType == 'code'
                      ? Icons.tag_rounded
                      : Icons.phone_rounded,
                  validator: (value) {
                    if (_isSaving) return null;
                    if (value == null || value.trim().isEmpty) {
                      return activeRouteType == 'code'
                          ? 'A merchant code is required'
                          : 'A MOMO number is required';
                    }
                    try {
                      if (activeRouteType == 'code') {
                        communityCountry.normalizeMerchantCode(value);
                      } else {
                        communityCountry.buildE164Phone(value);
                      }
                      return null;
                    } on FormatException catch (error) {
                      return error.message.toString();
                    } on UnsupportedError catch (error) {
                      return error.message?.toString() ??
                          'Route not configured.';
                    }
                  },
                ),
                const SizedBox(height: CoolSpace.x7),
              ],

              // ─── Saving: bank partner + monthly ─────────────
              if (_isSaving) ...[
                if (bankPartners.length > 1) ...[
                  const _SectionLabel(label: 'BANKING PARTNER'),
                  const SizedBox(height: CoolSpace.x3),
                  Wrap(
                    spacing: CoolSpace.x2,
                    runSpacing: CoolSpace.x2,
                    children: [
                      for (final bank in bankPartners)
                        _SelectionChip(
                          label: bank.name.toUpperCase(),
                          isSelected:
                              _selectedBankPartner?.id == bank.id,
                          onTap: () => setState(
                            () => _selectedBankPartner = bank,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: CoolSpace.x4),
                ],
                if (_selectedBankPartner != null &&
                    (_selectedBankPartner!.momoCode?.isNotEmpty ??
                        false))
                  _InfoBanner(
                    icon: Icons.shield_outlined,
                    text:
                        'Contributions go to ${_selectedBankPartner!.name} '
                        '(code: ${_selectedBankPartner!.momoCode}). '
                        'This cannot be changed.',
                    color: colors.accent,
                  ),
                if (_selectedBankPartner != null &&
                    (_selectedBankPartner!.momoCode?.isNotEmpty ??
                        false))
                  const SizedBox(height: CoolSpace.x4),
                CoolTextField(
                  label: 'Monthly (RWF)',
                  hint: '5,000',
                  controller: _monthlyController,
                  keyboardType: TextInputType.number,
                  prefixIcon: Icons.calendar_today_rounded,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: CoolSpace.x7),
              ],

              // ─── Description field ──────────────────────────
              CoolTextField(
                label: 'Description',
                hint: 'Group purpose?',
                controller: _descriptionController,
                maxLines: 3,
                textInputAction: TextInputAction.newline,
              ),
              const SizedBox(height: CoolSpace.x6),

              // ─── Visibility section ─────────────────────────
              const _SectionLabel(label: 'VISIBILITY'),
              const SizedBox(height: CoolSpace.x3),
              Wrap(
                spacing: CoolSpace.x2,
                runSpacing: CoolSpace.x2,
                children: [
                  _SelectionChip(
                    label: '🔒 PRIVATE',
                    isSelected: _visibility == 'private',
                    onTap: () =>
                        setState(() => _visibility = 'private'),
                  ),
                  _SelectionChip(
                    label: '🌐 PUBLIC',
                    isSelected: _visibility == 'public',
                    onTap: () => setState(() => _visibility = 'public'),
                  ),
                ],
              ),

              // ─── Error display ──────────────────────────────
              if (createError != null) ...[
                const SizedBox(height: CoolSpace.x5),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(CoolSpace.x3),
                  decoration: BoxDecoration(
                    color: colors.danger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(CoolRadii.sm),
                    border: Border.all(
                      color: colors.danger.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    createError,
                    style: text.rayon(
                      theme.textTheme.bodySmall,
                      fontWeight: FontWeight.w600,
                      color: colors.danger,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: CoolSpace.x7),

              // ─── Create button ──────────────────────────────
              CoolButton(
                label: 'Create Group',
                isLoading: isCreating,
                onTap: _createGroup,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _allFrequencies = <({String label, String value})>[
    (label: 'One-off', value: 'one_off'),
    (label: 'Daily', value: 'daily'),
    (label: 'Weekly', value: 'weekly'),
    (label: 'Monthly', value: 'monthly'),
  ];

  static List<({String label, String value})> _frequenciesFor(String type) {
    if (type == 'community') {
      return _allFrequencies; // one_off is first = default
    }
    // Savings groups: no one-off
    return _allFrequencies.where((f) => f.value != 'one_off').toList();
  }

  String _normalizeCommunityRecipient(String value) {
    if (_effectiveCommunityRouteType() == 'code') {
      return _communityCountry().normalizeMerchantCode(value);
    }
    return _communityCountry().buildE164Phone(value);
  }

  String _effectiveCommunityRouteType() {
    return _communityCountry().supportsMomoCode
        ? _communityRouteType
        : 'phone_number';
  }

  CoolCountry _communityCountry() => AppMarket.country;
}
