import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/country_catalog.dart';
import '../../../core/providers/supported_countries_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_text_field.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../auth/providers/auth_provider.dart';
import '../../partners/providers/partner_provider.dart';
import '../providers/groups_provider.dart';

/// Screen for creating a new group — either a Saving group
/// (bank custodian) or a Community Fund (MOMO to creator).
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
  String _bankPartner = 'BK Rwanda';
  String _communityRouteType = 'phone_number';
  bool _showAdvancedOptions = false;

  bool get _isSaving => _type == 'saving';

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    final viewerCountry = ref.read(currentUserCountryCodeProvider);
    final country = CoolCountryCatalog.resolve(
      country: viewerCountry,
      phone: user?.phone,
      providerId: user?.momoProvider,
    );
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

    final bankPartner = _isSaving ? _effectiveBankPartner() : null;
    if (_isSaving && bankPartner == null) {
      CoolToast.error(
        context,
        'No bank custodian is configured for your country yet.',
      );
      return;
    }

    final routeType = _effectiveCommunityRouteType();
    final data = GroupCreateData(
      name: _nameController.text.trim(),
      type: _type,
      visibility: _visibility,
      targetAmountRwf:
          int.tryParse(_targetController.text.replaceAll(',', '').trim()) ?? 0,
      monthlyContributionRwf: _isSaving
          ? int.tryParse(_monthlyController.text.replaceAll(',', '').trim())
          : null,
      bankPartner: bankPartner,
      momoNumber: !_isSaving
          ? _normalizeCommunityRecipient(_momoController.text.trim())
          : null,
      momoRouteType: !_isSaving ? routeType : null,
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      frequency: _frequency,
    );

    final created = await ref.read(groupsProvider.notifier).createGroup(data);

    if (!mounted) return;

    if (created != null && created.id != null) {
      context.go('/groups/${created.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCreating = ref.watch(groupsCreateLoadingProvider);
    final createError = ref.watch(groupsCreateErrorProvider);
    final user = ref.watch(authProvider).user;
    final viewerCountry = ref.watch(currentUserCountryCodeProvider);
    final countries =
        ref.watch(supportedCountriesProvider).valueOrNull ??
        CoolCountryCatalog.all;
    final communityCountry = CoolCountryCatalog.resolve(
      country: viewerCountry,
      phone: user?.phone,
      providerId: user?.momoProvider,
      source: countries,
    );
    final bankPartnersAsync = ref.watch(currentCountryBankPartnersProvider);
    final bankOptions =
        bankPartnersAsync.valueOrNull
            ?.map((partner) => partner.name.trim())
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList(growable: false) ??
        const <String>[];
    final selectedBank = bankOptions.contains(_bankPartner)
        ? _bankPartner
        : (bankOptions.isNotEmpty ? bankOptions.first : null);
    final activeRouteType = communityCountry.supportsMomoCode
        ? _communityRouteType
        : 'phone_number';
    final hasSingleBankOption = bankOptions.length == 1 && selectedBank != null;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(
          'Create Group',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
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
                    _label('Group Type'),
                    const SizedBox(height: 8),
                    _AdaptiveCardPair(
                      first: _TypeCard(
                        icon: Icons.account_balance_rounded,
                        title: 'Group Saving',
                        subtitle: 'Bank custodian',
                        isSelected: _isSaving,
                        onTap: () => setState(() => _type = 'saving'),
                      ),
                      second: _TypeCard(
                        icon: Icons.favorite_rounded,
                        title: 'Community Fund',
                        subtitle: 'MOMO to creator',
                        isSelected: !_isSaving,
                        onTap: () => setState(() => _type = 'community'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: _isSaving
                          ? _InfoBanner(
                              key: const ValueKey('saving'),
                              icon: Icons.account_balance_rounded,
                              text: 'Bank-held and insured.',
                              color: AppColors.accent,
                            )
                          : _InfoBanner(
                              key: const ValueKey('community'),
                              icon: Icons.phone_android_rounded,
                              text: communityCountry.supportsMomoCode
                                  ? 'Sent to your MOMO phone or code.'
                                  : 'Sent to your MOMO number.',
                              color: AppColors.orange,
                            ),
                    ),
                    const SizedBox(height: 24),
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
                      label: 'Saving Target (RWF)',
                      hint: '100,000',
                      controller: _targetController,
                      keyboardType: TextInputType.number,
                      prefixIcon: Icons.flag_rounded,
                      textInputAction: TextInputAction.next,
                      validator: (v) {
                        final normalized = v?.replaceAll(',', '').trim() ?? '';
                        final amount = int.tryParse(normalized);
                        if (amount == null || amount <= 0) {
                          return 'Enter a valid target amount';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    _label('Contribution Frequency'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final option in _frequencies)
                          _BankChip(
                            label: option.label,
                            isSelected: _frequency == option.value,
                            onTap: () =>
                                setState(() => _frequency = option.value),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    if (_isSaving) ...[
                      _label(hasSingleBankOption ? 'Custodian' : 'Bank Partner'),
                      const SizedBox(height: 8),
                      if (bankPartnersAsync.isLoading && bankOptions.isEmpty)
                        const LinearProgressIndicator(minHeight: 2)
                      else if (bankOptions.isEmpty)
                        Text(
                          'No bank custodians are configured for ${communityCountry.name} yet.',
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.orange,
                          ),
                        )
                      else if (hasSingleBankOption)
                        _SummaryCard(
                          title: selectedBank,
                          subtitle: 'Matched to ${communityCountry.name}.',
                          icon: Icons.account_balance_rounded,
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final bank in bankOptions)
                              _BankChip(
                                label: bank,
                                isSelected: selectedBank == bank,
                                onTap: () =>
                                    setState(() => _bankPartner = bank),
                              ),
                          ],
                        ),
                      if (!hasSingleBankOption) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Matched to your country.',
                          style: GoogleFonts.dmSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                            color: AppColors.text3,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                    ],

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
                        prefixIcon: activeRouteType == 'code' ? Icons.tag_rounded : Icons.phone_rounded,
                        validator: (value) {
                          if (_isSaving) {
                            return null;
                          }
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
                                'This route is not configured for ${communityCountry.name}.';
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        activeRouteType == 'code'
                            ? 'Via ${communityCountry.momoCodeUssdExample ?? 'merchant-code USSD'}.'
                            : 'Via ${communityCountry.momoNumberUssdExample ?? 'phone-number USSD'}.',
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: AppColors.text3,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    _SectionToggle(
                      title: 'More options',
                      subtitle: _showAdvancedOptions
                          ? 'Hide description and visibility.'
                          : 'Add description, visibility, and extra settings.',
                      isExpanded: _showAdvancedOptions,
                      onTap: () {
                        setState(() {
                          _showAdvancedOptions = !_showAdvancedOptions;
                        });
                      },
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _showAdvancedOptions
                          ? Padding(
                              key: const ValueKey('advanced-options'),
                              padding: const EdgeInsets.only(top: 18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CoolTextField(
                                    label: 'Description',
                                    hint: 'What is this group for?',
                                    controller: _descriptionController,
                                    maxLines: 3,
                                    textInputAction: TextInputAction.newline,
                                  ),
                                  if (_isSaving) ...[
                                    const SizedBox(height: 18),
                                    CoolTextField(
                                      label: 'Monthly Contribution (RWF)',
                                      hint: '5,000',
                                      controller: _monthlyController,
                                      keyboardType: TextInputType.number,
                                      prefixIcon:
                                          Icons.calendar_today_rounded,
                                      textInputAction: TextInputAction.done,
                                    ),
                                  ],
                                  const SizedBox(height: 18),
                                  _label('Visibility'),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _BankChip(
                                        label: 'Private',
                                        isSelected: _visibility == 'private',
                                        onTap: () => setState(
                                          () => _visibility = 'private',
                                        ),
                                      ),
                                      _BankChip(
                                        label: 'Public',
                                        isSelected: _visibility == 'public',
                                        onTap: () => setState(
                                          () => _visibility = 'public',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),

                    // Error message
                    if (createError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        createError,
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.red,
                        ),
                      ),
                    ],

                    // CTA
                    CoolButton(
                      label: 'Create Group',
                      onTap: _createGroup,
                      isLoading: isCreating,
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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

  static const _frequencies = <({String label, String value})>[
    (label: 'Daily', value: 'daily'),
    (label: 'Weekly', value: 'weekly'),
    (label: 'Monthly', value: 'monthly'),
  ];

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

  CoolCountry _communityCountry() {
    final user = ref.read(authProvider).user;
    final viewerCountry = ref.read(currentUserCountryCodeProvider);
    final countries =
        ref.read(supportedCountriesProvider).valueOrNull ??
        CoolCountryCatalog.all;
    return CoolCountryCatalog.resolve(
      country: viewerCountry,
      phone: user?.phone,
      providerId: user?.momoProvider,
      source: countries,
    );
  }

  String? _effectiveBankPartner() {
    final bankPartners =
        ref.read(currentCountryBankPartnersProvider).valueOrNull ??
        const <dynamic>[];
    final bankOptions = bankPartners
        .map((partner) => partner.name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (bankOptions.contains(_bankPartner)) {
      return _bankPartner;
    }
    if (bankOptions.isNotEmpty) {
      return bankOptions.first;
    }
    return null;
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Type / visibility selector card
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accentGlow : AppColors.surface2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.border,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 28, color: isSelected ? AppColors.accent : AppColors.text),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isSelected ? AppColors.accent : AppColors.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: AppColors.text2,
              ),
            ),
          ],
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
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(children: [first, const SizedBox(height: 12), second]);
        }

        return Row(
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );
      },
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accentGlow : AppColors.surface2,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.border,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? AppColors.accent : AppColors.text2,
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppColors.text2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionToggle extends StatelessWidget {
  const _SectionToggle({
    required this.title,
    required this.subtitle,
    required this.isExpanded,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool isExpanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: AppColors.text2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                isExpanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: AppColors.text2,
              ),
            ],
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
