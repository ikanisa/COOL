import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';
import '../auth/widgets/auth_screen_widgets.dart';

class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  final _displayName = TextEditingController();
  final _revolutName = TextEditingController();
  Country? _selectedCountry;
  String? _hydratedProfileId;
  String? _error;
  bool _dirty = false;
  bool _hydrating = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _displayName.addListener(_markDirty);
    _revolutName.addListener(_markDirty);
    _hydrate(ref.read(collectRepositoryProvider).currentProfile);
  }

  @override
  void dispose() {
    _displayName.removeListener(_markDirty);
    _revolutName.removeListener(_markDirty);
    _displayName.dispose();
    _revolutName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(collectRepositoryProvider).currentProfile;
    ref.listen<CollectProfile?>(
      collectRepositoryProvider.select((state) => state.currentProfile),
      (_, next) {
        if (next == null || _saving || _dirty) return;
        setState(() => _hydrate(next));
      },
    );

    final selectedCountry =
        _selectedCountry ??
        Country.tryParse(profile?.countryCode ?? '') ??
        Country.parse('RW');
    final isEuropean = CollectProfileCountryRules.isEuropeanCountry(
      selectedCountry.countryCode,
    );
    final currencyCode = CollectProfileCountryRules.currencyForCountry(
      selectedCountry.countryCode,
    );

    return ScreenScaffold(
      title: 'Profile',
      showHeader: false,
      bottomAction: BottomActionSurface(
        children: [
          if (profile != null)
            CollectButton(
              key: const ValueKey('profile_save_button'),
              label: _saving ? 'Saving profile' : 'Save profile',
              icon: CollectIcons.check,
              onPressed: _saving || !_dirty ? null : _save,
              expand: true,
            ),
          CollectButton(
            label: profile == null ? 'Sign in' : 'Back to settings',
            icon: profile == null ? CollectIcons.profile : CollectIcons.chevron,
            onPressed: _saving
                ? null
                : () => context.go(profile == null ? '/auth' : '/settings'),
            variant: profile == null
                ? CollectButtonVariant.primary
                : CollectButtonVariant.secondary,
            expand: true,
          ),
        ],
      ),
      children: [
        const CollectPlainPageHeader(title: 'Profile'),
        if (profile == null)
          const MinimalStatePanel(
            icon: CollectIcons.lock,
            title: 'Sign in first',
            message:
                'Collect creates your private 6-digit ID after WhatsApp verification.',
            tone: CollectStatusTone.warning,
          )
        else ...[
          InfoSecurityBanner(
            title: profile.isComplete && !_dirty
                ? 'Profile complete'
                : 'Complete your profile',
            message: profile.isComplete && !_dirty
                ? 'Your country, local currency and regional identity details are saved.'
                : 'Add your name, confirm your profile country and complete any regional field shown below.',
            tone: profile.isComplete && !_dirty
                ? CollectStatusTone.success
                : CollectStatusTone.warning,
          ),
          if (_error != null)
            InfoSecurityBanner(
              title: 'Profile not saved',
              message: _error!,
              tone: CollectStatusTone.danger,
            ),
          const InfoSecurityBanner(
            title: 'Country is independent from sign-in',
            message:
                'Your WhatsApp calling code suggests the first country only. Changing your profile country updates local currency and regional fields without changing your verified WhatsApp number.',
            tone: CollectStatusTone.info,
          ),
          const InfoSecurityBanner(
            title: 'Payment details are centrally governed',
            message:
                'Your local profile currency does not change settlement. Every contribution still uses the approved EUR bank beneficiary shown in Settings.',
            tone: CollectStatusTone.privacy,
          ),
          CollectIdDisplay(
            publicId: profile.publicId,
            onCopy: () => copyToClipboard(
              context,
              profile.publicId,
              message: 'Collect ID copied.',
            ),
          ),
          CollectCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CollectTextInput(
                  key: const ValueKey('profile_display_name_input'),
                  controller: _displayName,
                  label: 'Name',
                  helper: 'Shown only where you choose to use your name.',
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  autocorrect: true,
                  autofillHints: const [AutofillHints.name],
                ),
                CollectSpacing.gap16,
                _ProfileCountryField(
                  country: selectedCountry,
                  currencyCode: currencyCode,
                  onTap: _showCountryPicker,
                ),
                CollectSpacing.gap16,
                CollectListTile(
                  leading: CollectIcons.sms,
                  title: 'Verified WhatsApp',
                  subtitle:
                      '${profile.whatsappPhone}\nUsed only for sign-in and kept unchanged when country changes.',
                ),
                CollectListTile(
                  leading: CollectIcons.money,
                  title: 'Local profile currency',
                  subtitle:
                      '$currencyCode · Updated from profile country. Transfers remain EUR.',
                ),
                if (isEuropean) ...[
                  CollectSpacing.gap16,
                  CollectTextInput(
                    key: const ValueKey('profile_revolut_name_input'),
                    controller: _revolutName,
                    label: 'Revolut name',
                    helper:
                        'Required in Revolut’s supported European region. This identifies you; it never authorizes a transfer.',
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    autocorrect: false,
                    onSubmitted: (_) {
                      if (!_saving && _dirty) _save();
                    },
                  ),
                ],
              ],
            ),
          ),
          CollectCard(
            child: Column(
              children: [
                CollectListTile(
                  leading: CollectIcons.bank,
                  title: 'Bank transfer details',
                  subtitle: 'Review the approved beneficiary and IBAN.',
                  onTap: () => context.go('/settings/bank-transfer'),
                ),
                CollectListTile(
                  leading: CollectIcons.lock,
                  title: 'Account and session',
                  subtitle: 'Review session controls or sign out.',
                  onTap: () => context.go('/settings/account'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _hydrate(CollectProfile? profile) {
    if (profile == null || profile.id == _hydratedProfileId) return;
    _hydrating = true;
    _hydratedProfileId = profile.id;
    _displayName.text = profile.displayName;
    _revolutName.text = profile.revolutName;
    _selectedCountry =
        Country.tryParse(profile.countryCode) ??
        Country.parse(
          CollectProfileCountryRules.inferCountryCodeFromPhone(
            profile.whatsappPhone,
          ),
        );
    _dirty = false;
    _hydrating = false;
  }

  void _markDirty() {
    if (_hydrating || !mounted || _dirty) return;
    setState(() {
      _dirty = true;
      _error = null;
    });
  }

  Future<void> _showCountryPicker() async {
    final country = await showCollectCountryPicker(context);
    if (!mounted || country == null) return;
    setState(() {
      _selectedCountry = country;
      _dirty = true;
      _error = null;
    });
  }

  Future<void> _save() async {
    final selectedCountry = _selectedCountry;
    if (_saving || selectedCountry == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await ref
          .read(collectRepositoryProvider.notifier)
          .updateCurrentProfile(
            displayName: _displayName.text,
            countryCode: selectedCountry.countryCode,
            revolutName: _revolutName.text,
          );
      if (!mounted) return;
      _hydratedProfileId = null;
      setState(() {
        _hydrate(updated);
        _saving = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile saved.')));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _safeProfileError(error);
      });
    }
  }

  String _safeProfileError(Object error) {
    if (error is FormatException) return error.message.toString();
    final text = error.toString().toLowerCase();
    if (text.contains('network') ||
        text.contains('socket') ||
        text.contains('connection')) {
      return 'Check your connection and try saving again.';
    }
    return 'Your profile could not be saved. Try again.';
  }
}

class _ProfileCountryField extends StatelessWidget {
  const _ProfileCountryField({
    required this.country,
    required this.currencyCode,
    required this.onTap,
  });

  final Country country;
  final String currencyCode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final countryName = country.getTranslatedName(context) ?? country.name;
    return Semantics(
      button: true,
      label: 'Profile country, $countryName, local currency $currencyCode',
      child: InkWell(
        key: const ValueKey('profile_country_picker'),
        borderRadius: CollectRadius.controlBorder,
        onTap: onTap,
        child: InputDecorator(
          decoration: collectInputDecoration(
            context,
            label: 'Profile country',
            helper: 'Choose where you live, independently from WhatsApp.',
          ).copyWith(suffixIcon: const Icon(CollectIcons.chevronDown)),
          child: Row(
            children: [
              MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1,
                child: Text(
                  country.flagEmoji,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              CollectSpacing.gapW12,
              Expanded(
                child: Text(
                  '$countryName · $currencyCode',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
