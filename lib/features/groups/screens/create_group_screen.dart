import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/app_market.dart';
import '../../../core/config/country_catalog.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_text_field.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../auth/providers/auth_provider.dart';

import '../providers/groups_provider.dart';
import '../../partners/providers/partner_provider.dart';
import '../../partners/models/partner.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/widgets/cool_screen_background.dart';

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
    final palette = context.coolPalette;
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

    return CoolScreenBackground(


      showGlow: true,


      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.l10n.back,
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(
          'Create Group',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: palette.text,
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 80),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Group type ──────────────────────────────────────
                    _label('Group Type'),
                    const SizedBox(height: 8),
                    if (hasBankPartner)
                      _AdaptiveCardPair(
                        first: _TypeCard(
                          icon: Icons.account_balance_rounded,
                          title: context.l10n.groupSaving,
                          subtitle:
   'Bank custodian',
                          isSelected: _isSaving,
                          onTap: () => setState(() {
                            _type = 'saving';
                            _frequency = 'monthly';
                          }),
                        ),
                        second: _TypeCard(
                          icon: Icons.favorite_rounded,
                          title: 'Community Fund',
                          subtitle:
   'MOMO to creator',
                          isSelected: !_isSaving,
                          onTap: () => setState(() {
                            _type = 'community';
                            _frequency = 'one_off';
                          }),
                        ),
                      )
                    else
                      _TypeCard(
                        icon: Icons.favorite_rounded,
                        title: 'Community Fund',
                        subtitle:
 'MOMO to creator',
                        isSelected: true,
                        onTap: () {},
                      ),
                    const SizedBox(height: 16),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: _isSaving
                          ? _InfoBanner(
                              key: const ValueKey('saving'),
                              icon: Icons.account_balance_rounded,
                              text: 'Bank-held and insured.',
                              color: palette.accent,
                            )
                          : _InfoBanner(
                              key: const ValueKey('community'),
                              icon: Icons.phone_android_rounded,
                              text: communityCountry.supportsMomoCode
                                  ? 'Sent to your MOMO phone or code.'
                                  : 'Sent to your MOMO number.',
                              color: palette.orange,
                            ),
                    ),
                    const SizedBox(height: 24),

                    // ── Name + target ───────────────────────────────────
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
                    const SizedBox(height: 18),
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
                    const SizedBox(height: 24),

                    // ── Frequency ───────────────────────────────────────
                    _label('Frequency'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final option in _frequenciesFor(_type))
                          _BankChip(
                            label: option.label,
                            isSelected: _frequency == option.value,
                            onTap: () =>
                                setState(() => _frequency = option.value),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // ── MOMO route (community only) ─────────────────────
                    if (!_isSaving) ...[
                      _label('Collection Route'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _BankChip(
                            label: 'Phone Number',
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
                            _BankChip(
                              label: 'Merchant Code',
                              isSelected: activeRouteType == 'code',
                              onTap: () => setState(() {
                                _communityRouteType = 'code';
                                _momoController.text =
                                    user?.momoCode?.trim() ?? '';
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
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
                      const SizedBox(height: 24),
                    ],

                    // ── Monthly (saving only) ───────────────────────────
                    if (_isSaving) ...[
                      // ── Bank partner selector ──────────────────────────
                      if (bankPartners.length > 1) ...[
                        _label('Banking Partner'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final bank in bankPartners)
                              _BankChip(
                                label: bank.name,
                                isSelected: _selectedBankPartner?.id == bank.id,
                                onTap: () => setState(() => _selectedBankPartner = bank),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                      // ── Bank MoMo code (read-only) ─────────────────────
                      if (_selectedBankPartner != null &&
                          (_selectedBankPartner!.momoCode?.isNotEmpty ?? false))
                        _InfoBanner(
                          icon: Icons.account_balance_rounded,
                          text: 'Contributions go to ${_selectedBankPartner!.name} '
                              '(code: ${_selectedBankPartner!.momoCode}). '
                              'This cannot be changed.',
                          color: palette.accent,
                        ),
                      if (_selectedBankPartner != null &&
                          (_selectedBankPartner!.momoCode?.isNotEmpty ?? false))
                        const SizedBox(height: 16),
                      CoolTextField(
                        label: 'Monthly (RWF)',
                        hint: '5,000',
                        controller: _monthlyController,
                        keyboardType: TextInputType.number,
                        prefixIcon: Icons.calendar_today_rounded,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 24),
                    ],

                    // ── Description ─────────────────────────────────────
                    CoolTextField(
                      label: 'Description',
                      hint: 'Group purpose?',
                      controller: _descriptionController,
                      maxLines: 3,
                      textInputAction: TextInputAction.newline,
                    ),
                    const SizedBox(height: 18),

                    // ── Visibility ──────────────────────────────────────
                    _label('Visibility'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _BankChip(
                          label: 'Private',
                          isSelected: _visibility == 'private',
                          onTap: () =>
                              setState(() => _visibility = 'private'),
                        ),
                        _BankChip(
                          label: 'Public',
                          isSelected: _visibility == 'public',
                          onTap: () =>
                              setState(() => _visibility = 'public'),
                        ),
                      ],
                    ),

                    // ── Error ───────────────────────────────────────────
                    if (createError != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        createError,
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: palette.red,
                        ),
                      ),
                    ],

                    // ── CTA ─────────────────────────────────────────────
                    const SizedBox(height: 32),
                    CoolButton(
                      label: 'Create Group',
                      isLoading: isCreating,
                      onTap: _createGroup,
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),


    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  Widget _label(String text) {
    return Text(
      text,
      style: GoogleFonts.dmSans(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.text2,
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

// ═════════════════════════════════════════════════════════════════════════
// Type selector card
// ═════════════════════════════════════════════════════════════════════════

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Semantics(
      button: true,
      selected: isSelected,
      label: '$title group type',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
          decoration: BoxDecoration(
            color: isSelected ? palette.accentGlow : palette.surface2,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? palette.accent : palette.border,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 28,
                color: isSelected ? palette.accent : palette.text,
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? palette.accent : palette.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: palette.text2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdaptiveCardPair extends StatelessWidget {
  const _AdaptiveCardPair({required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: first),
        const SizedBox(width: 12),
        Expanded(child: second),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Bank chip
// ═════════════════════════════════════════════════════════════════════════

class _BankChip extends StatelessWidget {
  const _BankChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Semantics(
      button: true,
      selected: isSelected,
      label: '$label option',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? palette.accentGlow : palette.surface2,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: isSelected ? palette.accent : palette.border,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isSelected ? palette.accent : palette.text2,
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Info banner
// ═════════════════════════════════════════════════════════════════════════

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.text,
    required this.color,
    super.key,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: color,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}