import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/country_catalog.dart';
import '../../../core/providers/supported_countries_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_text_field.dart';
import '../../auth/providers/auth_provider.dart';
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
  bool _isLoading = false;
  String? _error;

  bool get _isSaving => _type == 'saving';

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    final country = CoolCountryCatalog.resolve(
      country: user?.country,
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

    setState(() {
      _isLoading = true;
      _error = null;
    });

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
      bankPartner: _isSaving ? _bankPartner : null,
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
    } else {
      final providerError = ref.read(groupsProvider).error;
      setState(() {
        _isLoading = false;
        _error = providerError ?? 'Failed to create group. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupsState = ref.watch(groupsProvider);
    final user = ref.watch(authProvider).user;
    final countries =
        ref.watch(supportedCountriesProvider).valueOrNull ??
        CoolCountryCatalog.all;
    final communityCountry = CoolCountryCatalog.resolve(
      country: user?.country,
      phone: user?.phone,
      providerId: user?.momoProvider,
      source: countries,
    );
    final activeRouteType = communityCountry.supportsMomoCode
        ? _communityRouteType
        : 'phone_number';

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
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),

              // ═════════════════════════════════════════════════════
              // TYPE SELECTOR
              // ═════════════════════════════════════════════════════
              _label('Group Type'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _TypeCard(
                      emoji: '🏦',
                      title: 'Group Saving',
                      subtitle: 'Bank custodian',
                      isSelected: _isSaving,
                      onTap: () => setState(() => _type = 'saving'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TypeCard(
                      emoji: '❤️',
                      title: 'Community Fund',
                      subtitle: 'MOMO to creator',
                      isSelected: !_isSaving,
                      onTap: () => setState(() => _type = 'community'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ═════════════════════════════════════════════════════
              // INFO BANNER
              // ═════════════════════════════════════════════════════
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _isSaving
                    ? _InfoBanner(
                        key: const ValueKey('saving'),
                        emoji: '🏦',
                        text:
                            'Funds held by bank partner as custodian. '
                            'Secure and insured.',
                        color: AppColors.accent,
                      )
                    : _InfoBanner(
                        key: const ValueKey('community'),
                        emoji: '📲',
                        text: communityCountry.supportsMomoCode
                            ? 'Funds sent directly to your MOMO route. '
                                  'Use a phone number or merchant code.'
                            : 'Funds sent directly to your MOMO number.',
                        color: AppColors.orange,
                      ),
              ),
              const SizedBox(height: 24),

              // ═════════════════════════════════════════════════════
              // FORM FIELDS
              // ═════════════════════════════════════════════════════
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
                label: 'Description',
                hint: 'What is this group for?',
                controller: _descriptionController,
                maxLines: 3,
                textInputAction: TextInputAction.newline,
              ),
              const SizedBox(height: 18),

              CoolTextField(
                label: 'Saving Target (RWF)',
                hint: '100,000',
                controller: _targetController,
                keyboardType: TextInputType.number,
                prefixEmoji: '🎯',
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

              // Monthly contribution — saving only
              if (_isSaving) ...[
                const SizedBox(height: 18),
                CoolTextField(
                  label: 'Monthly Contribution (RWF)',
                  hint: '5,000',
                  controller: _monthlyController,
                  keyboardType: TextInputType.number,
                  prefixEmoji: '📅',
                  textInputAction: TextInputAction.done,
                ),
              ],
              const SizedBox(height: 24),

              _label('Contribution Frequency'),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final option in _frequencies) ...[
                    Expanded(
                      child: _BankChip(
                        label: option.label,
                        isSelected: _frequency == option.value,
                        onTap: () => setState(() => _frequency = option.value),
                      ),
                    ),
                    if (option != _frequencies.last) const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 24),

              // ═════════════════════════════════════════════════════
              // VISIBILITY SELECTOR
              // ═════════════════════════════════════════════════════
              _label('Visibility'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _TypeCard(
                      emoji: '🔒',
                      title: 'Private',
                      subtitle: 'Invite only',
                      isSelected: _visibility == 'private',
                      onTap: () => setState(() => _visibility = 'private'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TypeCard(
                      emoji: '🌐',
                      title: 'Public',
                      subtitle: 'Anyone can join',
                      isSelected: _visibility == 'public',
                      onTap: () => setState(() => _visibility = 'public'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ═════════════════════════════════════════════════════
              // BANK PARTNER (saving only)
              // ═════════════════════════════════════════════════════
              if (_isSaving) ...[
                _label('Bank Partner (auto-matched)'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (var i = 0; i < _banks.length; i++) ...[
                      Expanded(
                        child: _BankChip(
                          label: _banks[i],
                          isSelected: _bankPartner == _banks[i],
                          onTap: () => setState(() => _bankPartner = _banks[i]),
                        ),
                      ),
                      if (i != _banks.length - 1) const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Auto-matched based on your country',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: AppColors.text3,
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // ═════════════════════════════════════════════════════
              // COMMUNITY FUND — MOMO route
              // ═════════════════════════════════════════════════════
              if (!_isSaving) ...[
                _label('Collection Route'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _BankChip(
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
                    ),
                    if (communityCountry.supportsMomoCode) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: _BankChip(
                          label: 'Merchant Code',
                          isSelected: activeRouteType == 'code',
                          onTap: () => setState(() {
                            _communityRouteType = 'code';
                            _momoController.text = user?.momoCode?.trim() ?? '';
                          }),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                CoolTextField(
                  label: activeRouteType == 'code'
                      ? 'Merchant Code for receiving funds'
                      : 'MOMO number for receiving funds',
                  hint: activeRouteType == 'code'
                      ? communityCountry.momoCodeExample ?? '123456'
                      : communityCountry.phoneExampleHint(),
                  controller: _momoController,
                  keyboardType: activeRouteType == 'code'
                      ? TextInputType.number
                      : TextInputType.phone,
                  prefixEmoji: activeRouteType == 'code' ? '🏷️' : '📱',
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
                      ? 'Contributors will dial ${communityCountry.momoCodeUssdExample ?? 'the merchant-code USSD route'}.'
                      : 'Contributors will dial ${communityCountry.momoNumberUssdExample ?? 'the phone-number USSD route'}.',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: AppColors.text3,
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Error message
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
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
                isLoading: _isLoading || groupsState.isLoading,
              ),
              const SizedBox(height: 80),
            ],
          ),
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

  static const _banks = ['BK Rwanda', 'Equity', 'I&M'];
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
    final countries =
        ref.read(supportedCountriesProvider).valueOrNull ??
        CoolCountryCatalog.all;
    return CoolCountryCatalog.resolve(
      country: user?.country,
      phone: user?.phone,
      providerId: user?.momoProvider,
      source: countries,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Type / visibility selector card
// ═════════════════════════════════════════════════════════════════════════

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  final String emoji;
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
            Text(emoji, style: const TextStyle(fontSize: 28)),
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

// ═════════════════════════════════════════════════════════════════════════
// Info banner
// ═════════════════════════════════════════════════════════════════════════

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.emoji,
    required this.text,
    required this.color,
    super.key,
  });

  final String emoji;
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
          Text(emoji, style: const TextStyle(fontSize: 18)),
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
